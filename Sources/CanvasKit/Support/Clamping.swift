//
//  Clamping.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//
//  Tiny, but used everywhere unit values arrive from hand-written JSON.
//  It lived inside a model file, which is how utilities get lost.
//

import Foundation

extension Double {
    /// Clamp to a closed range.
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
