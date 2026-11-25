//
//  CardContextMenuModel.swift
//  AppShared
//
//  Created by Vladimir Gusev on 27.06.2026.
//

import AnkiClients
public import AnkiKit
import Dependencies
import Foundation
public import Observation

public enum CardActionSheetTarget: Identifiable, Equatable, Sendable {
    case reschedule([CardID])
    case changeDeck(cardIds: [CardID], currentDeckId: DeckID?)

    public var id: String {
        switch self {
        case .reschedule(let ids):
            "reschedule-\(ids.map(\.rawValue).map(String.init).joined(separator: ","))"
        case .changeDeck(let ids, _):
            "changeDeck-\(ids.map(\.rawValue).map(String.init).joined(separator: ","))"
        }
    }
}

/// Card-operation I/O for `CardContextMenu`. Owns the card/note/tag clients
/// and the loaded display state (marked, current flag, queue state, undo availability)
/// plus the error-alert / sheet state so the menu carries no `@Dependency`.
///
/// `cardId`/`noteId` are **not** captured — the menu is a reused leaf whose
/// ids vary per use, so every action takes them as parameters and returns
/// `shouldAdvance` (`nil` on failure, with the error surfaced on the model);
/// the view forwards `onSuccess`/`onActionSuccess`.
@Observable
@MainActor
public final class CardContextMenuModel {
    public var isMarkedNote = false
    public var currentFlag: UInt32 = 0
    public var cardQueue: Int16 = 0
    public var currentDeckId: DeckID?
    public var canUndo = false
    public var isUndoing = false
    public var errorMessage: String?
    public var showError = false
    public var activeSheet: CardActionSheetTarget?

    public var isSuspended: Bool { cardQueue == -1 }
    public var isBuried: Bool { cardQueue == -2 || cardQueue == -3 }

    @ObservationIgnored @Dependency(\.cardClient) private var cardClient
    @ObservationIgnored @Dependency(\.noteClient) private var noteClient
    @ObservationIgnored @Dependency(\.tagClient) private var tagClient

    public init() {}

    // MARK: - Deferred sheet / dialog helper

