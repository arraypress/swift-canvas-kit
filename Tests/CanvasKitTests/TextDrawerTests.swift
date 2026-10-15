//
//  TextDrawerTests.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//

import XCTest

@testable import CanvasKit

// MARK: - The muted tier

final class MutedTierTests: XCTestCase {

    func testAMutedSpanIsItsOwnRun() {
        let runs = TextDrawer.parseAccents(in: "~Native~ and **Fast**")
        XCTAssertEqual(runs.count, 3)
        XCTAssertEqual(runs[0].text, "Native")
        XCTAssertTrue(runs[0].muted)
        XCTAssertFalse(runs[0].accented)
        XCTAssertEqual(runs[1].text, " and ")
        XCTAssertFalse(runs[1].muted)
        XCTAssertEqual(runs[2].text, "Fast")
        XCTAssertTrue(runs[2].accented)
    }

    func testItalicSurvivesInsideAMutedSpan() {
        // Muted is parsed first so `~a *b* c~` keeps the whole span quiet
        // rather than the italic escaping the tier.
        let runs = TextDrawer.parseAccents(in: "~made *clear*~")
        XCTAssertTrue(runs.allSatisfy(\.muted))
        XCTAssertTrue(runs.contains { $0.italic && $0.text == "clear" })
    }

    func testAnUnclosedTildeIsLeftAlone() {
        // Half a marker is a typo, not an instruction.
        let runs = TextDrawer.parseAccents(in: "5 ~ 6")
        XCTAssertEqual(runs.map(\.text).joined(), "5 ~ 6")
        XCTAssertFalse(runs.contains { $0.muted })
    }

    func testTheOtherMarkersStillWork() {
        let runs = TextDrawer.parseAccents(in: "**Amazing** *catchy* #Hooked")
        XCTAssertTrue(runs.contains { $0.text == "Amazing" && $0.accented })
        XCTAssertTrue(runs.contains { $0.text == "catchy" && $0.italic })
        XCTAssertTrue(runs.contains { $0.text == "#Hooked" && $0.accented })
        XCTAssertFalse(runs.contains { $0.muted })
    }

    func testPlainTextIsOneRun() {
        XCTAssertEqual(TextDrawer.parseAccents(in: "Your money").map(\.text), ["Your money"])
    }
}

final class FontAvailabilityTests: XCTestCase {

    func testAKnownFamilyIsFound() {
        XCTAssertTrue(FontResolver.isAvailable("Helvetica"))
    }

    func testAnUnknownFamilyIsRefused() {
        // The reason this exists: CoreText SUBSTITUTES a default face rather
        // than failing, so a typo would render a whole set in the wrong
        // typeface and look deliberate.
        XCTAssertFalse(FontResolver.isAvailable("Notafont Sans Fictional"))
    }
}

final class GradientCatalogTests: XCTestCase {

    func testTheCatalogParses() {
        // This is the test that matters: the catalog is JSON in Resources, and
        // a malformed file makes EVERY curated gradient silently become
        // magenta rather than failing loudly. A `//` comment nearly shipped in
        // there, which would have taken the whole list with it.
        XCTAssertGreaterThanOrEqual(Background.curatedGradients.count, 12)
    }

    func testEveryNameResolvesToAGradient() {
        for entry in Background.curatedGradients {
            guard case .linearGradient = Background.gradient(named: entry.name) else {
                return XCTFail("\(entry.name) fell back to the magenta placeholder")
            }
        }
    }

    func testEveryGradientIsTonalRatherThanARainbow() {
        // What dated the old catalog was hue TRAVEL: sunset-glow ran purple
        // to magenta to salmon, about 115 degrees across the wheel in three
        // stops. A ground is a ground; it should not be a journey. Two stops,
        // one hue family, is the whole rule.
        for entry in Background.curatedGradients {
            guard case .linearGradient(let colors, _) = entry.background else { continue }
            XCTAssertLessThanOrEqual(colors.count, 2, "\(entry.name) has \(colors.count) stops")

            let hues = colors.compactMap { hue(of: $0) }
            guard hues.count == 2 else { continue }
            var travel = abs(hues[0] - hues[1])
            if travel > 180 { travel = 360 - travel }   // the wheel wraps
            XCTAssertLessThanOrEqual(travel, 45, "\(entry.name) travels \(Int(travel))° of hue")
        }
    }

    /// Hue in degrees, or nil for something too grey to have one.
    ///
    /// The chroma floor is 0.08, not a hairline. Written at 0.02 this test
    /// failed the pale washes for "travelling 115°" — true of the numbers and
    /// meaningless of the picture, since at 4% chroma the two stops are both
    /// off-white and no eye reads a hue rotation between them. A rule about
    /// how something LOOKS has to stop measuring where looking stops.
    private func hue(of color: SlideColor) -> Double? {
        let parts = (color.cgColor.components ?? []).prefix(3).map(Double.init)
        guard parts.count == 3 else { return nil }
        let high = parts.max() ?? 0, low = parts.min() ?? 0
        let delta = high - low
        guard delta > 0.08 else { return nil }
        let (r, g, b) = (parts[0], parts[1], parts[2])
        let raw: Double
        if high == r { raw = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6)) }
        else if high == g { raw = 60 * ((b - r) / delta + 2) }
        else { raw = 60 * ((r - g) / delta + 4) }
        return raw < 0 ? raw + 360 : raw
    }

    func testThePaleTierIsPresentAndActuallyPale() {
        // The point of these three is that a device and BLACK type can sit on
        // them. A "pale" ground that is merely a lighter poster fails that.
        for name in ["blush-wash", "lilac-wash", "mist-wash"] {
            guard case .linearGradient(let colors, _) = Background.gradient(named: name) else {
                return XCTFail("\(name) is missing")
            }
            for color in colors {
                let parts = (color.cgColor.components ?? []).prefix(3)
                XCTAssertGreaterThan(parts.min() ?? 0, 0.88,
                                     "\(name) has a stop dark enough to fight black type")
            }
        }
    }

    func testAnUnknownNameIsVisiblyWrongNotSilentlyWrong() {
        // Magenta on purpose: a gradient you can see is wrong beats one that
        // quietly becomes something else.
        guard case .solid = Background.gradient(named: "no-such-gradient") else {
            return XCTFail("an unknown name should fall back to the placeholder")
        }
    }
}

