//
//  ReviewSettingsView.swift
//  SettingsFeature
//
//  Created by Vladimir Gusev on 02.05.2026.
//

import SwiftUI
import AppCore
import Theme
import Sharing
import ReviewCore
import ReviewFeature

struct ReviewSettingsView: View {
    @Shared(.appStorage(ReviewPreferences.Keys.openLinksExternally))
    private var openLinksExternally: Bool = true

    @Shared(.appStorage(ReviewPreferences.Keys.cardContentAlignment))
    private var cardContentAlignment: String = CardWebViewContentAlignment.center.rawValue

    @Shared(.appStorage(ReviewPreferences.Keys.autoMatchCardBackground))
    private var autoMatchCardBackground: Bool = true

    @Shared(.appStorage(ReviewPreferences.Keys.showRemainingDays))
    private var showRemainingDays: Bool = true

    @Shared(.appStorage(ReviewPreferences.Keys.showNextReviewTime))
    private var showNextReviewTime: Bool = true

    @Shared(.appStorage(ReviewPreferences.Keys.playAudioInSilentMode))
    private var playAudioInSilentMode: Bool = false

    @Shared(.appStorage(WhiteboardPreferences.Keys.enabledByDefault))
    private var whiteboardEnabledByDefault: Bool = false

    @Shared(.appStorage(WhiteboardPreferences.Keys.inkStyle))
    private var whiteboardInkStyleRaw: String = WhiteboardInkStyle.fountain.rawValue

    @Shared(.appStorage(WhiteboardPreferences.Keys.stability))
    private var whiteboardStability: Double = 0.45

    @Shared(.appStorage(WhiteboardPreferences.Keys.stylusOnly))
    private var whiteboardStylusOnly: Bool = false

    @Shared(.appStorage(WhiteboardPreferences.Keys.backgroundMode))
    private var whiteboardBackgroundRaw: String = WhiteboardBackgroundMode.transparent.rawValue

    @Shared(.appStorage(WhiteboardPreferences.Keys.persistPerCard))
    private var whiteboardPersistPerCard: Bool = false

    var body: some View {
        SettingsPage {
            cardDisplaySection
            answerButtonsSection
            audioSection
            whiteboardSection
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var cardDisplaySection: some View {
        Group {
            SettingsSectionHeader(title: "Card Display")
            SettingsGroup {
                SettingsToggleRow(
                    title: "Match toolbar to card background",
                    systemImage: "paintbrush",
                    tone: .mature,
                    isOn: Binding($autoMatchCardBackground)
                )
                SettingsSeparator()
                SettingsToggleRow(
                    title: "Open links externally",
                    systemImage: "arrow.up.right.square",
                    tone: .accent,
                    isOn: Binding($openLinksExternally)
                )
                SettingsSeparator()
                SettingsPickerRow(
                    title: "Content alignment",
                    systemImage: "arrow.up.and.down.text.horizontal",
                    tone: .link,
                    selection: Binding($cardContentAlignment)
                ) {
                    Text("Center").tag(CardWebViewContentAlignment.center.rawValue)
                    Text("Top").tag(CardWebViewContentAlignment.top.rawValue)
                }
            }
        }
    }

    private var answerButtonsSection: some View {
        Group {
            SettingsSectionHeader(title: "Answer Buttons")
            SettingsGroup {
                SettingsToggleRow(
                    title: "Show remaining counts",
                    systemImage: "number",
                    tone: .review,
                    isOn: Binding($showRemainingDays)
                )
                SettingsSeparator()
                SettingsToggleRow(
                    title: "Show next review time",
                    systemImage: "clock",
                    tone: .info,
                    isOn: Binding($showNextReviewTime)
                )
            }
        }
    }

    private var audioSection: some View {
        Group {
            SettingsSectionHeader(title: "Audio")
            SettingsGroup {
                SettingsToggleRow(
                    title: "Play audio in silent mode",
                    systemImage: "speaker.wave.2",
                    tone: .learning,
                    isOn: Binding($playAudioInSilentMode)
                )
            }
        }
    }

    private var whiteboardSection: some View {
        Group {
            SettingsSectionHeader(title: "Whiteboard & Stylus")
            SettingsGroup {
                SettingsToggleRow(
                    title: "Show whiteboard automatically",
                    systemImage: "pencil.tip.crop.circle",
                    tone: .accent,
                    isOn: Binding($whiteboardEnabledByDefault)
                )
                SettingsSeparator()
                SettingsPickerRow(
                    title: "Default ink style",
                    systemImage: "paintbrush.pointed",
                    tone: .mature,
                    selection: Binding($whiteboardInkStyleRaw)
                ) {
                    ForEach(WhiteboardInkStyle.allCases) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                }
                SettingsSeparator()
                VStack(alignment: .leading, spacing: AmgiSpacing.xs) {
                    HStack {
                        Text("Ink stability")
                            .amgiFont(.body)
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text("\(Int((whiteboardStability * 100).rounded()))%")
                            .amgiFont(.captionBold, .monospaced)
                            .foregroundStyle(palette.accent)
                    }
                    Slider(value: Binding($whiteboardStability), in: 0...1, step: 0.05)
                }
                .padding(.horizontal, AmgiSpacing.lg)
                .padding(.vertical, AmgiSpacing.sm)
                SettingsSeparator()
                SettingsPickerRow(
                    title: "Canvas background",
                    systemImage: "square.grid.3x3",
                    tone: .info,
                    selection: Binding($whiteboardBackgroundRaw)
                ) {
                    ForEach(WhiteboardBackgroundMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                SettingsSeparator()
                SettingsToggleRow(
                    title: "Apple Pencil only (palm rejection)",
                    systemImage: "applepencil",
                    tone: .link,
                    isOn: Binding($whiteboardStylusOnly)
                )
                SettingsSeparator()
                SettingsToggleRow(
                    title: "Save annotations per card",
                    systemImage: "tray.and.arrow.down",
                    tone: .review,
                    isOn: Binding($whiteboardPersistPerCard)
                )
            }
        }
    }

    @Environment(\.palette) private var palette
}

#if DEBUG

#Preview {
    NavigationStack {
        ReviewSettingsView()
    }
}
#endif
