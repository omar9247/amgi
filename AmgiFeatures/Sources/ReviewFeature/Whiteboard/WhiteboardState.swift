//
//  WhiteboardState.swift
//  ReviewFeature
//
//  Created by Amgi Contributors.
//

import AnkiKit
import AppCore
import CoreGraphics
import Foundation
import Observation

@Observable
@MainActor
final class WhiteboardState {
    var isOpen: Bool
    /// When false while `isOpen` is true, ink stays visible on the card while
    /// all finger/scroll/tap gestures pass straight through to the card below.
    var isDrawingActive: Bool = true
    var isInkHidden: Bool = false
    var isEraserSelected: Bool = false

    var strokes: [InkStroke] = []
    var redoStack: [InkStroke] = []
    private(set) var revision: Int = 0
    private(set) var activeCardId: CardID?

    var inkStyle: WhiteboardInkStyle {
        didSet { defaults.set(inkStyle.rawValue, forKey: WhiteboardPreferences.Keys.inkStyle) }
    }
    var stability: Double {
        didSet { defaults.set(stability, forKey: WhiteboardPreferences.Keys.stability) }
    }
    var strokeWidth: Double {
        didSet { defaults.set(strokeWidth, forKey: WhiteboardPreferences.Keys.strokeWidth) }
    }
    var highlighterWidth: Double {
        didSet { defaults.set(highlighterWidth, forKey: WhiteboardPreferences.Keys.highlighterWidth) }
    }
    var inkColorId: String {
        didSet { defaults.set(inkColorId, forKey: WhiteboardPreferences.Keys.inkColorId) }
    }
    var stylusOnly: Bool {
        didSet { defaults.set(stylusOnly, forKey: WhiteboardPreferences.Keys.stylusOnly) }
    }
    var eraserMode: WhiteboardEraserMode {
        didSet { defaults.set(eraserMode.rawValue, forKey: WhiteboardPreferences.Keys.eraserMode) }
    }
    var backgroundMode: WhiteboardBackgroundMode {
        didSet { defaults.set(backgroundMode.rawValue, forKey: WhiteboardPreferences.Keys.backgroundMode) }
    }
    var persistPerCard: Bool {
        didSet {
            defaults.set(persistPerCard, forKey: WhiteboardPreferences.Keys.persistPerCard)
            if persistPerCard, let activeCardId {
                WhiteboardAnnotationStore.save(strokes, for: activeCardId)
            }
        }
    }

    var canUndo: Bool { !strokes.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var activeWidth: Double {
        get { inkStyle.isHighlighter ? highlighterWidth : strokeWidth }
        set {
            if inkStyle.isHighlighter {
                highlighterWidth = newValue
            } else {
                strokeWidth = newValue
            }
        }
    }

    var activeSwatch: WhiteboardInkColor {
        WhiteboardInkColor.resolved(inkColorId, forHighlighter: inkStyle.isHighlighter)
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let openByDefault = defaults.bool(forKey: WhiteboardPreferences.Keys.enabledByDefault)
        self.isOpen = openByDefault
        self.inkStyle = defaults.string(forKey: WhiteboardPreferences.Keys.inkStyle)
            .flatMap(WhiteboardInkStyle.init(rawValue:)) ?? .fountain
        if defaults.object(forKey: WhiteboardPreferences.Keys.stability) != nil {
            self.stability = min(max(defaults.double(forKey: WhiteboardPreferences.Keys.stability), 0), 1)
        } else {
            self.stability = 0.45
        }
        let penW = defaults.double(forKey: WhiteboardPreferences.Keys.strokeWidth)
        self.strokeWidth = penW > 0 ? penW : 3.2
        let hiW = defaults.double(forKey: WhiteboardPreferences.Keys.highlighterWidth)
        self.highlighterWidth = hiW > 0 ? hiW : 18.0
        self.inkColorId = defaults.string(forKey: WhiteboardPreferences.Keys.inkColorId) ?? WhiteboardInkColor.adaptive.rawValue
        self.stylusOnly = defaults.bool(forKey: WhiteboardPreferences.Keys.stylusOnly)
        self.eraserMode = defaults.string(forKey: WhiteboardPreferences.Keys.eraserMode)
            .flatMap(WhiteboardEraserMode.init(rawValue:)) ?? .stroke
        self.backgroundMode = defaults.string(forKey: WhiteboardPreferences.Keys.backgroundMode)
            .flatMap(WhiteboardBackgroundMode.init(rawValue:)) ?? .transparent
        self.persistPerCard = defaults.bool(forKey: WhiteboardPreferences.Keys.persistPerCard)
    }

    func toggleOpen() {
        isOpen.toggle()
        if isOpen {
            isDrawingActive = true
            isInkHidden = false
        }
    }

    func selectStyle(_ style: WhiteboardInkStyle) {
        let wasHighlighter = inkStyle.isHighlighter
        inkStyle = style
        isEraserSelected = false
        isDrawingActive = true
        // Auto-switch between pen colors and highlighter tints when crossing the boundary
        if !wasHighlighter && style.isHighlighter && !WhiteboardInkColor.highlighterSwatches.contains(activeSwatch) {
            inkColorId = WhiteboardInkColor.highlightYellow.rawValue
        } else if wasHighlighter && !style.isHighlighter && !WhiteboardInkColor.penSwatches.contains(activeSwatch) {
            inkColorId = WhiteboardInkColor.adaptive.rawValue
        }
    }

    func commitStroke(_ stroke: InkStroke) {
        guard !stroke.samples.isEmpty else { return }
        strokes.append(stroke)
        redoStack.removeAll()
        revision += 1
        saveIfNeeded()
    }

    func erase(at point: CGPoint, in canvasSize: CGSize) {
        guard !strokes.isEmpty else { return }
        var changed = false
        switch eraserMode {
        case .stroke:
            let before = strokes.count
            strokes.removeAll { WhiteboardInkGeometry.hitTest(stroke: $0, point: point, in: canvasSize) }
            changed = strokes.count != before
        case .pixel:
            var next: [InkStroke] = []
            next.reserveCapacity(strokes.count)
            for stroke in strokes {
                let split = WhiteboardInkGeometry.splitStroke(stroke, erasingAt: point, radius: 14, in: canvasSize)
                if split.count != 1 || split.first?.id != stroke.id {
                    changed = true
                }
                next.append(contentsOf: split)
            }
            if changed { strokes = next }
        }
        if changed {
            redoStack.removeAll()
            revision += 1
            saveIfNeeded()
        }
    }

    func undo() {
        guard let last = strokes.popLast() else { return }
        redoStack.append(last)
        revision += 1
        saveIfNeeded()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        strokes.append(next)
        revision += 1
        saveIfNeeded()
    }

    func clear() {
        guard !strokes.isEmpty else { return }
        strokes.removeAll()
        redoStack.removeAll()
        revision += 1
        saveIfNeeded()
    }

    func switchToCard(_ cardId: CardID?) {
        guard cardId != activeCardId else { return }
        if persistPerCard, let prev = activeCardId {
            WhiteboardAnnotationStore.save(strokes, for: prev)
        }
        activeCardId = cardId
        redoStack.removeAll()
        if persistPerCard, let cardId {
            strokes = WhiteboardAnnotationStore.load(cardId: cardId)
        } else {
            strokes.removeAll()
        }
        revision += 1
    }

    private func saveIfNeeded() {
        guard persistPerCard, let activeCardId else { return }
        WhiteboardAnnotationStore.save(strokes, for: activeCardId)
    }
}
