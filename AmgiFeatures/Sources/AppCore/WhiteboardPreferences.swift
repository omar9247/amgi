//
//  WhiteboardPreferences.swift
//  AppCore
//
//  Created by Amgi Contributors.
//

public enum WhiteboardInkStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case fountain
    case ballpoint
    case brush
    case highlighter

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fountain: "Fountain"
        case .ballpoint: "Ballpoint"
        case .brush: "Brush"
        case .highlighter: "Highlighter"
        }
    }

    public var symbolName: String {
        switch self {
        case .fountain: "pencil.tip"
        case .ballpoint: "pencil"
        case .brush: "paintbrush.pointed"
        case .highlighter: "highlighter"
        }
    }

    public var isHighlighter: Bool { self == .highlighter }
}

public enum WhiteboardEraserMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case stroke
    case pixel

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .stroke: "Stroke Eraser"
        case .pixel: "Precision Eraser"
        }
    }
}

public enum WhiteboardBackgroundMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case transparent
    case scratchpadBlank
    case scratchpadGrid
    case scratchpadLined

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .transparent: "Card Overlay"
        case .scratchpadBlank: "Blank Pad"
        case .scratchpadGrid: "Dot Grid"
        case .scratchpadLined: "Ruled Lines"
        }
    }

    public var symbolName: String {
        switch self {
        case .transparent: "square.on.square.dashed"
        case .scratchpadBlank: "rectangle"
        case .scratchpadGrid: "square.grid.3x3"
        case .scratchpadLined: "line.3.horizontal"
        }
    }
}

public enum WhiteboardPreferences {
    public enum Keys {
        public static let enabledByDefault = "whiteboard_pref_enabled_by_default"
        public static let inkStyle = "whiteboard_pref_ink_style"
        public static let stability = "whiteboard_pref_stability"
        public static let strokeWidth = "whiteboard_pref_stroke_width"
        public static let highlighterWidth = "whiteboard_pref_highlighter_width"
        public static let inkColorId = "whiteboard_pref_ink_color_id"
        public static let stylusOnly = "whiteboard_pref_stylus_only"
        public static let eraserMode = "whiteboard_pref_eraser_mode"
        public static let backgroundMode = "whiteboard_pref_background_mode"
        public static let persistPerCard = "whiteboard_pref_persist_per_card"
    }
}
