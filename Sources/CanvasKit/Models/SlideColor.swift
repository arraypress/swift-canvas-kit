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
        self.hex = Self.normalize(hex)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        hex = Self.normalize(try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }

    /// The color as CoreGraphics sees it. Unparseable hex resolves to full
    /// magenta rather than crashing or vanishing — a wrong color you can see
    /// beats a silent black-on-black slide.
    public var cgColor: CGColor {
        var value = hex
        value.removeFirst()

        guard value.count == 6 || value.count == 8,
              let bits = UInt64(value, radix: 16) else {
            return CGColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
        }

        let hasAlpha = value.count == 8
        let shift: UInt64 = hasAlpha ? 8 : 0
        let red = CGFloat((bits >> (16 + shift)) & 0xFF) / 255
        let green = CGFloat((bits >> (8 + shift)) & 0xFF) / 255
        let blue = CGFloat((bits >> shift) & 0xFF) / 255
        let alpha = hasAlpha ? CGFloat(bits & 0xFF) / 255 : 1

        return CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    /// The same color with a different opacity — used for washes and shadows
    /// without the template needing eight-digit hex.
    public func opacity(_ alpha: Double) -> SlideColor {
        var value = hex
        value.removeFirst()
        if value.count == 8 { value.removeLast(2) }
        let byte = String(format: "%02X", Int((alpha.clamped(to: 0...1) * 255).rounded()))
        return SlideColor("#\(value)\(byte)")
    }

    private static func normalize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces).uppercased()
        if !value.hasPrefix("#") { value = "#" + value }

        /// CSS shorthand, because this JSON is written by hand: `#FC6`
        /// doubles to `#FFCC66`, `#FC68` to `#FFCC6688`. Normalized here so
        /// `SlideColor("#FFF") == SlideColor("#FFFFFF")` and the render
        /// path never sees the short form.
        let digits = value.dropFirst()
        if digits.count == 3 || digits.count == 4, digits.allSatisfy(\.isHexDigit) {
            value = "#" + digits.map { "\($0)\($0)" }.joined()
        }
        return value
    }

    // MARK: - Common colors

    public static let white = SlideColor("#FFFFFF")
    public static let black = SlideColor("#000000")
}

extension Double {
    /// Clamp to a closed range — tiny, but used everywhere unit values arrive
    /// from hand-written JSON.
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
