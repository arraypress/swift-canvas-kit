//
//  SlideDeck.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// The whole project as one `Codable` value — canvas, brand, slides, sound.
///
/// This is the unit everything trades in: templates are decks with `{tokens}`
/// in their text, generators emit decks, the renderer consumes them, and a
/// `.json` file of one is a complete, portable description of a post.
public struct SlideDeck: Codable, Equatable, Sendable {

    /// Output size and safe areas.
    public var canvas: Canvas

    /// Palette, type, handle, logo. See `BrandKit` — this is where
    /// customization lives.
    public var brand: BrandKit

    /// The deck-wide background. Slides may override it; when neither sets
    /// one, the brand's background color fills in.
    public var background: Background?

    /// The slides, in swipe order.
    public var slides: [Slide]

    /// Music bed for the video export, under any per-slide narration.
    /// Ignored by still export — carousels get their music at upload time,
    /// inside the platform's own tools.
    public var musicPath: String?

    /// Deck-wide entrance for stitched exports; slides may override.
    /// `nil` means content appears settled.
    public var entrance: SlideEntrance?

    /// Whether ``SlideLayer/pageIndicator`` layers draw at all.
    ///
    /// **Off by default**, deliberately: the surfaces this engine ships to
    /// page themselves — Instagram's carousel dots, TikTok's progress UI,
    /// App Store Connect's gallery pager — and a baked-in "3 / 10" argues
    /// with the platform's own counter right next to it. Templates keep
    /// the layer as a *placement* (position is design knowledge); this
    /// flag is the explicit opt-in for surfaces that really are unpaged —
    /// a PDF export, a printed board, a web embed.
    public var showsPageIndicator: Bool

    public init(
        canvas: Canvas = .portrait,
        brand: BrandKit = BrandKit(),
        background: Background? = nil,
        slides: [Slide] = [],
        musicPath: String? = nil,
        entrance: SlideEntrance? = nil,
        showsPageIndicator: Bool = false
    ) {
        self.canvas = canvas
        self.brand = brand
        self.background = background
        self.slides = slides
        self.musicPath = musicPath
        self.entrance = entrance
        self.showsPageIndicator = showsPageIndicator
    }

    /// Tolerant decoding — every field defaults, so a deck file can be as
    /// short as `{ "slides": [...] }`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        canvas = try container.decodeIfPresent(Canvas.self, forKey: .canvas) ?? .portrait
        brand = try container.decodeIfPresent(BrandKit.self, forKey: .brand) ?? BrandKit()
        background = try container.decodeIfPresent(Background.self, forKey: .background)
        slides = try container.decodeIfPresent([Slide].self, forKey: .slides) ?? []
        musicPath = try container.decodeIfPresent(String.self, forKey: .musicPath)
        entrance = try container.decodeIfPresent(SlideEntrance.self, forKey: .entrance)
        showsPageIndicator = try container.decodeIfPresent(Bool.self, forKey: .showsPageIndicator) ?? false
    }

    // MARK: - Loading and saving

    /// Read a deck from JSON on disk.
    public static func load(from url: URL) throws -> SlideDeck {
        try JSONDecoder().decode(SlideDeck.self, from: Data(contentsOf: url))
    }

    /// Write the deck as readable, stable JSON — sorted keys so diffs mean
    /// something.
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url)
    }

    /// The background a given slide actually renders with, after the
    /// slide → deck → brand fallback chain.
    func resolvedBackground(for slide: Slide) -> Background {
        slide.background ?? background ?? .solid(brand.backgroundColor)
    }
}
