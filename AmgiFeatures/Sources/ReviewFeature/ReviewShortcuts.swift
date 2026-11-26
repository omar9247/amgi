//
//  ReviewShortcuts.swift
//  ReviewFeature
//
//  Created by Amgi Contributors.
//

import AnkiKit
import AppCore
import AppShared
import ReviewCore
import SwiftUI

/// Desktop Anki keyboard shortcuts and hardware game controller bindings for
/// `ReviewContent`. Rating keys (`1`–`4`) live on `RatingBar`; `⌘Z` lives on
/// `ReviewUndoButton`; this modifier wires the remaining desktop Anki keys
/// (`Space`/`Return`, `Z`, `R`, `E`, `*`, `-`, `=`, `@`, `!`, `⌘1`–`⌘7`, `⌘0`,
/// `⌘⇧D`, `⌘D`, `⌘⌫`, `W`, `⇧W`, `↑`/`↓`/`J`/`K`, `D`/`Esc`) plus all
/// customizable `GameControllerManager` actions and analog-stick scrolling.
struct ReviewKeyboardAndGamepadShortcuts: ViewModifier {
    let session: ReviewSession
    let cardActions: CardContextMenuModel
    let whiteboard: WhiteboardState
    let scrollController: CardScrollController
    let keyboardShortcutsActive: Bool
    let gamepadShortcutsActive: Bool
    @Binding var destination: ReviewDestination?
    @Binding var confirmDeleteNote: Bool
    let onDismiss: @MainActor () -> Void

    @State private var gamepadToken: GameControllerManager.HandlerToken?

    private var canDispatchReviewInput: Bool {
        !session.isFinished && session.startError == nil
    }

    private var keyboardEnabled: Bool {
        keyboardShortcutsActive && canDispatchReviewInput
    }

