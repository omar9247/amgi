//
//  ShortcutsSettingsView.swift
//  SettingsFeature
//
//  Created by Amgi Contributors.
//

import AppCore
import AppShared
import Sharing
import SwiftUI
import Theme

struct ShortcutsSettingsView: View {
    @Shared(.appStorage(ShortcutPreferences.Keys.keyboardShortcutsEnabled))
    private var keyboardShortcutsEnabled: Bool = true

    @Bindable private var controllerManager = GameControllerManager.shared
    @Environment(\.palette) private var palette

    private var gamepadEnabledBinding: Binding<Bool> {
        Binding(
            get: { controllerManager.isEnabled },
            set: { controllerManager.isEnabled = $0 }
        )
    }

    private var thumbstickScrollBinding: Binding<Bool> {
        Binding(
            get: { controllerManager.thumbstickScrollEnabled },
            set: { controllerManager.thumbstickScrollEnabled = $0 }
        )
    }

    private var shortcutCategories: [(category: String, items: [DesktopShortcutInfo])] {
        var order: [String] = []
        var grouped: [String: [DesktopShortcutInfo]] = [:]
        for item in ShortcutPreferences.desktopShortcuts {
            if grouped[item.category] == nil {
                order.append(item.category)
                grouped[item.category] = []
            }
            grouped[item.category, default: []].append(item)
        }
        return order.compactMap { cat in
            grouped[cat].map { (category: cat, items: $0) }
        }
    }

    var body: some View {
        SettingsPage {
            controllerStatusSection
            inputOptionsSection
            controllerMappingSection
            keyboardReferenceSections
        }
        .navigationTitle("Keyboard & Controller")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var controllerStatusSection: some View {
        Group {
            SettingsSectionHeader(title: "Game Controller")
            SettingsGroup {
                SettingsValueRow(
                    title: "Connected",
                    value: controllerManager.isConnected
                        ? controllerManager.connectedControllers.joined(separator: ", ")
                        : "Not connected",
                    systemImage: "gamecontroller",
                    tone: controllerManager.isConnected ? .review : .neutral,
                    isMuted: !controllerManager.isConnected
                )
                SettingsSeparator()
                SettingsValueRow(
                    title: "Last input",
                    value: controllerManager.lastInputLabel ?? "Press any button to test",
                    systemImage: "dot.radiowaves.left.and.right",
                    tone: .info,
                    isMuted: controllerManager.lastInputLabel == nil
                )
            }
            SettingsFootnote(
                "Pair any Bluetooth controller (8BitDo Zero 2 / Micro, Nintendo Joy-Con, Xbox, PlayStation, or MFi) in iOS Settings → Bluetooth, then press a button here to test."
            )
        }
    }

    private var inputOptionsSection: some View {
        Group {
            SettingsSectionHeader(title: "Input Options")
            SettingsGroup {
                SettingsToggleRow(
                    title: "Keyboard Shortcuts",
                    systemImage: "keyboard",
                    tone: .accent,
                    isOn: Binding($keyboardShortcutsEnabled)
                )
                SettingsSeparator()
                SettingsToggleRow(
                    title: "Game Controller Support",
                    systemImage: "gamecontroller.fill",
                    tone: .review,
                    isOn: gamepadEnabledBinding
                )
                SettingsSeparator()
                SettingsToggleRow(
                    title: "Joystick Smooth Scrolling",
                    systemImage: "l.joystick",
                    tone: .info,
                    isOn: thumbstickScrollBinding
                )
            }
        }
    }

    private var controllerMappingSection: some View {
        Group {
            SettingsSectionHeader(title: "Controller Button Mapping")
            SettingsGroup {
                ForEach(Array(GamepadInput.allCases.enumerated()), id: \.element.id) { index, input in
                    if index > 0 {
                        SettingsSeparator()
                    }
                    SettingsPickerRow(
                        title: input.displayName,
                        systemImage: input.symbolName,
                        tone: .link,
                        selection: Binding(
                            get: { controllerManager.bindings[input] ?? input.defaultAction },
                            set: { controllerManager.setAction($0, for: input) }
                        )
                    ) {
                        ForEach(ReviewShortcutAction.allCases) { action in
                            Text(action.displayName).tag(action)
                        }
                    }
                }
                SettingsSeparator()
                SettingsButtonRow(
                    title: "Reset Controller Defaults",
                    systemImage: "arrow.counterclockwise",
                    tone: .danger,
                    isDestructive: true
                ) {
                    controllerManager.resetToDefaults()
                }
            }
        }
    }

    private var keyboardReferenceSections: some View {
        ForEach(shortcutCategories, id: \.category) { group in
            SettingsSectionHeader(title: "Keyboard · \(group.category)")
            SettingsGroup {
                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        SettingsSeparator()
                    }
                    HStack(spacing: AmgiSpacing.md) {
                        Text(item.title)
                            .amgiFont(.body)
                            .foregroundStyle(palette.textPrimary)
                        Spacer(minLength: AmgiSpacing.sm)
                        Text(item.keys)
                            .amgiFont(.captionBold, .monospaced)
                            .foregroundStyle(palette.textSecondary)
                            .padding(.horizontal, AmgiSpacing.sm)
                            .padding(.vertical, AmgiSpacing.xs)
                            .background(
                                palette.background,
                                in: RoundedRectangle(cornerRadius: AmgiRadius.small, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: AmgiRadius.small, style: .continuous)
                                    .strokeBorder(palette.separator, lineWidth: 1)
                            }
                    }
                    .padding(.horizontal, AmgiSpacing.lg)
                    .padding(.vertical, AmgiSpacing.md)
                    .frame(minHeight: 44)
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ShortcutsSettingsView()
    }
}
#endif
