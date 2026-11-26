//
//  CardContextMenu.swift
//  AppShared
//
//  Created by Vladimir Gusev on 29.04.2026.
//

public import SwiftUI
import Theme
import AppCore
public import AnkiKit

// MARK: - Menu content

/// The eight flags as an inline palette row rather than a submenu — the same
/// shape Mail and Reminders use for flags and tags. One tap instead of two,
/// and the current flag reads as a selection instead of a nested label.
@MainActor
public struct CardFlagPicker: View {
    let model: CardContextMenuModel
    let cardId: CardID
    var onAction: (_ shouldAdvance: Bool) -> Void

    public init(
        model: CardContextMenuModel,
        cardId: CardID,
        onAction: @escaping (_ shouldAdvance: Bool) -> Void
    ) {
        self.model = model
        self.cardId = cardId
        self.onAction = onAction
    }

    public var body: some View {
        let selectedFlag = model.currentFlag & 0b111
        Section {
            Picker("Flag", selection: Binding(
                get: { selectedFlag },
                set: { value in
                    Task {
                        if let advance = await model.flag(cardId, value) { onAction(advance) }
                    }
                }
            )) {
                ForEach(CardFlag.all, id: \.self) { value in
                    Label(CardFlag.name(value), systemImage: CardFlag.symbol(value))
                        .tint(CardFlag.color(value))
                        .tag(value)
                }
            }
            .pickerStyle(.palette)
        }
    }
}

/// Card and note operations as flat `Section`s — no submenus, so a host can
/// drop them straight into its own `Menu` without nesting. Card-scope and
/// note-scope actions are separated by section rather than by a "Note
/// actions ▸" submenu, and the one destructive action sits alone at the end.
///
/// The error alert, the delete confirmation, the reschedule / change-deck sheets,
/// and the initial state load live in `.cardActionPresentations`, which the host
/// applies *outside* the enclosing `Menu`.
@MainActor
public struct CardActionSections: View {
    let model: CardContextMenuModel
    let cardId: CardID
    var noteId: NoteID?
    @Binding var confirmDeleteNote: Bool
    var onAction: (_ shouldAdvance: Bool) -> Void

    public init(
        model: CardContextMenuModel,
        cardId: CardID,
        noteId: NoteID? = nil,
        confirmDeleteNote: Binding<Bool>,
        onAction: @escaping (_ shouldAdvance: Bool) -> Void
    ) {
        self.model = model
        self.cardId = cardId
        self.noteId = noteId
        self._confirmDeleteNote = confirmDeleteNote
        self.onAction = onAction
    }

    public var body: some View {
        let isSuspended = model.isSuspended
        let isBuried = model.isBuried
        let isMarked = model.isMarkedNote

        Section {
            Button { act { await model.toggleSuspend(cardId) } } label: {
                Label(
                    isSuspended ? "Unsuspend Card" : "Suspend Card",
                    systemImage: isSuspended ? "play.circle" : "pause.circle"
                )
            }
            Button { act { await model.toggleBury(cardId) } } label: {
                Label(
                    isBuried ? "Unbury Card" : "Bury Card Until Tomorrow",
                    systemImage: isBuried ? "sun.max" : "moon.zzz"
                )
            }
            Button { model.requestReschedule([cardId]) } label: {
                Label("Reschedule…", systemImage: "calendar.badge.clock")
            }
            Button { model.requestChangeDeck([cardId]) } label: {
                Label("Change Deck…", systemImage: "folder")
            }
            Button { act { await model.resetToNew(cardId) } } label: {
                Label("Forget Card", systemImage: "arrow.counterclockwise")
            }
        }

        if let noteId {
            Section {
                Button { act { await model.toggleMarked(noteId) } } label: {
                    Label(
                        isMarked ? "Unmark Note" : "Mark Note",
                        systemImage: isMarked ? "star.slash" : "star"
                    )
                }
                Button { act { await model.suspendNote(noteId) } } label: {
                    Label("Suspend Note", systemImage: "pause.circle.fill")
                }
                Button { act { await model.buryNote(noteId) } } label: {
                    Label("Bury Note", systemImage: "moon.zzz.fill")
                }
            }

            Section {
                Button(role: .destructive) {
                    model.presentAfterMenuDismiss {
                        confirmDeleteNote = true
                    }
                } label: {
                    Label("Delete Note", systemImage: "trash")
                }
            }
        }
    }

