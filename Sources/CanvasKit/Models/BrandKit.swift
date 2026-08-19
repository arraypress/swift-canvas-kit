//
//  BrandKit.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Everything that makes a deck *yours*, in one value: palette, type, handle,
/// logo.
///
/// This is the flexibility most people actually want — not a layout editor.
/// Templates position things; the brand decides how they look. The same
/// listicle template renders on-brand for two different accounts by swapping
/// this one struct.
public struct BrandKit: Codable, Equatable, Sendable {

    /// Display name, drawn next to the logo in the footer.
    public var name: String

    /// The @handle, drawn under the name — the follow prompt every slide
    /// carries for free.
    public var handle: String

    /// Path to a logo image (PNG/JPEG). Drawn in a circle in the footer.
    public var logoPath: String?

    /// Default font family for every text layer that doesn't set its own.
    public var fontFamily: String?

    /// The fallback canvas fill when neither slide nor deck sets a background.
    public var backgroundColor: SlideColor

    /// Primary text color.
    public var textColor: SlideColor

    /// Secondary text — eyebrows, footers, page numbers.
    public var secondaryTextColor: SlideColor

    /// The accent — `**starred**` spans, number chips, CTA fills.
    public var accentColor: SlideColor

    /// Whether slides carry the name/handle/logo footer.
    public var showsFooter: Bool

    public init(
        name: String = "",
        handle: String = "",
        logoPath: String? = nil,
        fontFamily: String? = nil,
        backgroundColor: SlideColor = SlideColor("#101418"),
        textColor: SlideColor = .white,
        secondaryTextColor: SlideColor = SlideColor("#FFFFFFB3"),
        accentColor: SlideColor = SlideColor("#4E9CFF"),
        showsFooter: Bool = true
    ) {
        self.name = name
        self.handle = handle
        self.logoPath = logoPath
        self.fontFamily = fontFamily
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.secondaryTextColor = secondaryTextColor
        self.accentColor = accentColor
        self.showsFooter = showsFooter
    }

    /// Tolerant decoding — a brand file with just a name and an accent is
    /// valid.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        handle = try container.decodeIfPresent(String.self, forKey: .handle) ?? ""
        logoPath = try container.decodeIfPresent(String.self, forKey: .logoPath)
        fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily)
        backgroundColor = try container.decodeIfPresent(SlideColor.self, forKey: .backgroundColor) ?? SlideColor("#101418")
        textColor = try container.decodeIfPresent(SlideColor.self, forKey: .textColor) ?? .white
        secondaryTextColor = try container.decodeIfPresent(SlideColor.self, forKey: .secondaryTextColor) ?? SlideColor("#FFFFFFB3")
        accentColor = try container.decodeIfPresent(SlideColor.self, forKey: .accentColor) ?? SlideColor("#4E9CFF")
        showsFooter = try container.decodeIfPresent(Bool.self, forKey: .showsFooter) ?? true
    }
}
