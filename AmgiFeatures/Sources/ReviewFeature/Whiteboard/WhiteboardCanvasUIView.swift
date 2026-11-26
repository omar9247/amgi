//
//  WhiteboardCanvasUIView.swift
//  ReviewFeature
//
//  Created by Amgi Contributors.
//

#if canImport(UIKit)
import AppCore
import CoreGraphics
import Foundation
import SwiftUI
import UIKit

/// SwiftUI wrapper around the high-frequency 240Hz UIKit ink canvas.
struct WhiteboardCanvasView: UIViewRepresentable {
    let state: WhiteboardState
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> WhiteboardCanvasUIView {
        let view = WhiteboardCanvasUIView()
        view.state = state
        return view
    }

    func updateUIView(_ uiView: WhiteboardCanvasUIView, context: Context) {
        uiView.state = state
        uiView.isDarkMode = colorScheme == .dark
        uiView.isDrawingActive = state.isOpen && state.isDrawingActive
        uiView.isInkHidden = state.isInkHidden
        uiView.stylusOnly = state.stylusOnly
        uiView.backgroundMode = state.backgroundMode
        uiView.syncCommittedStrokes(state.strokes, revision: state.revision)
    }
}

/// Exempt in `DesignConformanceTests`: this is a UIKit drawing canvas whose
/// ink/grid fills are drawing state rather than app chrome.
final class WhiteboardCanvasUIView: UIView, UIPencilInteractionDelegate {
    weak var state: WhiteboardState?

    var isDarkMode: Bool = false {
        didSet {
            if oldValue != isDarkMode {
                invalidateCache()
            }
        }
    }
    var isDrawingActive: Bool = true {
        didSet {
            isUserInteractionEnabled = isDrawingActive
        }
    }
    var isInkHidden: Bool = false {
        didSet {
            if oldValue != isInkHidden { setNeedsDisplay() }
        }
    }
    var stylusOnly: Bool = false
    var backgroundMode: WhiteboardBackgroundMode = .transparent {
        didSet {
            if oldValue != backgroundMode { setNeedsDisplay() }
        }
    }

    private var committedStrokes: [InkStroke] = []
    private var lastSyncedRevision: Int = -1
    private var cachedBackingImage: UIImage?
    private var cachedSize: CGSize = .zero

