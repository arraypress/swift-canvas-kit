//
//  BeatSync.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Snap slide boundaries to the music — the TikTok-native slideshow, where
/// every cut lands on the groove.
public enum BeatSync {

    /// The deck with each slide's duration adjusted so its cut lands on a
    /// detected beat of the deck's music. Slides keep at least
    /// `minimumSlide` seconds; decks without music (or music without a
    /// detectable pulse) come back unchanged. Meant for music-driven
    /// decks: narration still stretches its slide at export time and will
    /// pull a cut off the grid — voice wins over groove.
    public static func aligned(_ deck: SlideDeck, minimumSlide: Double = 1.2) throws -> SlideDeck {
        guard let musicPath = deck.musicPath else { return deck }
        let url = URL(fileURLWithPath: (musicPath as NSString).expandingTildeInPath)
        let beats = try BeatDetector.detect(url: url)
        guard beats.count > 1 else { return deck }

        var result = deck
        var cursor = 0.0
        for index in result.slides.indices {
            let desired = cursor + max(result.slides[index].duration, minimumSlide)
            /// The nearest beat to the desired cut that still leaves the
            /// slide its minimum; failing that, the first beat after it.
            let snapped = beats.min { abs($0 - desired) < abs($1 - desired) } ?? desired
            let end = snapped >= cursor + minimumSlide
                ? snapped
                : (beats.first { $0 >= cursor + minimumSlide } ?? desired)
            result.slides[index].duration = end - cursor
            cursor = end
        }
        return result
    }
}
