//
//  WhiteboardStabilizer.swift
//  ReviewFeature
//
//  Created by Amgi Contributors.
//

import AppCore
import CoreGraphics
import Foundation

/// Velocity-adaptive 1€ (One-Euro) low-pass filter for low-latency pen stabilization.
/// Smooths high-frequency hand tremor when drawing slowly while preserving crisp,
/// responsive tracking during fast strokes.
struct OneEuroFilter: Sendable {
    var minCutoff: Double
    var beta: Double
    var dCutoff: Double

    private var prevValue: Double?
    private var prevDerivative: Double = 0
    private var prevTime: TimeInterval?

    init(minCutoff: Double = 1.5, beta: Double = 0.02, dCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    mutating func filter(value: Double, timestamp: TimeInterval) -> Double {
        guard let prevValue, let prevTime else {
            self.prevValue = value
            self.prevTime = timestamp
            self.prevDerivative = 0
            return value
        }

        let dt = max(1.0 / 240.0, timestamp - prevTime)
        let rawDerivative = (value - prevValue) / dt
        let alphaD = smoothingFactor(dt: dt, cutoff: dCutoff)
        let smoothedDerivative = exponentialSmooth(alpha: alphaD, current: rawDerivative, previous: prevDerivative)

        let cutoff = minCutoff + beta * abs(smoothedDerivative)
        let alpha = smoothingFactor(dt: dt, cutoff: cutoff)
        let result = exponentialSmooth(alpha: alpha, current: value, previous: prevValue)

        self.prevValue = result
        self.prevDerivative = smoothedDerivative
        self.prevTime = timestamp
        return result
    }

    private func smoothingFactor(dt: Double, cutoff: Double) -> Double {
        let r = 2.0 * Double.pi * cutoff * dt
        return r / (r + 1.0)
    }

    private func exponentialSmooth(alpha: Double, current: Double, previous: Double) -> Double {
        alpha * current + (1.0 - alpha) * previous
    }
}

/// GoodNotes-style stroke stabilization pipeline:
/// - `stability == 0`: raw pass-through.
/// - `0 < stability <= 0.55`: velocity-adaptive 1€ filtering on position + pressure.
/// - `stability > 0.55`: adds a progressive string-pull ("lazy mouse") deadzone so
///   curves, CJK characters, and diagrams glide smoothly without jitter.
struct WhiteboardStrokeStabilizer: Sendable {
    let stability: Double

    private var filterX: OneEuroFilter
    private var filterY: OneEuroFilter
    private var filterForce: OneEuroFilter
    private var ropeAnchor: CGPoint?
    private var lastOutput: InkSample?

    init(stability: Double) {
        let clamped = min(max(stability, 0), 1)
        self.stability = clamped

        // Higher stability lowers minCutoff (stronger tremor suppression at slow speeds)
        // and tightens beta so pressure/position transitions feel silky.
        let posMinCutoff = 8.0 - clamped * 7.35      // 8.0 Hz -> 0.65 Hz
        let posBeta = 0.08 - clamped * 0.072         // 0.08 -> 0.008
        let forceMinCutoff = 10.0 - clamped * 8.8    // 10.0 Hz -> 1.2 Hz

        self.filterX = OneEuroFilter(minCutoff: posMinCutoff, beta: posBeta, dCutoff: 1.0)
        self.filterY = OneEuroFilter(minCutoff: posMinCutoff, beta: posBeta, dCutoff: 1.0)
        self.filterForce = OneEuroFilter(minCutoff: forceMinCutoff, beta: 0.005, dCutoff: 1.0)
    }