    private var activeTouch: UITouch?
    private var activeStabilizer: WhiteboardStrokeStabilizer?
    private var activeSamples: [InkSample] = []
    private var predictedTailSamples: [InkSample] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        isMultipleTouchEnabled = false

        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = self
        addInteraction(pencilInteraction)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != cachedSize {
            invalidateCache()
        }
    }

    func syncCommittedStrokes(_ strokes: [InkStroke], revision: Int) {
        guard revision != lastSyncedRevision else { return }
        lastSyncedRevision = revision
        committedStrokes = strokes
        invalidateCache()
    }

    private func invalidateCache() {
        cachedBackingImage = nil
        setNeedsDisplay()
    }

    // MARK: - UIPencilInteractionDelegate (Apple Pencil double-tap)

    func pencilInteraction(_ interaction: UIPencilInteraction, didTap tap: UIPencilInteraction.Tap) {
        state?.isEraserSelected.toggle()
    }

    // MARK: - 240Hz Touch Capture + Palm Rejection

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDrawingActive, let state else { return }
        guard let touch = touches.first else { return }
        if stylusOnly && touch.type != .pencil {
            return
        }
        activeTouch = touch

        if state.isEraserSelected {
            let loc = touch.location(in: self)
            state.erase(at: loc, in: bounds.size)
            return
        }

        let stabilizer = WhiteboardStrokeStabilizer(stability: state.stability)
        activeStabilizer = stabilizer
        activeSamples.removeAll(keepingCapacity: true)
        predictedTailSamples.removeAll(keepingCapacity: true)

        let coalesced = event?.coalescedTouches(for: touch) ?? [touch]
        appendSamples(from: coalesced)
        updatePredicted(from: event?.predictedTouches(for: touch) ?? [])
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDrawingActive, let state, let activeTouch, touches.contains(activeTouch) else { return }
        if state.isEraserSelected {
            let coalesced = event?.coalescedTouches(for: activeTouch) ?? [activeTouch]
            for t in coalesced {
                state.erase(at: t.location(in: self), in: bounds.size)
            }
            return
        }

        let coalesced = event?.coalescedTouches(for: activeTouch) ?? [activeTouch]
        appendSamples(from: coalesced)
        updatePredicted(from: event?.predictedTouches(for: activeTouch) ?? [])
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        finishActiveStroke(finalTouch: activeTouch)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        finishActiveStroke(finalTouch: nil)
    }

    private func appendSamples(from touches: [UITouch]) {
        guard var stabilizer = activeStabilizer else { return }
        for t in touches {
            let loc = t.location(in: self)
            let force = t.type == .pencil ? Double(t.force) : (t.maximumPossibleForce > 0 ? Double(t.force / t.maximumPossibleForce) : 0)
            let raw = InkSample(
                x: Double(loc.x),
                y: Double(loc.y),
                timestamp: t.timestamp,
                force: force,
                altitude: Double(t.altitudeAngle),
                azimuth: Double(t.azimuthAngle(in: self)),
                velocity: 0
            )
            let smoothed = stabilizer.process(raw)
            activeSamples.append(smoothed)
        }
        activeStabilizer = stabilizer
    }

    private func updatePredicted(from touches: [UITouch]) {
        predictedTailSamples.removeAll(keepingCapacity: true)
        guard !touches.isEmpty else { return }
        for t in touches {
            let loc = t.location(in: self)
            let force = t.type == .pencil ? Double(t.force) : 0
            predictedTailSamples.append(InkSample(
                x: Double(loc.x),
                y: Double(loc.y),
                timestamp: t.timestamp,
                force: force,
                altitude: Double(t.altitudeAngle),
                azimuth: Double(t.azimuthAngle(in: self)),
                velocity: activeSamples.last?.velocity ?? 0
            ))
        }
    }

    private func finishActiveStroke(finalTouch: UITouch?) {
        defer {
            activeTouch = nil
            activeStabilizer = nil
            activeSamples.removeAll(keepingCapacity: true)
            predictedTailSamples.removeAll(keepingCapacity: true)
        }
        guard let state, !state.isEraserSelected, !activeSamples.isEmpty else {
            setNeedsDisplay()
            return
        }
        if let finalTouch, var stabilizer = activeStabilizer {
            let loc = finalTouch.location(in: self)
            let endRaw = InkSample(
                x: Double(loc.x),
                y: Double(loc.y),
                timestamp: finalTouch.timestamp,
                force: finalTouch.type == .pencil ? Double(finalTouch.force) : 0,
                altitude: Double(finalTouch.altitudeAngle),
                azimuth: Double(finalTouch.azimuthAngle(in: self)),
                velocity: 0
            )
            activeSamples.append(contentsOf: stabilizer.finalize(toward: endRaw))
        }

        let stroke = InkStroke(
            style: state.inkStyle,
            colorId: state.inkColorId,
            baseWidth: state.activeWidth,
            stability: state.stability,
            samples: activeSamples,
            canvasSize: bounds.size
        )
        state.commitStroke(stroke)
    }

    // MARK: - Rendering

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        drawBackground(in: ctx, size: bounds.size)

        guard !isInkHidden else { return }

        if let backing = backingImage(for: bounds.size) {
            backing.draw(at: .zero)
        }

        if let state, !activeSamples.isEmpty {
            let combined = activeSamples + predictedTailSamples
            let previewStroke = InkStroke(
                style: state.inkStyle,
                colorId: state.inkColorId,
                baseWidth: state.activeWidth,
                stability: state.stability,
                samples: combined,
                canvasSize: bounds.size
            )
            drawStroke(previewStroke, in: ctx, canvasSize: bounds.size)
        }
    }

    private func backingImage(for size: CGSize) -> UIImage? {
        guard size.width >= 1, size.height >= 1 else { return nil }
        if let cachedBackingImage, cachedSize == size {
            return cachedBackingImage
        }
        cachedSize = size
        guard !committedStrokes.isEmpty else {
            cachedBackingImage = nil
            return nil
        }

        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let img = renderer.image { rendererCtx in
            let ctx = rendererCtx.cgContext
            // Draw highlighters underneath opaque pen strokes so card ink stays crisp
            for stroke in committedStrokes where stroke.style.isHighlighter {
                drawStroke(stroke, in: ctx, canvasSize: size)
            }
            for stroke in committedStrokes where !stroke.style.isHighlighter {
                drawStroke(stroke, in: ctx, canvasSize: size)
            }
        }
        cachedBackingImage = img
        return img
    }

    private func drawBackground(in ctx: CGContext, size: CGSize) {
        guard backgroundMode != .transparent else { return }
        let bgColor = isDarkMode
            ? UIColor(white: 0.11, alpha: 0.96)
            : UIColor(white: 0.985, alpha: 0.96)
        ctx.setFillColor(bgColor.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))

        let patternColor = isDarkMode
            ? UIColor(white: 1.0, alpha: 0.12)
            : UIColor(white: 0.0, alpha: 0.10)

        switch backgroundMode {
        case .transparent, .scratchpadBlank:
            break
        case .scratchpadGrid:
            ctx.setFillColor(patternColor.cgColor)
            let step: CGFloat = 24
            var y: CGFloat = step
            while y < size.height {
                var x: CGFloat = step
                while x < size.width {
                    ctx.fillEllipse(in: CGRect(x: x - 1.1, y: y - 1.1, width: 2.2, height: 2.2))
                    x += step
                }
                y += step
            }
        case .scratchpadLined:
            ctx.setStrokeColor(patternColor.cgColor)
            ctx.setLineWidth(1.0)
            let step: CGFloat = 32
            var y: CGFloat = step
            while y < size.height {
                ctx.move(to: CGPoint(x: 16, y: y))
                ctx.addLine(to: CGPoint(x: size.width - 16, y: y))
                y += step
            }
            ctx.strokePath()
        }
    }

    private func drawStroke(_ stroke: InkStroke, in ctx: CGContext, canvasSize: CGSize) {
        let samples = stroke.samples
        guard !samples.isEmpty else { return }

        let swatch = WhiteboardInkColor.resolved(stroke.colorId, forHighlighter: stroke.style.isHighlighter)
        let alpha: CGFloat = stroke.style.isHighlighter ? 0.30 : 1.0
        let color = swatch.uiColor(isDark: isDarkMode, alpha: alpha)

        if stroke.style.isHighlighter {
            ctx.saveGState()
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(CGFloat(stroke.baseWidth))
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            let p0 = stroke.scaledPoint(for: samples[0], in: canvasSize)
            ctx.move(to: p0)
            if samples.count == 1 {
                ctx.addLine(to: CGPoint(x: p0.x + 0.1, y: p0.y + 0.1))
            } else {
                for i in 1..<samples.count {
                    let prev = stroke.scaledPoint(for: samples[i - 1], in: canvasSize)
                    let curr = stroke.scaledPoint(for: samples[i], in: canvasSize)
                    let mid = CGPoint(x: (prev.x + curr.x) * 0.5, y: (prev.y + curr.y) * 0.5)
                    ctx.addQuadCurve(to: mid, control: prev)
                }
                ctx.addLine(to: stroke.scaledPoint(for: samples[samples.count - 1], in: canvasSize))
            }
            ctx.strokePath()
            ctx.restoreGState()
            return
        }

        ctx.saveGState()
        ctx.setFillColor(color.cgColor)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        if samples.count == 1 {
            let pt = stroke.scaledPoint(for: samples[0], in: canvasSize)
            let w = WhiteboardInkGeometry.strokeWidth(
                at: 0, totalCount: 1, sample: samples[0],
                style: stroke.style, baseWidth: stroke.baseWidth, stability: stroke.stability
            )
            ctx.fillEllipse(in: CGRect(x: pt.x - w * 0.5, y: pt.y - w * 0.5, width: w, height: w))
            ctx.restoreGState()
            return
        }

        // Variable-width subdivided quadratic interpolation for fountain/brush/ballpoint
        for i in 1..<samples.count {
            let prev = stroke.scaledPoint(for: samples[i - 1], in: canvasSize)
            let curr = stroke.scaledPoint(for: samples[i], in: canvasSize)
            let next = i + 1 < samples.count ? stroke.scaledPoint(for: samples[i + 1], in: canvasSize) : curr

            let startPt = i == 1 ? prev : CGPoint(x: (prev.x + curr.x) * 0.5, y: (prev.y + curr.y) * 0.5)
            let endPt = i + 1 < samples.count ? CGPoint(x: (curr.x + next.x) * 0.5, y: (curr.y + next.y) * 0.5) : curr

            let w0 = WhiteboardInkGeometry.strokeWidth(
                at: i - 1, totalCount: samples.count, sample: samples[i - 1],
                style: stroke.style, baseWidth: stroke.baseWidth, stability: stroke.stability
            )
            let w1 = WhiteboardInkGeometry.strokeWidth(
                at: i, totalCount: samples.count, sample: samples[i],
                style: stroke.style, baseWidth: stroke.baseWidth, stability: stroke.stability
            )

            let dist = hypot(endPt.x - startPt.x, endPt.y - startPt.y)
            let steps = max(1, min(12, Int(ceil(dist / 2.5))))
            var segStart = startPt
            var segW0 = w0
            for s in 1...steps {
                let t = CGFloat(s) / CGFloat(steps)
                let inv = 1.0 - t
                let qx = inv * inv * startPt.x + 2 * inv * t * curr.x + t * t * endPt.x
                let qy = inv * inv * startPt.y + 2 * inv * t * curr.y + t * t * endPt.y
                let segEnd = CGPoint(x: qx, y: qy)
                let segW1 = w0 + (w1 - w0) * t
                ctx.setLineWidth((segW0 + segW1) * 0.5)
                ctx.move(to: segStart)
                ctx.addLine(to: segEnd)
                ctx.strokePath()
                segStart = segEnd
                segW0 = segW1
            }
        }
        ctx.restoreGState()
    }
}
#endif
