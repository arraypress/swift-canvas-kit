//
//  Looks.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//

import VideoGrade

/// Shipped looks — the same philosophy as the palette table: a small set of
/// hand-tuned grades with names, not a slider farm. Any `VideoGrade` works
/// in a `Background`; these are the ones worth reaching for by name in a
/// template. All values are gentle offsets from neutral — a look should
/// flatter footage shot on a phone, not fight it.
public extension VideoGrade {

    /// Warm late-afternoon color: pushed temperature, lifted shadows, a
    /// touch of orange in the highlights. The travel-carousel default.
    static let goldenHour: VideoGrade = {
        var grade = VideoGrade(
            contrast: 1.05,
            vibrance: 0.15,
            temperature: 7400,
            highlights: 0.94,
            shadows: 0.06,
            vignette: 0.15
        )
        grade.splitHighlight = .orange
        grade.splitHighlightAmount = 0.22
        return grade
    }()

    /// The cinematic teal-and-orange: cool shadows, warm highlights, a
    /// little grain so footage stops looking like a screen recording.
    static let tealDusk: VideoGrade = {
        var grade = VideoGrade(
            contrast: 1.08,
            saturation: 0.95,
            temperature: 6100,
            vignette: 0.2
        )
        grade.splitShadow = .blue
        grade.splitShadowAmount = 0.3
        grade.splitHighlight = .orange
        grade.splitHighlightAmount = 0.18
        grade.grain = 0.12
        return grade
    }()

    /// Faded film stock: raised blacks, softened saturation, grain. The
    /// nostalgic look that makes harsh daylight photography forgiving.
    static let filmFade: VideoGrade = {
        var grade = VideoGrade(
            contrast: 0.97,
            saturation: 0.85,
            temperature: 6800
        )
        grade.fade = 0.22
        grade.grain = 0.16
        grade.vignette = 0.12
        return grade
    }()

    /// High-contrast black and white with crushed blacks and heavy
    /// vignette — the editorial statement look.
    static let noir: VideoGrade = {
        var grade = VideoGrade(
            contrast: 1.14,
            vignette: 0.3
        )
        grade.blackAndWhite = true
        grade.levelsBlack = 0.03
        grade.grain = 0.18
        return grade
    }()
}
