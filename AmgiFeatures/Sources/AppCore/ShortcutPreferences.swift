//
//  ShortcutPreferences.swift
//  AppCore
//
//  Created by Amgi Contributors.
//

public import Foundation

public enum ReviewShortcutAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case showAnswerOrGood
    case showAnswer
    case answerAgain
    case answerHard
    case answerGood
    case answerEasy
    case undo
    case replayAudio
    case editNote
    case toggleMark
    case buryCard
    case buryNote
    case suspendCard
    case suspendNote
    case reschedule
    case changeDeck
    case deleteNote
    case flagRed
    case flagOrange
    case flagGreen
    case flagBlue
    case flagPink
    case flagCyan
    case flagPurple
    case clearFlag
    case toggleWhiteboard
    case clearWhiteboard
    case scrollDown
    case scrollUp
    case closeReview

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: "Disabled"
        case .showAnswerOrGood: "Show Answer / Good"
        case .showAnswer: "Show Answer"
        case .answerAgain: "Answer: Again (1)"
        case .answerHard: "Answer: Hard (2)"
        case .answerGood: "Answer: Good (3)"
        case .answerEasy: "Answer: Easy (4)"
        case .undo: "Undo"
        case .replayAudio: "Replay / Stop Audio"
        case .editNote: "Edit Note"
        case .toggleMark: "Mark / Unmark Note"
        case .buryCard: "Bury / Unbury Card"
        case .buryNote: "Bury Note"
        case .suspendCard: "Suspend / Unsuspend Card"
        case .suspendNote: "Suspend Note"
        case .reschedule: "Reschedule (Set Due Date)"
        case .changeDeck: "Change Deck"
        case .deleteNote: "Delete Note"
        case .flagRed: "Flag: Red"
        case .flagOrange: "Flag: Orange"
        case .flagGreen: "Flag: Green"
        case .flagBlue: "Flag: Blue"
        case .flagPink: "Flag: Pink"
        case .flagCyan: "Flag: Cyan"
        case .flagPurple: "Flag: Purple"
        case .clearFlag: "Clear Flag"
        case .toggleWhiteboard: "Toggle Whiteboard"
        case .clearWhiteboard: "Clear Whiteboard"
        case .scrollDown: "Scroll Card Down"
        case .scrollUp: "Scroll Card Up"
        case .closeReview: "Close Review"
        }
    }

    public var symbolName: String {
        switch self {
        case .none: "nosign"
        case .showAnswerOrGood, .showAnswer: "rectangle.portrait.and.arrow.right"
        case .answerAgain: "1.circle"
        case .answerHard: "2.circle"
        case .answerGood: "3.circle"
        case .answerEasy: "4.circle"
        case .undo: "arrow.uturn.backward"
        case .replayAudio: "play.circle"
        case .editNote: "pencil"
        case .toggleMark: "star"
        case .buryCard, .buryNote: "moon.zzz"
        case .suspendCard, .suspendNote: "pause.circle"
        case .reschedule: "calendar"
        case .changeDeck: "folder"
        case .deleteNote: "trash"
        case .flagRed, .flagOrange, .flagGreen, .flagBlue, .flagPink, .flagCyan, .flagPurple: "flag.fill"
        case .clearFlag: "flag.slash"
        case .toggleWhiteboard: "pencil.tip.crop.circle"
        case .clearWhiteboard: "eraser"
        case .scrollDown: "arrow.down"
        case .scrollUp: "arrow.up"
        case .closeReview: "xmark.circle"
        }
    }

    public var flagValue: UInt32? {
        switch self {
        case .flagRed: 1
        case .flagOrange: 2
        case .flagGreen: 3
        case .flagBlue: 4
        case .flagPink: 5
        case .flagCyan: 6
        case .flagPurple: 7
        case .clearFlag: 0
        default: nil
        }
    }
}

