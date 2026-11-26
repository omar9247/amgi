//
//  ChangeDeckSheet.swift
//  AppShared
//
//  Created by Amgi Contributors.
//

import Foundation
public import SwiftUI
public import AnkiKit
import AnkiClients
import Dependencies
import Theme

/// Lets the user move one or more cards to a different non-filtered deck.
@MainActor
public struct ChangeDeckSheet: View {
    public let cardIds: [CardID]
    public let currentDeckId: DeckID?
    public let onSelectDeck: (_ deckId: DeckID) async -> String?

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Dependency(\.deckClient) private var deckClient

    @State private var decks: [DeckInfo] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    public init(
        cardIds: [CardID],
        currentDeckId: DeckID? = nil,
        onSelectDeck: @escaping (_ deckId: DeckID) async -> String?
    ) {
        self.cardIds = cardIds
        self.currentDeckId = currentDeckId
        self.onSelectDeck = onSelectDeck
    }

    private var filteredDecks: [DeckInfo] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let eligible = decks.filter { !$0.isFiltered }
        guard !trimmed.isEmpty else { return eligible }
        return eligible.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    public var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredDecks.isEmpty {
                    ContentUnavailableView("No Decks", systemImage: "folder")
                } else {
                    List(filteredDecks) { deck in
                        Button {
                            Task { await move(to: deck.id) }
                        } label: {
                            HStack {
                                Text(deck.name)
                                    .amgiFont(.body)
                                    .foregroundStyle(palette.textPrimary)
                                Spacer()
                                if deck.id == currentDeckId {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(palette.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isSubmitting)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Filter decks...")
            .navigationTitle(cardIds.count > 1 ? "Move \(cardIds.count) Cards" : "Change Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
            }
            .task {
                isLoading = true
                decks = (try? await deckClient.fetchAll()) ?? []
                isLoading = false
            }
            .alert(
                "Couldn't Move Card",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                ),
                presenting: errorMessage
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }

    private func move(to deckId: DeckID) async {
        isSubmitting = true
        defer { isSubmitting = false }
        if let err = await onSelectDeck(deckId) {
            errorMessage = err
        } else {
            dismiss()
        }
    }
}
