//
//  WhiteboardModels.swift
//  ReviewFeature
//
//  Created by Amgi Contributors.
//

import AppCore
import CoreGraphics
import Foundation

struct InkSample: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var timestamp: TimeInterval
    var force: Double
    var altitude: Double
    var azimuth: Double
    var velocity: Double

    var point: CGPoint {
        CGPoint(x: x, y: y)
    }
}

struct InkStroke: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var style: WhiteboardInkStyle
    var colorId: String
    var baseWidth: Double
    var stability: Double
    var samples: [InkSample]
    var canvasWidth: Double
    var canvasHeight: Double

    init(
        id: UUID = UUID(),
        style: WhiteboardInkStyle,
        colorId: String,
        baseWidth: Double,
        stability: Double,
        samples: [InkSample],
        canvasSize: CGSize
    ) {
        self.id = id
        self.style = style
        self.colorId = colorId
        self.baseWidth = baseWidth
        self.stability = stability
        self.samples = samples
        self.canvasWidth = max(1, Double(canvasSize.width))
        self.canvasHeight = max(1, Double(canvasSize.height))
    }

    /// Scales a sample from its recorded canvas coordinates into `targetSize`
    /// so annotations survive split-view resizing or device rotation cleanly.
    func scaledPoint(for sample: InkSample, in targetSize: CGSize) -> CGPoint {
        let sx = targetSize.width / max(1, CGFloat(canvasWidth))
        let sy = targetSize.height / max(1, CGFloat(canvasHeight))
        return CGPoint(x: CGFloat(sample.x) * sx, y: CGFloat(sample.y) * sy)
    }
}

struct WhiteboardDocument: Codable, Equatable, Sendable {
    var cardId: Int64
    var strokes: [InkStroke]
    var updatedAt: Date
}
