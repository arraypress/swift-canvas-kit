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
