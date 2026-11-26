//
//  CardPreviewPresenter.swift
//  AppShared
//
//  Created by Amgi Contributors.
//

public import Foundation
public import SwiftUI
public import AnkiKit

/// Request payload to launch the non-marking Card Viewer (Previewer).
public struct CardPreviewRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let cardIds: [CardID]
    public let initialIndex: Int
    public let title: String?

    public init(
        id: UUID = UUID(),
        cardIds: [CardID],
        initialIndex: Int = 0,
        title: String? = nil
    ) {
        self.id = id
        self.cardIds = cardIds
        self.initialIndex = initialIndex
        self.title = title
    }
}

/// Supplies `ReviewFeature`'s non-marking Card Viewer to `BrowseFeature` and
/// `DecksFeature` without introducing a `BrowseFeature -> ReviewFeature`
/// circular dependency.
///
/// Conforming types must hold zero stored properties (matching
/// `LookupPopupProviding`) so SwiftUI environment equality stays O(1).
@MainActor
public protocol CardPreviewProviding {
    func previewView(
        request: CardPreviewRequest,
        onCollectionChanged: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> AnyView
}

public extension EnvironmentValues {
    @Entry var cardPreview: (any CardPreviewProviding)? = nil
}