public enum GamepadInput: String, CaseIterable, Identifiable, Codable, Sendable {
    case buttonA
    case buttonB
    case buttonX
    case buttonY
    case leftShoulder
    case rightShoulder
    case leftTrigger
    case rightTrigger
    case dpadUp
    case dpadDown
    case dpadLeft
    case dpadRight
    case buttonMenu
    case buttonOptions
    case leftThumbstickButton
    case rightThumbstickButton

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .buttonA: "A / Cross (Bottom)"
        case .buttonB: "B / Circle (Right)"
        case .buttonX: "X / Square (Left)"
        case .buttonY: "Y / Triangle (Top)"
        case .leftShoulder: "L1 / LB (Left Bumper)"
        case .rightShoulder: "R1 / RB (Right Bumper)"
        case .leftTrigger: "L2 / LT (Left Trigger)"
        case .rightTrigger: "R2 / RT (Right Trigger)"
        case .dpadUp: "D-Pad Up"
        case .dpadDown: "D-Pad Down"
        case .dpadLeft: "D-Pad Left"
        case .dpadRight: "D-Pad Right"
        case .buttonMenu: "Menu / Start (+)"
        case .buttonOptions: "Options / Select (−)"
        case .leftThumbstickButton: "L3 (Left Stick Click)"
        case .rightThumbstickButton: "R3 (Right Stick Click)"
        }
    }

    public var symbolName: String {
        switch self {
        case .buttonA: "a.circle"
        case .buttonB: "b.circle"
        case .buttonX: "x.circle"
        case .buttonY: "y.circle"
        case .leftShoulder: "l1.rectangle.roundedbottom"
        case .rightShoulder: "r1.rectangle.roundedbottom"
        case .leftTrigger: "l2.rectangle.roundedtop"
        case .rightTrigger: "r2.rectangle.roundedtop"
        case .dpadUp: "dpad.up.filled"
        case .dpadDown: "dpad.down.filled"
        case .dpadLeft: "dpad.left.filled"
        case .dpadRight: "dpad.right.filled"
        case .buttonMenu: "line.3.horizontal.circle"
        case .buttonOptions: "ellipsis.circle"
        case .leftThumbstickButton: "l.joystick.press.down"
        case .rightThumbstickButton: "r.joystick.press.down"
        }
    }

    public var defaultAction: ReviewShortcutAction {
        switch self {
        case .buttonA: .showAnswerOrGood
        case .buttonB: .answerAgain
        case .buttonX: .answerHard
        case .buttonY: .answerEasy
        case .leftShoulder: .undo
        case .rightShoulder: .replayAudio
        case .leftTrigger: .scrollUp
        case .rightTrigger: .scrollDown
        case .dpadUp: .scrollUp
        case .dpadDown: .scrollDown
        case .dpadLeft: .undo
        case .dpadRight: .toggleMark
        case .buttonMenu: .toggleWhiteboard
        case .buttonOptions: .closeReview
        case .leftThumbstickButton: .buryCard
        case .rightThumbstickButton: .suspendCard
        }
    }
}

public struct DesktopShortcutInfo: Identifiable, Sendable {
    public let id: String
    public let category: String
    public let keys: String
    public let title: String

    public init(category: String, keys: String, title: String) {
        self.id = "\(category)|\(keys)|\(title)"
        self.category = category
        self.keys = keys
        self.title = title
    }
}

public enum ShortcutPreferences {
    public enum Keys {
        public static let keyboardShortcutsEnabled = "shortcuts_keyboard_enabled"
        public static let gamepadEnabled = "shortcuts_gamepad_enabled"
        public static let gamepadThumbstickScroll = "shortcuts_gamepad_thumbstick_scroll"
        public static let gamepadBindingsJSON = "shortcuts_gamepad_bindings_json"
    }

    public static func defaultGamepadBindings() -> [GamepadInput: ReviewShortcutAction] {
        var result: [GamepadInput: ReviewShortcutAction] = [:]
        for input in GamepadInput.allCases {
            result[input] = input.defaultAction
        }
        return result
    }

    public static func loadGamepadBindings(defaults: UserDefaults = .standard) -> [GamepadInput: ReviewShortcutAction] {
        var bindings = defaultGamepadBindings()
        guard let data = defaults.data(forKey: Keys.gamepadBindingsJSON),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else {
            return bindings
        }
        for (inputKey, actionRaw) in raw {
            if let input = GamepadInput(rawValue: inputKey),
               let action = ReviewShortcutAction(rawValue: actionRaw) {
                bindings[input] = action
            }
        }
        return bindings
    }