    /// Yields past UIKit's `UIMenu` dismissal transition so SwiftUI sheet/alert
    /// presentations triggered from inside a `Menu` button are never dropped.
    public func presentAfterMenuDismiss(_ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            work()
        }
    }

    public func requestReschedule(_ cardIds: [CardID]) {
        guard !cardIds.isEmpty else { return }
        presentAfterMenuDismiss { [weak self] in
            self?.activeSheet = .reschedule(cardIds)
        }
    }

    public func requestChangeDeck(_ cardIds: [CardID]) {
        guard !cardIds.isEmpty else { return }
        let deckId = currentDeckId
        presentAfterMenuDismiss { [weak self] in
            self?.activeSheet = .changeDeck(cardIds: cardIds, currentDeckId: deckId)
        }
    }

    // MARK: - Actions (return shouldAdvance on success, nil on failure)

    public func suspend(_ cardId: CardID) async -> Bool? {
        await run("Suspend failed") {
            try await cardClient.suspend(cardId)
            cardQueue = -1
            return true
        }
    }

    public func unsuspendOrUnbury(_ cardId: CardID) async -> Bool? {
        await run("Restore card failed") {
            try await cardClient.unsuspendOrUnbury([cardId])
            cardQueue = 0
            return true
        }
    }

    public func toggleSuspend(_ cardId: CardID) async -> Bool? {
        isSuspended ? await unsuspendOrUnbury(cardId) : await suspend(cardId)
    }

    public func bury(_ cardId: CardID) async -> Bool? {
        await run("Bury failed") {
            try await cardClient.bury(cardId)
            cardQueue = -3
            return true
        }
    }

    public func toggleBury(_ cardId: CardID) async -> Bool? {
        isBuried ? await unsuspendOrUnbury(cardId) : await bury(cardId)
    }

    public func resetToNew(_ cardId: CardID) async -> Bool? {
        await run("Forget failed") {
            try await cardClient.resetToNew(cardId)
            cardQueue = 0
            return true
        }
    }

    public func setDueDate(_ cardId: CardID, _ spec: String) async -> Bool? {
        let trimmed = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setError("Please enter a valid number of days.")
            return nil
        }
        return await run("Set due date failed") {
            try await cardClient.setDueDate(cardId, trimmed)
            return true
        }
    }

    /// Batch reschedule helper used by `RescheduleCardSheet`. Returns `nil` on
    /// success or a human-readable error message on failure.
    public func reschedule(_ cardIds: [CardID], spec: String) async -> String? {
        let trimmed = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !cardIds.isEmpty else {
            return "Please enter a valid number of days."
        }
        do {
            try await cardClient.setDueDateBatch(cardIds, trimmed)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Moves the given cards to `deckId`. Returns `nil` on success or an error
    /// message for `ChangeDeckSheet`.
    public func changeDeck(_ cardIds: [CardID], to deckId: DeckID) async -> String? {
        guard !cardIds.isEmpty else { return nil }
        do {
            try await cardClient.setDeck(cardIds, deckId)
            currentDeckId = deckId
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    public func deleteNote(_ noteId: NoteID) async -> Bool? {
        await run("Delete note failed") {
            try await noteClient.delete(noteId)
            return true
        }
    }

    public func toggleMarked(_ noteId: NoteID) async -> Bool? {
        await run("Mark note failed") {
            if isMarkedNote {
                try await tagClient.removeTagFromNotes(markedTag, [noteId])
            } else {
                try await tagClient.addTagToNotes(markedTag, [noteId])
            }
            isMarkedNote.toggle()
            return false
        }
    }

    public func suspendNote(_ noteId: NoteID) async -> Bool? {
        await noteAction(noteId, "Suspend note failed") { try await cardClient.suspend($0) }
    }

    public func buryNote(_ noteId: NoteID) async -> Bool? {
        await noteAction(noteId, "Bury note failed") { try await cardClient.bury($0) }
    }

    public func flag(_ cardId: CardID, _ value: UInt32) async -> Bool? {
        await run("Flag failed") {
            try await cardClient.flag(cardId, value)
            currentFlag = value
            return false
        }
    }

    public func undo(_ cardId: CardID) async -> Bool? {
        guard !isUndoing, canUndo else { return nil }
        isUndoing = true
        defer { isUndoing = false }
        do {
            try await cardClient.undoLast()
            return true
        } catch {
            setError("Undo failed: \(error.localizedDescription)")
            await refreshUndoAvailability()
            return nil
        }
    }

    // MARK: - Load

    public func load(cardId: CardID?, noteId: NoteID?) async {
        guard let cardId else {
            currentFlag = 0
            cardQueue = 0
            currentDeckId = nil
            isMarkedNote = false
            canUndo = false
            return
        }
        await loadMarkedState(noteId)
        if let card = try? await cardClient.getCard(cardId) {
            currentFlag = UInt32(max(0, card.flags)) & 0b111
            cardQueue = card.queue
            currentDeckId = card.did
        } else {
            currentFlag = (try? await cardClient.getCardFlags(cardId)) ?? 0
            cardQueue = 0
            currentDeckId = nil
        }
        await refreshUndoAvailability()
    }

    // MARK: - Helpers

    private func run(_ prefix: String, _ body: () async throws -> Bool) async -> Bool? {
        do {
            return try await body()
        } catch {
            setError("\(prefix): \(error.localizedDescription)")
            return nil
        }
    }

    private func noteAction(_ noteId: NoteID, _ prefix: String, _ action: (CardID) async throws -> Void) async -> Bool? {
        await run(prefix) {
            let cards = try await cardClient.fetchByNote(noteId)
            for card in cards {
                try await action(card.id)
            }
            return true
        }
    }

    private func loadMarkedState(_ noteId: NoteID?) async {
        guard let noteId else {
            isMarkedNote = false
            return
        }
        do {
            let note = try await noteClient.fetch(noteId)
            isMarkedNote = note.map {
                $0.tags
                    .split(separator: " ")
                    .contains { $0.caseInsensitiveCompare(markedTag) == .orderedSame }
            } ?? false
        } catch {
            isMarkedNote = false
        }
    }

    private func refreshUndoAvailability() async {
        canUndo = (try? await cardClient.hasUndoableAction()) ?? false
    }

    private func setError(_ message: String) {
        errorMessage = message
        showError = true
    }
}

private let markedTag = "marked"
