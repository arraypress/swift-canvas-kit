//
//  SlideLayer.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import Foundation

/// A rectangle in unit coordinates — fractions of the canvas, origin top-left
/// like a design tool, not like CoreGraphics.
///
/// Templates position everything with these, which is what makes one template
/// correct at 4:5, 9:16 and 1:1 without three layouts.
public struct UnitRect: Codable, Equatable, Sendable {

    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// The full canvas.
    public static let full = UnitRect(x: 0, y: 0, width: 1, height: 1)

    /// Resolved to pixels, converted to CoreGraphics coordinates
    /// (origin bottom-left).
    func pixels(in canvas: Canvas) -> CGRect {
        let w = CGFloat(canvas.width)
        let h = CGFloat(canvas.height)
        return CGRect(
            x: w * x,
            y: h * (1 - y - height),
            width: w * width,
            height: h * height
        )
    }
}

/// One thing drawn on a slide.
///
/// Deliberately a small vocabulary. Slides in this format are text on a
/// background with a brand footer — the restraint is what keeps templates
/// writable by hand and fillable by anything.
public enum SlideLayer: Equatable, Sendable {

    /// A block of styled text inside a region. `verticalAlignment` places the
    /// measured text within it: `top`, `middle`, or `bottom`.
    case text(text: String, style: TextStyle, region: UnitRect, verticalAlignment: String)

    /// An image inside a region. `scaling` is `fit` (aspect-fit, centered —
    /// logos, product shots) or `fill` (aspect-fill, cropped to the region —
    /// screenshots inside device frames, photo tiles). `cornerRadius`
    /// rounds the region clip in fill mode, the drawn image in fit mode.
    /// `rotationDegrees` tilts about the region's center — the store's
    /// angled-device idiom. `maskPath` clips through an image's alpha — the
    /// true squircle window from a bezel's mask, a blob, anything a corner
    /// radius cannot say.
    case image(path: String, region: UnitRect, cornerRadius: Double, scaling: String, rotationDegrees: Double = 0, maskPath: String? = nil)

    /// Construction ergonomics for the common fit case.
    public static func image(path: String, region: UnitRect, cornerRadius: Double) -> SlideLayer {
        .image(path: path, region: region, cornerRadius: cornerRadius, scaling: "fit")
    }

    /// A video inside a region — a device screen playing footage in the
    /// exports; still renders draw the frame the caller supplies or a dark
    /// screen, never a crash. Same clip vocabulary as `image`.
    case video(path: String, region: UnitRect, cornerRadius: Double, scaling: String, maskPath: String? = nil)

    /// The slide's position in the deck — "3 / 10" — drawn small in the top
    /// right of the safe area. Values come from the deck at render time.
    ///
    /// A placement, not a promise: it draws only when
    /// ``SlideDeck/showsPageIndicator`` is on. Instagram and TikTok render
    /// their own carousel progress, so the counter defaults off and exists
    /// for stills that live outside those platforms.
    case pageIndicator

    /// A rounded chip with a short label — the "02" number chips and
    /// "Read →" buttons in this genre. Sized to its text at `size` points,
    /// placed within the region by `alignment` (`left` / `center` /
    /// `right`). `color` fills the pill (`nil` means the brand accent —
    /// CTA buttons use the style's text color instead, the highest
    /// contrast available against the background); the label color is
    /// always computed from the fill's luminance.
    case chip(text: String, region: UnitRect, size: Double, alignment: String, color: SlideColor?)

    /// Construction ergonomics for the common number-chip case.
    public static func chip(text: String, region: UnitRect) -> SlideLayer {
        .chip(text: text, region: region, size: 30, alignment: "left", color: nil)
    }

    public static func chip(text: String, region: UnitRect, size: Double, alignment: String) -> SlideLayer {
        .chip(text: text, region: region, size: size, alignment: alignment, color: nil)
    }

    /// A filled rectangle — rules, side bars, split-color blocks. The quiet
    /// layer that makes layouts structurally different rather than
    /// recolored. `nil` color means the brand accent.
    case rect(color: SlideColor?, region: UnitRect, cornerRadius: Double)

    /// An emoji (or short glyph) drawn big, optionally tilted — the sticker
    /// idiom. CoreText renders color emoji natively, so this costs nothing.
    case sticker(text: String, region: UnitRect, rotationDegrees: Double)

    /// A dot-grid texture — the quiet surface detail that separates a
    /// designed slide from a colored rectangle. Spacing and radius are
    /// points at reference width.
    case dots(color: SlideColor, region: UnitRect, spacing: Double, radius: Double)

    /// A tiled glyph texture — squiggles, plus signs, slashes — the
    /// pattern idiom behind neo-brutalist and hand-drawn looks. Rows
    /// offset by half a step so the tile reads organic, not gridded.
    case pattern(glyph: String, color: SlideColor, region: UnitRect, size: Double, spacing: Double)

