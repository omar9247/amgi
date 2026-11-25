//
//  CardPreviewSession.swift
//  ReviewCore
//
//  Created by Amgi Contributors.
//

import OSLog
public import SwiftUI
import AppCore
public import AmgiCardWeb
import AnkiClients
public import AnkiKit
import AnkiServices
import Dependencies
import Foundation

/// Read-only card preview/browse session (like AnkiDroid's Card Viewer / Previewer).
/// Renders cards in sequence using the real Rust template engine and native/HTML
/// renderers without calling `getQueuedCards` or `answerReviewCard` — zero
/// scheduling side effects, zero review logs, zero FSRS changes.
@Observable
@MainActor
public final class CardPreviewSession {
    public private(set) var cardIds: [CardID]
    public private(set) var currentIndex: Int
    public let title: String?

    @ObservationIgnored @Dependency(\.cardClient) private var cardClient
    @ObservationIgnored @Dependency(\.notesService) private var notes
    @ObservationIgnored @Dependency(\.notetypesService) private var notetypes
    @ObservationIgnored @Dependency(\.notetypesClient) private var notetypesClient
    @ObservationIgnored @Dependency(\.cardRenderingService) private var cardRendering
    @ObservationIgnored @Dependency(\.decksService) private var decks

    public private(set) var currentCard: CardRecord?
    public private(set) var currentNote: NoteRecord?
    public private(set) var deckName: String = ""
    public private(set) var templateName: String?
    public private(set) var frontHTML: String = ""
    public private(set) var backHTML: String = ""
    public private(set) var cardCSS: String = ""
    public private(set) var resolvedMode: ResolvedRenderMode = .html
    public private(set) var resolvedByAuto: Bool = false

    public private(set) var showAnswer: Bool = false
    public var autoShowAnswer: Bool = false {
        didSet {
            if autoShowAnswer && !showAnswer {
                showAnswer = true
            }
        }
    }

    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var replayRequestID: Int = 0
    public private(set) var stopAudioRequestID: Int = 0
    public private(set) var isAudioPlaying: Bool = false
    public private(set) var cardChromeColor: Color = .clear
    public private(set) var cardChromeIsDark: Bool = false

    private var notetypeCache: [NotetypeID: Notetype] = [:]
    private var deckNameCache: [DeckID: String] = [:]
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    @ObservationIgnored public private(set) lazy var mediaFolder: URL? = {
        @Dependency(\.mediaClient) var mediaClient
        return mediaClient.folderURL()
    }()

    public init(cardIds: [CardID], initialIndex: Int = 0, title: String? = nil) {
        self.cardIds = cardIds
        if cardIds.isEmpty {
            self.currentIndex = 0
        } else {
            self.currentIndex = min(max(0, initialIndex), cardIds.count - 1)
        }
        self.title = title
    }

    public var totalCount: Int { cardIds.count }
    public var isEmpty: Bool { cardIds.isEmpty }
    public var canGoPrevious: Bool { currentIndex > 0 }
    public var canGoNext: Bool { currentIndex + 1 < cardIds.count }

    public var currentCardId: CardID? {
        guard cardIds.indices.contains(currentIndex) else { return nil }
        return cardIds[currentIndex]
    }

    public var currentCardOrdinal: UInt32 {
        UInt32(max(0, currentCard?.ord ?? 0))
    }

    public var currentTemplateTarget: ReviewSession.TemplateTarget? {
        guard let card = currentCard, let note = currentNote else { return nil }
        return ReviewSession.TemplateTarget(notetypeId: note.mid, ordinal: Int(card.ord))
    }

    public var cardStatusSummary: String {
        guard let card = currentCard else { return "" }
        if card.queue == -1 { return "Suspended" }
        if card.queue == -2 || card.queue == -3 { return "Buried" }
        switch card.type {
        case 0: return "New"
        case 1: return "Learning"
        case 2:
            return card.ivl > 0 ? "Review · \(card.ivl)d" : "Review"
        case 3: return "Relearning"
        default: return "Card"
        }
    }

    public func start() {
        loadCurrent()
    }

    public func goNext() {
        guard canGoNext else { return }
        currentIndex += 1
        loadCurrent()
    }

    public func goPrevious() {
        guard canGoPrevious else { return }
        currentIndex -= 1
        loadCurrent()
    }

    public func jump(to index: Int) {
        guard cardIds.indices.contains(index), index != currentIndex else { return }
        currentIndex = index
        loadCurrent()
    }

