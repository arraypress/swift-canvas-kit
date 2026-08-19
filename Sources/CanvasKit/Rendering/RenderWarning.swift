//
//  RenderWarning.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Something the renderer saved to disk but a human should look at.
///
/// The renderer is deliberately tolerant — long text shrinks, unknown
/// tokens stay visible, nothing throws for content reasons. That's right
/// for interactive use and dangerous for the actual workload: a model
/// generating a month of decks in a loop. `SlideRenderer.audit(deck:)`
/// turns the tolerances into a report, so a batch pipeline posts the
/// ninety clean decks and flags the three that need eyes.
public struct RenderWarning: Equatable, Sendable, CustomStringConvertible {

    public enum Kind: Equatable, Sendable {
        /// Auto-shrink hit `minimumSize` and the text still doesn't fit —
        /// the content is too long for the region at any allowed size.
        case shrunkToFloor(text: String)

        /// Auto-shrink was off and the text overflows its region — the
        /// bottom lines are clipped.
        case overflow(text: String)

        /// A `{token}` survived into the render — misspelled in the
        /// template or missing from the data.
        case unfilledToken(token: String)

        /// The text cannot be read against what is behind it. `ratio` is the
        /// WCAG figure: 21 is black on white, 1 is invisible.
        case lowContrast(text: String, ratio: Double)

        /// A background's grade could not be built — a missing or malformed
        /// LUT file, usually — so the plate rendered ungraded. The slide
        /// looks plausible and wrong, which is why it is reported rather
        /// than only tolerated.
        case gradeFailed(reason: String)

        /// A background image did not load — the path is wrong, the file is
        /// missing, or a `{token}` in it never filled — so the slide drew
        /// on the placeholder plate instead of the photograph.
        case missingImage(path: String)

        /// An image layer's file could not be read — moved, misspelled,
        /// or a `{token}` that never filled. The strict render throws;
        /// the audit reports it and keeps going, because a batch check
        /// that stops at the first missing file lists one problem when
        /// there are nine.
        case unreadableImage(path: String)

        /// Text or a CTA sits where the platform draws its own chrome —
        /// TikTok's action rail, the caption band, Instagram's carousel
        /// dots. The export looks perfect; the post covers it up.
        case chromeCollision(text: String, zone: String)
    }

    /// Which slide, zero-based.
    public let slideIndex: Int

    public let kind: Kind

    public var description: String {
        switch kind {
        case .shrunkToFloor(let text):
            return "slide \(slideIndex + 1): text hit the auto-shrink floor and still overflows — “\(text.prefix(48))…”"
        case .overflow(let text):
            return "slide \(slideIndex + 1): text overflows its region (autoShrink is off) — “\(text.prefix(48))…”"
        case .unfilledToken(let token):
            return "slide \(slideIndex + 1): unfilled token \(token) is visible in the render"
        case .lowContrast(let text, let ratio):
            let figure = String(format: "%.1f", ratio)
            return "slide \(slideIndex + 1): text is invisible against its background "
                + "(contrast \(figure):1) — “\(text.prefix(48))”"
        case .gradeFailed(let reason):
            return "slide \(slideIndex + 1): the background's grade could not be built, "
                + "so the plate rendered ungraded — \(reason)"
        case .missingImage(let path):
            return "slide \(slideIndex + 1): the background image at '\(path)' did not load — "
                + "a placeholder plate stands where the photograph should be"
        case .unreadableImage(let path):
            return "slide \(slideIndex + 1): no readable image at '\(path)'"
        case .chromeCollision(let text, let zone):
            return "slide \(slideIndex + 1): “\(text.prefix(36))” sits under the \(zone) — "
                + "the platform will draw over it"
        }
    }
}

/// Mutable box the draw path reports into. Internal — the public surface
/// is `SlideRenderer.audit(deck:)` and the `warnings:` render overload.
final class WarningCollector {
    var slideIndex = 0
    var warnings: [RenderWarning] = []

    func report(_ kind: RenderWarning.Kind) {
        warnings.append(RenderWarning(slideIndex: slideIndex, kind: kind))
    }
}
