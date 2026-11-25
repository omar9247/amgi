//
//  WhiteboardAnnotationStore.swift
//  ReviewFeature
//
//  Created by Amgi Contributors.
//

import AnkiKit
import AppCore
import Foundation

/// Persists per-card stylus annotations inside the active profile directory
/// when `persistPerCard` is enabled.
@MainActor
enum WhiteboardAnnotationStore {
    private static func folderURL() -> URL {
        let profileID = AccountStore.shared.selectedID
        return AccountStore.profileDirectory(for: profileID)
            .appendingPathComponent("whiteboard_annotations", isDirectory: true)
    }

    private static func fileURL(for cardId: CardID) -> URL {
        folderURL().appendingPathComponent("\(cardId.rawValue).json")
    }

    static func load(cardId: CardID) -> [InkStroke] {
        let url = fileURL(for: cardId)
        guard let data = try? Data(contentsOf: url),
              let doc = try? JSONDecoder().decode(WhiteboardDocument.self, from: data) else {
            return []
        }
        return doc.strokes
    }

    static func save(_ strokes: [InkStroke], for cardId: CardID) {
        let folder = folderURL()
        let url = fileURL(for: cardId)
        if strokes.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let doc = WhiteboardDocument(cardId: cardId.rawValue, strokes: strokes, updatedAt: .now)
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(doc) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
