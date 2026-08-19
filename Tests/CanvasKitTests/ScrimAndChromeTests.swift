//
//  ScrimAndChromeTests.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//
//  The agent-first contract: content that stops short still produces a
//  post-ready deck, the new archetypes carry long content honestly, the
//  scrim is measured rather than guessed, chrome zones are checked, and the
//  whole vocabulary is machine-readable.
//

import CoreGraphics
import Foundation
import Testing
@testable import CanvasKit

// MARK: - The measured scrim

@Test func theScrimIsChosenByMeasurementNotDeclaration() throws {
    func plate(_ gray: CGFloat) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 64, height: 80,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: gray, green: gray, blue: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 80))
        return try #require(context.makeImage())
    }

    let canvas = Canvas.portrait
    /// A caption block along the bottom, in canvas pixels.
    let caption = [CGRect(x: 108, y: 135, width: 864, height: 270)]
    let declared = (dim: 0.05, scrim: 0.5, edge: ScrimEdge.bottom)

    let sky = SlideRenderer.adaptiveWashes(
        plate: try plate(0.9), textRegions: caption, canvas: canvas, declared: declared
    )
    let alley = SlideRenderer.adaptiveWashes(
        plate: try plate(0.08), textRegions: caption, canvas: canvas, declared: declared
    )
    #expect(sky.1 > 0.6, "a bright sky needs a deep scrim — got \(sky.1)")
    #expect(alley.1 < 0.2, "a dark alley needs almost none — got \(alley.1)")
    #expect(sky.1 > alley.1 + 0.3, "the two plates must be treated differently")
    #expect(sky.2 == .bottom, "the edge follows the words")

    /// A headline block along the top pulls the scrim up with it.
    let headline = [CGRect(x: 108, y: 1000, width: 864, height: 270)]
    let top = SlideRenderer.adaptiveWashes(
        plate: try plate(0.9), textRegions: headline, canvas: canvas, declared: declared
    )
    #expect(top.2 == .top)

    /// Words at both ends darken both.
    let both = SlideRenderer.adaptiveWashes(
        plate: try plate(0.9), textRegions: caption + headline, canvas: canvas, declared: declared
    )
    #expect(both.2 == .both)

    /// Nothing to protect: the declaration stands.
    let bare = SlideRenderer.adaptiveWashes(
        plate: try plate(0.9), textRegions: [], canvas: canvas, declared: declared
    )
    #expect(bare.1 == declared.scrim && bare.2 == declared.edge)
}

// MARK: - Chrome zones

@Test func aChipUnderThePlatformChromeIsFlagged() throws {
    let chip = SlideLayer.chip(
        text: "Read more", region: UnitRect(x: 0.87, y: 0.5, width: 0.12, height: 0.06),
        size: 30, alignment: "center", color: nil
    )

    var deck = SlideDeck(canvas: .tiktok, slides: [Slide(layers: [chip])])
    let onTikTok = try SlideRenderer.audit(deck: deck)
    #expect(onTikTok.contains { warning in
        if case .chromeCollision(_, let zone) = warning.kind { return zone.contains("rail") }
        return false
    }, "a CTA in the action rail is a CTA nobody can press")

    /// The same layout on the 4:5 feed canvas collides with nothing —
    /// zones belong to platforms, not to slides.
    deck.canvas = .portrait
    let onFeed = try SlideRenderer.audit(deck: deck)
    #expect(!onFeed.contains { warning in
        if case .chromeCollision = warning.kind { return true }
        return false
    })
}

@Test func textUnderTheCarouselDotsIsFlagged() throws {
    let deck = SlideDeck(canvas: .portrait, slides: [Slide(layers: [
        .text(text: "Save this post", style: TextStyle(size: 30),
              region: UnitRect(x: 0.3, y: 0.945, width: 0.4, height: 0.05),
              verticalAlignment: "top")
    ])])
    let warnings = try SlideRenderer.audit(deck: deck)
    #expect(warnings.contains { warning in
        if case .chromeCollision(_, let zone) = warning.kind { return zone.contains("dots") }
        return false
    })
}

@Test func chromeZonesLoadFromTheBundle() {
    #expect(ChromeZones.zones(for: .tiktok).count >= 2)
    #expect(ChromeZones.zones(for: Canvas(width: 999, height: 999)).isEmpty,
            "a custom canvas claims no platform, so no zones apply")
}
