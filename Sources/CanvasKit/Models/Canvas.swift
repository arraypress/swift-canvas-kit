//
//  Canvas.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import Foundation

/// The output surface: pixel size plus the safe area content stays inside.
///
/// Everything else in the model is expressed in *unit coordinates* (fractions
/// of the canvas) and point sizes at a 1080-wide reference, so one deck
/// renders correctly at any of these sizes — the renderer scales, templates
/// never change.
public struct Canvas: Codable, Equatable, Sendable {

    /// Output width in pixels.
    public var width: Int

    /// Output height in pixels.
    public var height: Int

    /// Normalized insets (fractions of width/height) that text is kept
    /// inside — clear of platform UI like the TikTok side rail and caption
    /// strip.
    public var safeAreaTop: Double
    public var safeAreaBottom: Double
    public var safeAreaLeft: Double
    public var safeAreaRight: Double

    public init(
        width: Int = 1080,
        height: Int = 1350,
        safeAreaTop: Double = 0.06,
        safeAreaBottom: Double = 0.06,
        safeAreaLeft: Double = 0.07,
        safeAreaRight: Double = 0.07
    ) {
        self.width = width
        self.height = height
        self.safeAreaTop = safeAreaTop
        self.safeAreaBottom = safeAreaBottom
        self.safeAreaLeft = safeAreaLeft
        self.safeAreaRight = safeAreaRight
    }

    // MARK: - Platform presets
    //
    // Presets, not constraints — `Canvas` initializes at any size, and a
    // deck's canvas is just a value. These exist so nobody has to remember
    // that Instagram portrait is 1350 tall, and so safe areas match the
    // chrome each surface actually draws.

    /// Instagram feed portrait, 4:5 (1080×1350) — the default, and the
    /// format the carousel algorithm favors.
    public static let portrait = Canvas(width: 1080, height: 1350)

    /// Generic full-height 9:16 frame (1080×1920) with conservative safe
    /// areas that clear both TikTok's and Instagram's chrome.
    public static let story = Canvas(
        width: 1080, height: 1920,
        safeAreaTop: 0.10, safeAreaBottom: 0.12
    )

    /// Square, 1:1 (1080×1080).
    public static let square = Canvas(width: 1080, height: 1080)

    /// TikTok video and photo posts, 9:16 (1080×1920). The right inset
    /// clears the like/comment/share rail; the bottom clears the caption
    /// and music strip.
    public static let tiktok = Canvas(
        width: 1080, height: 1920,
        safeAreaTop: 0.08, safeAreaBottom: 0.15,
        safeAreaLeft: 0.06, safeAreaRight: 0.14
    )

    /// Instagram Stories and Reels, 9:16 (1080×1920). Top clears the story
    /// header/camera chrome; bottom clears the reply field and reel actions.
    public static let igStory = Canvas(
        width: 1080, height: 1920,
        safeAreaTop: 0.12, safeAreaBottom: 0.14,
        safeAreaLeft: 0.06, safeAreaRight: 0.10
    )

    /// Instagram feed 3:4 (1080×1440) — the taller feed ratio the grid
    /// switched to.
    public static let igTall = Canvas(width: 1080, height: 1440)

    /// Instagram feed landscape, 1.91:1 (1080×566). Tight vertically —
    /// safe areas stay slim because there's no room to give away.
    public static let igLandscape = Canvas(
        width: 1080, height: 566,
        safeAreaTop: 0.05, safeAreaBottom: 0.05
    )

    /// Every named preset, for pickers and CLI listings.
    public static let presets: [(name: String, canvas: Canvas)] = [
        ("portrait", .portrait),
        ("story", .story),
        ("square", .square),
        ("tiktok", .tiktok),
        ("ig-story", .igStory),
        ("ig-tall", .igTall),
        ("ig-landscape", .igLandscape)
    ]

    /// Everything scales from a 1080-wide reference so point sizes in
    /// templates mean the same thing at every output size.
    var scale: CGFloat { CGFloat(width) / 1080 }

    /// The safe rectangle in pixels, in CoreGraphics coordinates
    /// (origin bottom-left).
    var safeRect: CGRect {
        let w = CGFloat(width)
        let h = CGFloat(height)
        return CGRect(
            x: w * safeAreaLeft,
            y: h * safeAreaBottom,
            width: w * (1 - safeAreaLeft - safeAreaRight),
            height: h * (1 - safeAreaTop - safeAreaBottom)
        )
    }
}
