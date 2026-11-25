//
//  WhiteboardInkColor.swift
//  ReviewFeature
//
//  Created by Amgi Contributors.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// User-selectable ink and highlighter swatches for the Whiteboard.
/// Exempt in `DesignConformanceTests` because these represent physical pen
/// pigments rather than app chrome.
enum WhiteboardInkColor: String, CaseIterable, Identifiable, Sendable {
    case adaptive
    case royalBlue
    case crimson
    case emerald
    case amber
    case violet
    case highlightYellow
    case highlightMint
    case highlightPink
    case highlightSky

    var id: String { rawValue }

    var label: String {
        switch self {
        case .adaptive: "Ink"
        case .royalBlue: "Blue"
        case .crimson: "Red"
        case .emerald: "Green"
        case .amber: "Amber"
        case .violet: "Purple"
        case .highlightYellow: "Yellow"
        case .highlightMint: "Mint"
        case .highlightPink: "Pink"
        case .highlightSky: "Sky"
        }
    }

    static var penSwatches: [WhiteboardInkColor] {
        [.adaptive, .royalBlue, .crimson, .emerald, .amber, .violet]
    }

    static var highlighterSwatches: [WhiteboardInkColor] {
        [.highlightYellow, .highlightMint, .highlightPink, .highlightSky]
    }

    static func resolved(_ id: String, forHighlighter: Bool = false) -> WhiteboardInkColor {
        if let found = WhiteboardInkColor(rawValue: id) {
            return found
        }
        return forHighlighter ? .highlightYellow : .adaptive
    }

    func swiftUIColor(isDark: Bool) -> Color {
        switch self {
        case .adaptive:
            return isDark ? Color(red: 0.94, green: 0.94, blue: 0.96) : Color(red: 0.10, green: 0.11, blue: 0.13)
        case .royalBlue:
            return isDark ? Color(red: 0.38, green: 0.65, blue: 1.0) : Color(red: 0.11, green: 0.39, blue: 0.93)
        case .crimson:
            return isDark ? Color(red: 1.0, green: 0.42, blue: 0.42) : Color(red: 0.86, green: 0.15, blue: 0.15)
        case .emerald:
            return isDark ? Color(red: 0.30, green: 0.85, blue: 0.52) : Color(red: 0.08, green: 0.50, blue: 0.24)
        case .amber:
            return isDark ? Color(red: 0.98, green: 0.72, blue: 0.24) : Color(red: 0.85, green: 0.47, blue: 0.02)
        case .violet:
            return isDark ? Color(red: 0.72, green: 0.54, blue: 1.0) : Color(red: 0.49, green: 0.23, blue: 0.93)
        case .highlightYellow:
            return Color(red: 0.98, green: 0.80, blue: 0.08)
        case .highlightMint:
            return Color(red: 0.29, green: 0.87, blue: 0.50)
        case .highlightPink:
            return Color(red: 0.96, green: 0.45, blue: 0.71)
        case .highlightSky:
            return Color(red: 0.22, green: 0.74, blue: 0.97)
        }
    }

    #if canImport(UIKit)
    func uiColor(isDark: Bool, alpha: CGFloat = 1.0) -> UIColor {
        UIColor(swiftUIColor(isDark: isDark)).withAlphaComponent(alpha)
    }
    #endif
}
