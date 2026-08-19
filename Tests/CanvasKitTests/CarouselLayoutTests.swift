//
//  CarouselLayoutTests.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//
//  The four layouts that a survey of real carousels turned up and this could
//  not draw.
//
//  Everything else in that survey was already here: full-bleed photographs
//  with a caption, a headline with one word in another colour, highlighter
//  boxes behind each line, outlined text over a busy plate, watermarks in the
//  corners, text anchored anywhere in the frame. These four were not, and
//  each is the sort of thing that is invisible until somebody tries to make
//  the slide and finds they cannot.
//

import CoreGraphics
import Foundation
import Testing
@testable import CanvasKit

// MARK: - Emphasis that is weight rather than colour

@Test func accentSpansCanEmboldenInsteadOfRecolouring() throws {
    /// The magazine idiom: a phrase inside a paragraph picked out in the same
    /// ink, only heavier. Before this, `**span**` could only change colour,
    /// so the most ordinary kind of emphasis in written prose was the one
    /// thing the drawer could not do.
    let style = TextStyle(weight: "regular", size: 48, accentWeight: "bold")

    #expect(style.accentWeight == "bold")

    let deck = SlideDeck(slides: [
        Slide(layers: [
            .text(
                text: "Not emotional intelligence, but **systems thinking** — the kind "
                    + "that can reshape the world around it.",
                style: style, region: .full, verticalAlignment: "middle"
            )
        ])
    ])

    /// It renders, and it renders differently from the same text set without
    /// the heavier accent — otherwise the field would be decorative.
    let bolded = try SlideRenderer.render(deck: deck, slideIndex: 0)

    var plainStyle = style
    plainStyle.accentWeight = nil
    let plainDeck = SlideDeck(slides: [
        Slide(layers: [
            .text(
                text: "Not emotional intelligence, but **systems thinking** — the kind "
                    + "that can reshape the world around it.",
                style: plainStyle, region: .full, verticalAlignment: "middle"
            )
        ])
    ])
    let plain = try SlideRenderer.render(deck: plainDeck, slideIndex: 0)

    #expect(bolded.dataProvider?.data as Data? != plain.dataProvider?.data as Data?)
}

@Test func aWeightWithoutAColourKeepsTheBodyInk() throws {
    /// Asking to embolden is not asking to recolour as well. Without this,
    /// every emphasised phrase would come out in the brand accent, which is
    /// right for a headline with one yellow word and wrong for a paragraph.
    let deck = SlideDeck(slides: [
        Slide(layers: [
            .text(text: "plain **heavy** plain",
                  style: TextStyle(size: 48, accentWeight: "bold"),
                  region: .full, verticalAlignment: "middle")
        ])
    ])
    #expect(throws: Never.self) { try SlideRenderer.render(deck: deck, slideIndex: 0) }
}

@Test func accentWeightSurvivesJSON() throws {
    let style = TextStyle(size: 44, accentColor: SlideColor("#E5FF4F"), accentWeight: "black")
    let data = try JSONEncoder().encode(style)
    let back = try JSONDecoder().decode(TextStyle.self, from: data)

    #expect(back.accentWeight == "black")
    #expect(back.accentColor == SlideColor("#E5FF4F"))
}

