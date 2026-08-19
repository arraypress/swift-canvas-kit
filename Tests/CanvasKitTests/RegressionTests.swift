//
//  RegressionTests.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//
//  Fixes pinned so they cannot quietly come back. Each of these began as a
//  render that looked plausible and was wrong — the exact failure mode this
//  library's audit exists to hunt.
//

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import VideoGrade
@testable import CanvasKit

// MARK: - Beat detection on real (stereo) music

@Test func stereoMusicStillDetectsBeats() throws {
    /// Music is stereo. The detector used to read into a mono buffer, which
    /// `AVAudioFile` refuses against a stereo file (error -50) — so beat
    /// sync failed on every real track and passed every test, because every
    /// test clicked in mono.
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("slidekit-stereo-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let url = directory.appendingPathComponent("clicks.caf")
    let sampleRate = 44_100.0
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2))
    let frames = AVAudioFrameCount(sampleRate * 2)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
    buffer.frameLength = frames
    let channels = try #require(buffer.floatChannelData)
    for channel in 0..<2 {
        for beat in 0..<4 {
            let start = Int(sampleRate * 0.5) * beat
            for index in 0..<800 where start + index < Int(frames) {
                channels[channel][start + index] = sinf(Float(index) * 0.3) * expf(-Float(index) / 200)
            }
        }
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)

    let beats = try BeatDetector.detect(url: url)
    #expect(beats.count >= 3, "a stereo click track must still yield its beats")
    if beats.count >= 2 {
        #expect(abs((beats[1] - beats[0]) - 0.5) < 0.1, "the gaps are the click track's half second")
    }
}

// MARK: - EXIF orientation

@Test func aRotatedPhotoRendersTheWayTheCameraMeant() throws {
    /// A phone portrait is landscape sensor pixels plus an orientation tag.
    /// `CGImageSourceCreateImageAtIndex` ignores the tag, so the photo
    /// arrived on its side — visible on every slide that carries a person.
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("slidekit-exif-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    /// A 200×100 red frame tagged orientation 6 (90° CW): honoured, it
    /// displays 100×200 — taller than wide.
    let context = try #require(CGContext(
        data: nil, width: 200, height: 100,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
    let wide = try #require(context.makeImage())

    let url = directory.appendingPathComponent("portrait.jpg")
    let destination = try #require(CGImageDestinationCreateWithURL(
        url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
    ))
    CGImageDestinationAddImage(destination, wide, [
        kCGImagePropertyOrientation: CGImagePropertyOrientation.right.rawValue
    ] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))

    /// Aspect-FIT into a square canvas: a tall image letterboxes left and
    /// right, a wide one top and bottom. The top-centre pixel tells them
    /// apart.
    let deck = SlideDeck(
        canvas: Canvas(width: 200, height: 200),
        brand: BrandKit(backgroundColor: SlideColor("#0000FF"), showsFooter: false),
        slides: [Slide(layers: [
            .image(path: url.path, region: .full, cornerRadius: 0)
        ])]
    )
    let rendered = try SlideRenderer.render(deck: deck, slideIndex: 0)
    let pixel = try #require(sample(rendered, x: 100, y: 4))
    #expect(pixel.red > 0.5 && pixel.blue < 0.5,
            "the top centre must be the photo (tall), not the letterbox — the tag was ignored")
}

/// One pixel of an image, read through a tiny sRGB context.
private func sample(_ image: CGImage, x: Int, y: Int) -> (red: Double, green: Double, blue: Double)? {
    var data = [UInt8](repeating: 0, count: 4)
    guard let context = CGContext(
        data: &data, width: 1, height: 1,
        bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return (Double(data[0]) / 255, Double(data[1]) / 255, Double(data[2]) / 255)
}

// MARK: - Sticker sizing off the reference canvas

@Test func stickerSizeConvertsThroughTheCanvasAspect() {
    /// The height fraction converts through the canvas's own aspect. The
    /// old formula hardcoded the 4:5 reference height, which sized story
    /// stickers at two-thirds and let landscape ones overrun their region.
    let region = UnitRect(x: 0.2, y: 0.2, width: 0.5, height: 0.1)

    let portrait = SlideRenderer.stickerPointSize(region: region, canvas: .portrait)
    #expect(abs(portrait - 108) < 0.001, "the 4:5 reference answer is unchanged")

    let story = SlideRenderer.stickerPointSize(region: region, canvas: .story)
    #expect(abs(story - 153.6) < 0.001, "a 9:16 region is taller than the 4:5 formula said")

    let landscape = SlideRenderer.stickerPointSize(
        region: region, canvas: Canvas(width: 1080, height: 566)
    )
    #expect(landscape < portrait, "a landscape region is shorter, and the size must follow")
}

// MARK: - Token substitution

@Test func substitutionIsOnePassAndDeterministic() {
    /// The per-key loop walked the dictionary in hash order, so a VALUE
    /// containing `{count}` was filled on some runs and kept on others —
    /// the same deck rendering differently between invocations.
    let tokens = ["a": "{b}", "b": "X", "count": "5"]
    for _ in 0..<64 {
        #expect("{a} {b}".substituting(tokens) == "{b} X",
                "substituted text is never rescanned, whatever the hash order")
    }

    #expect("{missing} stays".substituting(["a": "1"]) == "{missing} stays")
    #expect("{} untouched".substituting(["a": "1"]) == "{} untouched")
    #expect("no tokens".substituting(["a": "1"]) == "no tokens")
    #expect("tail {a".substituting(["a": "1"]) == "tail {a", "an unclosed brace survives verbatim")
}

