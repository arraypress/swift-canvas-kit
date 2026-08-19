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
enum FontResolver {

    /// Weight names templates use, mapped to descriptor trait values.
    private static let weights: [String: CGFloat] = [
        "regular": 0.0,
        "medium": 0.23,
        "semibold": 0.30,
        "bold": 0.40,
        "heavy": 0.56,
        "black": 0.62
    ]

    /// Resolve a family + weight + size to a concrete font.
    static func font(family: String?, weight: String, size: CGFloat) -> CTFont {
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
}
