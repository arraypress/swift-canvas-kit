//
//  TextStyle.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import Foundation

/// How a block of text draws: face, size, color, and the accent treatment.
///
/// Sizes are points at the 1080-wide reference canvas — the renderer scales
/// them, so a template tuned once looks identical at 1080×1350 and 1080×1920.
///
/// Accenting uses inline markup rather than ranges: the text
/// `"**Amazing** Catchy Title"` draws the starred span in `accentColor`.
/// Ranges break the moment templated text changes length; markup travels
/// with the words.
public struct TextStyle: Codable, Equatable, Sendable {

    /// Font family. `nil` means the brand's font, or the system face when the
    /// brand doesn't set one.
    public var fontFamily: String?

    /// Weight, in font-descriptor terms: `"ultralight"`, `"thin"`, `"light"`,
    /// `"regular"`, `"medium"`, `"semibold"`, `"bold"`, `"heavy"`, `"black"`.
    public var weight: String

    /// Point size at the reference width.
    public var size: Double

    /// Text color. `nil` means the brand's primary text color.
    public var color: SlideColor?

    /// Color for `**accented**` spans. `nil` means the brand accent.
    /// The weight `**accent**` spans take, when emphasis means heavier
    /// rather than another colour.
    ///
    /// The editorial idiom this exists for is a paragraph with a phrase
    /// picked out in the same ink, only bolder — which is how a magazine
    /// emphasises, and how most carousels carrying real prose do it. Left
    /// unset, an accent span only recolours, which is what a headline with
    /// one word in yellow wants.
    ///
    /// Setting this without ``accentColor`` keeps the body colour: asking
    /// for a weight change is not asking for a colour change as well.
    public var accentWeight: String?

    public var accentColor: SlideColor?

    /// The colour `~muted~` spans take — a tier BELOW the body, not another
    /// accent.
    ///
    /// Two tiers were not enough for the headlines this is actually asked to
    /// set. "Native and Fast" reads grey / black / purple: a quieter word, the
    /// body, and the accent. With only base and accent, the quiet word has to
    /// borrow the accent and the emphasis collapses.
    ///
    /// `nil` leaves `~spans~` at the body colour, so the marker is inert
    /// rather than wrong where a style has not defined the tier.
    public var mutedColor: SlideColor?

    /// `left`, `center`, or `right`.
    public var alignment: String

    /// Multiple of the natural line height. `1.0` is unmodified.
    public var lineHeight: Double

    /// Tracking in points at reference width — small caps headers read better
    /// spread out.
    public var kerning: Double

    /// Underline `**accented**` spans as well as coloring them — the
    /// editorial "underlined lead phrase" idiom.
    public var underlineAccents: Bool

    /// Rounded background drawn behind each rendered *line* — the
    /// highlighter/sticker idiom. `nil` means none.
    public var linePill: SlideColor?

    /// Drop shadow / glow behind the text. `nil` means none; a saturated
    /// color with a large blur reads as neon glow.
    public var shadowColor: SlideColor?
    public var shadowBlur: Double
    public var shadowOffsetY: Double

    /// Uppercase the text at render time. In the style rather than the data,
    /// so "the eyebrow line is always caps" is a template decision.
    public var uppercased: Bool

    /// When the text overflows its region, shrink the point size until it
    /// fits (down to `minimumSize`). Templated content varies in length;
    /// this is what keeps a long word or quote inside the card.
    public var autoShrink: Bool

    /// The floor for `autoShrink`.
    public var minimumSize: Double

    /// The most lines the text may wrap to; `autoShrink` shrinks until it
    /// wraps to no more. `nil` means no limit — height alone decides.
    public var maxLines: Int?

    /// Shrink until no word has to break across lines. CoreText breaks a
    /// word that is wider than the region mid-word ("FREQUEN / CY"); a
    /// single-word block is always kept whole, and with this so is every
    /// word of a longer one. Off by default — the slide gallery is tuned
    /// without it.
    public var keepsWordsWhole: Bool

