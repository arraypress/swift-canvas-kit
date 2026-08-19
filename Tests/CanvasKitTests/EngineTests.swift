//
//  EngineTests.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//

import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import CanvasKit

// MARK: - Model

@Test func deckRoundTripsThroughJSON() throws {
    let deck = SlideDeck(
        canvas: .story,
        brand: BrandKit(name: "Test", handle: "@test", accentColor: SlideColor("#FF6A88")),
        background: .linearGradient(colors: [SlideColor("#101418"), SlideColor("#1C2B25")], angle: 200),
        slides: [
            Slide(role: "hook", layers: [
                .text(text: "Hello **world**", style: TextStyle(size: 80), region: .full, verticalAlignment: "middle"),
                .pageIndicator
            ])
        ]
    )

    let data = try JSONEncoder().encode(deck)
    let decoded = try JSONDecoder().decode(SlideDeck.self, from: data)
    #expect(decoded == deck)
}

@Test func minimalDeckJSONDecodes() throws {
    /// Tolerant decoding: a deck can be this short and still be valid.
    let json = #"{ "slides": [ { "layers": [ { "type": "text", "text": "Hi" } ] } ] }"#
    let deck = try JSONDecoder().decode(SlideDeck.self, from: Data(json.utf8))
    #expect(deck.slides.count == 1)
    #expect(deck.canvas == .portrait)
}

@Test func unparseableColorRendersMagentaNotCrash() {
    let color = SlideColor("not-a-color")
    #expect(color.cgColor.components?[0] == 1)
    #expect(color.cgColor.components?[1] == 0)
}

// MARK: - Templates

@Test func templateExpandsRepeatingSlidePerItem() {
    let template = Template(
        name: "t",
        deck: SlideDeck(slides: [
            Slide(id: "hook", role: "hook", layers: [
                .text(text: "{count} things", style: TextStyle(), region: .full, verticalAlignment: "top")
            ]),
            Slide(id: "item", role: "content", layers: [
                .text(text: "{n}. {title}", style: TextStyle(), region: .full, verticalAlignment: "top")
            ])
        ]),
        repeatSlideID: "item"
    )

    let deck = template.fill(with: TemplateData(items: [
        ["title": "One"], ["title": "Two"], ["title": "Three"]
    ]))

    #expect(deck.slides.count == 4)

    /// The hook sees `{count}` even though it isn't the repeating slide.
    guard case .text(let hookText, _, _, _) = deck.slides[0].layers[0] else {
        Issue.record("Expected a text layer"); return
    }
    #expect(hookText == "3 things")

    guard case .text(let secondItem, _, _, _) = deck.slides[2].layers[0] else {
        Issue.record("Expected a text layer"); return
    }
    #expect(secondItem == "2. Two")
}

@Test func unknownTokensStayVisible() {
    /// A misspelled token must be seen in output, not silently blanked.
    #expect("Hello {naem}".substituting(["name": "World"]) == "Hello {naem}")
}

// MARK: - Rendering

@Test func rendererProducesCanvasSizedImage() throws {
    let deck = SlideDeck(
        canvas: .portrait,
        slides: [
            Slide(layers: [
                .text(text: "**Accent** and body", style: TextStyle(size: 64), region: .full, verticalAlignment: "middle"),
                .chip(text: "1", region: UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1)),
                .pageIndicator
            ])
        ]
    )

    let image = try SlideRenderer.render(deck: deck, slideIndex: 0)
    #expect(image.width == 1080)
    #expect(image.height == 1350)
}

@Test func renderIsDeterministic() throws {
    /// The parity guarantee in miniature: the same deck renders to the same
    /// pixels, byte for byte.
    let deck = SlideDeck(slides: [
        Slide(layers: [
            .text(text: "Stable output", style: TextStyle(size: 60), region: .full, verticalAlignment: "middle")
        ])
    ])

    let first = try SlideRenderer.render(deck: deck, slideIndex: 0)
    let second = try SlideRenderer.render(deck: deck, slideIndex: 0)
    #expect(first.dataProvider?.data as Data? == second.dataProvider?.data as Data?)
}

