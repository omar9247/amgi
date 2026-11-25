//
//  WhiteboardToolbar.swift
//  ReviewFeature
//
//  Created by Amgi Contributors.
//

import AppCore
import SwiftUI
import Theme

/// Floating GoodNotes-style ink & whiteboard toolbar + overlay container.
struct WhiteboardOverlayView<Content: View>: View {
    @Bindable var state: WhiteboardState
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .top) {
            content()

            if state.isOpen {
                #if canImport(UIKit)
                WhiteboardCanvasView(state: state)
                    .allowsHitTesting(state.isDrawingActive)
                    .transition(.opacity)
                #endif

                WhiteboardToolbar(state: state)
                    .padding(.top, AmgiSpacing.xs)
                    .padding(.horizontal, AmgiSpacing.sm)
                    .transition(AmgiMotion.slide(from: .top))
            }
        }
        .animation(AmgiMotion.quick, value: state.isOpen)
    }
}

struct WhiteboardToolbar: View {
    @Bindable var state: WhiteboardState

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @State private var showSettingsPopover = false

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AmgiSpacing.sm) {
                penButton
                colorSwatches
                divider
                eraserButton
                undoRedoGroup
                divider
                interactToggleButton
                visibilityButton
                closeButton
            }
            .padding(.horizontal, AmgiSpacing.md)
            .padding(.vertical, AmgiSpacing.xs + 2)
        }
        .fixedSize(horizontal: false, vertical: true)
        .amgiMaterial(.regular, in: Capsule(), interactive: true)
        .amgiMaterialElevation(Capsule(), radius: AmgiRadius.small, y: 2, opacity: 0.14)
        .popover(isPresented: $showSettingsPopover, arrowEdge: .top) {
            WhiteboardPenSettingsPopover(state: state)
        }
    }

    private var penButton: some View {
        Button {
            if state.isEraserSelected || !state.isDrawingActive {
                state.isEraserSelected = false
                state.isDrawingActive = true
            } else {
                showSettingsPopover = true
            }
        } label: {
            HStack(spacing: AmgiSpacing.xs) {
                Image(systemName: state.inkStyle.symbolName)
                    .amgiFont(.bodyEmphasis)
                Text("\(Int((state.stability * 100).rounded()))%")
                    .amgiFont(.micro, .monospaced)
            }
            .padding(.horizontal, AmgiSpacing.sm)
            .padding(.vertical, AmgiSpacing.xs + 2)
            .background(
                (!state.isEraserSelected && state.isDrawingActive) ? palette.accentSoft : Color.clear,
                in: Capsule()
            )
            .foregroundStyle(
                (!state.isEraserSelected && state.isDrawingActive) ? palette.accent : palette.textPrimary
            )
        }
        .buttonStyle(.pressScale)
        .accessibilityLabel("Pen style and stability")
    }

    private var colorSwatches: some View {
        let swatches = state.inkStyle.isHighlighter
            ? WhiteboardInkColor.highlighterSwatches
            : WhiteboardInkColor.penSwatches
        return HStack(spacing: AmgiSpacing.xs + 2) {
            ForEach(swatches) { swatch in
                let selected = !state.isEraserSelected && state.inkColorId == swatch.id
                Button {
                    state.inkColorId = swatch.id
                    state.isEraserSelected = false
                    state.isDrawingActive = true
                } label: {
                    Circle()
                        .fill(swatch.swiftUIColor(isDark: isDark))
                        .frame(width: 20, height: 20)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    selected ? palette.accent : palette.border,
                                    lineWidth: selected ? 2.5 : 1
                                )
                        }
                        .scaleEffect(selected ? 1.12 : 1.0)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(swatch.label)
            }
        }
    }

    private var eraserButton: some View {
        Button {
            if state.isEraserSelected {
                showSettingsPopover = true
            } else {
                state.isEraserSelected = true
                state.isDrawingActive = true
            }
        } label: {
            Image(systemName: "eraser")
                .amgiFont(.bodyEmphasis)
                .padding(AmgiSpacing.xs + 2)
                .background(
                    (state.isEraserSelected && state.isDrawingActive) ? palette.accentSoft : Color.clear,
                    in: Circle()
                )
                .foregroundStyle(
                    (state.isEraserSelected && state.isDrawingActive) ? palette.accent : palette.textPrimary
                )
        }
        .buttonStyle(.pressScale)
        .accessibilityLabel("Eraser")
    }

    private var undoRedoGroup: some View {
        HStack(spacing: AmgiSpacing.xs) {
            Button { state.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .amgiFont(.body)
                    .padding(AmgiSpacing.xs)
            }
            .disabled(!state.canUndo)
            .accessibilityLabel("Undo stroke")

            Button { state.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
                    .amgiFont(.body)
                    .padding(AmgiSpacing.xs)
            }
            .disabled(!state.canRedo)
            .accessibilityLabel("Redo stroke")

            Button(role: .destructive) { state.clear() } label: {
                Image(systemName: "trash")
                    .amgiFont(.body)
                    .padding(AmgiSpacing.xs)
            }
            .disabled(!state.canUndo)
            .accessibilityLabel("Clear whiteboard")
        }
        .foregroundStyle(palette.textPrimary)
    }

    private var interactToggleButton: some View {
        Button {
            state.isDrawingActive.toggle()
        } label: {
            Image(systemName: state.isDrawingActive ? "hand.draw" : "hand.raised.fill")
                .amgiFont(.bodyEmphasis)
                .padding(AmgiSpacing.xs + 2)
                .background(
                    !state.isDrawingActive ? palette.accentSoft : Color.clear,
                    in: Circle()
                )
                .foregroundStyle(!state.isDrawingActive ? palette.accent : palette.textPrimary)
        }
        .buttonStyle(.pressScale)
        .accessibilityLabel(state.isDrawingActive ? "Switch to scroll and tap card" : "Resume drawing")
    }

    private var visibilityButton: some View {
        Button {
            state.isInkHidden.toggle()
        } label: {
            Image(systemName: state.isInkHidden ? "eye.slash" : "eye")
                .amgiFont(.body)
                .foregroundStyle(state.isInkHidden ? palette.warning : palette.textSecondary)
                .padding(AmgiSpacing.xs)
        }
        .buttonStyle(.pressScale)
        .accessibilityLabel(state.isInkHidden ? "Show ink" : "Hide ink")
    }

    private var closeButton: some View {
        Button {
            state.isOpen = false
        } label: {
            Image(systemName: "xmark")
                .amgiFont(.captionBold)
                .foregroundStyle(palette.textSecondary)
                .padding(AmgiSpacing.xs + 2)
        }
        .buttonStyle(.pressScale)
        .accessibilityLabel("Close whiteboard")
    }

    private var divider: some View {
        Rectangle()
            .fill(palette.separator)
            .frame(width: 1, height: 18)
    }
}