    /// Run a model action and forward its outcome. `nil` means the action
    /// failed and the model already raised the error alert.
    private func act(_ body: @escaping () async -> Bool?) {
        Task { if let shouldAdvance = await body() { onAction(shouldAdvance) } }
    }
}

// MARK: - Presentations

extension View {
    /// Error alert, delete confirmation, reschedule/change-deck sheets, and
    /// initial load for `CardActionSections`/`CardFlagPicker`. Apply this to
    /// the view that *hosts* the `Menu`, never inside the menu's content.
    @MainActor
    public func cardActionPresentations(
        model: CardContextMenuModel,
        cardId: CardID?,
        noteId: NoteID?,
        confirmDeleteNote: Binding<Bool>,
        onAction: @escaping (_ shouldAdvance: Bool) -> Void
    ) -> some View {
        modifier(CardActionPresentations(
            model: model,
            cardId: cardId,
            noteId: noteId,
            confirmDeleteNote: confirmDeleteNote,
            onAction: onAction
        ))
    }
}

private struct CardActionPresentations: ViewModifier {
    @Bindable var model: CardContextMenuModel
    let cardId: CardID?
    let noteId: NoteID?
    @Binding var confirmDeleteNote: Bool
    let onAction: (_ shouldAdvance: Bool) -> Void

    func body(content: Content) -> some View {
        content
            .alert("Action failed", isPresented: $model.showError) {
                Button("OK") { }
            } message: {
                Text(model.errorMessage ?? "An unknown error occurred.")
            }
            .confirmationDialog(
                "Delete this note?",
                isPresented: $confirmDeleteNote,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    guard let noteId else { return }
                    Task {
                        if let advance = await model.deleteNote(noteId) { onAction(advance) }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This deletes the note and all its cards. The action cannot be undone.")
            }
            .sheet(item: $model.activeSheet) { target in
                switch target {
                case .reschedule(let ids):
                    RescheduleCardSheet(cardIds: ids) { spec in
                        let error = await model.reschedule(ids, spec: spec)
                        if error == nil { onAction(true) }
                        return error
                    }
                case .changeDeck(let ids, let deckId):
                    ChangeDeckSheet(cardIds: ids, currentDeckId: deckId) { newDeckId in
                        let error = await model.changeDeck(ids, to: newDeckId)
                        if error == nil { onAction(true) }
                        return error
                    }
                }
            }
            .task(id: cardId) {
                await model.load(cardId: cardId, noteId: noteId)
            }
    }
}

// MARK: - Standalone button

/// Self-contained `…` button wrapping the card actions — used by Browse rows
/// or standalone hosts.
@MainActor
public struct CardContextMenu: View {
    let cardId: CardID
    var noteId: NoteID?
    var onSuccess: (() -> Void)?
    var onActionSuccess: ((_ shouldAdvance: Bool) -> Void)?

    @State private var model = CardContextMenuModel()
    @State private var confirmDeleteNote = false

    public init(
        cardId: CardID,
        noteId: NoteID? = nil,
        onSuccess: (() -> Void)? = nil,
        onActionSuccess: ((_ shouldAdvance: Bool) -> Void)? = nil
    ) {
        self.cardId = cardId
        self.noteId = noteId
        self.onSuccess = onSuccess
        self.onActionSuccess = onActionSuccess
    }

