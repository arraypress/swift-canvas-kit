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