    /// How thick the stroke is, as a percentage of the point size — 3 to 4
    /// reads well at display sizes. `0` means no stroke at all.
    public var strokeWidth: Double

    /// What the stroke does: replace the fill, or sit around it.
    ///
    /// Hollow is a display treatment — the word drawn as an outline, nothing
    /// inside it. Outlined is a legibility one: the word filled as normal
    /// with a dark keyline holding it off whatever it is sitting on, which is
    /// how every caption over a photograph survives a light patch in the
    /// picture. Both are stroked text and they look nothing alike.
    public var strokeStyle: StrokeStyle

    /// Stroke color for hollow text. `nil` means the text color.
    public var strokeColor: SlideColor?

    /// Gradient glyph fill, top to bottom. Two or more colors; `nil` means
    /// flat fill. Composes with `shadowColor` — the glow draws beneath.
    public var gradientColors: [SlideColor]?

    /// Variable-font axes by their four-letter tag — `wght`, `wdth`, `slnt`,
    /// `opsz`, or a font's own (`SOFT`, `WONK`). A face without the axis
    /// ignores it. `nil` draws the face's named instance as it is.
    public var variations: [String: Double]?

    /// OpenType features by tag, `1` on and `0` off — `smcp` small capitals,
    /// `liga` ligatures, `tnum` tabular figures, `onum` old-style figures,
    /// `ss01` a stylistic set. A face without the feature ignores it.
    public var features: [String: Int]?

    /// Styling for ranges of characters — a colour, a size, a lift off the
    /// baseline — counted in the characters drawn (markup removed, after
    /// uppercasing). Applied in order, later ranges over earlier ones.
    public var characterStyles: [CharacterStyle]?

    /// See ``TextStyle/strokeStyle``.
    public enum StrokeStyle: String, Codable, Equatable, Sendable, CaseIterable {

        /// Outline only, no fill — the display treatment.
        case hollow

        /// Filled, with the stroke around it — the legibility treatment.
        case outlined
    }

    public init(
        fontFamily: String? = nil,
        weight: String = "regular",
        size: Double = 48,
        color: SlideColor? = nil,
        accentColor: SlideColor? = nil,
        mutedColor: SlideColor? = nil,
        accentWeight: String? = nil,
        alignment: String = "left",
        lineHeight: Double = 1.0,
        kerning: Double = 0,
        underlineAccents: Bool = false,
        linePill: SlideColor? = nil,
        shadowColor: SlideColor? = nil,
        shadowBlur: Double = 0,
        shadowOffsetY: Double = 0,
        uppercased: Bool = false,
        autoShrink: Bool = true,
        minimumSize: Double = 18,
        strokeWidth: Double = 0,
        strokeStyle: StrokeStyle = .hollow,
        strokeColor: SlideColor? = nil,
        gradientColors: [SlideColor]? = nil,
        maxLines: Int? = nil,
        keepsWordsWhole: Bool = false,
        variations: [String: Double]? = nil,
        features: [String: Int]? = nil,
        characterStyles: [CharacterStyle]? = nil
    ) {
        self.fontFamily = fontFamily
        self.weight = weight
        self.size = size
        self.color = color
        self.accentColor = accentColor
        self.mutedColor = mutedColor
        self.accentWeight = accentWeight
        self.alignment = alignment
        self.lineHeight = lineHeight
        self.kerning = kerning
        self.underlineAccents = underlineAccents
        self.linePill = linePill
        self.shadowColor = shadowColor
        self.shadowBlur = shadowBlur
        self.shadowOffsetY = shadowOffsetY
        self.uppercased = uppercased
        self.autoShrink = autoShrink
        self.minimumSize = minimumSize
        self.strokeWidth = strokeWidth
        self.strokeStyle = strokeStyle
        self.strokeColor = strokeColor
        self.gradientColors = gradientColors
        self.maxLines = maxLines
        self.keepsWordsWhole = keepsWordsWhole
        self.variations = variations
        self.features = features
        self.characterStyles = characterStyles
    }