    mutating func process(_ raw: InkSample) -> InkSample {
        guard stability > 0.001 else {
            lastOutput = raw
            return raw
        }

        // Progressive string-pull deadzone above 55% stability
        var targetX = raw.x
        var targetY = raw.y
        if stability > 0.55 {
            let ropeRadius = ((stability - 0.55) / 0.45) * 7.5
            if let anchor = ropeAnchor {
                let dx = raw.x - Double(anchor.x)
                let dy = raw.y - Double(anchor.y)
                let dist = hypot(dx, dy)
                if dist > ropeRadius && dist > 0.0001 {
                    let pull = (dist - ropeRadius) / dist
                    let moved = CGPoint(
                        x: anchor.x + CGFloat(dx * pull),
                        y: anchor.y + CGFloat(dy * pull)
                    )
                    ropeAnchor = moved
                    targetX = Double(moved.x)
                    targetY = Double(moved.y)
                } else {
                    targetX = Double(anchor.x)
                    targetY = Double(anchor.y)
                }
            } else {
                ropeAnchor = CGPoint(x: raw.x, y: raw.y)
            }
        }

        let sx = filterX.filter(value: targetX, timestamp: raw.timestamp)
        let sy = filterY.filter(value: targetY, timestamp: raw.timestamp)
        let sf = filterForce.filter(value: raw.force, timestamp: raw.timestamp)

        let velocity: Double
        if let prev = lastOutput {
            let dt = max(1.0 / 240.0, raw.timestamp - prev.timestamp)
            velocity = hypot(sx - prev.x, sy - prev.y) / dt
        } else {
            velocity = raw.velocity
        }

        let out = InkSample(
            x: sx,
            y: sy,
            timestamp: raw.timestamp,
            force: sf,
            altitude: raw.altitude,
            azimuth: raw.azimuth,
            velocity: velocity
        )
        lastOutput = out
        return out
    }

    /// Pulls the stabilized end smoothly toward the final physical touch release
    /// so high-stability strokes still terminate cleanly where the pen lifted.
    mutating func finalize(toward endSample: InkSample) -> [InkSample] {
        guard stability > 0.001, let last = lastOutput else { return [] }
        let dist = hypot(endSample.x - last.x, endSample.y - last.y)
        guard dist > 0.75 else { return [] }
        let steps = min(4, max(1, Int(dist / 3.0)))
        var tail: [InkSample] = []
        tail.reserveCapacity(steps)
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            tail.append(InkSample(
                x: last.x + (endSample.x - last.x) * t,
                y: last.y + (endSample.y - last.y) * t,
                timestamp: last.timestamp + (endSample.timestamp - last.timestamp) * t,
                force: max(0.05, last.force * (1.0 - 0.35 * t)),
                altitude: endSample.altitude,
                azimuth: endSample.azimuth,
                velocity: last.velocity
            ))
        }
        return tail
    }
}

/// Width & hit-test geometry shared by the live UIKit ink renderer,
/// eraser tools, and the Settings/Toolbar live stability preview.
enum WhiteboardInkGeometry {
    static func strokeWidth(
        at index: Int,
        totalCount: Int,
        sample: InkSample,
        style: WhiteboardInkStyle,
        baseWidth: Double,
        stability: Double
    ) -> CGFloat {
        let base = max(0.75, CGFloat(baseWidth))

        switch style {
        case .ballpoint:
            return base

        case .highlighter:
            return base

        case .fountain:
            // Normalize force: Apple Pencil reports ~0.1...4.0; finger reports 0.
            let pressureFactor: CGFloat
            if sample.force > 0.01 {
                let norm = min(max((sample.force - 0.15) / 1.85, 0.0), 1.0)
                pressureFactor = CGFloat(0.42 + norm * 0.98)
            } else {
                // Velocity-based fountain modulation when using finger or non-pressure stylus
                let speedNorm = min(max(sample.velocity / 1100.0, 0.0), 1.0)
                let variance = 0.55 - 0.25 * stability
                pressureFactor = CGFloat(1.12 - speedNorm * variance)
            }
            let taper = endTaper(index: index, totalCount: totalCount, minScale: 0.45, span: 4)
            // Higher stability damps extreme width spikes for cleaner lettering
            let damped = 1.0 + (pressureFactor - 1.0) * CGFloat(1.0 - 0.35 * stability)
            return max(0.6, base * damped * taper)

        case .brush:
            let pressureFactor: CGFloat
            if sample.force > 0.01 {
                let norm = min(max((sample.force - 0.1) / 1.6, 0.0), 1.0)
                pressureFactor = CGFloat(0.28 + norm * 1.65)
            } else {
                let speedNorm = min(max(sample.velocity / 950.0, 0.0), 1.0)
                pressureFactor = CGFloat(1.45 - speedNorm * 0.85)
            }
            let taper = endTaper(index: index, totalCount: totalCount, minScale: 0.25, span: 5)
            return max(0.6, base * pressureFactor * taper)
        }
    }