// MARK: - Short hex

@Test func cssShorthandHexExpands() {
    /// Deck JSON is written by hand, and hands write `#FC6`.
    #expect(SlideColor("#FC6") == SlideColor("#FFCC66"))
    #expect(SlideColor("fff").hex == "#FFFFFF")
    #expect(SlideColor("#FC68").hex == "#FFCC6688")
    #expect(abs(Double(SlideColor("#F00").cgColor.components?[0] ?? 0) - 1) < 0.001)
    /// Not hex at all: left alone, and the render path shows magenta.
    #expect(SlideColor("#XYZ").hex == "#XYZ")
}

// MARK: - Video export honesty

@Test func aFailedExportLeavesNoHalfWrittenFile() async throws {
    /// A partial MP4 opens, plays a few seconds, and passes for the real
    /// thing in any pipeline that only checks the file exists.
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("slidekit-partial-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("broken.mp4")

    struct Boom: Error {}
    let canvas = Canvas.square
    let still = try SlideRenderer.render(deck: SlideDeck(slides: [Slide()]), slideIndex: 0)

    await #expect(throws: Error.self) {
        try await VideoExporter.write(
            width: canvas.width, height: canvas.height,
            duration: 2, framesPerSecond: 10, to: url
        ) { time in
            if time > 0.5 { throw Boom() }
            return still
        }
    }
    #expect(!FileManager.default.fileExists(atPath: url.path),
            "a failed export must clean up what it half wrote")
}

@Test func theReelIsTaggedBT709() async throws {
    /// Untagged H.264 is guessed at by every player — the same reel washed
    /// out in one app and fine in another is the classic missing-tag bug.
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("slidekit-color-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("tagged.mp4")

    let deck = SlideDeck(canvas: .square, slides: [Slide(duration: 0.3)])
    let still = try SlideRenderer.render(deck: deck, slideIndex: 0)
    try await VideoExporter.write(
        width: deck.canvas.width, height: deck.canvas.height,
        duration: 0.3, framesPerSecond: 10, to: url
    ) { _ in still }

    let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
    let descriptions = try await track.load(.formatDescriptions)
    let extensions = descriptions.compactMap {
        CMFormatDescriptionGetExtension($0, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries)
    }
    #expect(
        extensions.contains { ($0 as? String) == (kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String) },
        "the stream must say what its colors mean"
    )
}

@Test func aBrokenGradeIsReportedNotSwallowed() throws {
    /// `try?` around the grade filter meant a broken .cube rendered the
    /// plate ungraded — plausible and wrong, the fleet's anti-pattern.
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("slidekit-grade-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    /// A real plate with an unreadable LUT.
    let plate = try StillExporter.export(
        deck: SlideDeck(background: .solid(SlideColor("#446688")), slides: [Slide()]),
        to: directory
    )[0].path
    var grade = VideoGrade()
    grade.lutURL = directory.appendingPathComponent("missing.cube")

    let deck = SlideDeck(
        background: .image(path: plate, dim: 0, scrim: 0, grade: grade),
        slides: [Slide()]
    )
    let warnings = try SlideRenderer.audit(deck: deck)
    #expect(warnings.contains { warning in
        if case .gradeFailed = warning.kind { return true }
        return false
    }, "the audit must name the grade that never applied")
}

@Test func videoExportRefusesABrokenGrade() async throws {
    /// The still path degrades and reports; minutes of encoding deserve a
    /// refusal up front instead.
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("slidekit-grade-video-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let plate = try StillExporter.export(
        deck: SlideDeck(background: .solid(SlideColor("#446688")), slides: [Slide()]),
        to: directory
    )[0].path
    var grade = VideoGrade()
    grade.lutURL = directory.appendingPathComponent("missing.cube")

    let deck = SlideDeck(
        background: .image(path: plate, dim: 0, scrim: 0, grade: grade),
        slides: [Slide(duration: 0.2)]
    )
    await #expect(throws: VideoExporter.ExportError.self) {
        try await VideoExporter.export(deck: deck, to: directory.appendingPathComponent("out.mp4"))
    }
}