    /// Tolerant decoding: every field has a default, so template JSON only
    /// says what it means — `{ "size": 96, "weight": "black" }` is a complete
    /// style.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily)
        weight = try container.decodeIfPresent(String.self, forKey: .weight) ?? "regular"
        size = try container.decodeIfPresent(Double.self, forKey: .size) ?? 48
        color = try container.decodeIfPresent(SlideColor.self, forKey: .color)
        accentColor = try container.decodeIfPresent(SlideColor.self, forKey: .accentColor)
        mutedColor = try container.decodeIfPresent(SlideColor.self, forKey: .mutedColor)
        accentWeight = try container.decodeIfPresent(String.self, forKey: .accentWeight)
        alignment = try container.decodeIfPresent(String.self, forKey: .alignment) ?? "left"
        lineHeight = try container.decodeIfPresent(Double.self, forKey: .lineHeight) ?? 1.0
        kerning = try container.decodeIfPresent(Double.self, forKey: .kerning) ?? 0
        underlineAccents = try container.decodeIfPresent(Bool.self, forKey: .underlineAccents) ?? false
        linePill = try container.decodeIfPresent(SlideColor.self, forKey: .linePill)
        shadowColor = try container.decodeIfPresent(SlideColor.self, forKey: .shadowColor)
        shadowBlur = try container.decodeIfPresent(Double.self, forKey: .shadowBlur) ?? 0
        shadowOffsetY = try container.decodeIfPresent(Double.self, forKey: .shadowOffsetY) ?? 0
        uppercased = try container.decodeIfPresent(Bool.self, forKey: .uppercased) ?? false
        autoShrink = try container.decodeIfPresent(Bool.self, forKey: .autoShrink) ?? true
        minimumSize = try container.decodeIfPresent(Double.self, forKey: .minimumSize) ?? 18
        strokeWidth = try container.decodeIfPresent(Double.self, forKey: .strokeWidth) ?? 0
        strokeStyle = try container.decodeIfPresent(StrokeStyle.self, forKey: .strokeStyle) ?? .hollow
        strokeColor = try container.decodeIfPresent(SlideColor.self, forKey: .strokeColor)
        gradientColors = try container.decodeIfPresent([SlideColor].self, forKey: .gradientColors)
        maxLines = try container.decodeIfPresent(Int.self, forKey: .maxLines)
        keepsWordsWhole = try container.decodeIfPresent(Bool.self, forKey: .keepsWordsWhole) ?? false
        variations = try container.decodeIfPresent([String: Double].self, forKey: .variations)
        features = try container.decodeIfPresent([String: Int].self, forKey: .features)
        characterStyles = try container.decodeIfPresent([CharacterStyle].self, forKey: .characterStyles)
    }
}

public extension TextStyle {
    /// This style, center-aligned — hooks stay centered even in styles whose
    /// content leads left.
    func centered() -> TextStyle {
        var style = self
        style.alignment = "center"
        return style
    }
}

/// How a range of characters in a text block differs from the block: its
/// colour, its size, its weight, how far it sits off the baseline, its
/// tracking. Positions count the characters drawn (`"Ä"` is one).
public struct CharacterStyle: Codable, Equatable, Sendable, Hashable {

    /// The first character, from 0.
    public var start: Int

    /// How many characters.
    public var length: Int

    /// Their colour; `nil` keeps the block's.
    public var color: SlideColor?

    /// Their size as a multiple of the block's (`1.4` is 40% larger).
    public var scale: Double?

    /// Their weight (`"black"`); `nil` keeps the block's.
    public var weight: String?

    /// How far they sit above the baseline, as a fraction of the block's
    /// size (negative drops them).
    public var baseline: Double?

    /// Extra space after each, in thousandths of the block's size.
    public var tracking: Double?

    public init(start: Int, length: Int, color: SlideColor? = nil, scale: Double? = nil, weight: String? = nil,
                baseline: Double? = nil, tracking: Double? = nil) {
        self.start = start
        self.length = length
        self.color = color
        self.scale = scale
        self.weight = weight
        self.baseline = baseline
        self.tracking = tracking
    }
}