    public func toggleAnswer() {
        showAnswer.toggle()
    }

    public func revealAnswer() {
        showAnswer = true
    }

    public func toggleAutoShowAnswer() {
        autoShowAnswer.toggle()
    }

    public func updateAudioPlaying(_ playing: Bool) {
        isAudioPlaying = playing
    }

    public func updateCardChrome(color: Color, isDark: Bool) {
        cardChromeColor = color
        cardChromeIsDark = isDark
    }

    public func bumpReplayRequest() {
        replayRequestID += 1
    }

    public func bumpStopAudioRequest() {
        stopAudioRequestID += 1
    }

    public func reresolveCurrentCard() {
        guard let card = currentCard else { return }
        let prefs = currentRenderEnginePreferences(mid: currentNote?.mid, ord: Int(card.ord))
        let resolution = resolveRenderMode(
            renderedFront: frontHTML,
            renderedBack: backHTML,
            css: cardCSS,
            override: prefs.override,
            global: prefs.global
        )
        resolvedMode = resolution.mode
        resolvedByAuto = resolution.byAuto
    }

    public func refreshAfterCardAction() {
        guard let id = currentCardId else { return }
        let cardClient = self.cardClient
        Task {
            if (try? await cardClient.getCard(id)) == nil {
                removeCurrentNoteCards()
            } else {
                loadCard(id: id)
            }
        }
    }

    public func removeCurrentNoteCards() {
        guard let nid = currentNote?.id else { return }
        // Remove current card (and note if needed, refreshed safely)
        if let cid = currentCardId {
            cardIds.removeAll { $0 == cid }
        }
        if cardIds.isEmpty {
            currentCard = nil
            currentNote = nil
            return
        }
        currentIndex = min(currentIndex, cardIds.count - 1)
        let _ = nid
        loadCurrent()
    }

    public func loadCurrent() {
        guard let id = currentCardId else {
            currentCard = nil
            currentNote = nil
            return
        }
        loadCard(id: id)
    }

    private func loadCard(id: CardID) {
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil
        stopAudioRequestID += 1

        let cardClient = self.cardClient
        let notes = self.notes
        let notetypes = self.notetypes
        let notetypesClient = self.notetypesClient
        let cardRendering = self.cardRendering
        let decks = self.decks
        let ntCache = notetypeCache
        let dCache = deckNameCache

        loadTask = Task {
            do {
                let card = try await cardClient.getCard(id)
                guard !Task.isCancelled else { return }

                let queued = QueuedReviewCard(
                    card: card,
                    states: ReviewSchedulingStates(
                        current: SchedulingStateToken(Data()),
                        again: SchedulingStateToken(Data()),
                        hard: SchedulingStateToken(Data()),
                        good: SchedulingStateToken(Data()),
                        easy: SchedulingStateToken(Data())
                    ),
                    nextIntervals: [:]
                )
                let prepared = await Task.detached {
                    await prepareCard(
                        for: queued,
                        notes: notes,
                        notetypes: notetypes,
                        cardRendering: cardRendering,
                        notetypesClient: notetypesClient,
                        notetypeCache: ntCache
                    )
                }.value
                guard !Task.isCancelled else { return }

                var resolvedDeckName = dCache[card.did]
                if resolvedDeckName == nil {
                    let allDecks = try? await Task.detached { try decks.fetchAll() }.value
                    if let allDecks {
                        for d in allDecks {
                            deckNameCache[d.id] = d.name
                        }
                        resolvedDeckName = deckNameCache[card.did]
                    }
                }
                guard !Task.isCancelled else { return }

                currentCard = card
                currentNote = prepared.note
                if let nt = prepared.notetype {
                    notetypeCache[nt.id] = nt
                }
                deckName = resolvedDeckName ?? title ?? "Card Viewer"
                templateName = prepared.templateName
                frontHTML = strippingTypedAnswerPlaceholders(from: prepared.renderedFrontHTML)
                backHTML = strippingTypedAnswerPlaceholders(from: prepared.renderedBackHTML)
                cardCSS = prepared.cardCSS
                resolvedMode = prepared.resolvedMode
                resolvedByAuto = prepared.resolvedByAuto
                showAnswer = autoShowAnswer
                isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                // Card may have been deleted (e.g., Delete Note); handle gracefully
                Log.review.error("Preview load failed for card \(id.rawValue): \(error)")
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}