    func body(content: Content) -> some View {
        content
            .background {
                shortcutButtons
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .onAppear {
                gamepadToken = GameControllerManager.shared.registerHandler(
                    onAction: { action in
                        guard gamepadShortcutsActive, canDispatchReviewInput else { return }
                        perform(action)
                    },
                    onScrollDelta: { delta in
                        guard gamepadShortcutsActive, canDispatchReviewInput else { return }
                        scrollController.scroll(by: delta)
                    }
                )
            }
            .onDisappear {
                if let token = gamepadToken {
                    GameControllerManager.shared.unregisterHandler(token)
                    gamepadToken = nil
                }
            }
    }

    @ViewBuilder
    private var shortcutButtons: some View {
        Group {
            shortcutButton("Show Answer / Good", key: .space) { perform(.showAnswerOrGood) }
            shortcutButton("Show Answer / Good (Return)", key: .return) { perform(.showAnswerOrGood) }
            shortcutButton("Undo", key: "z") { perform(.undo) }
            shortcutButton("Replay Audio", key: "r") { perform(.replayAudio) }
            shortcutButton("Edit Note", key: "e") { perform(.editNote) }
            shortcutButton("Mark Note", key: "*") { perform(.toggleMark) }
            shortcutButton("Bury Card", key: "-") { perform(.buryCard) }
            shortcutButton("Bury Note", key: "=") { perform(.buryNote) }
            shortcutButton("Suspend Card", key: "@") { perform(.suspendCard) }
            shortcutButton("Suspend Note", key: "!") { perform(.suspendNote) }
        }
        Group {
            shortcutButton("Scroll Card Down", key: .downArrow) { perform(.scrollDown) }
            shortcutButton("Scroll Card Down (J)", key: "j") { perform(.scrollDown) }
            shortcutButton("Scroll Card Up", key: .upArrow) { perform(.scrollUp) }
            shortcutButton("Scroll Card Up (K)", key: "k") { perform(.scrollUp) }
            shortcutButton("Toggle Whiteboard", key: "w") { perform(.toggleWhiteboard) }
            shortcutButton("Clear Whiteboard", key: "w", modifiers: .shift) { perform(.clearWhiteboard) }
            shortcutButton("Close Review", key: "d") { perform(.closeReview) }
            shortcutButton("Close Review (Escape)", key: .escape) { perform(.closeReview) }
        }
        Group {
            shortcutButton("Flag Red", key: "1", modifiers: .command) { perform(.flagRed) }
            shortcutButton("Flag Orange", key: "2", modifiers: .command) { perform(.flagOrange) }
            shortcutButton("Flag Green", key: "3", modifiers: .command) { perform(.flagGreen) }
            shortcutButton("Flag Blue", key: "4", modifiers: .command) { perform(.flagBlue) }
            shortcutButton("Flag Pink", key: "5", modifiers: .command) { perform(.flagPink) }
            shortcutButton("Flag Cyan", key: "6", modifiers: .command) { perform(.flagCyan) }
            shortcutButton("Flag Purple", key: "7", modifiers: .command) { perform(.flagPurple) }
            shortcutButton("Clear Flag", key: "0", modifiers: .command) { perform(.clearFlag) }
            shortcutButton("Reschedule Card", key: "d", modifiers: [.command, .shift]) { perform(.reschedule) }
            shortcutButton("Change Deck", key: "d", modifiers: .command) { perform(.changeDeck) }
            shortcutButton("Delete Note", key: .delete, modifiers: .command) { perform(.deleteNote) }
        }
    }

    private func shortcutButton(
        _ title: String,
        key: KeyEquivalent,
        modifiers: EventModifiers = [],
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .keyboardShortcut(keyboardEnabled ? KeyboardShortcut(key, modifiers: modifiers) : nil)
    }

    private func perform(_ action: ReviewShortcutAction) {
        switch action {
        case .none:
            break
        case .showAnswerOrGood:
            if !session.showAnswer {
                session.revealAnswer()
            } else if !session.isAdvancing {
                session.answer(rating: .good)
            }
        case .showAnswer:
            if !session.showAnswer {
                session.revealAnswer()
            }
        case .answerAgain:
            guard session.showAnswer, !session.isAdvancing else { return }
            session.answer(rating: .again)
        case .answerHard:
            guard session.showAnswer, !session.isAdvancing else { return }
            session.answer(rating: .hard)
        case .answerGood:
            guard session.showAnswer, !session.isAdvancing else { return }
            session.answer(rating: .good)
        case .answerEasy:
            guard session.showAnswer, !session.isAdvancing else { return }
            session.answer(rating: .easy)
        case .undo:
            if session.canUndoAny {
                session.undoAny()
            }
        case .replayAudio:
            if session.isAudioPlaying {
                session.bumpStopAudioRequest()
            } else {
                session.bumpReplayRequest()
            }
        case .editNote:
            if let note = session.currentNote {
                destination = .editNote(note)
            }
        case .toggleMark:
            if let noteId = session.currentNote?.id {
                Task { _ = await cardActions.toggleMarked(noteId) }
            }
        case .buryCard:
            if let cardId = session.currentCardId {
                Task {
                    if let shouldAdvance = await cardActions.toggleBury(cardId), shouldAdvance {
                        session.requeueAfterCardRemoval()
                    }
                }
            }
        case .buryNote:
            if let noteId = session.currentNote?.id {
                Task {
                    if let shouldAdvance = await cardActions.buryNote(noteId), shouldAdvance {
                        session.requeueAfterCardRemoval()
                    }
                }
            }
        case .suspendCard:
            if let cardId = session.currentCardId {
                Task {
                    if let shouldAdvance = await cardActions.toggleSuspend(cardId), shouldAdvance {
                        session.requeueAfterCardRemoval()
                    }
                }
            }
        case .suspendNote:
            if let noteId = session.currentNote?.id {
                Task {
                    if let shouldAdvance = await cardActions.suspendNote(noteId), shouldAdvance {
                        session.requeueAfterCardRemoval()
                    }
                }
            }
        case .reschedule:
            if let cardId = session.currentCardId {
                cardActions.activeSheet = .reschedule([cardId])
            }
        case .changeDeck:
            if let cardId = session.currentCardId {
                cardActions.activeSheet = .changeDeck(cardIds: [cardId], currentDeckId: cardActions.currentDeckId)
            }
        case .deleteNote:
            if session.currentNote != nil {
                confirmDeleteNote = true
            }
        case .flagRed, .flagOrange, .flagGreen, .flagBlue, .flagPink, .flagCyan, .flagPurple:
            guard let cardId = session.currentCardId, let flagVal = action.flagValue else { return }
            let next: UInt32 = cardActions.currentFlag == flagVal ? 0 : flagVal
            Task { _ = await cardActions.flag(cardId, next) }
        case .clearFlag:
            guard let cardId = session.currentCardId else { return }
            Task { _ = await cardActions.flag(cardId, 0) }
        case .toggleWhiteboard:
            whiteboard.toggleOpen()
        case .clearWhiteboard:
            if whiteboard.isOpen {
                whiteboard.clear()
            }
        case .scrollDown:
            scrollController.scroll(by: 180)
        case .scrollUp:
            scrollController.scroll(by: -180)
        case .closeReview:
            onDismiss()
        }
    }
}
