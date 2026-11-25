//
//  CardClient+Live.swift
//  AnkiClients
//
//  Created by Vladimir Gusev on 27.03.2026.
//

import AnkiBackend
import AnkiKit
import AnkiProtoBridge
import AnkiServices
public import Dependencies
import DependenciesMacros
import Logging

private let logger = Logger(label: "com.ankiapp.card.client")

extension CardClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend
        @Dependency(\.schedulerService) var scheduler
        @Dependency(\.decksService) var decks

        return Self(
            getCard: { cardId in
                try await backend.invoke(.getCard(id: cardId))
            },
            searchCards: { query, limit in
                let ids = try await backend.invoke(.searchCardIds(query: query))
                if let limit {
                    return Array(ids.prefix(limit))
                }
                return ids
            },
            fetchDue: { deckId in
                try await backendOffload {
                    do {
                        try decks.setCurrentDeck(deckId)
                        logger.info("Set current deck to \(deckId)")
                    } catch {
                        logger.error("setCurrentDeck failed for deckId=\(deckId): \(error)")
                        throw error
                    }

                    do {
                        let currentDeck = try decks.getCurrentDeck()
                        logger.info("Verified current deck: id=\(currentDeck.id), name=\(currentDeck.name)")
                    } catch {
                        logger.warning("Could not verify current deck (non-fatal): \(error)")
                    }

                    do {
                        let result = try scheduler.getQueuedCards(200)
                        logger.info("QueuedCards for deckId=\(deckId): \(result.cards.count) cards")
                        return result.cards.map(\.card)
                    } catch {
                        logger.error("fetchDue failed for deckId=\(deckId): \(error)")
                        throw error
                    }
                }
            },
            fetchByNote: { noteId in
                let ids = try await backend.invoke(.cardIDsOfNote(id: noteId))
                var cards: [CardRecord] = []
                cards.reserveCapacity(ids.count)
                for id in ids {
                    cards.append(try await backend.invoke(.getCard(id: id)))
                }
                return cards
            },
            suspend: { cardId in
                try await backend.invoke(.suspendCards(cardIds: [cardId]))
            },
            suspendBatch: { cardIds in
                guard !cardIds.isEmpty else { return }
                try await backend.invoke(.suspendCards(cardIds: cardIds))
            },
            bury: { cardId in
                try await backend.invoke(.buryCards(cardIds: [cardId]))
            },
            buryBatch: { cardIds in
                guard !cardIds.isEmpty else { return }
                try await backend.invoke(.buryCards(cardIds: cardIds))
            },
            unsuspendOrUnbury: { cardIds in
                guard !cardIds.isEmpty else { return }
                try await backend.invoke(.restoreBuriedAndSuspendedCards(cardIds: cardIds))
            },
            flag: { cardId, value in
                try await backend.invoke(.setFlag(cardIds: [cardId], flag: value))
            },
            flagBatch: { cardIds, value in
                guard !cardIds.isEmpty else { return }
                try await backend.invoke(.setFlag(cardIds: cardIds, flag: value))
            },
            resetToNew: { cardId in
                try await backend.invoke(.scheduleCardsAsNew(cardIds: [cardId], log: true))
            },
            setDueDate: { cardId, days in
                try await backend.invoke(.setDueDate(cardIds: [cardId], days: days))
            },
            setDueDateBatch: { cardIds, days in
                guard !cardIds.isEmpty else { return }
                try await backend.invoke(.setDueDate(cardIds: cardIds, days: days))
            },
            setDeck: { cardIds, deckId in
                guard !cardIds.isEmpty else { return }
                try await backend.invoke(.setDeck(cardIds: cardIds, deckId: deckId))
            },
            undoLast: {
                try await backend.invoke(.undoLastAction)
            },
            getCardFlags: { cardId in
                let card = try await backend.invoke(.getCard(id: cardId))
                return UInt32(card.flags) & 0b111
            },
            hasUndoableAction: {
                try await backend.invoke(.hasUndoableAction)
            },
            removeCards: { cardIds in
                try await backend.invoke(.removeCards(cardIds: cardIds))
                logger.info("Removed \(cardIds.count) cards")
            }
        )
    }()
}
