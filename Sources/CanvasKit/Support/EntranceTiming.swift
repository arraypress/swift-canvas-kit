//
//  EntranceTiming.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//
//  The entrance arithmetic, alone and testable: when the last layer has
//  landed, and how far along one layer is at a time. An entrance is a
//  pure function of time — that promise is only checkable while the
//  math is reachable without building a deck.
//

import Foundation

/// The staggered-entrance timing rules.
enum EntranceTiming {

    /// When the last of `layerCount` layers has fully landed.
    static func settleTime(layerCount: Int, duration: Double, stagger: Double) -> Double {
        guard layerCount > 0 else { return 0 }
        return Double(layerCount - 1) * stagger + duration
    }

    /// Eased progress (0…1) for the layer at `layerIndex` at `time`.
    /// Ease-out cubic: fast arrival, gentle landing.
    static func progress(layerIndex: Int, at time: Double, duration: Double, stagger: Double) -> Double {
        guard time.isFinite else { return 1 }
        let raw = (time - Double(layerIndex) * stagger) / max(duration, 0.01)
        let clamped = min(max(raw, 0), 1)
        return 1 - pow(1 - clamped, 3)
    }
}
