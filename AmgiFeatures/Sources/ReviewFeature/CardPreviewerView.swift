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
import Dependencies
import BrowseFeature
import TemplatesFeature
import Sharing
import ReviewCore
import SwiftUINavigation

/// AnkiDroid-style non-marking Card Viewer / Previewer.
/// Lets the user browse through cards, flip Question/Answer, toggle auto-reveal,
/// annotate with the GoodNotes-style Whiteboard, and edit/flag/reschedule cards
/// without affecting FSRS scheduling or review counts.
package struct CardPreviewerView: View {
    let request: CardPreviewRequest
    let onCollectionChanged: @MainActor @Sendable () -> Void
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
    @State private var destination: ReviewDestination?
    @State private var showRenderModeSheet = false
    @State private var lookupHighlight = LookupHighlight()
    @State private var nativeAudioPlayer = NativeCardAudioPlayer()
    @State private var scrollController = CardScrollController()
    @State private var gamepadToken: GameControllerManager.HandlerToken?

    @Shared(.appStorage(ShortcutPreferences.Keys.keyboardShortcutsEnabled))
    private var keyboardShortcutsEnabled: Bool = true

    package init(
        request: CardPreviewRequest,
        onCollectionChanged: @escaping @MainActor @Sendable () -> Void = {},
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

    private var overlaysClear: Bool {
        destination == nil && !confirmDeleteNote && !showRenderModeSheet && cardActions.activeSheet == nil
    }

    private var keyboardActive: Bool {
        keyboardShortcutsEnabled && overlaysClear
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
                let onCollectionChanged = self.onCollectionChanged
                let session = self.session
                NavigationStack {
                    TemplateEditorView(
                        notetypeId: target.notetypeId,
                        initialTemplateIndex: target.ordinal,
                        mode: .currentCard,
                        onSaved: {
                            await MainActor.run {
                                onCollectionChanged()
                                session.refreshAfterCardAction()
                            }
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
            .background {
                previewShortcutButtons
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .task {
            ReviewAudioSession.apply(playInSilent: playAudioInSilentMode)
            session.start()
        }
        .onAppear {
            gamepadToken = GameControllerManager.shared.registerHandler(
                onAction: { action in
                    guard overlaysClear, !session.isEmpty else { return }
                    performShortcutAction(action)
                },
                onScrollDelta: { delta in
                    guard overlaysClear, !session.isEmpty else { return }
                    scrollController.scroll(by: delta)
                }
            )
        }
        .onDisappear {
            if let token = gamepadToken {
                GameControllerManager.shared.unregisterHandler(token)
                gamepadToken = nil
            }
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
                mediaFolder: session.mediaFolder,
                scrollRequestID: scrollController.requestID,
                scrollDelta: scrollController.delta
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
                scrollRequestID: scrollController.requestID,
                scrollDelta: scrollController.delta,
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
                        destination = note.map(ReviewDestination.editNote)
                    }
                } label: {
                    Label("Edit Note", systemImage: "pencil")
                }
                .disabled(note == nil)

                Button {
                    cardActions.presentAfterMenuDismiss {
                        destination = templateTarget.map(ReviewDestination.editTemplate)
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

    @ViewBuilder
    private var previewShortcutButtons: some View {
        Group {
            previewShortcutButton("Flip Question / Answer", key: .return) { performShortcutAction(.showAnswerOrGood) }
            previewShortcutButton("Scroll Card Down", key: .downArrow) { performShortcutAction(.scrollDown) }
            previewShortcutButton("Scroll Card Down (J)", key: "j") { performShortcutAction(.scrollDown) }
            previewShortcutButton("Scroll Card Up", key: .upArrow) { performShortcutAction(.scrollUp) }
            previewShortcutButton("Scroll Card Up (K)", key: "k") { performShortcutAction(.scrollUp) }
            previewShortcutButton("Edit Note", key: "e") { performShortcutAction(.editNote) }
            previewShortcutButton("Replay Audio", key: "r") { performShortcutAction(.replayAudio) }
            previewShortcutButton("Mark Note", key: "*") { performShortcutAction(.toggleMark) }
            previewShortcutButton("Bury Card", key: "-") { performShortcutAction(.buryCard) }
            previewShortcutButton("Suspend Card", key: "@") { performShortcutAction(.suspendCard) }
            previewShortcutButton("Toggle Whiteboard", key: "w") { performShortcutAction(.toggleWhiteboard) }
            previewShortcutButton("Clear Whiteboard", key: "w", modifiers: .shift) { performShortcutAction(.clearWhiteboard) }
            previewShortcutButton("Close Viewer", key: .escape) { performShortcutAction(.closeReview) }
        }
        Group {
            previewShortcutButton("Flag Red", key: "1", modifiers: .command) { performShortcutAction(.flagRed) }
            previewShortcutButton("Flag Orange", key: "2", modifiers: .command) { performShortcutAction(.flagOrange) }
            previewShortcutButton("Flag Green", key: "3", modifiers: .command) { performShortcutAction(.flagGreen) }
            previewShortcutButton("Flag Blue", key: "4", modifiers: .command) { performShortcutAction(.flagBlue) }
            previewShortcutButton("Flag Pink", key: "5", modifiers: .command) { performShortcutAction(.flagPink) }
            previewShortcutButton("Flag Cyan", key: "6", modifiers: .command) { performShortcutAction(.flagCyan) }
            previewShortcutButton("Flag Purple", key: "7", modifiers: .command) { performShortcutAction(.flagPurple) }
            previewShortcutButton("Clear Flag", key: "0", modifiers: .command) { performShortcutAction(.clearFlag) }
            previewShortcutButton("Reschedule Card", key: "d", modifiers: [.command, .shift]) { performShortcutAction(.reschedule) }
            previewShortcutButton("Change Deck", key: "d", modifiers: .command) { performShortcutAction(.changeDeck) }
        }
    }

    private func previewShortcutButton(
        _ title: String,
        key: KeyEquivalent,
        modifiers: EventModifiers = [],
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .keyboardShortcut(keyboardActive && !session.isEmpty ? KeyboardShortcut(key, modifiers: modifiers) : nil)
    }

    private func performShortcutAction(_ action: ReviewShortcutAction) {
        switch action {
        case .none:
            break
        case .showAnswerOrGood, .showAnswer, .answerHard:
            session.toggleAnswer()
        case .answerAgain, .undo:
            if session.canGoPrevious { session.goPrevious() }
        case .answerGood, .answerEasy:
            if session.canGoNext { session.goNext() }
        case .replayAudio:
            if session.isAudioPlaying {
                session.bumpStopAudioRequest()
            } else {
                session.bumpReplayRequest()
            }
        case .editNote:
            if let note = session.currentNote {
                destination = .editNote(note)
            }
        case .toggleMark:
            if let noteId = session.currentNote?.id {
                Task {
                    _ = await cardActions.toggleMarked(noteId)
                    onCollectionChanged()
                    session.refreshAfterCardAction()
                }
            }
        case .buryCard:
            if let cardId = session.currentCardId {
                Task {
                    if await cardActions.toggleBury(cardId) != nil {
                        onCollectionChanged()
                        session.refreshAfterCardAction()
                    }
                }
            }
        case .buryNote:
            if let noteId = session.currentNote?.id {
                Task {
                    if await cardActions.buryNote(noteId) != nil {
                        onCollectionChanged()
                        session.refreshAfterCardAction()
                    }
                }
            }
        case .suspendCard:
            if let cardId = session.currentCardId {
                Task {
                    if await cardActions.toggleSuspend(cardId) != nil {
                        onCollectionChanged()
                        session.refreshAfterCardAction()
                    }
                }
            }
        case .suspendNote:
            if let noteId = session.currentNote?.id {
                Task {
                    if await cardActions.suspendNote(noteId) != nil {
                        onCollectionChanged()
                        session.refreshAfterCardAction()
                    }
                }
            }
        case .reschedule:
            if let cardId = session.currentCardId {
                cardActions.activeSheet = .reschedule([cardId])
            }
        case .changeDeck:
            if let cardId = session.currentCardId {
                cardActions.activeSheet = .changeDeck(cardIds: [cardId], currentDeckId: cardActions.currentDeckId)
            }
        case .deleteNote:
            if session.currentNote != nil {
                confirmDeleteNote = true
            }
        case .flagRed, .flagOrange, .flagGreen, .flagBlue, .flagPink, .flagCyan, .flagPurple:
            guard let cardId = session.currentCardId, let flagVal = action.flagValue else { return }
            let next: UInt32 = cardActions.currentFlag == flagVal ? 0 : flagVal
            Task {
                _ = await cardActions.flag(cardId, next)
                onCollectionChanged()
                session.refreshAfterCardAction()
            }
        case .clearFlag:
            guard let cardId = session.currentCardId else { return }
            Task {
                _ = await cardActions.flag(cardId, 0)
                onCollectionChanged()
                session.refreshAfterCardAction()
            }
        case .toggleWhiteboard:
            whiteboard.toggleOpen()
        case .clearWhiteboard:
            if whiteboard.isOpen { whiteboard.clear() }
        case .scrollDown:
            scrollController.scroll(by: 180)
        case .scrollUp:
            scrollController.scroll(by: -180)
        case .closeReview:
            onDismiss()
        }
    }
}