    /// A run of entries, each with its own marker down the left.
    ///
    /// The ranked-list slide — "12th — Aries", four of them, each with a
    /// coloured rule beside it — is the most common carousel layout after
    /// the plain headline, and it cannot be built out of `rect` layers. The
    /// rule has to be as tall as the entry it belongs to, and how tall that
    /// is depends on where the text wrapped, which only the renderer knows.
    ///
    /// So the entries go in as data and the markers are measured, not
    /// placed. An entry with a title draws it in the accent weight above its
    /// body; an entry without one is a single block.
    case list(
        items: [ListItem],
        style: TextStyle,
        region: UnitRect,
        marker: ListMarker,
        spacing: Double
    )
}

// MARK: - Lists

/// One entry in a ``SlideLayer/list(items:style:region:marker:spacing:)``.
public struct ListItem: Codable, Equatable, Sendable {

    /// The lead-in, set in the style's accent weight and colour: `12th —
    /// Aries`. Optional, because a plain bulleted list has no titles.
    public var title: String?

    /// The entry itself. Takes `**accent**` and `*italic*` markup like any
    /// other text.
    public var body: String

    public init(title: String? = nil, body: String) {
        self.title = title
        self.body = body
    }
}

/// What sits to the left of each entry.
public enum ListMarker: Equatable, Sendable {

    /// A vertical rule as tall as its entry — the ranked-list idiom.
    case rule(color: SlideColor?, width: Double)

    /// A dot on the first line.
    case bullet(color: SlideColor?, radius: Double)

    /// The entry's position, counting from one.
    case number(color: SlideColor?)

    /// Nothing: entries separated by space alone.
    case none

    /// The gap between the marker and the text, in points at reference
    /// width. A rule needs more air than a bullet.
    var gutter: Double {
        switch self {
        case .rule(_, let width): return width + 22
        case .bullet(_, let radius): return radius * 2 + 20
        case .number: return 54
        case .none: return 0
        }
    }
}

extension ListMarker: Codable {

    private enum CodingKeys: String, CodingKey { case type, color, width, radius }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let color = try container.decodeIfPresent(SlideColor.self, forKey: .color)

        switch try container.decodeIfPresent(String.self, forKey: .type) ?? "rule" {
        case "bullet":
            self = .bullet(color: color,
                           radius: try container.decodeIfPresent(Double.self, forKey: .radius) ?? 7)
        case "number":
            self = .number(color: color)
        case "none":
            self = .none
        default:
            self = .rule(color: color,
                         width: try container.decodeIfPresent(Double.self, forKey: .width) ?? 8)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .rule(let color, let width):
            try container.encode("rule", forKey: .type)
            try container.encodeIfPresent(color, forKey: .color)
            try container.encode(width, forKey: .width)
        case .bullet(let color, let radius):
            try container.encode("bullet", forKey: .type)
            try container.encodeIfPresent(color, forKey: .color)
            try container.encode(radius, forKey: .radius)
        case .number(let color):
            try container.encode("number", forKey: .type)
            try container.encodeIfPresent(color, forKey: .color)
        case .none:
            try container.encode("none", forKey: .type)
        }
    }
}

// MARK: - Codable
extension SlideLayer: Codable {