@Test func aStyleThatSaysNothingAboutAccentsIsUnchanged() throws {
    /// The field is additive: decks written before it existed behave exactly
    /// as they did, with `**spans**` taking the brand accent colour.
    let decoded = try JSONDecoder().decode(TextStyle.self, from: Data(#"{"size": 60}"#.utf8))
    #expect(decoded.accentWeight == nil)
}

// MARK: - Lists with a marker per entry

@Test func aRankedListDrawsAMarkerBesideEachEntry() throws {
    /// The ranked-list slide — four places, each with a coloured rule beside
    /// it — could not be built out of `rect` layers, because the rule has to
    /// be as tall as the entry and how tall that is depends on where the text
    /// wrapped. Only the renderer knows that.
    let deck = SlideDeck(slides: [
        Slide(layers: [
            .list(
                items: [
                    ListItem(title: "12th — Aries",
                             body: "Emotional decisions often outweigh cool analysis."),
                    ListItem(title: "11th — Pisces",
                             body: "Powerful intuition, but logic isn't their strong suit."),
                    ListItem(title: "10th — Leo",
                             body: "A brilliant mind, but focus lets them down."),
                ],
                style: TextStyle(size: 40, accentWeight: "bold"),
                region: UnitRect(x: 0.1, y: 0.2, width: 0.8, height: 0.6),
                marker: .rule(color: SlideColor("#D6294B"), width: 8),
                spacing: 30
            )
        ])
    ])

    let image = try SlideRenderer.render(deck: deck, slideIndex: 0)
    #expect(image.width == 1080)
}

@Test func everyMarkerStyleDraws() throws {
    for marker: ListMarker in [
        .rule(color: nil, width: 8),
        .bullet(color: nil, radius: 7),
        .number(color: nil),
        .none,
    ] {
        let deck = SlideDeck(slides: [
            Slide(layers: [
                .list(
                    items: [ListItem(body: "One"), ListItem(body: "Two")],
                    style: TextStyle(size: 40),
                    region: UnitRect(x: 0.1, y: 0.2, width: 0.8, height: 0.6),
                    marker: marker, spacing: 24
                )
            ])
        ])
        #expect(throws: Never.self) { try SlideRenderer.render(deck: deck, slideIndex: 0) }
    }
}

@Test func numbersSurviveAComfortableLineHeight() throws {
    /// Found by rendering a list and looking at it: the number's frame was
    /// sized from the point size alone, so a body style leaded at 1.18 made
    /// the line taller than its box and CoreText drew nothing. The numbers
    /// disappeared from any list whose text was comfortably set — which is
    /// most of them — while the gutter they sat in stayed reserved, so the
    /// entries were indented against nothing.
    func render(lineHeight: Double) throws -> Data? {
        let deck = SlideDeck(canvas: .portrait, slides: [
            Slide(background: .solid(SlideColor("#FFFFFF")), layers: [
                .list(
                    items: [ListItem(title: "Cut the commute", body: "Move nearer.")],
                    style: TextStyle(size: 38, color: SlideColor("#101114"),
                                     accentWeight: "bold", lineHeight: lineHeight),
                    region: UnitRect(x: 0.1, y: 0.2, width: 0.8, height: 0.5),
                    marker: .number(color: SlideColor("#D6294B")), spacing: 30
                )
            ])
        ])
        return try SlideRenderer.render(deck: deck, slideIndex: 0).dataProvider?.data as Data?
    }

    /// The same list with no marker at all is the picture a missing number
    /// produces. A drawn number has to differ from it.
    let blank = try {
        let deck = SlideDeck(canvas: .portrait, slides: [
            Slide(background: .solid(SlideColor("#FFFFFF")), layers: [
                .list(
                    items: [ListItem(title: "Cut the commute", body: "Move nearer.")],
                    style: TextStyle(size: 38, color: SlideColor("#101114"),
                                     accentWeight: "bold", lineHeight: 1.18),
                    region: UnitRect(x: 0.1, y: 0.2, width: 0.8, height: 0.5),
                    marker: .number(color: SlideColor("#00000000")), spacing: 30
                )
            ])
        ])
        return try SlideRenderer.render(deck: deck, slideIndex: 0).dataProvider?.data as Data?
    }()

    #expect(try render(lineHeight: 1.18) != blank, "the number did not draw at 1.18 leading")
    #expect(try render(lineHeight: 1.0) != blank)
}

@Test func anEntryWithNoTitleIsASingleBlock() throws {
    let deck = SlideDeck(slides: [
        Slide(layers: [
            .list(
                items: [ListItem(body: "A plain bulleted point with no lead-in.")],
                style: TextStyle(size: 40),
                region: UnitRect(x: 0.1, y: 0.3, width: 0.8, height: 0.4),
                marker: .bullet(color: nil, radius: 6), spacing: 20
            )
        ])
    ])
    #expect(throws: Never.self) { try SlideRenderer.render(deck: deck, slideIndex: 0) }
}

@Test func entriesThatDoNotFitAreReportedRatherThanDrawnOffTheEdge() throws {
    /// A slide quietly missing its last two places is worse than one that
    /// says so — the whole point of a ranked list is that it is complete.
    let many = (1...20).map { ListItem(title: "\($0)th", body: String(repeating: "word ", count: 20)) }
    let deck = SlideDeck(slides: [
        Slide(layers: [
            .list(
                items: many, style: TextStyle(size: 44),
                region: UnitRect(x: 0.1, y: 0.4, width: 0.8, height: 0.2),
                marker: .rule(color: nil, width: 8), spacing: 24
            )
        ])
    ])

    let warnings = try SlideRenderer.audit(deck: deck)
    #expect(warnings.contains { "\($0)".contains("th") || "\($0)".contains("overflow") })
}

@Test func aListSurvivesJSON() throws {
    let layer = SlideLayer.list(
        items: [ListItem(title: "1st — Aquarius", body: "Systems thinking.")],
        style: TextStyle(size: 42, accentWeight: "bold"),
        region: UnitRect(x: 0.1, y: 0.2, width: 0.8, height: 0.5),
        marker: .rule(color: SlideColor("#D6294B"), width: 10),
        spacing: 28
    )

    let data = try JSONEncoder().encode(layer)
    #expect(try JSONDecoder().decode(SlideLayer.self, from: data) == layer)
}

@Test func aListTakesTemplateTokensLikeAnythingElse() throws {
    /// So a template can carry a ranked list whose places and names arrive as
    /// data, which is the only way this is worth having.
    let layer = SlideLayer.list(
        items: [ListItem(title: "{place}", body: "{reason}")],
        style: TextStyle(), region: .full,
        marker: .rule(color: nil, width: 8), spacing: 24
    )

    guard case .list(let filled, _, _, _, _) =
        layer.substituting(["place": "12th — Aries", "reason": "Emotional decisions."])
    else {
        Issue.record("expected a list"); return
    }

    #expect(filled[0].title == "12th — Aries")
    #expect(filled[0].body == "Emotional decisions.")
}

// MARK: - Which end the scrim darkens

@Test func aScrimCanDarkenTheTopAsWellAsTheBottom() throws {
    /// A caption along the bottom wants the bottom darkened and the sky left
    /// alone; a headline across the top wants the opposite. Before this the
    /// gradient was hard-coded upward from the bottom, so a slide with text
    /// at the top had to dim the whole frame and lose the picture.
    let top = SlideRenderer.renderWashes(dim: 0, scrim: 0.8, edge: .top, width: 200, height: 400)
    let bottom = SlideRenderer.renderWashes(dim: 0, scrim: 0.8, edge: .bottom, width: 200, height: 400)
    let both = SlideRenderer.renderWashes(dim: 0, scrim: 0.8, edge: .both, width: 200, height: 400)

    #expect(top != nil)
    #expect(top?.dataProvider?.data as Data? != bottom?.dataProvider?.data as Data?)
    #expect(both?.dataProvider?.data as Data? != bottom?.dataProvider?.data as Data?)
}

@Test func theScrimEdgeSurvivesJSONAndDefaultsToTheBottom() throws {
    let background = Background.image(path: "x.jpg", dim: 0, scrim: 0.7, grade: nil,
                                      scrimEdge: .both, blur: 12)
    let data = try JSONEncoder().encode(background)
    #expect(try JSONDecoder().decode(Background.self, from: data) == background)

    /// A deck written before the field existed still reads, and reads as it
    /// used to behave.
    let old = try JSONDecoder().decode(
        Background.self,
        from: Data(#"{"type":"image","path":"x.jpg","scrim":0.6}"#.utf8)
    )
    guard case .image(_, _, let scrim, _, let edge, let blur, _) = old else {
        Issue.record("expected an image background"); return
    }
    #expect(scrim == 0.6)
    #expect(edge == .bottom)
    #expect(blur == 0)
}

// MARK: - A blurred backdrop

@Test func aBackgroundCanBeBlurred() throws {
    /// The idiom is a portrait photograph on a square canvas: rather than
    /// bars down each side, the same picture is blown up, blurred and used as
    /// its own backdrop with the sharp copy laid over it.
    let plate = try makePlate(width: 64, height: 64)

    let sharp = SlideRenderer.blurred(plate, radius: 0)
    let soft = SlideRenderer.blurred(plate, radius: 8)

    #expect(sharp.dataProvider?.data as Data? == plate.dataProvider?.data as Data?)
    #expect(soft.width == plate.width)
    #expect(soft.height == plate.height)
    #expect(soft.dataProvider?.data as Data? != plate.dataProvider?.data as Data?)
}

@Test func blurringDoesNotDarkenTheEdges() throws {
    /// A Gaussian samples past the bounds and reads transparent black out
    /// there, which rings a blurred image with a dark band — the one artefact
    /// that gives the trick away. The plate is clamped before blurring.
    let plate = try makePlate(width: 64, height: 64, white: true)
    let soft = SlideRenderer.blurred(plate, radius: 10)

    let corner = try pixel(of: soft, x: 1, y: 1)
    #expect(corner > 200, "the corner darkened to \(corner) — the blur is sampling past the edge")
}

// MARK: - A keyline round filled text

@Test func textCanBeFilledAndOutlinedRatherThanHollow() throws {
    /// Found by rendering one and looking at it. `strokeWidth` was
    /// stroke-only — the hollow display treatment — so the commonest thing
    /// anybody does to text over a photograph, filling it and holding it off
    /// the picture with a dark keyline, came out as empty letters.
    ///
    /// CoreText reads the sign of the stroke width as the mode. That is not
    /// something a caller should have to know, so the style names the
    /// treatment.
    let base = TextStyle(size: 80, color: SlideColor("#E5FF4F"),
                         strokeWidth: 4, strokeColor: SlideColor("#000000"))

    var hollow = base
    hollow.strokeStyle = .hollow
    var outlined = base
    outlined.strokeStyle = .outlined

    func render(_ style: TextStyle) throws -> Data? {
        let deck = SlideDeck(slides: [
            Slide(background: .solid(SlideColor("#3B6FD4")), layers: [
                .text(text: "I'VE GAINED WEIGHT", style: style,
                      region: .full, verticalAlignment: "middle")
            ])
        ])
        return try SlideRenderer.render(deck: deck, slideIndex: 0).dataProvider?.data as Data?
    }

    #expect(try render(hollow) != render(outlined))
}

@Test func hollowRemainsTheDefault() throws {
    /// Decks written before the treatment was nameable keep the look they
    /// were drawn with.
    #expect(TextStyle(strokeWidth: 4).strokeStyle == .hollow)

    let decoded = try JSONDecoder().decode(
        TextStyle.self, from: Data(#"{"size": 60, "strokeWidth": 4}"#.utf8)
    )
    #expect(decoded.strokeStyle == .hollow)
}

@Test func theStrokeStyleSurvivesJSON() throws {
    let style = TextStyle(size: 70, strokeWidth: 3, strokeStyle: .outlined,
                          strokeColor: SlideColor("#000000"))
    let data = try JSONEncoder().encode(style)
    #expect(try JSONDecoder().decode(TextStyle.self, from: data).strokeStyle == .outlined)
}

// MARK: - The seams inside a stroked glyph

@Test func outlinedTextIsAKeylineWithAFillOverIt() throws {
    /// A glyph outline is often several overlapping subpaths — the diagonal
    /// of an N laid across its stems, the bowls of a B across its spine.
    /// Filling hides the seams; CoreText's fill-and-stroke mode strokes every
    /// subpath and draws all of them, which put a lightning bolt through the
    /// N and a ghost letter inside the A.
    ///
    /// So outlined text is not one pass — it is the keyline laid down alone
    /// and the fill painted over it, which covers the seams and leaves only
    /// the part of the stroke outside the letter. That is what this asserts,
    /// and it asserts it exactly: the same thing built by hand out of two
    /// ordinary text layers has to come out pixel for pixel identical.
    ///
    /// Stated this way rather than by hunting for dark marks in the render,
    /// because a threshold that separates "seam" from "two strokes meeting
    /// at a shallow angle" is a threshold tuned until the test passes.
    for letter in ["N", "A", "B", "R", "M", "K"] {
        let style = TextStyle(
            weight: "black", size: 260, color: SlideColor("#E5FF4F"),
            autoShrink: false, strokeWidth: 4, strokeStyle: .outlined,
            strokeColor: SlideColor("#000000")
        )

        var keyline = style
        keyline.strokeStyle = .hollow
        keyline.strokeWidth = style.strokeWidth * 2

        var fill = style
        fill.strokeWidth = 0

        let byHand = SlideDeck(canvas: .square, slides: [
            Slide(background: .solid(SlideColor("#FFFFFF")), layers: [
                .text(text: letter, style: keyline, region: .full, verticalAlignment: "middle"),
                .text(text: letter, style: fill, region: .full, verticalAlignment: "middle"),
            ])
        ])

        let one = try render(letter, stroke: .outlined).dataProvider?.data as Data?
        let two = try SlideRenderer.render(deck: byHand, slideIndex: 0)
            .dataProvider?.data as Data?

        #expect(one == two, "\(letter): outlined is not the keyline-then-fill it claims to be")
    }
}

@Test func theKeylineIsActuallyDrawn() throws {
    /// The other way this can go wrong: no seams because no stroke. The
    /// letter must sit inside a dark edge.
    let image = try render("N", stroke: .outlined)
    #expect(darkPixels(in: image) > 0, "no keyline was drawn at all")
}

@Test func aKeylineIsAsHeavyAsTheHollowOneOfTheSameWidth() throws {
    /// CoreText centres a stroke on the outline, so the fill pass covers the
    /// inner half and a keyline drawn at the nominal width comes back half as
    /// heavy as the same number gives in hollow. `strokeWidth` has to mean
    /// the same thickness in both treatments or it is not one setting.
    let outlined = darkPixels(in: try render("O", stroke: .outlined))
    let hollow = darkPixels(in: try render("O", stroke: .hollow))

    /// Hollow strokes the whole outline; outlined keeps the visible outer
    /// half of a doubled stroke. Within a quarter of each other is as close
    /// as two different constructions get.
    #expect(Double(outlined) > Double(hollow) * 0.75, "the keyline came back thin: \(outlined) vs \(hollow)")
    #expect(Double(outlined) < Double(hollow) * 1.5, "the keyline came back heavy: \(outlined) vs \(hollow)")
}

private func render(_ text: String, stroke: TextStyle.StrokeStyle) throws -> CGImage {
    let deck = SlideDeck(canvas: .square, slides: [
        Slide(background: .solid(SlideColor("#FFFFFF")), layers: [
            .text(text: text,
                  style: TextStyle(weight: "black", size: 260,
                                   color: SlideColor("#E5FF4F"), autoShrink: false,
                                   strokeWidth: 4, strokeStyle: stroke,
                                   strokeColor: SlideColor("#000000")),
                  region: .full, verticalAlignment: "middle")
        ])
    ])
    return try SlideRenderer.render(deck: deck, slideIndex: 0)
}

/// The pixels, copied out. The bytes have to be copied rather than pointed
/// at: the context owns them and frees them when it goes, so a pointer
/// returned from here is dangling by the time anybody reads it.
private func pixels(of image: CGImage) -> (bytes: [UInt8], width: Int, height: Int)? {
    guard let context = CGContext(
        data: nil, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let data = context.data else { return nil }

    let count = image.width * image.height * 4
    let raw = data.bindMemory(to: UInt8.self, capacity: count)
    return ([UInt8](UnsafeBufferPointer(start: raw, count: count)), image.width, image.height)
}

private func darkPixels(in image: CGImage) -> Int {
    guard let map = pixels(of: image) else { return -1 }
    var count = 0
    for i in stride(from: 0, to: map.width * map.height * 4, by: 4)
    where Int(map.bytes[i]) + Int(map.bytes[i + 1]) + Int(map.bytes[i + 2]) < 200 {
        count += 1
    }
    return count
}

// MARK: - Helpers

private enum PlateError: Error { case failed }

private func makePlate(width: Int, height: Int, white: Bool = false) throws -> CGImage {
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw PlateError.failed }

    if white {
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    } else {
        /// Something with edges in it, so a blur has work to do.
        for row in 0..<height where row % 4 == 0 {
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: row, width: width, height: 2))
        }
    }

    guard let image = context.makeImage() else { throw PlateError.failed }
    return image
}

private func pixel(of image: CGImage, x: Int, y: Int) throws -> Int {
    guard let context = CGContext(
        data: nil, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw PlateError.failed }

    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let data = context.data else { throw PlateError.failed }

    let bytes = data.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
    return Int(bytes[(y * image.width + x) * 4])
}
