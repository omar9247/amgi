//
//  CardPreviewerView.swift
//  ReviewFeature
//
//  Created by Amgi Contributors.
//

package import SwiftUI
import AmgiCardWeb
import Theme
import UI
import AppCore
package import AppShared
import AnkiClients
import AnkiKit
import CasePaths
import Dependencies
import BrowseFeature
import TemplatesFeature
import Sharing
import ReviewCore
import SwiftUINavigation

@CasePathable
private enum CardPreviewDestination {
    case editNote(NoteRecord)
    case editTemplate(ReviewSession.TemplateTarget)
    case lookup(String)
}

private extension Optional where Wrapped == CardPreviewDestination {
    var lookupText: String? {
        get {
            guard case .lookup(let text) = self else { return nil }
            return text
        }
        set { self = newValue.map(CardPreviewDestination.lookup) }
    }
}

/// AnkiDroid-style non-marking Card Viewer / Previewer.
/// Lets the user browse through cards, flip Question/Answer, toggle auto-reveal,
/// annotate with the GoodNotes-style Whiteboard, and edit/flag/reschedule cards
/// without affecting FSRS scheduling or review counts.
package struct CardPreviewerView: View {
    let request: CardPreviewRequest
    let onCollectionChanged: () -> Void
    let onDismiss: () -> Void

    @Shared(.appStorage(ReviewPreferences.Keys.openLinksExternally))
    private var openLinksExternally: Bool = true

    @Shared(.appStorage(ReviewPreferences.Keys.cardContentAlignment))
    private var cardContentAlignment: String = CardWebViewContentAlignment.center.rawValue

    @Shared(.appStorage(ReviewPreferences.Keys.autoMatchCardBackground))
    private var autoMatchCardBackground: Bool = true

    @Shared(.appStorage(ReaderPreferences.Keys.tapLookup))
    private var tapLookup: Bool = true

    @Shared(.appStorage(ReaderPreferences.Keys.dictionaryScanLength))
    private var dictionaryScanLength: Int = 16

    @Shared(.appStorage(ReviewPreferences.Keys.playAudioInSilentMode))
    private var playAudioInSilentMode: Bool = false

    @Environment(\.palette) private var palette
    @Environment(\.lookupPopup) private var lookupPopup

    @State private var session: CardPreviewSession
    @State private var whiteboard = WhiteboardState()
    @State private var cardActions = CardContextMenuModel()
    @State private var confirmDeleteNote = false
    @State private var destination: CardPreviewDestination?
    @State private var showRenderModeSheet = false
    @State private var lookupHighlight = LookupHighlight()
    @State private var nativeAudioPlayer = NativeCardAudioPlayer()

    package init(
        request: CardPreviewRequest,
        onCollectionChanged: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void
    ) {
        self.request = request
        self.onCollectionChanged = onCollectionChanged
        self.onDismiss = onDismiss
        self._session = State(initialValue: CardPreviewSession(
            cardIds: request.cardIds,
            initialIndex: request.initialIndex,
            title: request.title
        ))
    }

    private var keyboardActive: Bool {
        destination == nil && !confirmDeleteNote && !showRenderModeSheet
    }

    private var isNativeMode: Bool {
        if case .native = session.resolvedMode { return true }
        return false
    }

    package var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if session.isEmpty {
                    ContentUnavailableView(
                        "No Cards to View",
                        systemImage: "rectangle.stack",
                        description: Text("No cards match the current selection.")
                    )
                } else if let error = session.errorMessage, session.currentCard == nil {
                    ContentUnavailableView {
                        Label("Couldn't Load Card", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") { session.loadCurrent() }
                            .buttonStyle(AmgiPrimaryButtonStyle())
                    }
                } else {
                    previewBody
                }
            }
            .background(palette.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .cardActionPresentations(
                model: cardActions,
                cardId: session.currentCardId,
                noteId: session.currentNote?.id,
                confirmDeleteNote: $confirmDeleteNote,
                onAction: { didMutateCollection in
                    onCollectionChanged()
                    if didMutateCollection {
                        session.refreshAfterCardAction()
                        Task { await cardActions.load(cardId: session.currentCardId, noteId: session.currentNote?.id) }
                    }
                }
            )
            .sheet(item: $destination.editNote) { note in
                NavigationStack {
                    NoteEditorView(note: note) {
                        onCollectionChanged()
                        session.refreshAfterCardAction()
                    }
                }
            }
            .sheet(item: $destination.editTemplate) { target in
                NavigationStack {
                    TemplateEditorView(
                        notetypeId: target.notetypeId,
                        initialTemplateIndex: target.ordinal,
                        mode: .currentCard,
                        onSaved: {
                            onCollectionChanged()
                            session.refreshAfterCardAction()
                        }
                    )
                }
            }
            .sheet(isPresented: $showRenderModeSheet) {
                RenderModeSheet(
                    explainer: isNativeMode
                        ? "shown with the built-in renderer."
                        : "shown with its own template.",
                    template: session.currentTemplateTarget,
                    templateName: session.templateName,
                    onChanged: { session.reresolveCurrentCard() }
                )
            }
            .sheet(isPresented: Binding($destination.lookup), onDismiss: { lookupHighlight.clear() }) {
                if let lookupPopup {
                    lookupPopup.popup(
                        query: destination.lookupText ?? "",
                        onMatched: { lookupHighlight.show(matched: $0) },
                        onDismiss: { destination = nil }
                    )
                }
            }
            #if canImport(UIKit)
            .toolbarBackground(
                autoMatchCardBackground ? session.cardChromeColor : Color.clear,
                for: .navigationBar
            )
            .toolbarBackground(
                autoMatchCardBackground ? .visible : .automatic,
                for: .navigationBar
            )
            .toolbarColorScheme(
                autoMatchCardBackground && session.cardChromeIsDark ? .dark : .light,
                for: .navigationBar
            )
            #endif
        }
        .task {
            ReviewAudioSession.apply(playInSilent: playAudioInSilentMode)
            session.start()
        }
        .onDisappear {
            nativeAudioPlayer.stop()
            ReviewAudioSession.release()
        }
    }

    private var previewBody: some View {
        VStack(spacing: 0) {
            RenderModeChipRow(
                isNative: isNativeMode,
                isAuto: session.resolvedByAuto,
                templateName: session.templateName,
                onTap: { showRenderModeSheet = true }
            )
            .padding(.horizontal)

            WhiteboardOverlayView(state: whiteboard) {
                Group {
                    if session.isLoading && session.currentCard == nil {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if isNativeMode {
                        FlipContainer(showBack: session.showAnswer) { isBack in
                            cardSurface(isBack: isBack)
                        }
                    } else {
                        cardSurface(isBack: session.showAnswer)
                    }
                }
                .simultaneousGesture(swipeGesture)
            }
            .onChange(of: session.currentCardId, initial: true) { _, newId in
                whiteboard.switchToCard(newId)
                playNativeAudio()
            }
            .onChange(of: session.showAnswer) { _, shown in
                if shown { playNativeAudio() }
            }
            .onChange(of: session.replayRequestID) { _, _ in
                playNativeAudio()
            }
            .onChange(of: session.stopAudioRequestID) { _, _ in
                if isNativeMode { nativeAudioPlayer.stop() }
            }
            .onChange(of: nativeAudioPlayer.isPlaying) { _, playing in
                if isNativeMode { session.updateAudioPlaying(playing) }
            }

            Spacer(minLength: 0)

            bottomNavigationBar
        }
        .animation(AmgiMotion.quick, value: session.showAnswer)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 44, coordinateSpace: .local)
            .onEnded { value in
                guard !whiteboard.isOpen || !whiteboard.isDrawingActive else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > abs(dy) * 1.4 else { return }
                if dx < -50 {
                    session.goNext()
                } else if dx > 50 {
                    session.goPrevious()
                }
            }
    }

    @ViewBuilder
    private func cardSurface(isBack: Bool) -> some View {
        switch session.resolvedMode {
        case .native(let front, let back):
            NativeCardView(
                content: isBack ? back : front,
                isAnswerSide: isBack,
                mediaFolder: session.mediaFolder
            )
        case .html:
            CardWebView(
                html: isBack ? session.backHTML : session.frontHTML,
                cardCSS: session.cardCSS,
                autoplayEnabled: false,
                isAnswerSide: isBack,
                cardOrdinal: session.currentCardOrdinal,
                replayRequestID: session.replayRequestID,
                stopAudioRequestID: session.stopAudioRequestID,
                openLinksExternally: openLinksExternally,
                lookupPopupEnabled: tapLookup,
                dictionaryScanLength: dictionaryScanLength,
                lookupHighlight: lookupHighlight,
                contentAlignment: CardWebViewContentAlignment(rawValue: cardContentAlignment) ?? .center,
                onAudioStateChange: { playing in session.updateAudioPlaying(playing) },
                onCardBackgroundColorChange: { color, isDark in
                    session.updateCardChrome(color: color, isDark: isDark)
                },
                onLookupRequested: tapLookup ? { text, _, _ in
                    if let text, !text.isEmpty { destination = .lookup(text) }
                } : nil,
                onShowAnswerRequested: { session.revealAnswer() }
            )
        }
    }

    private var bottomNavigationBar: some View {
        VStack(spacing: AmgiSpacing.xs) {
            Divider()
            HStack(spacing: AmgiSpacing.md) {
                Button {
                    session.goPrevious()
                } label: {
                    Image(systemName: "chevron.left")
                        .amgiFont(.bodyEmphasis)
                        .frame(width: 44, height: 44)
                        .background(palette.surface, in: Circle())
                        .overlay { Circle().strokeBorder(palette.separator, lineWidth: 1) }
                }
                .buttonStyle(.pressScale)
                .disabled(!session.canGoPrevious)
                .keyboardShortcut(keyboardActive ? KeyboardShortcut(.leftArrow, modifiers: []) : nil)
                .accessibilityLabel("Previous card")

                Button {
                    session.toggleAnswer()
                } label: {
                    Text(session.showAnswer ? "Show Question" : "Show Answer")
                        .amgiFont(.bodyEmphasis)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(keyboardActive ? KeyboardShortcut(.space, modifiers: []) : nil)

                Button {
                    session.toggleAutoShowAnswer()
                } label: {
                    Image(systemName: session.autoShowAnswer ? "eye.fill" : "eye")
                        .amgiFont(.bodyEmphasis)
                        .foregroundStyle(session.autoShowAnswer ? palette.accent : palette.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(
                            session.autoShowAnswer ? palette.accentSoft : palette.surface,
                            in: Circle()
                        )
                        .overlay { Circle().strokeBorder(palette.separator, lineWidth: 1) }
                }
                .buttonStyle(.pressScale)
                .accessibilityLabel(session.autoShowAnswer ? "Disable auto-show answer" : "Enable auto-show answer")

                Button {
                    session.goNext()
                } label: {
                    Image(systemName: "chevron.right")
                        .amgiFont(.bodyEmphasis)
                        .frame(width: 44, height: 44)
                        .background(palette.surface, in: Circle())
                        .overlay { Circle().strokeBorder(palette.separator, lineWidth: 1) }
                }
                .buttonStyle(.pressScale)
                .disabled(!session.canGoNext)
                .keyboardShortcut(keyboardActive ? KeyboardShortcut(.rightArrow, modifiers: []) : nil)
                .accessibilityLabel("Next card")
            }
            .padding(.horizontal, AmgiSpacing.lg)
            .padding(.vertical, AmgiSpacing.sm)
        }
        .background(palette.background)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Close")
        }

        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text(session.deckName.isEmpty ? (request.title ?? "Card Viewer") : session.deckName)
                    .amgiFont(.bodyEmphasis)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(session.cardStatusSummary.isEmpty ? "Preview (no grading)" : "Preview · \(session.cardStatusSummary)")
                    .amgiFont(.micro)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
        }

        if !session.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(session.currentIndex + 1)/\(session.totalCount)")
                    .amgiFont(.caption)
                    .monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                whiteboard.toggleOpen()
            } label: {
                Image(systemName: whiteboard.isOpen ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                    .foregroundStyle(whiteboard.isOpen ? palette.accent : palette.textPrimary)
            }
            .accessibilityLabel(whiteboard.isOpen ? "Hide whiteboard" : "Show whiteboard")
        }

        ToolbarItem(placement: .topBarTrailing) {
            previewActionsMenu
        }
    }

    private var previewActionsMenu: some View {
        let cardId = session.currentCardId
        let note = session.currentNote
        let templateTarget = session.currentTemplateTarget
        let isAudioPlaying = session.isAudioPlaying
        let currentFlag = cardActions.currentFlag
        let isMarked = cardActions.isMarkedNote
        let isSuspended = cardActions.isSuspended
        let isBuried = cardActions.isBuried
        let menuIdentity = "\(cardId?.rawValue ?? -1)-\(note?.id.rawValue ?? -1)-\(isAudioPlaying)-\(currentFlag)-\(isMarked)-\(isSuspended)-\(isBuried)"

        return Menu {
            if let cardId {
                CardFlagPicker(
                    model: cardActions,
                    cardId: cardId,
                    onAction: { _ in
                        onCollectionChanged()
                        session.refreshAfterCardAction()
                    }
                )
            }

            Section {
                Button {
                    cardActions.presentAfterMenuDismiss {
                        destination = note.map(CardPreviewDestination.editNote)
                    }
                } label: {
                    Label("Edit Note", systemImage: "pencil")
                }
                .disabled(note == nil)

                Button {
                    cardActions.presentAfterMenuDismiss {
                        destination = templateTarget.map(CardPreviewDestination.editTemplate)
                    }
                } label: {
                    Label("Edit Template", systemImage: "square.and.pencil")
                }
                .disabled(templateTarget == nil)

                Button {
                    cardActions.presentAfterMenuDismiss {
                        destination = .lookup("")
                    }
                } label: {
                    Label("Look Up", systemImage: "character.book.closed")
                }

                Button {
                    if isAudioPlaying {
                        session.bumpStopAudioRequest()
                    } else {
                        session.bumpReplayRequest()
                    }
                } label: {
                    Label(
                        isAudioPlaying ? "Stop Audio" : "Replay Audio",
                        systemImage: isAudioPlaying ? "pause.circle" : "play.circle"
                    )
                }
                .disabled(note == nil)
            }

            if let cardId {
                CardActionSections(
                    model: cardActions,
                    cardId: cardId,
                    noteId: note?.id,
                    confirmDeleteNote: $confirmDeleteNote,
                    onAction: { _ in
                        onCollectionChanged()
                        session.refreshAfterCardAction()
                    }
                )
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(
                    currentFlag == 0
                        ? palette.accent
                        : CardFlag.color(currentFlag)
                )
        }
        .id(menuIdentity)
        .disabled(cardId == nil)
        .accessibilityLabel("Card actions")
    }

    private func playNativeAudio() {
        guard case .native(let front, let back) = session.resolvedMode else { return }
        let files = session.showAnswer ? back.audioFiles : front.audioFiles
        guard !files.isEmpty else { return }
        nativeAudioPlayer.play(files: files, mediaFolder: session.mediaFolder)
    }
}
