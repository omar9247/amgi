//
//  BrowseModel.swift
//  BrowseFeature
//
//  Created by Vladimir Gusev on 22.06.2026.
//

import AppCore
import AppShared
import AnkiClients
import AnkiBackend
import AnkiKit
import AnkiServices
import Dependencies
import Foundation
import OSLog

enum BrowseMode: String, CaseIterable, Sendable {
    case cards = "Cards"
    case notes = "Notes"
}

enum BrowseCardStateFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case due = "Due"
    case new = "New"
    case suspended = "Suspended"
    case buried = "Buried"
    case flagged = "Flagged"
    case marked = "Marked"

    var id: String { rawValue }

    var searchTerm: String? {
        switch self {
        case .all: nil
        case .due: "is:due"
        case .new: "is:new"
        case .suspended: "is:suspended"
        case .buried: "is:buried"
        case .flagged: "(flag:1 OR flag:2 OR flag:3 OR flag:4 OR flag:5 OR flag:6 OR flag:7)"
        case .marked: "tag:marked"
        }
    }
}

struct BrowseCardItem: Identifiable, Sendable, Equatable {
    let id: CardID
    var card: CardRecord?
    var note: NoteRecord?
    var isStub: Bool

    var title: String {
        guard !isStub else { return "Loading..." }
        let sfld = note?.sfld ?? ""
        return sfld.isEmpty ? "Card #\(id.rawValue)" : sfld
    }

    var stateLabel: String? {
        guard let card else { return nil }
        if card.queue == -1 { return "Suspended" }
        if card.queue == -2 || card.queue == -3 { return "Buried" }
        switch card.type {
        case 0: return "New"
        case 1: return "Learning"
        case 2: return card.ivl > 0 ? "Review · \(card.ivl)d" : "Review"
        case 3: return "Relearning"
        default: return nil
        }
    }

    var flagValue: UInt32 {
        UInt32(max(0, card?.flags ?? 0)) & 0b111
    }
}

/// Data state + load/search/mutation logic for the Browse screen (Cards & Notes).
@Observable
@MainActor
final class BrowseModel {
    var browseMode: BrowseMode {
        didSet {
            if oldValue != browseMode {
                cardStateFilter = .all
            }
        }
    }
    var cardStateFilter: BrowseCardStateFilter = .all
    var searchText = ""
    /// Surfaced when a batch mutation partially or wholly fails.
    var errorMessage: String?

    // Notes mode storage
    var allNotes: [NoteRecord] = []
    var notes: [NoteRecord] = [] {
        didSet { if !isPatchingInPlace { resort() } }
    }

    // Cards mode storage
    var allCardIDs: [CardID] = []
    var cardItems: [BrowseCardItem] = []
    var hasMoreCardPages = false

    private var isPatchingInPlace = false
    var allDecks: [DeckInfo] = []
    var deckNamesByID: [DeckID: String] = [:]
    /// The top-level parent deck selected (stays set even when drilling into subdecks).
    var parentDeck: DeckInfo?
    /// The actual deck filter applied (could be parent or a subdeck).
    var activeDeck: DeckInfo?
    var isLoading = false
    /// True when the last search threw, so the empty state can say "search
    /// failed" rather than "no results".
    private(set) var searchFailed = false
    var hasMorePages = true
    var allTags: [String] = []
    var activeTag: String?
    var sortOrder: BrowseSortOrder = .dateDesc {
        didSet { resort() }
    }
    var notetypeNames: [NotetypeID: String] = [:] {
        didSet { if sortOrder == .templateAsc { resort() } }
    }

    @ObservationIgnored private var firstCardIDs: [NoteID: CardID] = [:]

    private let pageSize = 50

    @ObservationIgnored @Dependency(\.noteClient) private var noteClient
    @ObservationIgnored @Dependency(\.collectionStore) private var store
    @ObservationIgnored @Dependency(\.deckClient) private var deckClient
    @ObservationIgnored @Dependency(\.cardClient) private var cardClient
    @ObservationIgnored @Dependency(\.tagClient) private var tagClient
    @ObservationIgnored @Dependency(\.notetypesService) private var notetypesService

