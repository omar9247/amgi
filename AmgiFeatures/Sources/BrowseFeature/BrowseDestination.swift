//
//  BrowseDestination.swift
//  BrowseFeature
//
//  Created by Vladimir Gusev on 18.08.2026.
//

import Foundation
import CasePaths
import AnkiKit

enum BrowseTool: Hashable {
    case duplicates
}

@CasePathable
enum BrowseDestination {
    case addNote
    case addImageOcclusion
    case batchTag
    case findReplaceSelected
    case findReplaceAll
    case deleteSelected
    case deleteNote(NoteRecord)
    case deleteNoteByID(NoteID)
    case editNote(NoteRecord)
    case rescheduleSelectedCards([CardID])
    case changeDeckSelectedCards([CardID])
}