final class TemplateDataDecodingTests: XCTestCase {

    private func decode(_ json: String) throws -> TemplateData {
        try JSONDecoder().decode(TemplateData.self, from: Data(json.utf8))
    }

    func testItemsAloneIsEnough() throws {
        // The commonest shape by far: most templates take a list and no
        // deck-wide tokens. The synthesised decoder required both keys and
        // rejected this with a message describing what the author had written.
        let data = try decode(#"{"items":[{"headline":"One"},{"headline":"Two"}]}"#)
        XCTAssertEqual(data.items.count, 2)
        XCTAssertTrue(data.values.isEmpty)
    }

    func testValuesAloneIsEnough() throws {
        let data = try decode(#"{"values":{"topic":"Focus"}}"#)
        XCTAssertEqual(data.values["topic"], "Focus")
        XCTAssertTrue(data.items.isEmpty)
    }

    func testBothStillWork() throws {
        let data = try decode(#"{"values":{"topic":"Focus"},"items":[{"headline":"One"}]}"#)
        XCTAssertEqual(data.values["topic"], "Focus")
        XCTAssertEqual(data.items.count, 1)
    }

    func testAnEmptyObjectIsEmptyRatherThanAnError() throws {
        let data = try decode("{}")
        XCTAssertTrue(data.values.isEmpty)
        XCTAssertTrue(data.items.isEmpty)
    }
}

// MARK: - The public layout (0.4.0)

final class TextLayoutTests: XCTestCase {

    private let region = CGRect(x: 0, y: 0, width: 600, height: 400)

    func testLayoutReportsSizeLinesAndFit() throws {
        let style = TextStyle(size: 40, autoShrink: false)
        let fit = try XCTUnwrap(TextDrawer.layout(text: "One two three", style: style, in: region,
                                                  verticalAlignment: "top", scale: 1))
        XCTAssertEqual(fit.pointSize, 40)
        XCTAssertTrue(fit.fits)
        XCTAssertEqual(fit.lineCount, 1)
        XCTAssertEqual(fit.lineRects.count, 1)
        let line = try XCTUnwrap(fit.linesBounds)
        XCTAssertTrue(region.insetBy(dx: 0, dy: -2).contains(line), "\(line)")
        // The frame carries 2 px of slack above the text, as it always has.
        XCTAssertEqual(fit.frame.maxY - 2, region.maxY, accuracy: 0.001, "top alignment hangs from the top")
    }

    func testMaxLinesShrinksUntilTheTextWrapsToThatMany() throws {
        let text = "A long title that wraps across several lines at this size"
        let free = try XCTUnwrap(TextDrawer.layout(text: text, style: TextStyle(size: 90, minimumSize: 10),
                                                   in: region, verticalAlignment: "top", scale: 1))
        XCTAssertGreaterThan(free.lineCount, 2)
        let limited = try XCTUnwrap(TextDrawer.layout(text: text, style: TextStyle(size: 90, minimumSize: 10, maxLines: 2),
                                                      in: region, verticalAlignment: "top", scale: 1))
        XCTAssertLessThanOrEqual(limited.lineCount, 2)
        XCTAssertTrue(limited.fits)
        XCTAssertLessThan(limited.pointSize, free.pointSize)
    }

    func testAFloorThatCannotFitIsReported() throws {
        let fit = try XCTUnwrap(TextDrawer.layout(text: "Words words words words", style: TextStyle(size: 200, minimumSize: 150, maxLines: 1),
                                                  in: region, verticalAlignment: "middle", scale: 1))
        XCTAssertFalse(fit.fits)
        XCTAssertEqual(fit.pointSize, 150, accuracy: 0.001)
    }

    func testDrawReturnsTheSameFitAsLayout() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let style = TextStyle(size: 60, maxLines: 2)
        let drawn = TextDrawer.draw(text: "Night Drive", style: style, in: region, verticalAlignment: "bottom",
                                    context: context, scale: 1)
        let laid = TextDrawer.layout(text: "Night Drive", style: style, in: region, verticalAlignment: "bottom", scale: 1)
        XCTAssertEqual(drawn, laid)
        XCTAssertNil(TextDrawer.layout(text: "", style: style, in: region, verticalAlignment: "top", scale: 1))
    }

    func testMaxLinesRoundTripsAndDefaultsToNoLimit() throws {
        XCTAssertNil(try JSONDecoder().decode(TextStyle.self, from: Data("{}".utf8)).maxLines)
        let style = try JSONDecoder().decode(TextStyle.self, from: Data(#"{"maxLines": 2}"#.utf8))
        XCTAssertEqual(style.maxLines, 2)
        XCTAssertEqual(try JSONDecoder().decode(TextStyle.self, from: JSONEncoder().encode(style)), style)
    }
}
