//
//  CardScrollController.swift
//  ReviewFeature
//
//  Created by Amgi Contributors.
//

import CoreGraphics
import Observation

@Observable
@MainActor
final class CardScrollController {
    private(set) var requestID: Int = 0
    private(set) var delta: CGFloat = 0

    func scroll(by delta: CGFloat) {
        self.delta = delta
        self.requestID += 1
    }
}
