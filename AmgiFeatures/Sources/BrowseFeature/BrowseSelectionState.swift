//
//  BrowseSelectionState.swift
//  BrowseFeature
//
//  Created by Vladimir Gusev on 02.05.2026.
//

import Foundation
import AnkiKit

struct BrowseSelectionState: Equatable, Sendable {
    var isSelectMode: Bool = false
    var selectedNoteIDs: Set<NoteID> = []
    var selectedCardIDs: Set<CardID> = []

    var isEmpty: Bool { selectedNoteIDs.isEmpty && selectedCardIDs.isEmpty }
    var count: Int { max(selectedNoteIDs.count, selectedCardIDs.count) }

    mutating func enterSelectMode(preselect: NoteID? = nil) {
        isSelectMode = true
        selectedCardIDs = []
        selectedNoteIDs = preselect.map { [$0] } ?? []
    }

    mutating func enterCardSelectMode(preselect: CardID? = nil) {
        isSelectMode = true
        selectedNoteIDs = []
        selectedCardIDs = preselect.map { [$0] } ?? []
    }

    mutating func exitSelectMode() {
        isSelectMode = false
        selectedNoteIDs = []
        selectedCardIDs = []
    }

    mutating func toggle(_ id: NoteID) {
        if selectedNoteIDs.contains(id) {
            selectedNoteIDs.remove(id)
        } else {
            selectedNoteIDs.insert(id)
        }
    }

    mutating func toggleCard(_ id: CardID) {
        if selectedCardIDs.contains(id) {
            selectedCardIDs.remove(id)
        } else {
            selectedCardIDs.insert(id)
        }
    }

    func contains(_ id: NoteID) -> Bool {
        selectedNoteIDs.contains(id)
    }

    func containsCard(_ id: CardID) -> Bool {
        selectedCardIDs.contains(id)
    }
}
