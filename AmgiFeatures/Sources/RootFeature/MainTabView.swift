//
//  MainTabView.swift
//  RootFeature
//
//  Created by Vladimir Gusev on 27.03.2026.
//

import AppCore
import AnkiKit
import BrowseFeature
import DecksFeature
import ReaderFeature
import SettingsFeature
import Sharing
import StatsFeature
import SwiftUI
import SyncFeature

/// Root tab bar. Pure layout: each tab wraps a feature view in a
/// `NavigationStack`. `refreshID` (bumped by the host after sync / import /
/// review) now only drives the tabs not yet on `CollectionStore` — Library
/// and Study reload via the store's generation instead. All side effects are
/// forwarded to the host via closures or `\.startSync` so this view owns no
/// I/O or sync state.
///
/// `refreshID` is *handed to* the two tabs that reload from it, not applied as
/// an `.id()`. As an `.id()` it discarded each tab's whole subtree — scroll
/// position, search text, selected deck, pushed navigation — to trigger a
/// reload their own `.task` already performs. Settings took the teardown and
/// got nothing for it: its root has no data load at all.
struct MainTabView: View {
    let refreshID: UUID
    let showReaderTab: Bool
    var isGlobalShortcutsEnabled: Bool = true
    let onImport: () -> Void
    let onSelectStudyDeck: (DeckID) -> Void

    @Environment(\.startSync) private var startSync

    @Shared(.appStorage(ShortcutPreferences.Keys.keyboardShortcutsEnabled))
    private var keyboardShortcutsEnabled: Bool = true

    private enum MainTab: Hashable {
        case library, browse, read, study, stats, settings
    }

    @State private var selection: MainTab = .library
    @State private var showAddNoteSheet = false

    private var globalCommandShortcutsActive: Bool {
        isGlobalShortcutsEnabled && keyboardShortcutsEnabled && !showAddNoteSheet
    }

    private var singleKeyGlobalShortcutsActive: Bool {
        globalCommandShortcutsActive && selection != .browse
    }

    var body: some View {
        TabView(selection: $selection) {
            // 1. Library
            Tab("Library", systemImage: "rectangle.stack", value: MainTab.library) {
                NavigationStack {
                    DeckListView(
                        onSwitchProfile: { await switchProfile(to: $0) },
                        onSync: { startSync() },
                        onImport: onImport
                    )
                }
            }
            // 2. Card & Note Browser
            Tab("Browse", systemImage: "rectangle.grid.1x2", value: MainTab.browse) {
                NavigationStack {
                    BrowseView()
                }
            }
            // 3. Reader and 4. Study both live in ReaderFeature.
            if showReaderTab {
                Tab("Read", systemImage: "book", value: MainTab.read) {
                    NavigationStack {
                        ReaderLibraryView(refreshID: refreshID)
                    }
                }
            }
            Tab("Study", systemImage: "graduationcap", value: MainTab.study) {
                NavigationStack {
                    StudyLandingView(onSelectDeck: onSelectStudyDeck)
                }
            }
            // 4. Stats
            Tab("Stats", systemImage: "chart.bar", value: MainTab.stats) {
                NavigationStack {
                    StatsDashboardView(refreshID: refreshID)
                }
            }
            // 5. Settings
            Tab("Settings", systemImage: "gearshape", value: MainTab.settings) {
                NavigationStack {
                    SettingsView(onSwitchProfile: { await switchProfile(to: $0) })
                }
            }
        }
        .sheet(isPresented: $showAddNoteSheet) {
            AddNoteView(preselectedDeckId: nil) {
                showAddNoteSheet = false
            }
        }
        .background {
            ZStack {
                Group {
                    Button("Decks") { selection = .library }
                        .keyboardShortcut(globalCommandShortcutsActive ? KeyboardShortcut("1", modifiers: .command) : nil)
                    Button("Browse") { selection = .browse }
                        .keyboardShortcut(globalCommandShortcutsActive ? KeyboardShortcut("2", modifiers: .command) : nil)
                    Button("Study") { selection = .study }
                        .keyboardShortcut(globalCommandShortcutsActive ? KeyboardShortcut("3", modifiers: .command) : nil)
                    Button("Stats") { selection = .stats }
                        .keyboardShortcut(globalCommandShortcutsActive ? KeyboardShortcut("4", modifiers: .command) : nil)
                    Button("Settings") { selection = .settings }
                        .keyboardShortcut(globalCommandShortcutsActive ? KeyboardShortcut(",", modifiers: .command) : nil)
                    Button("Sync") { startSync() }
                        .keyboardShortcut(globalCommandShortcutsActive ? KeyboardShortcut("y", modifiers: .command) : nil)
                }
                Group {
                    Button("Decks (D)") { selection = .library }
                        .keyboardShortcut(singleKeyGlobalShortcutsActive ? KeyboardShortcut("d", modifiers: []) : nil)
                    Button("Browse (B)") { selection = .browse }
                        .keyboardShortcut(singleKeyGlobalShortcutsActive ? KeyboardShortcut("b", modifiers: []) : nil)
                    Button("Study (S)") { selection = .study }
                        .keyboardShortcut(singleKeyGlobalShortcutsActive ? KeyboardShortcut("s", modifiers: []) : nil)
                    Button("Add Note") { showAddNoteSheet = true }
                        .keyboardShortcut(singleKeyGlobalShortcutsActive ? KeyboardShortcut("a", modifiers: []) : nil)
                    Button("Sync (Y)") { startSync() }
                        .keyboardShortcut(singleKeyGlobalShortcutsActive ? KeyboardShortcut("y", modifiers: []) : nil)
                }
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

}