// MARK: - Chips that outgrow their region

@Test func aChipWiderThanItsRegionIsReported() throws {
    /// A chip never shrinks its label; the pill grows instead, and one
    /// wider than its region runs off the canvas with nothing said.
    let deck = SlideDeck(slides: [Slide(layers: [
        .chip(
            text: "An enormous call to action that cannot possibly fit",
            region: UnitRect(x: 0.4, y: 0.4, width: 0.1, height: 0.06),
            size: 40, alignment: "left", color: nil
        )
    ])])
    let warnings = try SlideRenderer.audit(deck: deck)
    #expect(warnings.contains { warning in
        if case .overflow = warning.kind { return true }
        return false
    }, "the audit must flag the chip that outgrew its region")
}

// MARK: - The still export audits in the same pass

@Test func exportAuditingRendersOnceAndReportsTheSameFindings() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("slidekit-auditing-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }

    /// A deck with a deliberate finding: an unfilled token.
    let deck = SlideDeck(slides: [Slide(layers: [
        .text(text: "Hello {nobody}", style: TextStyle(size: 60), region: .full, verticalAlignment: "top")
    ])])

    let (files, warnings) = try StillExporter.exportAuditing(deck: deck, to: directory)
    #expect(files.count == 1)
    #expect(warnings == (try SlideRenderer.audit(deck: deck)),
            "one pass must report exactly what the dedicated audit reports")
}

// MARK: - Repeat groups of one

@Test func aSingleMemberRepeatGroupStillExpandsPerItem() {
    /// `repeatSlideIDs: ["item"]` fell through both expansion branches —
    /// the group gate wanted more than one member and the single-slide
    /// path only knew `repeatSlideID` — so ten items rendered one slide.
    let template = Template(
        name: "one-member-group",
        deck: SlideDeck(slides: [
            Slide(id: "hook", role: "hook", layers: [
                .text(text: "{topic}", style: TextStyle(), region: .full, verticalAlignment: "top")
            ]),
            Slide(id: "item", role: "content", layers: [
                .text(text: "{title}", style: TextStyle(), region: .full, verticalAlignment: "top")
            ])
        ]),
        repeatSlideIDs: ["item"]
    )
    let deck = template.fill(with: TemplateData(
        values: ["topic": "Habits"],
        items: [["title": "One"], ["title": "Two"], ["title": "Three"]]
    ))
    #expect(deck.slides.count == 4, "hook + one slide per item")
    #expect(deck.slides.map(\.id) == ["hook", "item-1", "item-2", "item-3"])
}

// MARK: - Degenerate styles

@Test func zeroPointSizeWithKerningDoesNotPoisonCoreText() throws {
    /// `kerning × pointSize ÷ size` with a declared size of zero fed NaN
    /// into a CoreText attribute. A hand-written style can say anything.
    let deck = SlideDeck(slides: [Slide(layers: [
        .text(
            text: "Tracked",
            style: TextStyle(size: 0, kerning: 4),
            region: .full,
            verticalAlignment: "top"
        )
    ])])
    let image = try SlideRenderer.render(deck: deck, slideIndex: 0)
    #expect(image.width == deck.canvas.width, "the render survives the degenerate style")
}

// MARK: - Page counters are the platform's job

@Test func pageCountersDefaultOffAndOptIn() throws {
    /// Instagram draws its carousel dots and TikTok its progress bar; a
    /// baked "1 / 3" duplicates platform furniture, so the layer is a
    /// placement that draws only when the deck opts in.
    let slides = [Slide(layers: [.pageIndicator]), Slide(layers: [.pageIndicator])]

    var quiet = SlideDeck(brand: BrandKit(showsFooter: false), slides: slides)
    let bare = SlideDeck(brand: BrandKit(showsFooter: false),
                         slides: [Slide(), Slide()])
    let quietRender = try SlideRenderer.render(deck: quiet, slideIndex: 0)
    let bareRender = try SlideRenderer.render(deck: bare, slideIndex: 0)
    #expect(quietRender.dataProvider?.data as Data? == bareRender.dataProvider?.data as Data?,
            "off by default: a counter-only slide renders as an empty one")

    quiet.showsPageIndicator = true
    let counted = try SlideRenderer.render(deck: quiet, slideIndex: 0)
    #expect(counted.dataProvider?.data as Data? != bareRender.dataProvider?.data as Data?,
            "opting in draws the counter")

    /// The decision survives JSON, defaulting off for every existing deck.
    let decoded = try JSONDecoder().decode(SlideDeck.self, from: JSONEncoder().encode(quiet))
    #expect(decoded.showsPageIndicator)
    let legacy = try JSONDecoder().decode(SlideDeck.self, from: Data(#"{"slides":[]}"#.utf8))
    #expect(!legacy.showsPageIndicator)
}
