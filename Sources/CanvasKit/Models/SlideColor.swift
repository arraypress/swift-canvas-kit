//
//  SlideColor.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import Foundation

/// A color as a hex string — `"#1B2A4A"` or `"#1B2A4AFF"` with alpha.
///
/// Stored as text rather than components so deck and template JSON stays
/// hand-writable and diff-able; a template author should be able to change a
/// palette in a text editor. Resolution to `CGColor` happens only at render
/// time.
public struct SlideColor: Codable, Equatable, Sendable, Hashable {

    /// The hex string, always normalized to uppercase `#RRGGBB` or `#RRGGBBAA`.
    public var hex: String

    public init(_ hex: String) {
        self.hex = HexColor.normalize(hex)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        hex = HexColor.normalize(try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }

    /// The color as CoreGraphics sees it. Unparseable hex resolves to full
    /// magenta rather than crashing or vanishing — a wrong color you can see
    /// beats a silent black-on-black slide.
    public var cgColor: CGColor {
        guard let c = HexColor.components(hex) else {
            return CGColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
        }
        return CGColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }

    /// The same color with a different opacity — used for washes and shadows
    /// without the template needing eight-digit hex.
    public func opacity(_ alpha: Double) -> SlideColor {
        SlideColor(HexColor.withAlphaByte(hex, alpha: alpha))
    }


    // MARK: - Common colors

    public static let white = SlideColor("#FFFFFF")
    public static let black = SlideColor("#000000")
}
