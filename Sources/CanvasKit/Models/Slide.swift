//
//  Slide.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// The rounded content card behind a slide's text — the look this whole genre
/// carries: a soft panel floating on the background.
public struct CardStyle: Codable, Equatable, Sendable {

    /// Card fill.
    public var color: SlideColor

    /// Corner radius, points at reference width.
    public var cornerRadius: Double

    /// Inset from the safe area, unit fraction of canvas width.
    public var inset: Double

    /// Card border — the neo-brutalist thick black stroke, the glass
    /// card's bright hairline. `nil` / `0` means none.
    public var borderColor: SlideColor?
    public var borderWidth: Double

    public init(
        color: SlideColor = SlideColor("#FFFFFF14"),
        cornerRadius: Double = 28,
        inset: Double = 0.0,
        borderColor: SlideColor? = nil,
        borderWidth: Double = 0
    ) {
        self.color = color
        self.cornerRadius = cornerRadius
        self.inset = inset
        self.borderColor = borderColor
        self.borderWidth = borderWidth
    }

    /// Tolerant like every model type: cards written before borders
    /// existed keep decoding.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = try container.decodeIfPresent(SlideColor.self, forKey: .color) ?? SlideColor("#FFFFFF14")
        cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 28
        inset = try container.decodeIfPresent(Double.self, forKey: .inset) ?? 0
        borderColor = try container.decodeIfPresent(SlideColor.self, forKey: .borderColor)
        borderWidth = try container.decodeIfPresent(Double.self, forKey: .borderWidth) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case color, cornerRadius, inset, borderColor, borderWidth
    }
}

/// One slide of a deck.
///
/// A slide is a *still* — this format is swiped, not watched. Time exists
/// only for the video export flavor: a slide with a video background and a
/// narration file plays for `duration` seconds; the still export draws the
/// same slide at its poster frame. One document, both outputs.
public struct Slide: Codable, Equatable, Sendable, Identifiable {

    /// Stable identity — what `repeatSlideID(s)` name and expansion
    /// suffixes (`item-3`) build on.
    public var id: String

    /// What this slide *is* in the deck's rhetoric: `hook` (the scroll-stopper),
    /// `content`, or `cta` (the follow/get-the-app close). Templates target
    /// roles; generators fill them.
    public var role: String

    /// This slide's background. `nil` inherits the deck's.
    public var background: Background?

    /// Optional content card behind the layers.
    public var card: CardStyle?

    /// Everything drawn on the slide, in order.
    public var layers: [SlideLayer]

    /// This slide's entrance, overriding the deck's. `nil` inherits.
    public var entrance: SlideEntrance?

    /// Chrome (footer, page indicator) color override for this slide —
    /// a dark cover over a light-carded deck needs light chrome. `nil`
    /// uses the brand's text colors.
    public var chromeColor: SlideColor?

    /// Voiceover audio for the video export — the pronounced word, the read
    /// quote. The library muxes the file it is given; where it came from
    /// (TTS, a microphone) is the caller's business.
    public var narrationAudioPath: String?

    /// Seconds on screen in the video export. Ignored by still export.
    public var duration: Double

    public init(
        id: String = UUID().uuidString,
        role: String = "content",
        background: Background? = nil,
        card: CardStyle? = nil,
        layers: [SlideLayer] = [],
        narrationAudioPath: String? = nil,
        duration: Double = 4,
        chromeColor: SlideColor? = nil,
        entrance: SlideEntrance? = nil
    ) {
        self.id = id
        self.role = role
        self.background = background
        self.card = card
        self.layers = layers
        self.narrationAudioPath = narrationAudioPath
        self.duration = duration
        self.chromeColor = chromeColor
        self.entrance = entrance
    }

    /// Tolerant decoding — old decks keep opening as the model grows.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? "content"
        background = try container.decodeIfPresent(Background.self, forKey: .background)
        card = try container.decodeIfPresent(CardStyle.self, forKey: .card)
        layers = try container.decodeIfPresent([SlideLayer].self, forKey: .layers) ?? []
        narrationAudioPath = try container.decodeIfPresent(String.self, forKey: .narrationAudioPath)
        chromeColor = try container.decodeIfPresent(SlideColor.self, forKey: .chromeColor)
        entrance = try container.decodeIfPresent(SlideEntrance.self, forKey: .entrance)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration) ?? 4
    }
}