// MARK: - Pen & Stability Settings Popover

struct WhiteboardPenSettingsPopover: View {
    @Bindable var state: WhiteboardState

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    private static let stabilityPresets: [(label: String, value: Double)] = [
        ("Off", 0.0),
        ("Low", 0.25),
        ("Natural", 0.45),
        ("High", 0.80),
        ("Calligraphy", 0.95),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Ink Style") {
                    Picker("Style", selection: Binding(
                        get: { state.inkStyle },
                        set: { state.selectStyle($0) }
                    )) {
                        ForEach(WhiteboardInkStyle.allCases) { style in
                            Label(style.displayName, systemImage: style.symbolName)
                                .tag(style)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Thickness")
                        Slider(
                            value: $state.activeWidth,
                            in: state.inkStyle.isHighlighter ? 8...36 : 1...16,
                            step: 0.5
                        )
                        Text("\(String(format: "%.1f", state.activeWidth))pt")
                            .amgiFont(.caption, .monospaced)
                            .foregroundStyle(palette.textSecondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
                        HStack {
                            Text("Ink Stability")
                                .amgiFont(.bodyEmphasis)
                            Spacer()
                            Text("\(Int((state.stability * 100).rounded()))%")
                                .amgiFont(.captionBold, .monospaced)
                                .foregroundStyle(palette.accent)
                        }

                        Slider(value: $state.stability, in: 0...1, step: 0.05)

                        HStack(spacing: AmgiSpacing.xs) {
                            ForEach(Self.stabilityPresets, id: \.label) { preset in
                                let selected = abs(state.stability - preset.value) < 0.06
                                Button {
                                    state.stability = preset.value
                                } label: {
                                    Text(preset.label)
                                        .amgiFont(.micro)
                                        .padding(.horizontal, AmgiSpacing.sm)
                                        .padding(.vertical, AmgiSpacing.xs)
                                        .background(
                                            selected ? palette.accent : palette.background,
                                            in: Capsule()
                                        )
                                        .foregroundStyle(selected ? .white : palette.textPrimary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        StabilityPreviewStrip(
                            stability: state.stability,
                            style: state.inkStyle,
                            color: state.activeSwatch.swiftUIColor(isDark: colorScheme == .dark),
                            baseWidth: state.activeWidth
                        )
                    }
                    .padding(.vertical, AmgiSpacing.xs)
                } header: {
                    Text("GoodNotes-Style Stabilization")
                } footer: {
                    Text("Higher stability filters hand tremor and smooths stroke width transitions for cleaner handwriting and kanji.")
                }

                Section("Eraser & Canvas") {
                    Picker("Eraser Mode", selection: $state.eraserMode) {
                        ForEach(WhiteboardEraserMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    Picker("Background", selection: $state.backgroundMode) {
                        ForEach(WhiteboardBackgroundMode.allCases) { bg in
                            Label(bg.displayName, systemImage: bg.symbolName).tag(bg)
                        }
                    }
                }

                Section("Stylus & Storage") {
                    Toggle("Apple Pencil Only (Palm Rejection)", isOn: $state.stylusOnly)
                    Toggle("Save Annotations per Card", isOn: $state.persistPerCard)
                }
            }
            .navigationTitle("Ink & Whiteboard")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

/// Live preview comparing a raw shaky input wave against the stabilized output
/// so the user immediately sees how the Stability slider shapes the ink.
private struct StabilityPreviewStrip: View {
    let stability: Double
    let style: WhiteboardInkStyle
    let color: Color
    let baseWidth: Double

    @Environment(\.palette) private var palette

    var body: some View {
        Canvas { context, size in
            let midY = size.height * 0.5
            let count = 48
            var stabilizer = WhiteboardStrokeStabilizer(stability: stability)
            var samples: [InkSample] = []
            samples.reserveCapacity(count)

            for i in 0..<count {
                let t = Double(i) / Double(count - 1)
                let x = 10 + t * (Double(size.width) - 20)
                let baseWave = sin(t * Double.pi * 2.2) * (Double(size.height) * 0.24)
                let jitter = sin(Double(i) * 2.7) * 4.2
                let raw = InkSample(
                    x: x,
                    y: Double(midY) + baseWave + jitter,
                    timestamp: Double(i) * (1.0 / 120.0),
                    force: 0.45 + 0.45 * sin(t * Double.pi),
                    altitude: 1.0,
                    azimuth: 0,
                    velocity: 420
                )
                samples.append(stabilizer.process(raw))
            }

            let previewAlpha = style.isHighlighter ? 0.35 : 1.0
            let resolvedColor = color.opacity(previewAlpha)
            for i in 1..<samples.count {
                var path = Path()
                path.move(to: samples[i - 1].point)
                path.addLine(to: samples[i].point)
                let w = WhiteboardInkGeometry.strokeWidth(
                    at: i,
                    totalCount: samples.count,
                    sample: samples[i],
                    style: style,
                    baseWidth: min(baseWidth, 12),
                    stability: stability
                )
                context.stroke(
                    path,
                    with: .color(resolvedColor),
                    style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(height: 52)
        .background(palette.background, in: RoundedRectangle(cornerRadius: AmgiRadius.small, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AmgiRadius.small, style: .continuous)
                .strokeBorder(palette.separator, lineWidth: 1)
        }
    }
}
