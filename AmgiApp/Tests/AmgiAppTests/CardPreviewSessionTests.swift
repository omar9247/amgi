//
//  CardPreviewSessionTests.swift
//  AmgiAppTests
//
//  Created by Amgi Contributors.
//

import Testing
import Dependencies
import Foundation
import AnkiClients
import AnkiKit
import AnkiServices
@testable import ReviewCore

@MainActor
@Suite("Non-marking CardPreviewSession")
struct CardPreviewSessionTests {

    @Test func previewLoadsAndNavigatesWithoutCallingScheduler() async throws {
        final class SchedulerTracker: @unchecked Sendable {
            var calledGetQueue = false
            var calledAnswer = false
        }
        let tracker = SchedulerTracker()

        let card1 = CardRecord(id: CardID(10), nid: NoteID(100), did: DeckID(1), mod: 0, type: 2, queue: 2, ivl: 12)
        let card2 = CardRecord(id: CardID(20), nid: NoteID(200), did: DeckID(1), mod: 0, type: 0, queue: 0, ivl: 0)
        let note1 = NoteRecord(id: NoteID(100), guid: "g1", mid: NotetypeID(1), mod: 0, flds: "Q1\u{1f}A1", sfld: "Q1", csum: 0)
        let note2 = NoteRecord(id: NoteID(200), guid: "g2", mid: NotetypeID(1), mod: 0, flds: "Q2\u{1f}A2", sfld: "Q2", csum: 0)

        try await withDependencies {
            $0.schedulerService.getQueuedCards = { _ in
                tracker.calledGetQueue = true
                return QueuedCardsResult(cards: [], newCount: 0, learningCount: 0, reviewCount: 0)
            }
            $0.schedulerService.answerReviewCard = { _, _, _, _ in
                tracker.calledAnswer = true
            }
            $0.cardClient.getCard = { id in
                id == CardID(10) ? card1 : card2
            }
            $0.notesService.getNote = { id in
                id == NoteID(100) ? note1 : note2
            }
            $0.notetypesClient.get = { _ in
                Notetype(
                    id: NotetypeID(1),
                    name: "Basic",
                    fields: [
                        Notetype.Field(ord: 0, name: "Front"),
                        Notetype.Field(ord: 1, name: "Back"),
                    ],
                    templates: [
                        Notetype.Template(
                            ord: 0,
                            name: "Card 1",
                            config: Notetype.Template.Config(qFormat: "{{Front}}", aFormat: "{{Back}}")
                        ),
                    ]
                )
            }
            $0.cardRenderingService.renderCard = { id in
                id == CardID(10)
                    ? RenderedCard(frontHTML: "<p>Q1</p>", backHTML: "<p>A1</p>", cardCSS: "")
                    : RenderedCard(frontHTML: "<p>Q2</p>", backHTML: "<p>A2</p>", cardCSS: "")
            }
            $0.decksService.fetchAll = { [DeckInfo(id: DeckID(1), name: "Korean")] }
        } operation: {
            let session = CardPreviewSession(cardIds: [CardID(10), CardID(20)], initialIndex: 0)
            session.start()

            let deadline = ContinuousClock.now.advanced(by: .milliseconds(1500))
            while session.currentCard == nil && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }

            #expect(session.currentCard?.id == CardID(10))
            #expect(session.deckName == "Korean")
            #expect(!session.showAnswer)
            #expect(session.canGoNext)
            #expect(!session.canGoPrevious)

            session.toggleAnswer()
            #expect(session.showAnswer)

            session.goNext()
            while session.currentCard?.id != CardID(20) && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(session.currentCard?.id == CardID(20))
            #expect(!session.showAnswer)
            #expect(!tracker.calledGetQueue)
            #expect(!tracker.calledAnswer)
        }
    }
}