    init(browseMode: BrowseMode = .notes, initialDeck: DeckInfo? = nil) {
        self.browseMode = browseMode
        self.parentDeck = initialDeck
        self.activeDeck = initialDeck
    }

    // MARK: - Derived

    private(set) var sortedNotes: [NoteRecord] = []

    private func resort() {
        switch sortOrder {
        case .dateDesc:
            sortedNotes = notes.sorted { $0.mod > $1.mod }
        case .titleAsc:
            sortedNotes = notes.sorted {
                $0.sfld.localizedCaseInsensitiveCompare($1.sfld) == .orderedAscending
            }
        case .templateAsc:
            sortedNotes = notes.sorted { (notetypeNames[$0.mid] ?? "") < (notetypeNames[$1.mid] ?? "") }
        }
    }

    var topLevelDecks: [DeckInfo] {
        allDecks.filter { !$0.name.contains("::") }
    }

    /// Direct children of the parent deck (shown as the second filter row).
    var childDecks: [DeckInfo] {
        guard let parent = parentDeck else { return [] }
        let prefix = parent.name + "::"
        return allDecks.filter { deck in
            guard deck.name.hasPrefix(prefix) else { return false }
            let remainder = deck.name.dropFirst(prefix.count)
            return !remainder.contains("::")
        }
    }

    // MARK: - Loading

    func loadInitial() async {
        await loadDecks()
        allTags = ((try? await tagClient.getAllTags()) ?? []).sorted()
        let notetypes = notetypesService
        if let pairs = try? await backendOffload({ try notetypes.getNotetypeNames() }) {
            notetypeNames = Dictionary(uniqueKeysWithValues: pairs.map { ($0.id, $0.name) })
        }
    }

