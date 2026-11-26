//
//  GameControllerManager.swift
//  AppShared
//
//  Created by Amgi Contributors.
//

public import AppCore
#if canImport(CoreGraphics)
public import CoreGraphics
#endif
public import Foundation
public import Observation
#if canImport(GameController)
import GameController
#endif

/// Bridges hardware game controllers (8BitDo, Nintendo Joy-Con/Pro, Xbox,
/// PlayStation DualSense/DualShock, MFi) into customizable Anki review actions
/// and smooth analog-stick card scrolling.
@Observable
@MainActor
public final class GameControllerManager {
    public static let shared = GameControllerManager()

    public struct HandlerToken: Hashable, Sendable {
        let id = UUID()
    }

    private struct HandlerEntry {
        let token: HandlerToken
        let onAction: @MainActor (ReviewShortcutAction) -> Void
        let onScrollDelta: (@MainActor (CGFloat) -> Void)?
    }

    public private(set) var connectedControllers: [String] = []
    public private(set) var lastInputLabel: String?

    public var isConnected: Bool { !connectedControllers.isEmpty }

    public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: ShortcutPreferences.Keys.gamepadEnabled)
            if !isEnabled {
                stopThumbstickLoop()
            }
        }
    }

    public var thumbstickScrollEnabled: Bool {
        didSet {
            UserDefaults.standard.set(thumbstickScrollEnabled, forKey: ShortcutPreferences.Keys.gamepadThumbstickScroll)
            if !thumbstickScrollEnabled {
                stopThumbstickLoop()
            }
        }
    }

    public private(set) var bindings: [GamepadInput: ReviewShortcutAction]

    @ObservationIgnored private var handlers: [HandlerEntry] = []
    @ObservationIgnored private var observerTokens: [any NSObjectProtocol] = []
    @ObservationIgnored private var lastPressTimes: [GamepadInput: ContinuousClock.Instant] = [:]
    @ObservationIgnored private var currentStickY: Float = 0
    @ObservationIgnored private var thumbstickScrollTask: Task<Void, Never>?

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: ShortcutPreferences.Keys.gamepadEnabled) != nil {
            self.isEnabled = defaults.bool(forKey: ShortcutPreferences.Keys.gamepadEnabled)
        } else {
            self.isEnabled = true
        }
        if defaults.object(forKey: ShortcutPreferences.Keys.gamepadThumbstickScroll) != nil {
            self.thumbstickScrollEnabled = defaults.bool(forKey: ShortcutPreferences.Keys.gamepadThumbstickScroll)
        } else {
            self.thumbstickScrollEnabled = true
        }
        self.bindings = ShortcutPreferences.loadGamepadBindings(defaults: defaults)

        startObservingControllers()
    }

    public func setAction(_ action: ReviewShortcutAction, for input: GamepadInput) {
        bindings[input] = action
        ShortcutPreferences.saveGamepadBindings(bindings)
    }

    public func resetToDefaults() {
        ShortcutPreferences.resetGamepadBindings()
        bindings = ShortcutPreferences.defaultGamepadBindings()
    }

    @discardableResult
    public func registerHandler(
        onAction: @escaping @MainActor (ReviewShortcutAction) -> Void,
        onScrollDelta: (@MainActor (CGFloat) -> Void)? = nil
    ) -> HandlerToken {
        let token = HandlerToken()
        handlers.append(HandlerEntry(token: token, onAction: onAction, onScrollDelta: onScrollDelta))
        return token
    }

    public func unregisterHandler(_ token: HandlerToken) {
        handlers.removeAll { $0.token == token }
        if handlers.isEmpty {
            stopThumbstickLoop()
        }
    }

    // MARK: - Controller Discovery & Input Binding

    private func startObservingControllers() {
        #if canImport(GameController)
        GCController.shouldMonitorBackgroundEvents = false
        let center = NotificationCenter.default
        let connectToken = center.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshControllers()
            }
        }
        let disconnectToken = center.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshControllers()
            }
        }
        observerTokens = [connectToken, disconnectToken]
        refreshControllers()
        #endif
    }

    public func refreshControllers() {
        #if canImport(GameController)
        let controllers = GCController.controllers()
        connectedControllers = controllers.map { $0.vendorName ?? "Game Controller" }

        for controller in controllers {
            if let pad = controller.extendedGamepad {
                Self.bindButton(pad.buttonA, input: .buttonA, manager: self)
                Self.bindButton(pad.buttonB, input: .buttonB, manager: self)
                Self.bindButton(pad.buttonX, input: .buttonX, manager: self)
                Self.bindButton(pad.buttonY, input: .buttonY, manager: self)
                Self.bindButton(pad.leftShoulder, input: .leftShoulder, manager: self)
                Self.bindButton(pad.rightShoulder, input: .rightShoulder, manager: self)
                Self.bindButton(pad.leftTrigger, input: .leftTrigger, manager: self)
                Self.bindButton(pad.rightTrigger, input: .rightTrigger, manager: self)
                Self.bindButton(pad.dpad.up, input: .dpadUp, manager: self)
                Self.bindButton(pad.dpad.down, input: .dpadDown, manager: self)
                Self.bindButton(pad.dpad.left, input: .dpadLeft, manager: self)
                Self.bindButton(pad.dpad.right, input: .dpadRight, manager: self)
                Self.bindButton(pad.buttonMenu, input: .buttonMenu, manager: self)
                Self.bindButton(pad.buttonOptions, input: .buttonOptions, manager: self)
                Self.bindButton(pad.leftThumbstickButton, input: .leftThumbstickButton, manager: self)
                Self.bindButton(pad.rightThumbstickButton, input: .rightThumbstickButton, manager: self)
                Self.bindThumbstickYAxis(pad.leftThumbstick.yAxis, manager: self)
                Self.bindThumbstickYAxis(pad.rightThumbstick.yAxis, manager: self)
            } else if let micro = controller.microGamepad {
                Self.bindButton(micro.buttonA, input: .buttonA, manager: self)
                Self.bindButton(micro.buttonX, input: .buttonX, manager: self)
                Self.bindButton(micro.buttonMenu, input: .buttonMenu, manager: self)
                Self.bindButton(micro.dpad.up, input: .dpadUp, manager: self)
                Self.bindButton(micro.dpad.down, input: .dpadDown, manager: self)
                Self.bindButton(micro.dpad.left, input: .dpadLeft, manager: self)
                Self.bindButton(micro.dpad.right, input: .dpadRight, manager: self)
            }
        }
        #endif
    }

    #if canImport(GameController)
    private nonisolated static func bindButton(
        _ button: GCControllerButtonInput?,
        input: GamepadInput,
        manager: GameControllerManager
    ) {
        button?.pressedChangedHandler = { [weak manager] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor [weak manager] in
                manager?.handlePress(input)
            }
        }
    }

    private nonisolated static func bindThumbstickYAxis(
        _ axis: GCControllerAxisInput,
        manager: GameControllerManager
    ) {
        axis.valueChangedHandler = { [weak manager] _, value in
            Task { @MainActor [weak manager] in
                manager?.updateThumbstickY(value)
            }
        }
    }
    #endif

    private func handlePress(_ input: GamepadInput) {
        let now = ContinuousClock.now
        if let prev = lastPressTimes[input], prev.duration(to: now) < .milliseconds(80) {
            return
        }
        lastPressTimes[input] = now

        let action = bindings[input] ?? input.defaultAction
        lastInputLabel = "\(input.displayName) → \(action.displayName)"

        guard isEnabled, action != .none, let top = handlers.last else { return }
        top.onAction(action)
    }

    private func updateThumbstickY(_ y: Float) {
        guard isEnabled, thumbstickScrollEnabled, abs(y) >= 0.25 else {
            stopThumbstickLoop()
            return
        }
        currentStickY = y
        guard thumbstickScrollTask == nil, !handlers.isEmpty else { return }

        thumbstickScrollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isEnabled, self.thumbstickScrollEnabled, abs(self.currentStickY) >= 0.25 else {
                    break
                }
                let delta = CGFloat(-self.currentStickY) * 26.0
                self.handlers.last?.onScrollDelta?(delta)
                try? await Task.sleep(for: .milliseconds(33))
            }
            self?.thumbstickScrollTask = nil
        }
    }

    private func stopThumbstickLoop() {
        currentStickY = 0
        thumbstickScrollTask?.cancel()
        thumbstickScrollTask = nil
    }
}