@Test func exporterWritesOnePNGPerSlideInOrder() throws {
    let deck = SlideDeck(slides: [
        Slide(role: "hook", layers: [.text(text: "A", style: TextStyle(), region: .full, verticalAlignment: "top")]),
        Slide(role: "content", layers: [.text(text: "B", style: TextStyle(), region: .full, verticalAlignment: "top")]),
        Slide(role: "cta", layers: [.text(text: "C", style: TextStyle(), region: .full, verticalAlignment: "top")])
    ])

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("slidekit-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }

    let files = try StillExporter.export(deck: deck, to: directory)
    #expect(files.count == 3)
    #expect(files[0].lastPathComponent == "01-hook.png")
    #expect(files[2].lastPathComponent == "03-cta.png")
}

@Test func brandingKeepsPaletteChangesIdentity() {
    let template = Template(
        name: "styled",
        deck: SlideDeck(brand: BrandKit(accentColor: SlideColor("#F7C948"), showsFooter: false))
    )
    let branded = template.branded(name: "Me", handle: "@me")
    #expect(branded.deck.brand.name == "Me")
    #expect(branded.deck.brand.showsFooter)
    #expect(branded.deck.brand.accentColor == template.deck.brand.accentColor)
}

// MARK: - Grades

@Test func gradedBackgroundRoundTripsThroughJSON() throws {
    /// The look travels inside the document: a deck with a graded plate
    /// decodes back to the same deck, grade and all.
    let deck = SlideDeck(
        background: .image(path: "bg.jpg", dim: 0.2, scrim: 0.6, grade: .goldenHour),
        slides: [Slide(layers: [.text(text: "Hi", style: TextStyle(), region: .full, verticalAlignment: "top")])]
    )
    let data = try JSONEncoder().encode(deck)
    let decoded = try JSONDecoder().decode(SlideDeck.self, from: data)
    #expect(decoded == deck)
    guard case .image(_, _, _, let grade, _, _, _) = decoded.background else {
        Issue.record("Expected an image background"); return
    }
    #expect(grade == .goldenHour)
}

@Test func ungradedBackgroundJSONStillDecodes() throws {
    /// Decks written before grades existed keep opening — `grade` is
    /// optional in the document like every other new field.
    let json = #"{ "slides": [], "background": { "type": "image", "path": "bg.jpg", "dim": 0.3 } }"#
    let deck = try JSONDecoder().decode(SlideDeck.self, from: Data(json.utf8))
    guard case .image(let path, let dim, _, let grade, _, _, _) = deck.background else {
        Issue.record("Expected an image background"); return
    }
    #expect(path == "bg.jpg")
    #expect(dim == 0.3)
    #expect(grade == nil)
}

@Test func gradedRenderDegradesGracefullyWhenPlateMissing() throws {
    /// A graded background whose file is missing still renders the deck —
    /// fallback fill, washes, text; the grade never turns into a crash.
    let deck = SlideDeck(
        background: .image(path: "/nonexistent.jpg", dim: 0.2, scrim: 0.5, grade: .noir),
        slides: [Slide(layers: [.text(text: "Still here", style: TextStyle(size: 60), region: .full, verticalAlignment: "middle")])]
    )
    let image = try SlideRenderer.render(deck: deck, slideIndex: 0)
    #expect(image.width == 1080)
}

@Test func mediaTokensFillBackgroundsPerItem() {
    /// A repeating slide whose background is `.image(path: "{photo}")`
    /// becomes a travel carousel from data alone — and each filled plate
    /// adopts the template look like any other media.
    var repeating = Slide(id: "stop", role: "content", layers: [
        .text(text: "{title}", style: TextStyle(), region: .full, verticalAlignment: "top")
    ])
    repeating.background = .image(path: "{photo}", dim: 0.2, scrim: 0.6)

    let template = Template(
        name: "photo-essay",
        deck: SlideDeck(slides: [repeating]),
        repeatSlideID: "stop",
        look: .goldenHour
    )

    let deck = template.fill(with: TemplateData(items: [
        ["title": "Wat Arun", "photo": "wat-arun.jpg"],
        ["title": "Street food", "photo": "street-food.jpg"]
    ]))

    #expect(deck.slides.count == 2)
    guard case .image(let path, _, _, let grade, _, _, _) = deck.slides[1].background else {
        Issue.record("Expected an image background"); return
    }
    #expect(path == "street-food.jpg")
    #expect(grade == .goldenHour)
}

@Test func cubeLUTGradeShiftsPlatePixels() throws {
    /// The grade is the whole VideoGrade engine, LUTs included: a .cube
    /// file on a background plate must actually move pixels through the
    /// renderer, not just decode.
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("slidekit-lut-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    /// A plate to grade: render a plain gradient deck and reuse its PNG.
    let plainDeck = SlideDeck(
        background: .linearGradient(colors: [SlideColor("#3A6EA5"), SlideColor("#E8834A")], angle: 160),
        slides: [Slide()]
    )
    let platePath = try StillExporter.export(deck: plainDeck, to: directory)[0].path

    /// A size-2 warming cube: blue crushed, red nudged.
    let cubeURL = directory.appendingPathComponent("warm.cube")
    try """
    LUT_3D_SIZE 2
    0.05 0 0
    1 0.05 0
    0.05 1 0
    1 1 0
    0.05 0 0.6
    1 0.05 0.6
    0.05 1 0.6
    1 1 0.6
    """.write(to: cubeURL, atomically: true, encoding: .utf8)

    var lutGrade = VideoGrade()
    lutGrade.lutURL = cubeURL

    func render(_ grade: VideoGrade?) throws -> Data? {
        let deck = SlideDeck(
            background: .image(path: platePath, dim: 0, scrim: 0, grade: grade),
            slides: [Slide()]
        )
        return try SlideRenderer.render(deck: deck, slideIndex: 0).dataProvider?.data as Data?
    }

    let ungraded = try render(nil)
    let graded = try render(lutGrade)
    #expect(ungraded != nil && graded != nil)
    #expect(ungraded != graded)

    /// Contrast alone must move pixels too — the tone knobs, not just LUTs.
    let contrasty = try render(VideoGrade(contrast: 1.4))
    #expect(contrasty != ungraded)
}

// MARK: - Gradients and vector logos

@Test func gradientCatalogLoadsFromBundledJSON() {
    /// The catalog is a resource, not code — it must actually decode from
    /// the bundle, keep file order, and resolve by name.
    #expect(!Background.curatedGradients.isEmpty)
    #expect(Background.curatedGradients.first?.name == "sunset-glow")
    guard case .linearGradient(let colors, let angle) = Background.gradient(named: "aurora-night") else {
        Issue.record("Expected a gradient"); return
    }
    #expect(colors.count == 4)
    #expect(angle == 200)

    /// Unknown names are visible magenta, never a crash.
    #expect(Background.gradient(named: "does-not-exist") == .solid(SlideColor("#FF00FF")))
}

@Test func pdfLogoRendersHeadlessly() throws {
    /// Vector logos ship as PDF (SVG has no headless CoreGraphics path).
    /// Draw a tiny PDF, use it as an image layer, and expect the marked
    /// pixel region to change against a render without it.
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("slidekit-pdf-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let pdfURL = directory.appendingPathComponent("logo.pdf")
    var box = CGRect(x: 0, y: 0, width: 100, height: 100)
    let pdf = CGContext(pdfURL as CFURL, mediaBox: &box, nil)!
    pdf.beginPDFPage(nil)
    pdf.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    pdf.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
    pdf.endPDFPage()
    pdf.closePDF()

    func render(withLogo: Bool) throws -> Data? {
        let deck = SlideDeck(slides: [Slide(layers: withLogo ? [
            .image(path: pdfURL.path, region: UnitRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2), cornerRadius: 0)
        ] : [])])
        return try SlideRenderer.render(deck: deck, slideIndex: 0).dataProvider?.data as Data?
    }
    #expect(try render(withLogo: true) != render(withLogo: false))
}

// MARK: - Audit and stitch

@Test func auditFlagsWhatToleranceHides() throws {
    /// The renderer saves these decks without complaint — audit is where
    /// the tolerances turn into a report.
    let overstuffed = SlideDeck(slides: [
        Slide(layers: [.text(
            text: String(repeating: "This will never fit. ", count: 40),
            style: TextStyle(size: 90, minimumSize: 80),
            region: UnitRect(x: 0.1, y: 0.1, width: 0.5, height: 0.08),
            verticalAlignment: "top"
        )])
    ])
    let warnings = try SlideRenderer.audit(deck: overstuffed)
    #expect(warnings.contains { if case .shrunkToFloor = $0.kind { return true }; return false })

    let misspelled = SlideDeck(slides: [
        Slide(layers: [.text(text: "Hello {naem}", style: TextStyle(), region: .full, verticalAlignment: "top")])
    ])
    let tokenWarnings = try SlideRenderer.audit(deck: misspelled)
    #expect(tokenWarnings.contains { $0.kind == .unfilledToken(token: "{naem}") })

    let clean = SlideDeck(slides: [
        Slide(layers: [.text(text: "Fits fine", style: TextStyle(size: 40), region: .full, verticalAlignment: "top")])
    ])
    #expect(try SlideRenderer.audit(deck: clean).isEmpty)
}

@Test func deckStitchesIntoOneVideo() async throws {
    /// Two one-second slides become one two-second MP4 — the reel export.
    let deck = SlideDeck(
        canvas: Canvas(width: 270, height: 480),
        slides: [
            Slide(role: "hook", layers: [.text(text: "One", style: TextStyle(size: 60), region: .full, verticalAlignment: "middle")], duration: 1),
            Slide(role: "content", layers: [.text(text: "Two", style: TextStyle(size: 60), region: .full, verticalAlignment: "middle")], duration: 1)
        ]
    )
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("slidekit-stitch-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: url) }

    try await VideoExporter.export(deck: deck, to: url, transition: .crossfade, framesPerSecond: 12)

    let asset = AVURLAsset(url: url)
    let duration = try await asset.load(.duration).seconds
    #expect(abs(duration - 2.0) < 0.2)
    #expect(try await !asset.loadTracks(withMediaType: .video).isEmpty)
}

@Test func parameterizedTransitionsAndMotionExport() async throws {
    /// The full vocabulary compiles into real frames: iris transition at a
    /// custom duration, alternating Ken Burns — and the clock still adds up.
    let deck = SlideDeck(
        canvas: Canvas(width: 270, height: 480),
        slides: [
            Slide(role: "hook", layers: [.text(text: "A", style: TextStyle(size: 60), region: .full, verticalAlignment: "middle")], duration: 1),
            Slide(role: "content", layers: [.text(text: "B", style: TextStyle(size: 60), region: .full, verticalAlignment: "middle")], duration: 1),
            Slide(role: "cta", layers: [.text(text: "C", style: TextStyle(size: 60), region: .full, verticalAlignment: "middle")], duration: 1)
        ]
    )
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("slidekit-params-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: url) }

    try await VideoExporter.export(
        deck: deck, to: url,
        transition: .iris, transitionDuration: 0.3,
        motion: .kenBurnsAlternating(intensity: 0.1),
        framesPerSecond: 12
    )
    let duration = try await AVURLAsset(url: url).load(.duration).seconds
    #expect(abs(duration - 3.0) < 0.2)
}

// MARK: - Entrances, beats, SFX

@Test func entranceAnimatesTowardTheSettledFrame() throws {
    /// An entrance is a pure function of time: mid-entrance differs from
    /// settled, and settled is pixel-identical to having no entrance at
    /// all — the still export contract.
    var deck = SlideDeck(slides: [
        Slide(layers: [
            .text(text: "Title", style: TextStyle(size: 80), region: UnitRect(x: 0.1, y: 0.3, width: 0.8, height: 0.2), verticalAlignment: "top"),
            .text(text: "Body line", style: TextStyle(size: 40), region: UnitRect(x: 0.1, y: 0.55, width: 0.8, height: 0.2), verticalAlignment: "top")
        ])
    ])
    let settledPlain = try SlideRenderer.render(deck: deck, slideIndex: 0).dataProvider?.data as Data?

    deck.entrance = SlideEntrance(style: .fadeUp)
    let mid = try SlideRenderer.render(deck: deck, slideIndex: 0, at: 0.2).dataProvider?.data as Data?
    let settled = try SlideRenderer.render(deck: deck, slideIndex: 0).dataProvider?.data as Data?

    #expect(mid != settled)
    #expect(settled == settledPlain)
}

@Test func beatSyncSnapsCutsToAClickTrack() throws {
    /// Synthesize a 2 Hz click track, then expect slide cuts on the grid.
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("slidekit-beats-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let clickURL = directory.appendingPathComponent("clicks.caf")
    let sampleRate = 44_100.0
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let seconds = 12.0
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleRate * seconds))!
    buffer.frameLength = buffer.frameCapacity
    let channel = buffer.floatChannelData![0]
    for beat in stride(from: 0.5, to: seconds, by: 0.5) {
        let start = Int(beat * sampleRate)
        for offset in 0..<800 where start + offset < Int(buffer.frameLength) {
            channel[start + offset] += Float(sin(Double(offset) * 0.35) * exp(-Double(offset) / 180)) * 0.9
        }
    }
    let file = try AVAudioFile(forWriting: clickURL, settings: format.settings)
    try file.write(from: buffer)

    var deck = SlideDeck(slides: [
        Slide(duration: 1.7), Slide(duration: 2.2), Slide(duration: 1.4)
    ])
    deck.musicPath = clickURL.path

    let aligned = try BeatSync.aligned(deck)
    var cursor = 0.0
    for slide in aligned.slides {
        cursor += slide.duration
        let offGrid = abs(cursor / 0.5 - (cursor / 0.5).rounded())
        #expect(offGrid < 0.12, "cut at \(cursor) missed the 0.5s grid")
    }
}

@Test func sfxSynthesizesDeterministically() throws {
    /// The whoosh renders once, caches, and is byte-stable.
    let first = try SFXSynth.url(for: .whoosh)
    let second = try SFXSynth.url(for: .whoosh)
    #expect(first == second)
    #expect(FileManager.default.fileExists(atPath: first.path))
    let duration = try AVAudioFile(forReading: first).length
    #expect(duration > 0)
}

@Test func repeatGroupExpandsPairsPerItem() {
    /// The question→reveal shape: two slides per item, in order, both
    /// filled — built inline, because the group machinery is the engine's.
    let template = Template(
        name: "pairs",
        deck: SlideDeck(slides: [
            Slide(id: "hook", role: "hook", layers: [
                .text(text: "{hook}", style: TextStyle(), region: .full, verticalAlignment: "top")
            ]),
            Slide(id: "question", role: "content", layers: [
                .text(text: "{question}", style: TextStyle(), region: .full, verticalAlignment: "top")
            ]),
            Slide(id: "answer", role: "content", layers: [
                .text(text: "{answer} {detail}", style: TextStyle(), region: .full, verticalAlignment: "top")
            ]),
            Slide(id: "cta", role: "cta", layers: [
                .text(text: "{cta}", style: TextStyle(), region: .full, verticalAlignment: "top")
            ])
        ]),
        repeatSlideIDs: ["question", "answer"]
    )
    let deck = template.fill(with: TemplateData(
        values: ["topic": "T", "hook": "H", "cta": "C", "ctaButton": "B"],
        items: [
            ["question": "Q1", "answer": "A1", "detail": "D1"],
            ["question": "Q2", "answer": "A2", "detail": "D2"]
        ]
    ))
    /// hook + (question + answer) × 2 + cta
    #expect(deck.slides.count == 6)
    guard case .text(_, _, _, _) = deck.slides[1].layers.first ?? .pageIndicator else { return }
    let allText = deck.slides.flatMap(\.layers).compactMap { layer -> String? in
        if case .text(let text, _, _, _) = layer { return text }
        return nil
    }.joined(separator: " ")
    #expect(allText.contains("Q2"))
    #expect(allText.contains("A2"))
    /// Q2's question slide comes before A2's answer slide.
    #expect(deck.slides[3].id.hasPrefix("question"))
    #expect(deck.slides[4].id.hasPrefix("answer"))
}

@Test func fillModeImagesCropInsteadOfFloat() throws {
    /// fill crops the image through the region clip; fit centers it. The
    /// two must produce different pixels for a mismatched aspect, and
    /// fill must round-trip through JSON.
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("slidekit-fill-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let plate = SlideDeck(
        background: .linearGradient(colors: [SlideColor("#FF0000"), SlideColor("#0000FF")], angle: 90),
        slides: [Slide()]
    )
    let photoPath = try StillExporter.export(deck: plate, to: directory)[0].path

    func render(_ scaling: String) throws -> Data? {
        let deck = SlideDeck(slides: [Slide(layers: [
            .image(path: photoPath, region: UnitRect(x: 0.3, y: 0.1, width: 0.4, height: 0.8), cornerRadius: 24, scaling: scaling)
        ])])
        return try SlideRenderer.render(deck: deck, slideIndex: 0).dataProvider?.data as Data?
    }
    #expect(try render("fill") != render("fit"))

    let layer = SlideLayer.image(path: "p.jpg", region: .full, cornerRadius: 8, scaling: "fill")
    let decoded = try JSONDecoder().decode(SlideLayer.self, from: JSONEncoder().encode(layer))
    #expect(decoded == layer)
}