    func loadDecks() async {
        do {
            let fetched = try await deckClient.fetchAll()
            allDecks = fetched
            deckNamesByID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0.name) })
        } catch {
            allDecks = []
            deckNamesByID = [:]
        }
    }

    /// The full query the list reflects. Includes `browseMode` and `cardStateFilter`
    /// so switching mode or state filter immediately restarts `.task(id: searchQuery)`.
    var searchQuery: String {
        let base = buildQuery()
        if browseMode == .cards {
            return "cards:\(cardStateFilter.rawValue)|\(base)"
        }
        return base
    }

    func performSearch(debounce: Duration = .milliseconds(250)) async {
        if debounce > .zero {
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
        }

        isLoading = true
        let query = buildQuery()

        if browseMode == .cards {
            do {
                let ids = try await cardClient.searchCards(query, nil)
                guard !Task.isCancelled else { return }
                searchFailed = false
                allCardIDs = ids
                let firstBatch = Array(ids.prefix(pageSize))
                var items = await hydrateCards(firstBatch)
                guard !Task.isCancelled else { return }
                for id in ids.dropFirst(firstBatch.count) {
                    items.append(BrowseCardItem(id: id, card: nil, note: nil, isStub: true))
                }
                // Keep initial visible page bounded for smooth scrolling while preserving total count
                cardItems = Array(items.prefix(pageSize))
                hasMoreCardPages = ids.count > pageSize
            } catch {
                guard !Task.isCancelled else { return }
                searchFailed = true
                allCardIDs = []
                cardItems = []
                hasMoreCardPages = false
            }
            isLoading = false
            return
        }

        do {
            let results = try await noteClient.search(query, nil)
            guard !Task.isCancelled else { return }
            searchFailed = false
            allNotes = results
            notes = Array(results.prefix(pageSize))
            hasMorePages = results.count > pageSize
        } catch {
            guard !Task.isCancelled else { return }
            searchFailed = true
            allNotes = []
            notes = []
            hasMorePages = false
        }
        isLoading = false
    }

    func loadNextPage() async {
        guard hasMorePages, !isLoading else { return }
        let loaded = notes.count
        let nextBatch = Array(allNotes.dropFirst(loaded).prefix(pageSize))
        notes.append(contentsOf: nextBatch)
        hasMorePages = notes.count < allNotes.count
    }

    func loadNextCardPage() async {
        guard hasMoreCardPages, !isLoading else { return }
        let loaded = cardItems.count
        let nextIDs = Array(allCardIDs.dropFirst(loaded).prefix(pageSize))
        guard !nextIDs.isEmpty else {
            hasMoreCardPages = false
            return
        }
        let hydrated = await hydrateCards(nextIDs)
        cardItems.append(contentsOf: hydrated)
        hasMoreCardPages = cardItems.count < allCardIDs.count
    }

    func fetchCardDetails(id: CardID) async {
        guard let idx = cardItems.firstIndex(where: { $0.id == id }),
              cardItems[idx].isStub else { return }
        let hydrated = await hydrateCards([id])
        if let item = hydrated.first,
           let currentIdx = cardItems.firstIndex(where: { $0.id == id }) {
            cardItems[currentIdx] = item
        }
    }

    private func hydrateCards(_ ids: [CardID]) async -> [BrowseCardItem] {
        var result: [BrowseCardItem] = []
        result.reserveCapacity(ids.count)
        var noteCache: [NoteID: NoteRecord] = [:]
        for cid in ids {
            guard !Task.isCancelled else { break }
            let card = try? await cardClient.getCard(cid)
            var note: NoteRecord?
            if let card {
                if let cached = noteCache[card.nid] {
                    note = cached
                } else if let fetched = try? await noteClient.fetch(card.nid) {
                    noteCache[card.nid] = fetched
                    note = fetched
                }
            }
            result.append(BrowseCardItem(id: cid, card: card, note: note, isStub: false))
        }
        return result
    }

    func fetchNoteDetails(id: NoteID) async {
        guard let fullNote = try? await noteClient.fetch(id) else { return }
        if let idx = notes.firstIndex(where: { $0.id == id }) {
            isPatchingInPlace = true
            notes[idx] = fullNote
            isPatchingInPlace = false
        }
        if let idx = allNotes.firstIndex(where: { $0.id == id }) {
            allNotes[idx] = fullNote
        }
        if let idx = sortedNotes.firstIndex(where: { $0.id == id }) {
            sortedNotes[idx] = fullNote
        }
    }

    func firstCardID(for noteId: NoteID) async -> CardID? {
        if let cached = firstCardIDs[noteId] { return cached }
        guard let cardId = (try? await cardClient.fetchByNote(noteId))?.first?.id else {
            return nil
        }
        firstCardIDs[noteId] = cardId
        return cardId
    }

    func resolved(_ note: NoteRecord) -> NoteRecord {
        guard note.sfld == "Loading..." else { return note }
        return notes.first(where: { $0.id == note.id })
            ?? allNotes.first(where: { $0.id == note.id })
            ?? note
    }

    // MARK: - Note Mutations

    func delete(_ id: NoteID) async {
        await runBatch("delete", over: [id]) { try await self.noteClient.delete($0) }
        store.apply(CollectionChanges(card: true, note: true))
    }

    func suspendSelected(_ noteIDs: Set<NoteID>) async {
        let cardIDs = await collectCardIDs(for: noteIDs)
        await runBatch("suspend", over: cardIDs) { try await self.cardClient.suspend($0) }
    }

    func flagSelected(_ noteIDs: Set<NoteID>, value: UInt32) async {
        let cardIDs = await collectCardIDs(for: noteIDs)
        await runBatch("flag", over: cardIDs) { try await self.cardClient.flag($0, value) }
    }

    func deleteSelected(_ noteIDs: Set<NoteID>) async {
        await runBatch("delete", over: Array(noteIDs)) { try await self.noteClient.delete($0) }
        store.apply(CollectionChanges(card: true, note: true))
    }

    // MARK: - Card Mutations (Cards mode)

    func suspendSelectedCards(_ cardIDs: Set<CardID>) async {
        let ids = Array(cardIDs)
        guard !ids.isEmpty else { return }
        do {
            try await cardClient.suspendBatch(ids)
            store.apply(CollectionChanges(card: true, studyQueues: true))
        } catch {
            errorMessage = "Couldn't suspend cards: \(error.localizedDescription)"
        }
        await performSearch(debounce: .zero)
    }

    func unsuspendSelectedCards(_ cardIDs: Set<CardID>) async {
        let ids = Array(cardIDs)
        guard !ids.isEmpty else { return }
        do {
            try await cardClient.unsuspendOrUnbury(ids)
            store.apply(CollectionChanges(card: true, studyQueues: true))
        } catch {
            errorMessage = "Couldn't unsuspend cards: \(error.localizedDescription)"
        }
        await performSearch(debounce: .zero)
    }

    func flagSelectedCards(_ cardIDs: Set<CardID>, value: UInt32) async {
        let ids = Array(cardIDs)
        guard !ids.isEmpty else { return }
        do {
            try await cardClient.flagBatch(ids, value)
            store.apply(CollectionChanges(card: true))
        } catch {
            errorMessage = "Couldn't flag cards: \(error.localizedDescription)"
        }
        await performSearch(debounce: .zero)
    }

    func rescheduleSelectedCards(_ cardIDs: [CardID], spec: String) async -> String? {
        guard !cardIDs.isEmpty else { return nil }
        do {
            try await cardClient.setDueDateBatch(cardIDs, spec)
            store.apply(CollectionChanges(card: true, studyQueues: true))
            await performSearch(debounce: .zero)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func changeDeckSelectedCards(_ cardIDs: [CardID], to deckId: DeckID) async -> String? {
        guard !cardIDs.isEmpty else { return nil }
        do {
            try await cardClient.setDeck(cardIDs, deckId)
            store.apply(CollectionChanges(card: true, deck: true, studyQueues: true))
            await performSearch(debounce: .zero)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func deleteSelectedCards(_ cardIDs: Set<CardID>) async {
        let ids = Array(cardIDs)
        guard !ids.isEmpty else { return }
        do {
            try await cardClient.removeCards(ids)
            store.apply(CollectionChanges(card: true, note: true, studyQueues: true))
        } catch {
            errorMessage = "Couldn't delete cards: \(error.localizedDescription)"
        }
        await performSearch(debounce: .zero)
    }

    private func runBatch<ID>(
        _ verb: String,
        over ids: [ID],
        _ work: (ID) async throws -> Void
    ) async {
        var failures = 0
        var firstError: String?
        for id in ids {
            do {
                try await work(id)
            } catch {
                failures += 1
                if firstError == nil { firstError = error.localizedDescription }
                Log.browse.error("Batch \(verb) failed for one item: \(error)")
            }
        }
        if failures > 0 {
            errorMessage = failures == ids.count
                ? "Couldn't \(verb) \(failures == 1 ? "that item" : "those \(failures) items"): \(firstError ?? "unknown error")"
                : "\(failures) of \(ids.count) items couldn't be \(verb)d: \(firstError ?? "unknown error")"
        }
        await performSearch()
    }

    // MARK: - Query

    func buildQuery() -> String {
        var parts: [String] = []
        if let deck = activeDeck {
            parts.append(DeckSearch.term(deck.name))
        }
        if let tag = activeTag {
            parts.append("tag:\"\(tag)\"")
        }
        if browseMode == .cards, let stateTerm = cardStateFilter.searchTerm {
            parts.append(stateTerm)
        }
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            parts.append(trimmed)
        }
        return parts.joined(separator: " ")
    }

    private func collectCardIDs(for noteIDs: Set<NoteID>) async -> [CardID] {
        var result: [CardID] = []
        result.reserveCapacity(noteIDs.count)
        let cardClient = cardClient
        for nid in noteIDs {
            if let cards = try? await cardClient.fetchByNote(nid) {
                result.append(contentsOf: cards.map(\.id))
            }
        }
        return result
    }
}
