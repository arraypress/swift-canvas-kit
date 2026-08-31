//
//  ModelBehaviorTests.swift
//  CanvasKitTests
//
//  Created by David Sherlock on 2026.
//
//  The rules that used to live inside the models, pinned directly — hex
//  normalization without a color, entrance math without a deck, the
//  coordinate flip without a renderer.
//

import CoreGraphics
import Testing
@testable import CanvasKit

@Suite("Model behavior extracted")
struct ModelBehaviorTests {

    @Test("Hex normalization pins CSS shorthand and case")
    func hexNormalization() {
        #expect(HexColor.normalize("#fc6") == "#FFCC66")
        #expect(HexColor.normalize("FC68") == "#FFCC6688")
        #expect(HexColor.normalize(" 1b2a4a ") == "#1B2A4A")
        #expect(SlideColor("#FFF") == SlideColor("#FFFFFF"))
        let c = HexColor.components("#FF0000")
        #expect(c != nil && c!.red == 1 && c!.green == 0 && c!.alpha == 1)
        #expect(HexColor.components("#GGGGGG") == nil)
        #expect(SlideColor("#FFCC66").opacity(0.5).hex == "#FFCC6680")
    }

    @Test("Entrance timing pins the stagger math")
    func entranceTiming() {
        #expect(EntranceTiming.settleTime(layerCount: 0, duration: 0.5, stagger: 0.18) == 0)
        let settle = EntranceTiming.settleTime(layerCount: 3, duration: 0.5, stagger: 0.18)
        #expect(abs(settle - 0.86) < 0.0001)
        #expect(EntranceTiming.progress(layerIndex: 0, at: .infinity, duration: 0.5, stagger: 0.18) == 1)
        #expect(EntranceTiming.progress(layerIndex: 1, at: 0, duration: 0.5, stagger: 0.18) == 0)
        #expect(EntranceTiming.progress(layerIndex: 0, at: 10, duration: 0.5, stagger: 0.18) == 1)
    }

    @Test("Unit-to-pixel conversion pins the CoreGraphics flip")
    func unitGeometry() {
        let top = UnitRect(x: 0, y: 0, width: 1, height: 0.5)
        let rect = UnitGeometry.pixels(top, in: .portrait)
        // Top half in design space lands in the UPPER half of CG space.
        #expect(rect.origin.y == CGFloat(Canvas.portrait.height) / 2)
        #expect(rect.height == CGFloat(Canvas.portrait.height) / 2)
        #expect(rect.width == CGFloat(Canvas.portrait.width))
    }
}
