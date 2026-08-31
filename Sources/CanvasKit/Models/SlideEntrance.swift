//
//  SlideEntrance.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// How a slide's content arrives — the retention lever of the stitched
/// reel.
///
/// Content layers (text, chips, stickers, images) enter one after another,
/// each `stagger` seconds behind the last, taking `duration` seconds to
/// land. Decorative layers (rects, dots, patterns) and chrome never
/// animate. An entrance is a pure function of time: the still export draws
/// `t = ∞` where everything has settled, so the same deck ships as PNGs
/// and video with one description.
public struct SlideEntrance: Codable, Equatable, Sendable {

    public enum Style: String, Codable, Equatable, Sendable {
        /// Fade in while rising a few points — the genre default.
        case fadeUp
        /// Scale up with a slight overshoot — stickers and hooks.
        case pop
        /// Slide in from the leading edge with a fade.
        case slideFromLeading
        /// Slide in from the trailing edge with a fade.
        case slideFromTrailing
    }

    public var style: Style

    /// Seconds a single layer takes to land.
    public var duration: Double

    /// Seconds between one layer starting and the next.
    public var stagger: Double

    public init(style: Style = .fadeUp, duration: Double = 0.5, stagger: Double = 0.18) {
        self.style = style
        self.duration = duration
        self.stagger = stagger
    }

    /// Tolerant decoding, like every model type.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = try container.decodeIfPresent(Style.self, forKey: .style) ?? .fadeUp
        duration = try container.decodeIfPresent(Double.self, forKey: .duration) ?? 0.5
        stagger = try container.decodeIfPresent(Double.self, forKey: .stagger) ?? 0.18
    }

    /// When the last of `layerCount` layers has fully landed.
    public func settleTime(layerCount: Int) -> Double {
        EntranceTiming.settleTime(layerCount: layerCount, duration: duration, stagger: stagger)
    }

    /// Eased progress (0…1) for the layer at `index` at `time`.
    func progress(layerIndex: Int, at time: Double) -> Double {
        EntranceTiming.progress(layerIndex: layerIndex, at: time, duration: duration, stagger: stagger)
    }
}