    private enum CodingKeys: String, CodingKey {
        case type, text, style, region, verticalAlignment, path, cornerRadius, color, rotationDegrees, spacing, radius, size, alignment, glyph, scaling, items, marker, maskPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = .text(
                text: try container.decode(String.self, forKey: .text),
                style: try container.decodeIfPresent(TextStyle.self, forKey: .style) ?? TextStyle(),
                region: try container.decodeIfPresent(UnitRect.self, forKey: .region) ?? .full,
                verticalAlignment: try container.decodeIfPresent(String.self, forKey: .verticalAlignment) ?? "top"
            )
        case "image":
            self = .image(
                path: try container.decode(String.self, forKey: .path),
                region: try container.decodeIfPresent(UnitRect.self, forKey: .region) ?? .full,
                cornerRadius: try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 0,
                scaling: try container.decodeIfPresent(String.self, forKey: .scaling) ?? "fit",
                rotationDegrees: try container.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0,
                maskPath: try container.decodeIfPresent(String.self, forKey: .maskPath)
            )
        case "video":
            self = .video(
                path: try container.decode(String.self, forKey: .path),
                region: try container.decodeIfPresent(UnitRect.self, forKey: .region) ?? .full,
                cornerRadius: try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 0,
                scaling: try container.decodeIfPresent(String.self, forKey: .scaling) ?? "fill",
                maskPath: try container.decodeIfPresent(String.self, forKey: .maskPath)
            )
        case "pageIndicator":
            self = .pageIndicator
        case "chip":
            self = .chip(
                text: try container.decode(String.self, forKey: .text),
                region: try container.decodeIfPresent(UnitRect.self, forKey: .region) ?? .full,
                size: try container.decodeIfPresent(Double.self, forKey: .size) ?? 30,
                alignment: try container.decodeIfPresent(String.self, forKey: .alignment) ?? "left",
                color: try container.decodeIfPresent(SlideColor.self, forKey: .color)
            )
        case "rect":
            self = .rect(
                color: try container.decodeIfPresent(SlideColor.self, forKey: .color),
                region: try container.decodeIfPresent(UnitRect.self, forKey: .region) ?? .full,
                cornerRadius: try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 0
            )
        case "sticker":
            self = .sticker(
                text: try container.decode(String.self, forKey: .text),
                region: try container.decodeIfPresent(UnitRect.self, forKey: .region) ?? .full,
                rotationDegrees: try container.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0
            )
        case "list":
            self = .list(
                items: try container.decode([ListItem].self, forKey: .items),
                style: try container.decodeIfPresent(TextStyle.self, forKey: .style) ?? TextStyle(),
                region: try container.decodeIfPresent(UnitRect.self, forKey: .region) ?? .full,
                marker: try container.decodeIfPresent(ListMarker.self, forKey: .marker)
                    ?? .rule(color: nil, width: 8),
                spacing: try container.decodeIfPresent(Double.self, forKey: .spacing) ?? 34
            )
        case "pattern":
            self = .pattern(
                glyph: try container.decode(String.self, forKey: .glyph),
                color: try container.decodeIfPresent(SlideColor.self, forKey: .color) ?? SlideColor("#FFFFFF14"),
                region: try container.decodeIfPresent(UnitRect.self, forKey: .region) ?? .full,
                size: try container.decodeIfPresent(Double.self, forKey: .size) ?? 44,
                spacing: try container.decodeIfPresent(Double.self, forKey: .spacing) ?? 140
            )
        case "dots":
            self = .dots(
                color: try container.decodeIfPresent(SlideColor.self, forKey: .color) ?? SlideColor("#FFFFFF14"),
                region: try container.decodeIfPresent(UnitRect.self, forKey: .region) ?? .full,
                spacing: try container.decodeIfPresent(Double.self, forKey: .spacing) ?? 44,
                radius: try container.decodeIfPresent(Double.self, forKey: .radius) ?? 2.4
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown layer type '\(type)'"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text, let style, let region, let verticalAlignment):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encode(style, forKey: .style)
            try container.encode(region, forKey: .region)
            try container.encode(verticalAlignment, forKey: .verticalAlignment)
        case .image(let path, let region, let cornerRadius, let scaling, let rotationDegrees, let maskPath):
            try container.encode("image", forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encode(region, forKey: .region)
            try container.encode(cornerRadius, forKey: .cornerRadius)
            try container.encode(scaling, forKey: .scaling)
            try container.encode(rotationDegrees, forKey: .rotationDegrees)
            try container.encodeIfPresent(maskPath, forKey: .maskPath)
        case .video(let path, let region, let cornerRadius, let scaling, let maskPath):
            try container.encode("video", forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encode(region, forKey: .region)
            try container.encode(cornerRadius, forKey: .cornerRadius)
            try container.encode(scaling, forKey: .scaling)
            try container.encodeIfPresent(maskPath, forKey: .maskPath)
        case .pageIndicator:
            try container.encode("pageIndicator", forKey: .type)
        case .chip(let text, let region, let size, let alignment, let color):
            try container.encode("chip", forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encode(region, forKey: .region)
            try container.encode(size, forKey: .size)
            try container.encode(alignment, forKey: .alignment)
            try container.encodeIfPresent(color, forKey: .color)
        case .rect(let color, let region, let cornerRadius):
            try container.encode("rect", forKey: .type)
            try container.encodeIfPresent(color, forKey: .color)
            try container.encode(region, forKey: .region)
            try container.encode(cornerRadius, forKey: .cornerRadius)
        case .sticker(let text, let region, let rotationDegrees):
            try container.encode("sticker", forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encode(region, forKey: .region)
            try container.encode(rotationDegrees, forKey: .rotationDegrees)
        case .list(let items, let style, let region, let marker, let spacing):
            try container.encode("list", forKey: .type)
            try container.encode(items, forKey: .items)
            try container.encode(style, forKey: .style)
            try container.encode(region, forKey: .region)
            try container.encode(marker, forKey: .marker)
            try container.encode(spacing, forKey: .spacing)

        case .pattern(let glyph, let color, let region, let size, let spacing):
            try container.encode("pattern", forKey: .type)
            try container.encode(glyph, forKey: .glyph)
            try container.encode(color, forKey: .color)
            try container.encode(region, forKey: .region)
            try container.encode(size, forKey: .size)
            try container.encode(spacing, forKey: .spacing)
        case .dots(let color, let region, let spacing, let radius):
            try container.encode("dots", forKey: .type)
            try container.encode(color, forKey: .color)
            try container.encode(region, forKey: .region)
            try container.encode(spacing, forKey: .spacing)
            try container.encode(radius, forKey: .radius)
        }
    }
}
