//
//  ContrastTests.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//
//  Making a design of your own, and being told when it cannot be read.
//
//  The two halves belong together. Customising a template is easy to offer
//  and easy to get wrong — a palette changed halfway leaves white text on a
//  cream ground, and the render succeeds, and the file is fine, and nobody
//  looks at slide four until it is posted. So the same work that made designs
//  editable added the check that says when an edit has gone wrong.
//

import CoreGraphics
import Foundation
import Testing
@testable import CanvasKit

@Test func aPaletteChangedHalfwayIsCaught() throws {
    /// The case this exists for: a dark design given a light background,
    /// where the heading was recoloured and the secondary text was not.
    let deck = SlideDeck(
        brand: BrandKit(textColor: SlideColor("#FFFFFF")),
        slides: [
            Slide(background: .solid(SlideColor("#FFF6F9")), layers: [
                .text(text: "Rose faster than wages for the fourth year.",
                      style: TextStyle(size: 44), region: .full, verticalAlignment: "middle")
            ])
        ]
    )

    let warnings = try SlideRenderer.audit(deck: deck)
    #expect(warnings.contains { if case .lowContrast = $0.kind { return true } else { return false } })
}

@Test func aPillIsTheBackdropRatherThanAnExcuse() throws {
    /// Skipping pilled text was the first version, and it missed white on a
    /// white pill in the shipped library — the highlighter idiom is exactly
    /// where the wrong ink hides.
    func audit(ink: SlideColor) throws -> Bool {
        let deck = SlideDeck(slides: [
            Slide(background: .solid(SlideColor("#4C1D95")), layers: [
                .text(text: "A headline",
                      style: TextStyle(size: 84, color: ink, linePill: SlideColor("#FFFFFF")),
                      region: .full, verticalAlignment: "middle")
            ])
        ])
        return try SlideRenderer.audit(deck: deck)
            .contains { if case .lowContrast = $0.kind { return true } else { return false } }
    }

    #expect(try audit(ink: SlideColor("#FFFFFF")), "white on a white pill was not caught")
    #expect(try !audit(ink: SlideColor("#141115")), "dark on a white pill was wrongly flagged")
}

@Test func decorationIsNotJudgedAsCopy() throws {
    /// The oversized watermark glyph behind a question slide is meant to be
    /// barely there. Flagging it taught people to ignore the warning.
    let deck = SlideDeck(slides: [
        Slide(background: .solid(SlideColor("#020C1B")), layers: [
            .text(text: "?",
                  style: TextStyle(size: 240, color: SlideColor("#5EEAD41E"), autoShrink: false),
                  region: .full, verticalAlignment: "middle")
        ])
    ])

    #expect(try SlideRenderer.audit(deck: deck)
        .allSatisfy { if case .lowContrast = $0.kind { return false } else { return true } })
}

@Test func aPhotographIsNotJudgedAsOneColour() throws {
    /// A caption is readable over the dark half of a picture and gone over
    /// the bright half, and a number averaged over the plate is wrong in
    /// both. That is what the scrim is for, and whether it is deep enough is
    /// a judgement about a photograph.
    let deck = SlideDeck(slides: [
        Slide(background: .image(path: "/nowhere.jpg", dim: 0, scrim: 0, grade: nil),
              layers: [
                .text(text: "A caption",
                      style: TextStyle(size: 60, color: SlideColor("#FFFFFF")),
                      region: .full, verticalAlignment: "middle")
              ])
    ])

    #expect(Contrast.backdrop(of: deck.slides[0], in: deck) == nil)
}

@Test func aGradientIsJudgedByItsWorstEnd() throws {
    /// A headline that clears the light end and disappears into the dark end
    /// is not a headline that passes.
    let deck = SlideDeck(slides: [
        Slide(background: .linearGradient(
            colors: [SlideColor("#000000"), SlideColor("#FFFFFF")], angle: 0
        ), layers: [])
    ])

    #expect(Contrast.backdrop(of: deck.slides[0], in: deck) == SlideColor("#000000"))
}

@Test func translucentInkIsJudgedAsItLooks() throws {
    /// Text at 60% on a light ground is a lighter grey than its hex says, and
    /// a secondary colour that was fine over black is the commonest way a
    /// half-changed palette goes wrong.
    let over = Contrast.composited(SlideColor("#00000080"), over: SlideColor("#FFFFFF"))
    #expect(Contrast.ratio(over, on: SlideColor("#FFFFFF"))
            < Contrast.ratio(SlideColor("#000000"), on: SlideColor("#FFFFFF")))
}