    public static func saveGamepadBindings(
        _ bindings: [GamepadInput: ReviewShortcutAction],
        defaults: UserDefaults = .standard
    ) {
        var raw: [String: String] = [:]
        for (input, action) in bindings {
            raw[input.rawValue] = action.rawValue
        }
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: Keys.gamepadBindingsJSON)
        }
    }

    public static func resetGamepadBindings(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: Keys.gamepadBindingsJSON)
    }

    public static let desktopShortcuts: [DesktopShortcutInfo] = [
        // Review
        DesktopShortcutInfo(category: "Review", keys: "Space / Return", title: "Show Answer / Answer Good"),
        DesktopShortcutInfo(category: "Review", keys: "1 / 2 / 3 / 4", title: "Again / Hard / Good / Easy"),
        DesktopShortcutInfo(category: "Review", keys: "Z / ⌘Z", title: "Undo Last Review or Action"),
        DesktopShortcutInfo(category: "Review", keys: "R", title: "Replay / Stop Audio"),
        DesktopShortcutInfo(category: "Review", keys: "↑ / ↓  or  K / J", title: "Scroll Card Up / Down"),
        DesktopShortcutInfo(category: "Review", keys: "D / Esc", title: "Close Review (Back to Decks)"),

        // Card Actions
        DesktopShortcutInfo(category: "Card Actions", keys: "E", title: "Edit Current Note"),
        DesktopShortcutInfo(category: "Card Actions", keys: "*", title: "Mark / Unmark Note"),
        DesktopShortcutInfo(category: "Card Actions", keys: "-", title: "Bury / Unbury Card"),
        DesktopShortcutInfo(category: "Card Actions", keys: "=", title: "Bury Note"),
        DesktopShortcutInfo(category: "Card Actions", keys: "@", title: "Suspend / Unsuspend Card"),
        DesktopShortcutInfo(category: "Card Actions", keys: "!", title: "Suspend Note"),
        DesktopShortcutInfo(category: "Card Actions", keys: "⌘⇧D", title: "Reschedule (Set Due Date)"),
        DesktopShortcutInfo(category: "Card Actions", keys: "⌘D", title: "Change Deck"),
        DesktopShortcutInfo(category: "Card Actions", keys: "⌘⌫", title: "Delete Note"),

        // Flags
        DesktopShortcutInfo(category: "Flags", keys: "⌘1 – ⌘7", title: "Toggle Flag (Red – Purple)"),
        DesktopShortcutInfo(category: "Flags", keys: "⌘0", title: "Clear Card Flag"),

        // Whiteboard
        DesktopShortcutInfo(category: "Whiteboard", keys: "W", title: "Show / Hide Whiteboard"),
        DesktopShortcutInfo(category: "Whiteboard", keys: "⇧W", title: "Clear Whiteboard Ink"),

        // Card Viewer
        DesktopShortcutInfo(category: "Card Viewer", keys: "← / →", title: "Previous / Next Card"),
        DesktopShortcutInfo(category: "Card Viewer", keys: "Space / Return", title: "Flip Question / Answer"),

        // Global Navigation
        DesktopShortcutInfo(category: "Global Navigation", keys: "D  or  ⌘1", title: "Go to Decks (Library)"),
        DesktopShortcutInfo(category: "Global Navigation", keys: "B  or  ⌘2", title: "Go to Browse"),
        DesktopShortcutInfo(category: "Global Navigation", keys: "S  or  ⌘3", title: "Go to Study"),
        DesktopShortcutInfo(category: "Global Navigation", keys: "⌘4", title: "Go to Stats"),
        DesktopShortcutInfo(category: "Global Navigation", keys: "⌘,", title: "Go to Settings"),
        DesktopShortcutInfo(category: "Global Navigation", keys: "A", title: "Add New Note"),
        DesktopShortcutInfo(category: "Global Navigation", keys: "Y  or  ⌘Y", title: "Sync Collection"),
        DesktopShortcutInfo(category: "Global Navigation", keys: "⌘F", title: "Focus Search (in Browse)"),
    ]
}
