//
//  TypographyTests.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import CoreText
import XCTest

@testable import CanvasKit

final class TypographyTests: XCTestCase {

    /// A white-on-black bitmap of `draw`, as bytes, for comparing two drawings.
    private func pixels(width: Int = 900, height: Int = 260, _ draw: (CGContext) -> Void) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            draw(context)
        }
        return bytes
    }

    private func meanDifference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        Double(zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / Double(a.count)
    }

    private let region = CGRect(x: 10, y: 10, width: 880, height: 240)

    func testAWeightAxisChangesTheWidth() throws {
        // SF Pro is variable on every Mac: wght 1…1000.
        var light = TextStyle(fontFamily: "SF Pro", weight: "regular", size: 60, autoShrink: false)
        light.variations = ["wght": 200]
        var heavy = light
        heavy.variations = ["wght": 900]
        let thin = try XCTUnwrap(TextDrawer.line(text: "Variable", style: light, pointSize: 60))
        let thick = try XCTUnwrap(TextDrawer.line(text: "Variable", style: heavy, pointSize: 60))
        XCTAssertGreaterThan(thick.lines[0].width, thin.lines[0].width * 1.08)
        XCTAssertEqual(FontTags.number("wght"), 0x7767_6874)
        XCTAssertEqual(FontTags.text(0x7767_6874), "wght")
        XCTAssertNil(FontTags.number("weight"))
    }

    func testSmallCapsAndLigaturesChangeTheGlyphs() throws {
        let plain = TextStyle(fontFamily: "Avenir Next", weight: "regular", size: 60, autoShrink: false)
        var caps = plain
        caps.features = ["smcp": 1]
        let a = try XCTUnwrap(TextDrawer.line(text: "acorn", style: plain, pointSize: 60))
        let b = try XCTUnwrap(TextDrawer.line(text: "acorn", style: caps, pointSize: 60))
        // Small capitals stand taller than the x-height they replace.
        XCTAssertGreaterThan(b.path.boundingBoxOfPath.height, a.path.boundingBoxOfPath.height * 1.1)
        var noLigatures = plain
        noLigatures.features = ["liga": 0]
        let joined = try XCTUnwrap(TextDrawer.line(text: "office", style: plain, pointSize: 60))
        let apart = try XCTUnwrap(TextDrawer.line(text: "office", style: noLigatures, pointSize: 60))
        XCTAssertLessThan(joined.glyphs.count, apart.glyphs.count)
        XCTAssertEqual(apart.glyphs.count, 6)
    }

    func testCharacterStylesColourSizeAndLift() throws {
        var style = TextStyle(fontFamily: "Helvetica", weight: "bold", size: 60, color: SlideColor("#FFFFFF"), autoShrink: false)
        style.characterStyles = [CharacterStyle(start: 0, length: 1, color: SlideColor("#FF0000"), scale: 1.5),
                                 CharacterStyle(start: 5, length: 3, baseline: 0.3)]
        let outlines = try XCTUnwrap(TextDrawer.outlines(text: "Night Owl", style: style, in: region, verticalAlignment: "middle", scale: 1))
        let first = try XCTUnwrap(outlines.glyphs.first)
        XCTAssertEqual(first.character, 0)
        XCTAssertEqual(first.color.components?.prefix(3).map { ($0 * 255).rounded() }, [255, 0, 0])
        XCTAssertEqual(outlines.glyphs[1].color.components?.prefix(3).map { ($0 * 255).rounded() }, [255, 255, 255])
        // The large N is about half again as tall as the i after it would be at its cap height.
        let n = first.path.boundingBoxOfPath.height, g = outlines.glyphs[3].path.boundingBoxOfPath.height
        XCTAssertGreaterThan(n, g)
        // "Owl" (characters 6…8) sits 0.3 × 60 = 18 px above the rest.
        let o = try XCTUnwrap(outlines.glyphs.first { $0.character == 6 })
        XCTAssertEqual(o.origin.y - first.origin.y, 18, accuracy: 0.5)
    }

    func testOutlinesLandWhereTheWordsAreDrawn() throws {
        var style = TextStyle(fontFamily: "Helvetica", weight: "bold", size: 80, color: SlideColor("#FFFFFF"),
                              autoShrink: true, minimumSize: 20)
        style.characterStyles = [CharacterStyle(start: 2, length: 3, scale: 1.3, baseline: 0.2)]
        let drawn = pixels { context in
            // Font smoothing thickens CoreText's own glyphs a little; filled outlines get none.
            context.setAllowsFontSmoothing(false)
            TextDrawer.draw(text: "Late **Bloom** in May", style: style, in: region, verticalAlignment: "middle", context: context, scale: 1)
        }
        let outlines = try XCTUnwrap(TextDrawer.outlines(text: "Late **Bloom** in May", style: style, in: region,
                                                         verticalAlignment: "middle", scale: 1))
        let shapes = pixels { context in
            for glyph in outlines.glyphs {
                context.addPath(glyph.placed)
                context.setFillColor(glyph.color)
                context.fillPath()
            }
        }
        XCTAssertEqual(outlines.text, "Late Bloom in May")
        let ink = Double(drawn.reduce(0) { $0 + Int($1) }) / Double(drawn.count)
        // Antialiasing aside, the same pixels: under 2% of the ink.
        XCTAssertLessThan(meanDifference(drawn, shapes), ink * 0.02)
        XCTAssertEqual(outlines.lines.map(\.text).joined(), "Late Bloom in May")
    }

    func testInksConvertIntoTheSpaceAsked() {
        let cmyk = CGColorSpace(name: CGColorSpace.genericCMYK)!
        let red = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        XCTAssertEqual(Inks.converted(red).colorSpace?.model, .rgb)
        Inks.$space.withValue(cmyk) {
            let converted = Inks.converted(red)
            XCTAssertEqual(converted.colorSpace?.model, .cmyk)
            XCTAssertEqual(converted.numberOfComponents, 5)
        }
    }

    func testCharacterOffsetsCountGraphemes() {
        let offsets = CharacterOffsets("Ä👍🏽b")
        XCTAssertEqual(offsets.count, 3)
        XCTAssertEqual(offsets.utf16Range(start: 1, length: 1)?.length, 4)
        XCTAssertEqual(offsets.character(atUTF16: 3), 1)
        XCTAssertNil(offsets.utf16Range(start: 3, length: 2))
    }
}
