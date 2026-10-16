//
//  FontResolver.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import CoreText
import Foundation

/// Style names → `CTFont`, headlessly.
///
/// CoreText only — no AppKit/UIKit, per the package rule — so this runs in a
/// unit test or a CLI. A named family resolves through a font descriptor with
/// weight traits; no family means the system face, which is the right default
/// for this genre anyway.
public enum FontResolver {

    /// Whether a family is installed on this machine.
    ///
    /// Public because the alternative is worse than a missing feature:
    /// CoreText SUBSTITUTES a default face for an unknown family rather than
    /// failing, so a typo in `--font` renders an entire marketing set in the
    /// wrong typeface and looks deliberate. A caller taking a family name from
    /// a human needs to be able to refuse it.
    public static func isAvailable(_ family: String) -> Bool {
        let descriptor = CTFontDescriptorCreateWithAttributes(
            [kCTFontFamilyNameAttribute: family as CFString] as CFDictionary
        )
        let keys = Set([kCTFontFamilyNameAttribute as String]) as NSSet
        let matches = CTFontDescriptorCreateMatchingFontDescriptors(descriptor, keys)
            as? [CTFontDescriptor]
        return !(matches ?? []).isEmpty
    }


    /// Weight names templates use, mapped to descriptor trait values.
    private static let weights: [String: CGFloat] = [
        "ultralight": -0.8,
        "thin": -0.6,
        "light": -0.4,
        "regular": 0.0,
        "medium": 0.23,
        "semibold": 0.30,
        "bold": 0.40,
        "heavy": 0.56,
        "black": 0.62
    ]

    /// Resolve a family + weight + size to a concrete font.
    public static func font(family: String?, weight: String, size: CGFloat) -> CTFont {
        let trait = weights[weight.lowercased()] ?? 0.0

        var attributes: [CFString: Any] = [
            kCTFontTraitsAttribute: [kCTFontWeightTrait: trait]
        ]
        if let family {
            attributes[kCTFontFamilyNameAttribute] = family
        }

        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)

        if family != nil {
            return CTFontCreateWithFontDescriptor(descriptor, size, nil)
        }

        /// System face at the requested weight: start from the UI font and
        /// apply the weighted descriptor, so it stays San Francisco rather
        /// than falling back to Helvetica.
        let system = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        return CTFontCreateCopyWithAttributes(system, size, nil, descriptor)
    }

    /// `font` with variable-font axes set (`wght`, `wdth`, `slnt`, `opsz`,
    /// or the font's own tags) and OpenType features turned on or off
    /// (`smcp`: 1, `liga`: 0). Nothing asked for returns the font as it is;
    /// an axis or feature the face lacks is ignored by CoreText.
    public static func applying(variations: [String: Double]?, features: [String: Int]?, to font: CTFont) -> CTFont {
        var attributes: [CFString: Any] = [:]
        if let variations, !variations.isEmpty {
            var axes: [Int: Double] = [:]
            for (tag, value) in variations {
                if let number = FontTags.number(tag) { axes[number] = value }
            }
            if !axes.isEmpty { attributes[kCTFontVariationAttribute] = axes }
        }
        if let features, !features.isEmpty {
            attributes[kCTFontFeatureSettingsAttribute] = features.keys.sorted().map {
                [kCTFontOpenTypeFeatureTag: $0, kCTFontOpenTypeFeatureValue: features[$0] ?? 1] as [CFString: Any]
            }
        }
        guard !attributes.isEmpty else { return font }
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return CTFontCreateCopyWithAttributes(font, CTFontGetSize(font), nil, descriptor)
    }

    /// The variation axes a face has: tag, smallest, largest, default.
    public static func axes(of font: CTFont) -> [(tag: String, minimum: Double, maximum: Double, defaultValue: Double)] {
        (CTFontCopyVariationAxes(font) as? [[CFString: Any]] ?? []).compactMap { axis in
            guard let number = (axis[kCTFontVariationAxisIdentifierKey] as? NSNumber)?.intValue else { return nil }
            return (FontTags.text(number),
                    (axis[kCTFontVariationAxisMinimumValueKey] as? NSNumber)?.doubleValue ?? 0,
                    (axis[kCTFontVariationAxisMaximumValueKey] as? NSNumber)?.doubleValue ?? 0,
                    (axis[kCTFontVariationAxisDefaultValueKey] as? NSNumber)?.doubleValue ?? 0)
        }
    }
}

/// Four-letter OpenType tags and the numbers CoreText keys axes by.
public enum FontTags {

    /// `wght` as its big-endian four-character code; `nil` unless four ASCII characters.
    public static func number(_ tag: String) -> Int? {
        let bytes = Array(tag.utf8)
        guard bytes.count == 4, bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) else { return nil }
        return bytes.reduce(0) { $0 << 8 | Int($1) }
    }

    /// The tag a four-character code spells.
    public static func text(_ number: Int) -> String {
        String(decoding: (0..<4).reversed().map { UInt8((number >> ($0 * 8)) & 0xFF) }, as: UTF8.self)
    }
}