    private static func endTaper(index: Int, totalCount: Int, minScale: CGFloat, span: Int) -> CGFloat {
        guard totalCount > 2 else { return 1.0 }
        let startDist = index
        let endDist = totalCount - 1 - index
        let edgeDist = min(startDist, endDist)
        if edgeDist >= span { return 1.0 }
        let t = CGFloat(edgeDist) / CGFloat(span)
        return minScale + (1.0 - minScale) * t
    }

    static func hitTest(
        stroke: InkStroke,
        point: CGPoint,
        in canvasSize: CGSize,
        tolerance: CGFloat = 14
    ) -> Bool {
        let samples = stroke.samples
        guard !samples.isEmpty else { return false }
        let hitRadius = max(tolerance, CGFloat(stroke.baseWidth) * 0.65 + 8)
        if samples.count == 1 {
            let p = stroke.scaledPoint(for: samples[0], in: canvasSize)
            return hypot(p.x - point.x, p.y - point.y) <= hitRadius
        }
        for idx in 1..<samples.count {
            let a = stroke.scaledPoint(for: samples[idx - 1], in: canvasSize)
            let b = stroke.scaledPoint(for: samples[idx], in: canvasSize)
            if distanceFromPoint(point, toSegmentA: a, b: b) <= hitRadius {
                return true
            }
        }
        return false
    }

    static func splitStroke(
        _ stroke: InkStroke,
        erasingAt point: CGPoint,
        radius: CGFloat,
        in canvasSize: CGSize
    ) -> [InkStroke] {
        var keptRuns: [[InkSample]] = []
        var currentRun: [InkSample] = []

        for sample in stroke.samples {
            let pt = stroke.scaledPoint(for: sample, in: canvasSize)
            if hypot(pt.x - point.x, pt.y - point.y) <= radius {
                if !currentRun.isEmpty {
                    keptRuns.append(currentRun)
                    currentRun.removeAll(keepingCapacity: true)
                }
            } else {
                currentRun.append(sample)
            }
        }
        if !currentRun.isEmpty {
            keptRuns.append(currentRun)
        }

        // Preserve original ID if stroke wasn't split into multiple pieces and wasn't touched
        if keptRuns.count == 1, keptRuns[0].count == stroke.samples.count {
            return [stroke]
        }

        return keptRuns.compactMap { run in
            guard !run.isEmpty else { return nil }
            return InkStroke(
                style: stroke.style,
                colorId: stroke.colorId,
                baseWidth: stroke.baseWidth,
                stability: stroke.stability,
                samples: run,
                canvasSize: canvasSize
            )
        }
    }

    static func distanceFromPoint(_ p: CGPoint, toSegmentA a: CGPoint, b: CGPoint) -> CGFloat {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let lenSq = abx * abx + aby * aby
        if lenSq <= 0.0001 {
            return hypot(p.x - a.x, p.y - a.y)
        }
        let t = max(0, min(1, ((p.x - a.x) * abx + (p.y - a.y) * aby) / lenSq))
        let projX = a.x + t * abx
        let projY = a.y + t * aby
        return hypot(p.x - projX, p.y - projY)
    }
}