    public var body: some View {
        Menu {
            CardFlagPicker(model: model, cardId: cardId, onAction: forward)
            CardActionSections(
                model: model,
                cardId: cardId,
                noteId: noteId,
                confirmDeleteNote: $confirmDeleteNote,
                onAction: forward
            )
            Section {
                Button {
                    Task { if let advance = await model.undo(cardId) { forward(advance) } }
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!model.canUndo || model.isUndoing)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .amgiFont(.bodyEmphasis)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Card actions")
        .cardActionPresentations(
            model: model,
            cardId: cardId,
            noteId: noteId,
            confirmDeleteNote: $confirmDeleteNote,
            onAction: forward
        )
    }

    private func forward(_ shouldAdvance: Bool) {
        onSuccess?()
        onActionSuccess?(shouldAdvance)
    }
}

/// Lightweight `…` menu button driven by a **host-owned** `CardContextMenuModel`.
/// Used in `List` rows (`BrowseView`) so `.cardActionPresentations(...)` lives
/// once on the outer list instead of duplicating alerts/sheets per cell.
@MainActor
public struct HostedCardContextMenu: View {
    let model: CardContextMenuModel
    let cardId: CardID
    var noteId: NoteID?
    var isSuspended: Bool = false
    var isBuried: Bool = false
    var onEditNote: (() -> Void)?
    var onRequestDeleteNote: ((NoteID) -> Void)?
    var onAction: ((_ shouldAdvance: Bool) -> Void)?

    public init(
        model: CardContextMenuModel,
        cardId: CardID,
        noteId: NoteID? = nil,
        isSuspended: Bool = false,
        isBuried: Bool = false,
        onEditNote: (() -> Void)? = nil,
        onRequestDeleteNote: ((NoteID) -> Void)? = nil,
        onAction: ((_ shouldAdvance: Bool) -> Void)? = nil
    ) {
        self.model = model
        self.cardId = cardId
        self.noteId = noteId
        self.isSuspended = isSuspended
        self.isBuried = isBuried
        self.onEditNote = onEditNote
        self.onRequestDeleteNote = onRequestDeleteNote
        self.onAction = onAction
    }

    public var body: some View {
        Menu {
            Menu {
                ForEach(CardFlag.all, id: \.self) { value in
                    Button {
                        Task { if let adv = await model.flag(cardId, value) { onAction?(adv) } }
                    } label: {
                        Label(CardFlag.name(value), systemImage: CardFlag.symbol(value))
                    }
                }
            } label: {
                Label("Flag", systemImage: "flag")
            }
            if let onEditNote {
                Section {
                    Button {
                        model.presentAfterMenuDismiss {
                            onEditNote()
                        }
                    } label: {
                        Label("Edit Note", systemImage: "pencil")
                    }
                }
            }
            Section {
                Button {
                    Task {
                        let adv = isSuspended
                            ? await model.unsuspendOrUnbury(cardId)
                            : await model.suspend(cardId)
                        if let adv { onAction?(adv) }
                    }
                } label: {
                    Label(
                        isSuspended ? "Unsuspend Card" : "Suspend Card",
                        systemImage: isSuspended ? "play.circle" : "pause.circle"
                    )
                }
                Button {
                    Task {
                        let adv = isBuried
                            ? await model.unsuspendOrUnbury(cardId)
                            : await model.bury(cardId)
                        if let adv { onAction?(adv) }
                    }
                } label: {
                    Label(
                        isBuried ? "Unbury Card" : "Bury Card",
                        systemImage: isBuried ? "sun.max" : "moon.zzz"
                    )
                }
                Button {
                    model.requestReschedule([cardId])
                } label: {
                    Label("Reschedule…", systemImage: "calendar.badge.clock")
                }
                Button {
                    model.requestChangeDeck([cardId])
                } label: {
                    Label("Change Deck…", systemImage: "folder")
                }
                Button {
                    Task { if let adv = await model.resetToNew(cardId) { onAction?(adv) } }
                } label: {
                    Label("Forget Card", systemImage: "arrow.counterclockwise")
                }
            }
            if let noteId {
                Section {
                    Button {
                        Task { if let adv = await model.suspendNote(noteId) { onAction?(adv) } }
                    } label: {
                        Label("Suspend Note", systemImage: "pause.circle.fill")
                    }
                    Button {
                        Task { if let adv = await model.buryNote(noteId) { onAction?(adv) } }
                    } label: {
                        Label("Bury Note", systemImage: "moon.zzz.fill")
                    }
                }
                if let onRequestDeleteNote {
                    Section {
                        Button(role: .destructive) {
                            model.presentAfterMenuDismiss {
                                onRequestDeleteNote(noteId)
                            }
                        } label: {
                            Label("Delete Note", systemImage: "trash")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .amgiFont(.bodyEmphasis)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Card actions")
    }
}

#if DEBUG

#Preview {
    VStack(spacing: 20) {
        Text("Tap the menu button below")
            .amgiFont(.bodyEmphasis)

        Spacer()

        HStack {
            Text("Card Menu:")
            CardContextMenu(
                cardId: CardID(12345),
                onSuccess: { print("Action succeeded") }
            )
        }

        Spacer()
    }
    .padding()
}
#endif
