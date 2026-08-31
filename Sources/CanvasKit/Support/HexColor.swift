//
//  HexColor.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//
//  The hex-string rules behind SlideColor, alone and testable: shorthand
//  doubling, parsing to components, alpha-byte surgery. The model states
//  that a color IS a hex string; everything about how that string is
//  read and rewritten lives here.
//

import CoreGraphics
import Foundation

/// Parsing and rewriting for `SlideColor`'s hex form.
enum HexColor {

    /// Uppercased, `#`-prefixed, shorthand expanded.
    ///
    /// CSS shorthand, because this JSON is written by hand: `#FC6`
    /// doubles to `#FFCC66`, `#FC68` to `#FFCC6688`. Normalized here so
    /// `SlideColor("#FFF") == SlideColor("#FFFFFF")` and the render
    /// path never sees the short form.
    static func normalize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces).uppercased()
        if !value.hasPrefix("#") { value = "#" + value }
        let digits = value.dropFirst()
        if digits.count == 3 || digits.count == 4, digits.allSatisfy(\.isHexDigit) {
            value = "#" + digits.map { "\($0)\($0)" }.joined()
        }
        return value
    }

    /// sRGB components of a normalized `#RRGGBB` / `#RRGGBBAA` string,
    /// or `nil` when it doesn't parse.
    static func components(_ normalizedHex: String) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        var value = normalizedHex
        value.removeFirst()
        guard value.count == 6 || value.count == 8,
              let bits = UInt64(value, radix: 16) else { return nil }
        let hasAlpha = value.count == 8
        let shift: UInt64 = hasAlpha ? 8 : 0
        return (
            red: CGFloat((bits >> (16 + shift)) & 0xFF) / 255,
            green: CGFloat((bits >> (8 + shift)) & 0xFF) / 255,
            blue: CGFloat((bits >> shift) & 0xFF) / 255,
            alpha: hasAlpha ? CGFloat(bits & 0xFF) / 255 : 1
        )
    }

    /// The normalized hex with its alpha byte replaced — washes and
    /// shadows without the template needing eight-digit hex.
    static func withAlphaByte(_ normalizedHex: String, alpha: Double) -> String {
        var value = normalizedHex
        value.removeFirst()
        if value.count == 8 { value.removeLast(2) }
        let byte = String(format: "%02X", Int((alpha.clamped(to: 0...1) * 255).rounded()))
        return "#\(value)\(byte)"
    }
}
