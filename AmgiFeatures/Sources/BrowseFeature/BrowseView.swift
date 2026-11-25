//
//  BrowseView.swift
//  BrowseFeature
//
//  Created by Vladimir Gusev on 27.03.2026.
//

package import SwiftUI
import AppCore
import AppShared
package import AnkiKit
import Dependencies
import Theme
import SwiftUINavigation

enum BrowseSortOrder: String, CaseIterable, Sendable {
    case dateDesc = "Date (newest)"
    case titleAsc = "Title (A→Z)"
    case templateAsc = "Type (A→Z)"
}

/// Browse container: AnkiDroid-style Card & Note Browser.
/// In Cards mode, tapping a card launches the non-marking Card Viewer (`CardPreviewerView`);
/// in Notes mode, tapping a note opens `NoteEditingDestinationView`.
package struct BrowseView: View {
    @State private var model: BrowseModel
    @State private var selectionState = BrowseSelectionState()
    @State private var destination: BrowseDestination?
    @State private var pendingTool: BrowseTool?
    @State private var previewRequest: CardPreviewRequest?
    @State private var cardActions = CardContextMenuModel()
    @State private var hostConfirmDeleteNote = false
    @State private var hostContextCardId: CardID?
    @State private var hostContextNoteId: NoteID?
    @FocusState private var searchFocused: Bool

    @Environment(\.cardPreview) private var cardPreview
    @Dependency(\.collectionStore) private var store

    package init(initialDeck: DeckInfo? = nil) {
        _model = State(initialValue: BrowseModel(browseMode: .cards, initialDeck: initialDeck))
    }

    init(model: BrowseModel) {
        _model = State(initialValue: model)
    }

    package var body: some View {
        @Bindable var model = model
        decoratedContent
            .searchable(
                text: $model.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: model.browseMode == .cards ? "Search cards (deck:, tag:, is:due)..." : "Search notes..."
            )
            .searchFocused($searchFocused)
            .task { await model.loadInitial() }
            .task(id: model.searchQuery) { await model.performSearch() }
            .sensoryFeedback(trigger: selectionState.isSelectMode) { _, entered in
                entered ? .selection : nil
            }
            .fullScreenCover(item: $previewRequest) { request in
                if let cardPreview {
                    cardPreview.previewView(
                        request: request,
                        onCollectionChanged: {
                            store.invalidateAll()
                        },
                        onDismiss: {
                            previewRequest = nil
                            Task { await model.performSearch(debounce: .zero) }
                        }
                    )
                }
            }
    }

    private var decoratedContent: some View {
        dialogContent
            .navigationTitle("Browse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .toolbarVisibility(selectionState.isSelectMode ? .hidden : .automatic, for: .tabBar)
            .navigationDestination(item: $pendingTool) { tool in
                switch tool {
                case .duplicates: DuplicatesView()
                }
            }
            .cardActionPresentations(
                model: cardActions,
                cardId: hostContextCardId,
                noteId: hostContextNoteId,
                confirmDeleteNote: $hostConfirmDeleteNote,
                onAction: { _ in
                    store.invalidateAll()
                    Task { await model.performSearch(debounce: .zero) }
                }
            )
    }

    private var dialogContent: some View {
        sheetContent
            .confirmationDialog(
                "Delete this note?",
                isPresented: Binding($destination.deleteNote),
                presenting: pendingSwipeDelete
            ) { note in
                Button("Delete", role: .destructive) {
                    Task { await model.delete(note.id) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This action cannot be undone.")
            }
            .confirmationDialog(
                "Delete this note?",
                isPresented: Binding($destination.deleteNoteByID),
                presenting: pendingDeleteNoteID
            ) { noteId in
                Button("Delete", role: .destructive) {
                    Task { await model.delete(noteId) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This deletes the note and all its cards. This action cannot be undone.")
            }
            .confirmationDialog(
                model.browseMode == .cards
                    ? "Delete \(selectionState.selectedCardIDs.count) card\(selectionState.selectedCardIDs.count == 1 ? "" : "s")?"
                    : "Delete \(selectionState.selectedNoteIDs.count) note\(selectionState.selectedNoteIDs.count == 1 ? "" : "s")?",
                isPresented: $destination.deleteSelected
            ) {
                Button("Delete", role: .destructive) {
                    deleteSelected()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
    }

    private var pendingSwipeDelete: NoteRecord? {
        if case .deleteNote(let note) = destination { return note }
        return nil
    }

    private var pendingDeleteNoteID: NoteID? {
        if case .deleteNoteByID(let nid) = destination { return nid }
        return nil
    }

    private var pendingRescheduleCardIDs: [CardID]? {
        if case .rescheduleSelectedCards(let ids) = destination { return ids }
        return nil
    }

    private var pendingChangeDeckCardIDs: [CardID]? {
        if case .changeDeckSelectedCards(let ids) = destination { return ids }
        return nil
    }

    private var sheetContent: some View {
        BrowseContent(
            model: model,
            cardActions: cardActions,
            selectionState: $selectionState,
            onPreviewCard: { index in
                previewCards(startingAt: index)
            },
            onEditNote: { note in
                destination = .editNote(note)
            },
            onRequestDeleteNote: { noteId in
                destination = .deleteNoteByID(noteId)
            },
            onSwipeDelete: { destination = .deleteNote($0) }
        )
        .sheet(isPresented: $destination.addNote) {
            AddNoteView(preselectedDeckId: model.activeDeck?.id) {
                Task { await model.performSearch(debounce: .zero) }
            }
        }
        #if canImport(UIKit)
        .sheet(isPresented: $destination.addImageOcclusion) {
            AddImageOcclusionNoteView { Task { await model.performSearch(debounce: .zero) } }
        }
        #endif
        .sheet(item: $destination.editNote) { note in
            NoteEditingDestinationView(note: note, embedInNavigationStack: true) {
                Task { await model.performSearch(debounce: .zero) }
            }
        }
        .sheet(isPresented: Binding(
            get: { pendingRescheduleCardIDs != nil },
            set: { if !$0 { destination = nil } }
        )) {
            if let ids = pendingRescheduleCardIDs {
                RescheduleCardSheet(cardIds: ids) { spec in
                    await model.rescheduleSelectedCards(ids, spec: spec)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { pendingChangeDeckCardIDs != nil },
            set: { if !$0 { destination = nil } }
        )) {
            if let ids = pendingChangeDeckCardIDs {
                ChangeDeckSheet(cardIds: ids) { deckId in
                    await model.changeDeckSelectedCards(ids, to: deckId)
                }
            }
        }
        .alert(
            "Some changes didn't apply",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(isPresented: $destination.findReplaceSelected) {
            FindReplaceSheet(noteIDs: Array(selectionState.selectedNoteIDs)) {
                Task { await model.performSearch(debounce: .zero) }
            }
        }
        .sheet(isPresented: $destination.findReplaceAll) {
            FindReplaceSheet(noteIDs: []) {
                Task { await model.performSearch(debounce: .zero) }
            }
        }
        .sheet(isPresented: $destination.batchTag) {
            BatchTagSheet(noteIDs: selectionState.selectedNoteIDs) {
                Task {
                    selectionState.exitSelectMode()
                    await model.performSearch(debounce: .zero)
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if selectionState.isSelectMode {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    selectionState.exitSelectMode()
                }
            }
            selectionToolbar
        } else {
            if model.browseMode == .cards && !model.allCardIDs.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        previewCards(startingAt: 0)
                    } label: {
                        Label("Preview", systemImage: "eye")
                    }
                    .accessibilityLabel("Preview filtered cards")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add Note", systemImage: "square.and.pencil") {
                        destination = .addNote
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    Button("Add Image Occlusion", systemImage: "rectangle.on.rectangle") {
                        destination = .addImageOcclusion
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if !model.notes.isEmpty || !model.cardItems.isEmpty {
                        Section {
                            Button("Select", systemImage: "checkmark.circle") {
                                if model.browseMode == .cards {
                                    selectionState.enterCardSelectMode()
                                } else {
                                    selectionState.enterSelectMode()
                                }
                            }
                        }
                        if model.browseMode == .notes {
                            Section {
                                Picker("Sort By", selection: $model.sortOrder) {
                                    ForEach(BrowseSortOrder.allCases, id: \.self) { order in
                                        Text(order.rawValue).tag(order)
                                    }
                                }
                                .pickerStyle(.inline)
                            }
                        }
                    }
                    Section {
                        Button("Find", systemImage: "magnifyingglass") {
                            searchFocused = true
                        }
                        .keyboardShortcut("f", modifiers: .command)
                        Button("Find Duplicates", systemImage: "doc.on.doc") {
                            pendingTool = .duplicates
                        }
                        Button("Find & Replace", systemImage: "text.magnifyingglass") {
                            destination = .findReplaceAll
                        }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var selectionToolbar: some ToolbarContent {
        if model.browseMode == .cards {
            ToolbarItem(placement: .bottomBar) {
                Menu {
                    Button { suspendSelectedCards() } label: { Label("Suspend", systemImage: "pause.circle") }
                    Button { unsuspendSelectedCards() } label: { Label("Unsuspend / Unbury", systemImage: "play.circle") }
                } label: {
                    Label("State", systemImage: "pause.circle")
                }
                .disabled(selectionState.selectedCardIDs.isEmpty)
            }
            ToolbarItem(placement: .bottomBar) { Spacer() }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    let ids = Array(selectionState.selectedCardIDs)
                    selectionState.exitSelectMode()
                    destination = .rescheduleSelectedCards(ids)
                } label: {
                    Label("Reschedule", systemImage: "calendar.badge.clock")
                }
                .disabled(selectionState.selectedCardIDs.isEmpty)
            }
            ToolbarItem(placement: .bottomBar) { Spacer() }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    let ids = Array(selectionState.selectedCardIDs)
                    selectionState.exitSelectMode()
                    destination = .changeDeckSelectedCards(ids)
                } label: {
                    Label("Deck", systemImage: "folder")
                }
                .disabled(selectionState.selectedCardIDs.isEmpty)
            }
            ToolbarItem(placement: .bottomBar) { Spacer() }
            ToolbarItem(placement: .bottomBar) {
                flagMenu.disabled(selectionState.selectedCardIDs.isEmpty)
            }
            ToolbarItem(placement: .bottomBar) { Spacer() }
            ToolbarItem(placement: .bottomBar) {
                Button(role: .destructive) {
                    destination = .deleteSelected
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectionState.selectedCardIDs.isEmpty)
            }
        } else {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    suspendSelected()
                } label: {
                    Label("Suspend", systemImage: "pause.circle")
                }
                .disabled(selectionState.isEmpty)
            }
            ToolbarItem(placement: .bottomBar) { Spacer() }
            ToolbarItem(placement: .bottomBar) {
                flagMenu.disabled(selectionState.isEmpty)
            }
            ToolbarItem(placement: .bottomBar) { Spacer() }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    destination = .batchTag
                } label: {
                    Label("Tags", systemImage: "tag")
                }
                .disabled(selectionState.isEmpty)
            }
            ToolbarItem(placement: .bottomBar) { Spacer() }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    destination = .findReplaceSelected
                } label: {
                    Label("Find & Replace", systemImage: "text.magnifyingglass")
                }
                .disabled(selectionState.isEmpty)
            }
            ToolbarItem(placement: .bottomBar) { Spacer() }
            ToolbarItem(placement: .bottomBar) {
                Button(role: .destructive) {
                    destination = .deleteSelected
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectionState.isEmpty)
            }
        }
    }

    private var flagMenu: some View {
        Menu {
            Button { applyFlag(1) } label: { Label("Red flag",       systemImage: "flag.fill") }
            Button { applyFlag(2) } label: { Label("Orange flag",    systemImage: "flag.fill") }
            Button { applyFlag(3) } label: { Label("Green flag",     systemImage: "flag.fill") }
            Button { applyFlag(4) } label: { Label("Blue flag",      systemImage: "flag.fill") }
            Button { applyFlag(5) } label: { Label("Pink flag",      systemImage: "flag.fill") }
            Button { applyFlag(6) } label: { Label("Turquoise flag", systemImage: "flag.fill") }
            Button { applyFlag(7) } label: { Label("Purple flag",    systemImage: "flag.fill") }
            Divider()
            Button { applyFlag(0) } label: { Label("Clear flag",     systemImage: "flag.slash") }
        } label: {
            Label("Flag", systemImage: "flag")
        }
    }

    // MARK: - Preview launch

    private func previewCards(startingAt index: Int) {
        guard !model.allCardIDs.isEmpty else { return }
        previewRequest = CardPreviewRequest(
            cardIds: model.allCardIDs,
            initialIndex: index,
            title: model.activeDeck?.name ?? "Card Viewer"
        )
    }

    // MARK: - Selection actions

    private func suspendSelected() {
        let ids = selectionState.selectedNoteIDs
        selectionState.exitSelectMode()
        Task { await model.suspendSelected(ids) }
    }

    private func suspendSelectedCards() {
        let ids = selectionState.selectedCardIDs
        selectionState.exitSelectMode()
        Task { await model.suspendSelectedCards(ids) }
    }

    private func unsuspendSelectedCards() {
        let ids = selectionState.selectedCardIDs
        selectionState.exitSelectMode()
        Task { await model.unsuspendSelectedCards(ids) }
    }

    private func applyFlag(_ value: UInt32) {
        if model.browseMode == .cards {
            let ids = selectionState.selectedCardIDs
            selectionState.exitSelectMode()
            Task { await model.flagSelectedCards(ids, value: value) }
        } else {
            let ids = selectionState.selectedNoteIDs
            selectionState.exitSelectMode()
            Task { await model.flagSelected(ids, value: value) }
        }
    }

    private func deleteSelected() {
        if model.browseMode == .cards {
            let ids = selectionState.selectedCardIDs
            selectionState.exitSelectMode()
            Task { await model.deleteSelectedCards(ids) }
        } else {
            let ids = selectionState.selectedNoteIDs
            selectionState.exitSelectMode()
            Task { await model.deleteSelected(ids) }
        }
    }
}

// MARK: - BrowseContent

struct BrowseContent: View {
    @Environment(\.palette) private var palette
    @Bindable var model: BrowseModel
    let cardActions: CardContextMenuModel
    @Binding var selectionState: BrowseSelectionState
    let onPreviewCard: (Int) -> Void
    let onEditNote: (NoteRecord) -> Void
    let onRequestDeleteNote: (NoteID) -> Void
    let onSwipeDelete: (NoteRecord) -> Void

    var body: some View {
        statefulContent
            .safeAreaInset(edge: .top) {
                filterBar
            }
    }

    @ViewBuilder
    private var statefulContent: some View {
        if model.browseMode == .cards {
            cardsStatefulContent
        } else {
            notesStatefulContent
        }
    }

    @ViewBuilder
    private var cardsStatefulContent: some View {
        if model.cardItems.isEmpty && !model.isLoading && model.searchFailed {
            searchFailedView
        } else if model.cardItems.isEmpty && !model.isLoading && model.searchText.isEmpty
            && model.activeDeck == nil && model.activeTag == nil && model.cardStateFilter == .all {
            ContentUnavailableView(
                "Browse Cards",
                systemImage: "rectangle.grid.1x2",
                description: Text("Search by content, tags, state, or filter by deck.")
            )
        } else if model.cardItems.isEmpty && !model.isLoading {
            ContentUnavailableView.search(text: model.searchText)
        } else {
            cardList
        }
    }

    @ViewBuilder
    private var notesStatefulContent: some View {
        if model.notes.isEmpty && !model.isLoading && model.searchText.isEmpty
            && model.activeDeck == nil && model.activeTag == nil {
            ContentUnavailableView(
                "Browse Notes",
                systemImage: "magnifyingglass",
                description: Text("Search by content, tags, or filter by deck.")
            )
        } else if model.notes.isEmpty && !model.isLoading && model.searchFailed {
            searchFailedView
        } else if model.notes.isEmpty && !model.isLoading {
            ContentUnavailableView.search(text: model.searchText)
        } else {
            noteList
        }
    }

    private var searchFailedView: some View {
        ContentUnavailableView {
            Label("Search Failed", systemImage: "exclamationmark.triangle")
        } description: {
            Text("The collection couldn't be searched.")
        } actions: {
            Button("Try Again") {
                Task { await model.performSearch(debounce: .zero) }
            }
        }
    }

    // MARK: - Card List (AnkiDroid-style)

    private var cardList: some View {
        List {
            ForEach(Array(model.cardItems.enumerated()), id: \.element.id) { index, item in
                cardRow(item, index: index)
            }

            if model.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func cardRow(_ item: BrowseCardItem, index: Int) -> some View {
        if selectionState.isSelectMode {
            Button {
                selectionState.toggleCard(item.id)
            } label: {
                HStack {
                    Image(systemName: selectionState.containsCard(item.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectionState.containsCard(item.id) ? palette.accent : palette.textSecondary)
                        .accessibilityHidden(true)
                    CardRowSummaryView(
                        item: item,
                        deckName: item.card.flatMap { model.deckNamesByID[$0.did] },
                        notetypeName: item.note.flatMap { model.notetypeNames[$0.mid] }
                    )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressScale)
            .accessibilityAddTraits(selectionState.containsCard(item.id) ? .isSelected : [])
            .onAppear { onCardRowAppear(item) }
        } else {
            HStack(spacing: AmgiSpacing.sm) {
                Button {
                    onPreviewCard(index)
                } label: {
                    CardRowSummaryView(
                        item: item,
                        deckName: item.card.flatMap { model.deckNamesByID[$0.did] },
                        notetypeName: item.note.flatMap { model.notetypeNames[$0.mid] }
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onAppear { onCardRowAppear(item) }

                HostedCardContextMenu(
                    model: cardActions,
                    cardId: item.id,
                    noteId: item.note?.id,
                    isSuspended: item.card?.queue == -1,
                    isBuried: item.card?.queue == -2 || item.card?.queue == -3,
                    onEditNote: item.note.map { note in { onEditNote(note) } },
                    onRequestDeleteNote: onRequestDeleteNote,
                    onAction: { _ in
                        Task { await model.performSearch(debounce: .zero) }
                    }
                )
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                    selectionState.enterCardSelectMode(preselect: item.id)
                }
            )
            .accessibilityAction(named: "Select") {
                selectionState.enterCardSelectMode(preselect: item.id)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if let note = item.note {
                    Button {
                        onEditNote(note)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                }
            }
        }
    }

    private func onCardRowAppear(_ item: BrowseCardItem) {
        if item.isStub {
            Task { await model.fetchCardDetails(id: item.id) }
        }
        if item.id == model.cardItems.last?.id {
            Task { await model.loadNextCardPage() }
        }
    }

    // MARK: - Note List

    private var noteList: some View {
        List {
            ForEach(model.sortedNotes, id: \.id) { note in
                noteRow(note)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            onSwipeDelete(note)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }

            if model.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func noteRow(_ note: NoteRecord) -> some View {
        HStack {
            if selectionState.isSelectMode {
                Button {
                    selectionState.toggle(note.id)
                } label: {
                    HStack {
                        Image(systemName: selectionState.contains(note.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectionState.contains(note.id) ? palette.accent : palette.textSecondary)
                            .accessibilityHidden(true)
                        NoteRowView(note: note, notetypeName: model.notetypeNames[note.mid])
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressScale)
                .accessibilityAddTraits(selectionState.contains(note.id) ? .isSelected : [])
                .onAppear { onRowAppear(note) }
            } else {
                HStack {
                    NavigationLink {
                        NoteEditingDestinationView(note: model.resolved(note)) {
                            Task { await model.performSearch() }
                        }
                    } label: {
                        NoteRowView(note: note, notetypeName: model.notetypeNames[note.mid])
                            .onAppear { onRowAppear(note) }
                    }
                    NoteContextMenuButton(
                        model: model,
                        cardActions: cardActions,
                        noteId: note.id,
                        onRequestDeleteNote: onRequestDeleteNote
                    ) {
                        Task { await model.performSearch(debounce: .zero) }
                    }
                }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                        selectionState.enterSelectMode(preselect: note.id)
                    }
                )
                .accessibilityAction(named: "Select") {
                    selectionState.enterSelectMode(preselect: note.id)
                }
            }
        }
    }

    private func onRowAppear(_ note: NoteRecord) {
        if note.sfld == "Loading..." {
            Task { await model.fetchNoteDetails(id: note.id) }
        }
        if note.id == model.notes.last?.id {
            Task { await model.loadNextPage() }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 0) {
            Picker("Browse Mode", selection: Binding(
                get: { model.browseMode },
                set: { newMode in
                    selectionState.exitSelectMode()
                    model.browseMode = newMode
                }
            )) {
                ForEach(BrowseMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, AmgiSpacing.sm)
            .padding(.bottom, AmgiSpacing.xs)

            if model.browseMode == .cards {
                cardStateChipRow
            }
            if !model.allDecks.isEmpty {
                deckFilterBar
            }
            if !model.allTags.isEmpty {
                tagChipRow
            }
        }
        .background(.bar)
    }

    private var cardStateChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AmgiSpacing.sm) {
                ForEach(BrowseCardStateFilter.allCases) { filter in
                    chipButton(
                        label: filter.rawValue,
                        isSelected: model.cardStateFilter == filter,
                        small: true
                    ) {
                        model.cardStateFilter = filter
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    private var tagChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton(label: "All", isSelected: model.activeTag == nil) {
                    model.activeTag = nil
                }
                ForEach(model.allTags, id: \.self) { tag in
                    chipButton(label: tag, isSelected: model.activeTag == tag) {
                        model.activeTag = (model.activeTag == tag) ? nil : tag
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var deckFilterBar: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chipButton(label: "All", isSelected: model.activeDeck == nil) {
                        model.parentDeck = nil
                        model.activeDeck = nil
                    }
                    ForEach(model.topLevelDecks) { deck in
                        chipButton(
                            label: deck.name,
                            isSelected: model.parentDeck?.id == deck.id && model.activeDeck?.id == deck.id
                        ) {
                            model.parentDeck = deck
                            model.activeDeck = deck
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            if !model.childDecks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chipButton(
                            label: "All",
                            isSelected: model.activeDeck?.id == model.parentDeck?.id,
                            small: true
                        ) {
                            model.activeDeck = model.parentDeck
                        }
                        ForEach(model.childDecks) { child in
                            chipButton(
                                label: shortName(child.name),
                                isSelected: model.activeDeck?.id == child.id,
                                small: true
                            ) {
                                model.activeDeck = child
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
        }
    }
}

private extension BrowseContent {
    func chipButton(
        label: String,
        isSelected: Bool,
        small: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .amgiFont(small ? .caption : .body)
                .padding(.horizontal, small ? 10 : 12)
                .padding(.vertical, small ? 4 : 6)
                .background(isSelected ? palette.accent : palette.surface)
                .foregroundStyle(isSelected ? .white : palette.textPrimary)
                .clipShape(Capsule())
        }
        .buttonStyle(.pressScale)
    }

    func shortName(_ fullName: String) -> String {
        String(fullName.split(separator: "::").last ?? Substring(fullName))
    }
}

// MARK: - CardRowSummaryView

private struct CardRowSummaryView: View {
    @Environment(\.palette) private var palette
    let item: BrowseCardItem
    let deckName: String?
    let notetypeName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.xs) {
            HStack(spacing: AmgiSpacing.xs) {
                if item.flagValue > 0 {
                    Image(systemName: "flag.fill")
                        .amgiFont(.micro)
                        .foregroundStyle(CardFlag.color(item.flagValue))
                }
                Text(item.title)
                    .amgiFont(.body)
                    .foregroundStyle(item.card?.queue == -1 ? palette.textSecondary : palette.textPrimary)
                    .lineLimit(1)
            }

            HStack(spacing: AmgiSpacing.sm) {
                if let state = item.stateLabel {
                    Text(state)
                        .amgiFont(.micro)
                        .foregroundStyle(stateColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(stateColor.opacity(0.14), in: Capsule())
                }
                if let deckName {
                    Text(deckName)
                        .amgiFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                if let notetypeName {
                    Text(notetypeName)
                        .amgiFont(.caption)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stateColor: Color {
        guard let card = item.card else { return palette.textSecondary }
        if card.queue == -1 || card.queue == -2 || card.queue == -3 {
            return palette.cardStateSuspended
        }
        switch card.type {
        case 0: return palette.cardStateNew
        case 1: return palette.cardStateLearning
        case 2: return palette.cardStateReview
        case 3: return palette.cardStateRelearn
        default: return palette.textSecondary
        }
    }
}

// MARK: - NoteContextMenuButton

@MainActor
struct NoteContextMenuButton: View {
    let model: BrowseModel
    let cardActions: CardContextMenuModel
    let noteId: NoteID
    var onRequestDeleteNote: ((NoteID) -> Void)?
    var onSuccess: (() -> Void)?

    @State private var cardId: CardID?

    var body: some View {
        Group {
            if let cardId {
                HostedCardContextMenu(
                    model: cardActions,
                    cardId: cardId,
                    noteId: noteId,
                    onRequestDeleteNote: onRequestDeleteNote,
                    onAction: { _ in onSuccess?() }
                )
            } else {
                Image(systemName: "ellipsis.circle")
                    .amgiFont(.bodyEmphasis)
                    .foregroundStyle(.tertiary)
            }
        }
        .task(id: noteId) {
            cardId = await model.firstCardID(for: noteId)
        }
    }
}

// MARK: - NoteRowView

struct NoteRowView: View {
    @Environment(\.palette) private var palette
    let note: NoteRecord
    let notetypeName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.sfld)
                .amgiFont(.body)
                .lineLimit(1)
            if let subtitle = composeNoteSubtitle(notetypeName: notetypeName, tags: note.tags) {
                Text(subtitle)
                    .amgiFont(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let model = BrowseModel()
    model.notes = [
        NoteRecord(id: NoteID(1), guid: "g1", mid: NotetypeID(1), mod: 1_700_000_300,
                   tags: "vocab", flds: "", sfld: "안녕하세요 — hello", csum: 0),
        NoteRecord(id: NoteID(2), guid: "g2", mid: NotetypeID(1), mod: 1_700_000_200,
                   tags: "marked grammar", flds: "", sfld: "Bonjour le monde", csum: 0),
        NoteRecord(id: NoteID(3), guid: "g3", mid: NotetypeID(2), mod: 1_700_000_100,
                   flds: "", sfld: "The quick brown fox jumps over the lazy dog", csum: 0),
    ]
    model.allNotes = model.notes
    model.hasMorePages = false
    model.notetypeNames = [NotetypeID(1): "Basic", NotetypeID(2): "Cloze"]
    model.allTags = ["vocab", "grammar", "marked"]
    return NavigationStack {
        BrowseContent(
            model: model,
            cardActions: CardContextMenuModel(),
            selectionState: .constant(BrowseSelectionState()),
            onPreviewCard: { _ in },
            onEditNote: { _ in },
            onRequestDeleteNote: { _ in },
            onSwipeDelete: { _ in }
        )
        .navigationTitle("Browse")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
