//
//  Background.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import Foundation
import VideoGrade

/// What fills the slide behind everything else.
///
/// A slide without its own background inherits the deck's; the deck without
/// one falls back to the brand's background color. That chain is what lets a
/// ten-slide deck restyle from one line of JSON.
/// Which edge a scrim darkens from.
///
/// A scrim is the gradient that buys a caption enough contrast to be read
/// over a photograph without dimming the photograph everywhere. Which edge it
/// runs from is decided by where the words are: a caption along the bottom
/// wants the bottom darkened and the sky left alone, and a headline across
/// the top wants the opposite. Darkening the whole frame to cover both is
/// what `dim` is for, and it costs the picture.
public enum ScrimEdge: String, Codable, Equatable, Sendable, CaseIterable {

    /// Dark at the bottom, clearing upward. The caption idiom.
    case bottom

    /// Dark at the top, clearing downward. For a headline over a bright sky.
    case top

    /// Both ends, clear through the middle — text at each end with the
    /// subject visible between them.
    case both
}

public enum Background: Equatable, Sendable {

    /// A flat color.
    case solid(SlideColor)

    /// A linear gradient. `angle` is degrees, `0` pointing up, clockwise —
    /// `180` is the classic top-lit look.
    case linearGradient(colors: [SlideColor], angle: Double)

    /// An image, aspect-filled and center-cropped to the canvas.
    ///
    /// `dim` lays a flat black wash over the whole frame; `scrim` darkens
    /// from the bottom up — the standard treatment that keeps text readable
    /// over a photograph without flattening the sky. They compose: a light
    /// dim plus a scrim is the travel-content look.
    ///
    /// `grade` color-grades the plate *before* the washes — a VideoGrade
    /// description (curves, split-tone, grain, LUTs…). Text and chrome are
    /// never graded; the look belongs to the plate, the type stays clean.
    ///
    /// `adaptiveScrim` replaces the declared strength and edge with a
    /// measured one: the renderer samples the plate's luminance under the
    /// slide's text and darkens by what legibility actually costs — a
    /// bright sky gets a deep scrim, a dark alley almost none, and the
    /// edge follows where the words sit. The declared values remain the
    /// fallback for a slide with no text or a plate that will not load.
    case image(path: String, dim: Double, scrim: Double, grade: VideoGrade?, scrimEdge: ScrimEdge = .bottom, blur: Double = 0, adaptiveScrim: Bool = false)

    /// A looping video, aspect-filled — the "engaging motion behind the
    /// words" look. Still exports draw its poster frame, so the same deck
    /// works as a photo carousel; the video exporter plays it for the
    /// slide's duration. `dim`, `scrim` and `grade` behave as on images;
    /// animated grade effects (grain, light leaks) advance with the clock.
    case video(path: String, dim: Double, scrim: Double, grade: VideoGrade?, scrimEdge: ScrimEdge = .bottom, blur: Double = 0, adaptiveScrim: Bool = false)

    /// Construction-site ergonomics: the associated values can't default,
    /// so these overloads keep `.image(path:dim:scrim:)` call sites valid.
    public static func image(path: String, dim: Double = 0, scrim: Double = 0) -> Background {
        .image(path: path, dim: dim, scrim: scrim, grade: nil)
    }

    public static func video(path: String, dim: Double = 0, scrim: Double = 0) -> Background {
        .video(path: path, dim: dim, scrim: scrim, grade: nil)
    }
}

// MARK: - Codable
///
/// Hand-written with a `type` discriminator so deck JSON reads the way a
/// template author would write it:
///
///     { "type": "solid", "color": "#1B2A4A" }
///     { "type": "gradient", "colors": ["#FF9A8B", "#FF6A88"], "angle": 160 }
///     { "type": "image", "path": "bg.jpg", "dim": 0.35 }
extension Background: Codable {

    private enum CodingKeys: String, CodingKey {
        case type, color, colors, angle, path, dim, scrim, grade, scrimEdge, blur, adaptiveScrim
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "solid":
            self = .solid(try container.decode(SlideColor.self, forKey: .color))
        case "gradient":
            self = .linearGradient(
                colors: try container.decode([SlideColor].self, forKey: .colors),
                angle: try container.decodeIfPresent(Double.self, forKey: .angle) ?? 180
            )
        case "image":
            self = .image(
                path: try container.decode(String.self, forKey: .path),
                dim: try container.decodeIfPresent(Double.self, forKey: .dim) ?? 0,
                scrim: try container.decodeIfPresent(Double.self, forKey: .scrim) ?? 0,
                grade: try container.decodeIfPresent(VideoGrade.self, forKey: .grade),
                scrimEdge: try container.decodeIfPresent(ScrimEdge.self, forKey: .scrimEdge) ?? .bottom,
                blur: try container.decodeIfPresent(Double.self, forKey: .blur) ?? 0,
                adaptiveScrim: try container.decodeIfPresent(Bool.self, forKey: .adaptiveScrim) ?? false
            )
        case "video":
            self = .video(
                path: try container.decode(String.self, forKey: .path),
                dim: try container.decodeIfPresent(Double.self, forKey: .dim) ?? 0,
                scrim: try container.decodeIfPresent(Double.self, forKey: .scrim) ?? 0,
                grade: try container.decodeIfPresent(VideoGrade.self, forKey: .grade),
                scrimEdge: try container.decodeIfPresent(ScrimEdge.self, forKey: .scrimEdge) ?? .bottom,
                blur: try container.decodeIfPresent(Double.self, forKey: .blur) ?? 0,
                adaptiveScrim: try container.decodeIfPresent(Bool.self, forKey: .adaptiveScrim) ?? false
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown background type '\(type)'"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .solid(let color):
            try container.encode("solid", forKey: .type)
            try container.encode(color, forKey: .color)
        case .linearGradient(let colors, let angle):
            try container.encode("gradient", forKey: .type)
            try container.encode(colors, forKey: .colors)
            try container.encode(angle, forKey: .angle)
        case .image(let path, let dim, let scrim, let grade, let edge, let blur, let adaptive):
            try container.encode("image", forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encode(dim, forKey: .dim)
            try container.encode(scrim, forKey: .scrim)
            try container.encodeIfPresent(grade, forKey: .grade)
            try container.encode(edge, forKey: .scrimEdge)
            try container.encode(blur, forKey: .blur)
            try container.encode(adaptive, forKey: .adaptiveScrim)
        case .video(let path, let dim, let scrim, let grade, let edge, let blur, let adaptive):
            try container.encode("video", forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encode(dim, forKey: .dim)
            try container.encode(scrim, forKey: .scrim)
            try container.encodeIfPresent(grade, forKey: .grade)
            try container.encode(edge, forKey: .scrimEdge)
            try container.encode(blur, forKey: .blur)
            try container.encode(adaptive, forKey: .adaptiveScrim)
        }
    }
}
