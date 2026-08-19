//
//  SlideRenderer.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO
import VideoGrade

/// The renderer.
///
/// **There is exactly one function that draws a slide** —
/// `SlideRenderer.render(deck:slideIndex:)` — and every output format calls
/// it: still export, contact sheets, the future video exporter (which draws
/// the same layers over decoded video frames). It is a pure, deterministic
/// function of the deck. Never add a second rendering path.
public enum SlideRenderer {

    public enum RenderError: Error, CustomStringConvertible {
        case contextCreationFailed
        case slideIndexOutOfRange(Int)
        case unreadableImage(String)

        public var description: String {
            switch self {
            case .contextCreationFailed:
                return "Could not create a drawing context."
            case .slideIndexOutOfRange(let index):
                return "Slide index \(index) is out of range."
            case .unreadableImage(let path):
                return "Could not read image at '\(path)'."
            }
        }
    }

    /// Render one slide of a deck to a bitmap.
    ///
    /// `backgroundFrame` is the video exporter's hook: a decoded frame of the
    /// slide's video background, drawn where the background would be — the
    /// same wash, card, layers and chrome draw on top. Still exports pass
    /// nothing. One function, every output format.
    public static func render(deck: SlideDeck, slideIndex: Int, backgroundFrame: CGImage? = nil, at time: Double = .infinity, layerFrames: [Int: CGImage] = [:]) throws -> CGImage {
        try render(deck: deck, slideIndex: slideIndex, backgroundFrame: backgroundFrame, at: time, layerFrames: layerFrames, collector: nil)
    }

    /// Render every slide and report what a human should look at — content
    /// that hit the shrink floor, clipped text, tokens that survived into
    /// pixels. An empty array is the "provably postable" signal batch
    /// pipelines gate on.
    public static func audit(deck: SlideDeck) throws -> [RenderWarning] {
        let collector = WarningCollector()
        for index in deck.slides.indices {
            collector.slideIndex = index
            _ = try render(deck: deck, slideIndex: index, collector: collector)
        }
        return collector.warnings
    }

    static func render(deck: SlideDeck, slideIndex: Int, backgroundFrame: CGImage? = nil, at time: Double = .infinity, layerFrames: [Int: CGImage] = [:], collector: WarningCollector?) throws -> CGImage {
        guard deck.slides.indices.contains(slideIndex) else {
            throw RenderError.slideIndexOutOfRange(slideIndex)
        }

        let canvas = deck.canvas
        let slide = deck.slides[slideIndex]

        guard let context = CGContext(
            data: nil,
            width: canvas.width,
            height: canvas.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw RenderError.contextCreationFailed
        }

        drawBackground(
            deck.resolvedBackground(for: slide),
            in: context, canvas: canvas,
            override: backgroundFrame,
            collector: collector,
            textRegions: textRegions(of: slide, in: canvas)
        )

        try drawContent(deck: deck, slide: slide, slideIndex: slideIndex, in: context, at: time, layerFrames: layerFrames, collector: collector)

        if let collector {
            reportChromeCollisions(of: slide, deck: deck, to: collector)
        }

        guard let image = context.makeImage() else {
            throw RenderError.contextCreationFailed
        }
        return image
    }

    /// Words and CTAs that land where the platform draws its own UI.
    ///
    /// Judged against the canvas preset's chrome zones (see ``ChromeZones``)
    /// at a 20% overlap threshold — a corner grazing the rail is layout, a
    /// fifth of a button under it is a button somebody cannot press.
    static func reportChromeCollisions(of slide: Slide, deck: SlideDeck, to collector: WarningCollector) {
        let zones = ChromeZones.zones(for: deck.canvas)
        guard !zones.isEmpty else { return }
        let canvas = deck.canvas

        for layer in slide.layers {
            let content: (text: String, rect: CGRect)?
            switch layer {
            case .text(let text, _, let region, _):
                content = text.isEmpty ? nil : (text, region.pixels(in: canvas))
            case .chip(let text, let region, _, _, _):
                content = (text, region.pixels(in: canvas))
            case .list(let items, _, let region, _, _):
                content = ((items.first?.title ?? items.first?.body) ?? "list",
                           region.pixels(in: canvas))
            case .image, .video, .rect, .dots, .pattern, .sticker, .pageIndicator:
                content = nil
            }
            guard let (text, rect) = content, rect.width > 0, rect.height > 0 else { continue }

            for zone in zones {
                let overlap = rect.intersection(zone.region.pixels(in: canvas))
                guard !overlap.isNull else { continue }
                let fraction = (overlap.width * overlap.height) / (rect.width * rect.height)
                if fraction > 0.2 {
                    collector.report(.chromeCollision(text: text, zone: zone.name))
                    break
                }
            }
        }
    }

    /// The slide's content — card, layers, chrome — on a transparent canvas.
    ///
    /// The video exporter draws this once per slide and composites it over
    /// each decoded background frame: text layout is by far the expensive
    /// part of a render, and it doesn't change while the background moves.
    /// Layout is identical to the still export because it *is* the same code.
    public static func renderOverlay(deck: SlideDeck, slideIndex: Int, at time: Double = .infinity) throws -> CGImage {
        guard deck.slides.indices.contains(slideIndex) else {
            throw RenderError.slideIndexOutOfRange(slideIndex)
        }
        let canvas = deck.canvas
        let slide = deck.slides[slideIndex]

        guard let context = CGContext(
            data: nil,
            width: canvas.width,
            height: canvas.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw RenderError.contextCreationFailed
        }

        try drawContent(deck: deck, slide: slide, slideIndex: slideIndex, in: context, at: time, collector: nil)

        guard let image = context.makeImage() else {
            throw RenderError.contextCreationFailed
        }
        return image
    }

    /// Layers that enter; decoration and chrome stay planted.
    static func isAnimatable(_ layer: SlideLayer) -> Bool {
        switch layer {
        case .text, .chip, .sticker, .image, .video, .list: return true
        case .rect, .dots, .pattern, .pageIndicator: return false
        }
    }

    /// The region an entrance transform pivots around.
    private static func layerRegion(_ layer: SlideLayer) -> UnitRect? {
        switch layer {
        case .text(_, _, let region, _): return region
        case .chip(_, let region, _, _, _): return region
        case .sticker(_, let region, _): return region
        case .image(_, let region, _, _, _, _): return region
        case .video(_, let region, _, _, _): return region
        case .list(_, _, let region, _, _): return region
        case .rect, .dots, .pattern, .pageIndicator: return nil
        }
    }

    /// Everything above the background, in drawing order.
    private static func drawContent(
        deck: SlideDeck,
        slide: Slide,
        slideIndex: Int,
        in context: CGContext,
        at time: Double = .infinity,
        layerFrames: [Int: CGImage] = [:],
        collector: WarningCollector?
    ) throws {
        let canvas = deck.canvas

        if let card = slide.card {
            drawCard(card, in: context, canvas: canvas)
        }

        /// Where footer and page indicator may sit. On a bare slide that's the
        /// safe area; on a card slide it's inside the card's own padding —
        /// chrome flush against a rounded corner reads as a rendering mistake.
        let chrome = chromeRect(canvas: canvas, card: slide.card)

        let entrance = slide.entrance ?? deck.entrance
        var animatedIndex = 0
        for (layerIndex, layer) in slide.layers.enumerated() {
            /// Entrances: each content layer arrives on its own clock,
            /// eased, translated/scaled/faded around its region. At
            /// `t = ∞` every transform is the identity — the still export
            /// path unchanged.
            if let entrance, isAnimatable(layer) {
                let progress = entrance.progress(layerIndex: animatedIndex, at: time)
                animatedIndex += 1
                if progress <= 0 { continue }
                if progress < 1 {
                    context.saveGState()
                    apply(entrance.style, progress: progress, to: layer, in: context, canvas: canvas)
                    try drawLayer(
                        layer, in: context,
                        deck: deck, slide: slide, slideIndex: slideIndex,
                        chrome: chrome, videoFrame: layerFrames[layerIndex], collector: collector
                    )
                    context.restoreGState()
                    continue
                }
            }
            try drawLayer(
                layer, in: context,
                deck: deck, slide: slide, slideIndex: slideIndex,
                chrome: chrome, videoFrame: layerFrames[layerIndex], collector: collector
            )
        }

        if deck.brand.showsFooter {
            try drawFooter(deck.brand, in: context, canvas: canvas, chrome: chrome, chromeColor: slide.chromeColor)
        }
    }

    /// One entrance frame's transform: alpha plus a small travel, scaled
    /// to the canvas so the motion reads identically at every size.
    private static func apply(
        _ style: SlideEntrance.Style,
        progress: Double,
        to layer: SlideLayer,
        in context: CGContext,
        canvas: Canvas
    ) {
        context.setAlpha(CGFloat(min(1, progress * 1.6)))
        let remaining = CGFloat(1 - progress)
        switch style {
        case .fadeUp:
            /// Visual rise: starts below its resting place.
            context.translateBy(x: 0, y: -36 * canvas.scale * remaining)
        case .slideFromLeading:
            context.translateBy(x: -90 * canvas.scale * remaining, y: 0)
        case .slideFromTrailing:
            context.translateBy(x: 90 * canvas.scale * remaining, y: 0)
        case .pop:
            guard let region = layerRegion(layer) else { return }
            let pivot = region.pixels(in: canvas)
            let scale = 0.82 + 0.18 * progress
            context.translateBy(x: pivot.midX, y: pivot.midY)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -pivot.midX, y: -pivot.midY)
        }
    }

    // MARK: - Background

    private static func drawBackground(
        _ background: Background,
        in context: CGContext,
        canvas: Canvas,
        override: CGImage? = nil,
        collector: WarningCollector? = nil,
        textRegions: [CGRect] = []
    ) {
        let bounds = CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height)

        /// A decoded video frame replaces the background fill but keeps the
        /// declared dim wash — text legibility rules don't change because the
        /// background moves.
        if let override {
            if case .video(_, let dim, let scrim, let grade, let edge, let blur, let adaptive) = background {
                let frame = blurred(graded(override, with: grade, time: 0, collector: collector),
                                    radius: blur * Double(bounds.height) / 1920)
                drawAspectFilled(frame, in: context, bounds: bounds)
                let treatment = adaptive
                    ? adaptiveWashes(plate: frame, textRegions: textRegions,
                                     canvas: canvas, declared: (dim, scrim, edge))
                    : (dim, scrim, edge)
                applyWashes(dim: treatment.0, scrim: treatment.1, edge: treatment.2,
                            in: context, bounds: bounds)
            } else {
                drawAspectFilled(override, in: context, bounds: bounds)
            }
            return
        }

        switch background {
        case .solid(let color):
            context.setFillColor(color.cgColor)
            context.fill(bounds)

        case .linearGradient(let colors, let angle):
            let cgColors = colors.map(\.cgColor) as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: cgColors,
                locations: nil
            ) else { return }

            /// Angle 0 points up, clockwise — convert to a line through the
            /// canvas center long enough to cover the corners.
            let radians = (90 - angle) * .pi / 180
            let direction = CGVector(dx: cos(radians), dy: sin(radians))
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let reach = hypot(bounds.width, bounds.height) / 2
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: center.x - direction.dx * reach, y: center.y - direction.dy * reach),
                end: CGPoint(x: center.x + direction.dx * reach, y: center.y + direction.dy * reach),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )

        case .image(let path, let dim, let scrim, let grade, let edge, let blur, let adaptive), .video(let path, let dim, let scrim, let grade, let edge, let blur, let adaptive):
            /// Stills use a video background's poster frame; a missing or
            /// non-image file falls back to a dark fill rather than failing
            /// the whole deck — reported, because a photo listicle whose
            /// photos never arrived looks plausible and is not the post.
            if let image = loadImage(at: path) {
                let plate = blurred(graded(image, with: grade, time: 0, collector: collector),
                                    radius: blur * Double(bounds.height) / 1920)
                drawAspectFilled(plate, in: context, bounds: bounds)
                let treatment = adaptive
                    ? adaptiveWashes(plate: plate, textRegions: textRegions,
                                     canvas: canvas, declared: (dim, scrim, edge))
                    : (dim, scrim, edge)
                applyWashes(dim: treatment.0, scrim: treatment.1, edge: treatment.2,
                            in: context, bounds: bounds)
            } else {
                collector?.report(.missingImage(path: path))
                context.setFillColor(SlideColor("#15181D").cgColor)
                context.fill(bounds)
                applyWashes(dim: dim, scrim: scrim, edge: edge, in: context, bounds: bounds)
            }
        }
    }

    // MARK: - Adaptive washes

    /// The regions a slide's words occupy, for the scrim measurement.
    static func textRegions(of slide: Slide, in canvas: Canvas) -> [CGRect] {
        slide.layers.compactMap { layer in
            switch layer {
            case .text(let text, _, let region, _):
                return text.isEmpty ? nil : region.pixels(in: canvas)
            case .list(_, _, let region, _, _), .chip(_, let region, _, _, _):
                return region.pixels(in: canvas)
            case .image, .video, .rect, .dots, .pattern, .sticker, .pageIndicator:
                return nil
            }
        }
    }

    /// A scrim chosen by measuring, not declaring.
    ///
    /// Method: the plate is drawn exactly as the slide draws it —
    /// aspect-filled, graded, blurred — into a small canvas-shaped
    /// grayscale grid (32 columns), and the mean luminance is taken over
    /// the pixels under the slide's text regions. Strength maps linearly
    /// from that mean: a dark alley (≈0.15) gets barely any scrim because
    /// the type already reads, a bright sky (≈0.8) gets a deep one, and
    /// the result is clamped to 0.12…0.8 so a plate never goes unprotected
    /// or crushed. The edge follows where the words actually sit — bottom,
    /// top, or both — because darkening an end nobody reads costs the
    /// picture for nothing. The declared values remain the fallback when
    /// there is no text to protect; the declared `dim` is always kept,
    /// because dim is art direction, not legibility.
    ///
    /// Video plates are measured once, on the poster frame — a scrim that
    /// breathed with every bright frame would flicker.
    static func adaptiveWashes(
        plate: CGImage,
        textRegions: [CGRect],
        canvas: Canvas,
        declared: (dim: Double, scrim: Double, edge: ScrimEdge)
    ) -> (Double, Double, ScrimEdge) {
        guard !textRegions.isEmpty else { return declared }

        let gridWidth = 32
        let gridHeight = max(8, Int(32.0 * Double(canvas.height) / Double(canvas.width)))
        var pixels = [UInt8](repeating: 0, count: gridWidth * gridHeight)
        guard let context = CGContext(
            data: &pixels, width: gridWidth, height: gridHeight,
            bitsPerComponent: 8, bytesPerRow: gridWidth,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return declared }
        drawAspectFilled(plate, in: context,
                         bounds: CGRect(x: 0, y: 0, width: gridWidth, height: gridHeight))

        /// Mean luminance under the words. Region coordinates are canvas
        /// pixels (origin bottom-left); the grid rows run top-down.
        let scaleX = Double(gridWidth) / Double(canvas.width)
        let scaleY = Double(gridHeight) / Double(canvas.height)
        var total = 0.0
        var count = 0
        var textTop = false
        var textBottom = false

        for region in textRegions {
            let left = max(0, Int(region.minX * scaleX))
            let right = min(gridWidth - 1, Int(region.maxX * scaleX))
            let bottom = max(0, Int(region.minY * scaleY))
            let top = min(gridHeight - 1, Int(region.maxY * scaleY))
            guard left <= right, bottom <= top else { continue }

            for y in bottom...top {
                let row = gridHeight - 1 - y
                for x in left...right {
                    total += Double(pixels[row * gridWidth + x]) / 255
                    count += 1
                }
            }
            if region.midY >= CGFloat(canvas.height) / 2 { textTop = true } else { textBottom = true }
        }
        guard count > 0 else { return declared }

        let luminance = total / Double(count)
        let strength = min(0.8, max(0.12, (luminance - 0.08) * 1.05))
        let edge: ScrimEdge = textTop && textBottom ? .both : (textTop ? .top : .bottom)
        return (declared.dim, strength, edge)
    }

    /// The wash a slide's media plate needs — declared, or measured when
    /// the background asks for an adaptive scrim. `nil` for backgrounds
    /// that take no washes at all. The video exporter bakes this once per
    /// segment from the poster frame.
    static func washTreatment(
        for background: Background, slide: Slide, canvas: Canvas
    ) -> (dim: Double, scrim: Double, edge: ScrimEdge)? {
        switch background {
        case .image(let path, let dim, let scrim, let grade, let edge, _, let adaptive),
             .video(let path, let dim, let scrim, let grade, let edge, _, let adaptive):
            guard adaptive, let plate = loadImage(at: path) else { return (dim, scrim, edge) }
            return adaptiveWashes(
                plate: graded(plate, with: grade, time: 0),
                textRegions: textRegions(of: slide, in: canvas),
                canvas: canvas,
                declared: (dim, scrim, edge)
            )
        case .solid, .linearGradient:
            return nil
        }
    }

    /// The dim and scrim washes as one transparent image — the video
    /// exporter bakes this once and draws it per frame between the decoded
    /// background and the content overlay. `nil` when there is nothing to
    /// draw.
    static func renderWashes(
        dim: Double, scrim: Double, edge: ScrimEdge = .bottom, width: Int, height: Int
    ) -> CGImage? {
        guard dim > 0 || scrim > 0 else { return nil }
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        applyWashes(dim: dim, scrim: scrim, edge: edge, in: context,
                    bounds: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// The photo treatments: a flat dim over everything, then a scrim rising
    /// from the bottom — transparent above the midline, `scrim`-strength
    /// black at the base, where the text usually sits.
    private static func applyWashes(
        dim: Double, scrim: Double, edge: ScrimEdge = .bottom,
        in context: CGContext, bounds: CGRect
    ) {
        if dim > 0 {
            context.setFillColor(SlideColor.black.opacity(dim).cgColor)
            context.fill(bounds)
        }
        guard scrim > 0 else { return }

        /// Which end darkens is decided by where the words are. Dimming the
        /// whole frame to cover both ends is what `dim` is for, and it costs
        /// the picture; a scrim buys the same contrast where it is needed and
        /// leaves the subject alone.
        ///
        /// `both` runs each half at the full value rather than sharing it
        /// out: a caption at the bottom needs the same cover whether or not
        /// there is also a headline at the top.
        switch edge {
        case .bottom:
            drawScrim(scrim, from: bounds.minY, to: bounds.minY + bounds.height * 0.6,
                      in: context, bounds: bounds)
        case .top:
            drawScrim(scrim, from: bounds.maxY, to: bounds.maxY - bounds.height * 0.6,
                      in: context, bounds: bounds)
        case .both:
            drawScrim(scrim, from: bounds.minY, to: bounds.minY + bounds.height * 0.45,
                      in: context, bounds: bounds)
            drawScrim(scrim, from: bounds.maxY, to: bounds.maxY - bounds.height * 0.45,
                      in: context, bounds: bounds)
        }
    }

    /// One gradient from opaque-at-`start` to clear-at-`end`.
    private static func drawScrim(
        _ strength: Double, from start: CGFloat, to end: CGFloat,
        in context: CGContext, bounds: CGRect
    ) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [
                SlideColor.black.opacity(strength).cgColor,
                SlideColor.black.opacity(0).cgColor
            ] as CFArray,
            locations: [0, 1]
        ) else { return }

        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: bounds.midX, y: start),
            end: CGPoint(x: bounds.midX, y: end),
            options: [.drawsBeforeStartLocation]
        )
    }

    /// The image, blurred, for a backdrop that a card or a caption sits over.
    ///
    /// The idiom is a portrait photograph on a square canvas: rather than
    /// bars down each side, the same picture is blown up, blurred and used as
    /// its own background, so the frame is filled with something that belongs
    /// to the picture instead of a colour guessed from it.
    ///
    /// The edges are clamped before blurring. A Gaussian samples past the
    /// bounds and reads transparent black out there, which leaves a dark band
    /// around a blurred image — the one artefact that gives the trick away.
    static func blurred(_ image: CGImage, radius: Double) -> CGImage {
        guard radius > 0 else { return image }

        let input = CIImage(cgImage: image)
        guard let clamp = CIFilter(name: "CIAffineClamp") else { return image }
        clamp.setValue(input, forKey: kCIInputImageKey)

        guard let blur = CIFilter(name: "CIGaussianBlur"),
              let clamped = clamp.outputImage else { return image }
        blur.setValue(clamped, forKey: kCIInputImageKey)
        blur.setValue(radius, forKey: kCIInputRadiusKey)

        guard let output = blur.outputImage,
              let result = ciContext.createCGImage(output, from: input.extent)
        else { return image }

        return result
    }

    /// One shared Core Image context — creating one per frame would be the
    /// slow path Core Image documentation warns about.
    static let ciContext = CIContext()

    /// The last grade's built filter. Building one bakes the tone cube;
    /// a deck grades run after run with the same grade, and re-baking per
    /// call was most of a plate's cost. One slot, because plates arrive
    /// grade-by-grade — a dictionary would only hoard dead cubes.
    nonisolated(unsafe) private static var cachedGrade: VideoGrade?
    nonisolated(unsafe) private static var cachedFilter: GradeFilter?
    private static let gradeCacheLock = NSLock()

    /// How often the memo answered — a counter the cache test reads.
    nonisolated(unsafe) private(set) static var gradeCacheHits = 0

    /// The filter for a grade, memoized on the grade's value.
    static func filter(for grade: VideoGrade) throws -> GradeFilter {
        gradeCacheLock.lock()
        defer { gradeCacheLock.unlock() }
        if cachedGrade == grade, let filter = cachedFilter {
            gradeCacheHits += 1
            return filter
        }
        let filter = try GradeFilter(grade: grade)
        cachedGrade = grade
        cachedFilter = filter
        return filter
    }

    /// The plate, graded. Tolerant like the rest of the renderer — an
    /// unresolvable grade degrades to the ungraded plate, never a crash —
    /// but never silent: ungraded looks plausible in a way magenta does
    /// not, so the failure goes to the collector and `audit` reports it.
    static func graded(
        _ image: CGImage, with grade: VideoGrade?, time: Double,
        collector: WarningCollector? = nil
    ) -> CGImage {
        guard let grade else { return image }
        do {
            return graded(image, using: try filter(for: grade), time: time)
        } catch {
            collector?.report(.gradeFailed(reason: "\(error)"))
            return image
        }
    }

    /// The same, with a filter the caller already built — the video export
    /// bakes one filter per segment and grades every frame through it,
    /// because building a `GradeFilter` bakes a tone cube and doing that
    /// per frame is a cost nobody sees until the reel is a minute long.
    static func graded(_ image: CGImage, using filter: GradeFilter, time: Double) -> CGImage {
        let input = CIImage(cgImage: image)
        let output = filter.apply(input, time: time)
        return ciContext.createCGImage(output, from: input.extent) ?? image
    }

    static func drawAspectFilled(_ image: CGImage, in context: CGContext, bounds: CGRect) {
        let imageSize = CGSize(width: image.width, height: image.height)
        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: bounds.midX - drawSize.width / 2,
            y: bounds.midY - drawSize.height / 2
        )
        context.saveGState()
        context.clip(to: bounds)
        context.draw(image, in: CGRect(origin: origin, size: drawSize))
        context.restoreGState()
    }

    private static func loadImage(at path: String) -> CGImage? {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            if let image = orientedImage(from: source) {
                return image
            }
        }
        /// Vector logos ship as PDF — CoreGraphics renders it headlessly,
        /// which SVG cannot do without AppKit. Rasterized at 4× so a small
        /// footer logo stays crisp after aspect-fit scaling.
        return pdfImage(at: url)
    }

    /// The image the way the camera meant it.
    ///
    /// `CGImageSourceCreateImageAtIndex` hands back the sensor's pixels and
    /// leaves the EXIF orientation for the caller to honour — Preview does,
    /// a raw `CGContext` draw does not, so a phone portrait dropped into a
    /// slide arrived on its side. Files that carry a non-identity
    /// orientation decode through the thumbnail API with the transform
    /// applied, at full resolution; everything else takes the plain path.
    private static func orientedImage(from source: CGImageSource) -> CGImage? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1

        guard orientation > 1 else {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }

        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height, 1)
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func pdfImage(at url: URL) -> CGImage? {
        guard let document = CGPDFDocument(url as CFURL),
              let page = document.page(at: 1) else { return nil }
        let box = page.getBoxRect(.mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let scale: CGFloat = 4
        guard let context = CGContext(
            data: nil,
            width: Int(box.width * scale), height: Int(box.height * scale),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        context.drawPDFPage(page)
        return context.makeImage()
    }

    // MARK: - Card

    private static func cardRect(_ card: CardStyle, canvas: Canvas) -> CGRect {
        let inset = CGFloat(canvas.width) * card.inset
        return canvas.safeRect.insetBy(dx: inset, dy: inset)
    }

    private static func chromeRect(canvas: Canvas, card: CardStyle?) -> CGRect {
        guard let card else {
            /// Cardless chrome sits on the content grid (x = 0.1), not the
            /// safe area — a footer 3% left of every headline reads as a
            /// mistake, not a margin. The safe area still wins when it is
            /// wider (the TikTok rail's 14% right inset).
            let rect = canvas.safeRect
            let w = CGFloat(canvas.width)
            let left = max(rect.minX, 0.1 * w)
            let right = min(rect.maxX, 0.9 * w)
            return CGRect(x: left, y: rect.minY, width: right - left, height: rect.height)
        }
        /// 32pt lands the chrome on the same optical left margin content
        /// regions use (x = 0.1) — one grid, not two nearly-equal ones.
        let padding = 32 * canvas.scale
        return cardRect(card, canvas: canvas).insetBy(dx: padding, dy: padding)
    }

    private static func drawCard(_ card: CardStyle, in context: CGContext, canvas: Canvas) {
        let rect = cardRect(card, canvas: canvas)
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: card.cornerRadius * canvas.scale,
            cornerHeight: card.cornerRadius * canvas.scale,
            transform: nil
        )
        context.setFillColor(card.color.cgColor)
        context.addPath(path)
        context.fillPath()

        if let borderColor = card.borderColor, card.borderWidth > 0 {
            /// Stroked inward so a thick brutalist border never leaves the
            /// card's own footprint.
            let width = card.borderWidth * canvas.scale
            let innerRect = rect.insetBy(dx: width / 2, dy: width / 2)
            let radius = max(card.cornerRadius * canvas.scale - width / 2, 0)
            let border = CGPath(
                roundedRect: innerRect,
                cornerWidth: radius, cornerHeight: radius,
                transform: nil
            )
            context.setStrokeColor(borderColor.cgColor)
            context.setLineWidth(width)
            context.addPath(border)
            context.strokePath()
        }
    }

    // MARK: - Layers

    private static func drawLayer(
        _ layer: SlideLayer,
        in context: CGContext,
        deck: SlideDeck,
        slide: Slide,
        slideIndex: Int,
        chrome: CGRect,
        videoFrame: CGImage? = nil,
        collector: WarningCollector?
    ) throws {
        let canvas = deck.canvas

        switch layer {
        case .text(let text, let style, let region, let verticalAlignment):
            if let collector {
                reportUnfilledTokens(in: text, to: collector)
                reportContrast(of: style, drawing: text, slide: slide, deck: deck, to: collector)
            }
            TextDrawer.draw(
                text: text,
                style: style,
                brand: deck.brand,
                in: region.pixels(in: canvas),
                verticalAlignment: verticalAlignment,
                context: context,
                scale: canvas.scale,
                collector: collector
            )

        case .list(let items, let style, let region, let marker, let spacing):
            if let collector {
                for item in items {
                    reportContrast(of: style, drawing: item.title ?? item.body,
                                   slide: slide, deck: deck, to: collector)
                }
            }
            drawList(
                items: items, style: style, marker: marker, spacing: spacing,
                in: region.pixels(in: canvas), deck: deck,
                context: context, scale: canvas.scale, collector: collector
            )

        case .image(let path, let region, let cornerRadius, let scaling, let rotationDegrees, let maskPath):
            guard let image = loadImage(at: path) else {
                /// Under the audit, a missing image is a finding, not a
                /// full stop — the placeholder keeps the rest of the
                /// slide's findings collectable. A real render still
                /// refuses: nobody ships a gray rectangle by surprise.
                if let collector {
                    collector.report(.unreadableImage(path: path))
                    let bounds = region.pixels(in: canvas)
                    context.setFillColor(SlideColor("#3A3A3E").cgColor)
                    context.fill(bounds)
                    return
                }
                throw RenderError.unreadableImage(path)
            }
            let bounds = region.pixels(in: canvas)
            context.saveGState()
            if let maskPath, let mask = loadImage(at: maskPath) {
                /// An arbitrary-shape clip from an image's alpha — the true
                /// squircle window from a bezel's mask, a blob, anything.
                context.clip(to: bounds, mask: mask)
            }
            if rotationDegrees != 0 {
                /// Tilt about the region's center — the store's angled-
                /// device idiom. (Positive turns clockwise on screen.)
                context.translateBy(x: bounds.midX, y: bounds.midY)
                context.rotate(by: -rotationDegrees * .pi / 180)
                context.translateBy(x: -bounds.midX, y: -bounds.midY)
            }
            if scaling == "fill" {
                /// Fill: the region is the shape — clip it (rounded if
                /// asked) and aspect-fill the image through it. The device-
                /// frame and photo-tile mode.
                if cornerRadius > 0 {
                    context.addPath(CGPath(
                        roundedRect: bounds,
                        cornerWidth: cornerRadius * canvas.scale,
                        cornerHeight: cornerRadius * canvas.scale,
                        transform: nil
                    ))
                    context.clip()
                }
                drawAspectFilled(image, in: context, bounds: bounds)
            } else {
                let imageSize = CGSize(width: image.width, height: image.height)
                let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
                let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
                let rect = CGRect(
                    x: bounds.midX - drawSize.width / 2,
                    y: bounds.midY - drawSize.height / 2,
                    width: drawSize.width,
                    height: drawSize.height
                )
                if cornerRadius > 0 {
                    context.addPath(CGPath(
                        roundedRect: rect,
                        cornerWidth: cornerRadius * canvas.scale,
                        cornerHeight: cornerRadius * canvas.scale,
                        transform: nil
                    ))
                    context.clip()
                }
                context.draw(image, in: rect)
            }
            context.restoreGState()

        case .video(_, let region, let cornerRadius, let scaling, let maskPath):
            /// The exporter decodes and hands the frame in; a still render
            /// without one draws a dark screen — never a crash.
            let bounds = region.pixels(in: canvas)
            context.saveGState()
            if let maskPath, let mask = loadImage(at: maskPath) {
                context.clip(to: bounds, mask: mask)
            }
            if cornerRadius > 0 {
                context.addPath(CGPath(
                    roundedRect: bounds,
                    cornerWidth: cornerRadius * canvas.scale,
                    cornerHeight: cornerRadius * canvas.scale,
                    transform: nil
                ))
                context.clip()
            }
            if let videoFrame {
                if scaling == "fill" {
                    drawAspectFilled(videoFrame, in: context, bounds: bounds)
                } else {
                    context.draw(videoFrame, in: bounds)
                }
            } else {
                context.setFillColor(SlideColor("#0A0A0C").cgColor)
                context.fill(bounds)
            }
            context.restoreGState()

        case .pageIndicator:
            /// Opt-in only: the platforms this genre ships to draw their own
            /// carousel progress, and a baked counter duplicates it — see
            /// ``SlideDeck/showsPageIndicator``.
            guard deck.showsPageIndicator else { return }
            let text = "\(slideIndex + 1) / \(deck.slides.count)"
            let region = CGRect(
                x: chrome.maxX - 240 * canvas.scale,
                y: chrome.maxY - 44 * canvas.scale,
                width: 240 * canvas.scale,
                height: 44 * canvas.scale
            )
            TextDrawer.draw(
                text: text,
                style: TextStyle(
                    weight: "semibold", size: 26,
                    color: slide.chromeColor?.opacity(0.75) ?? deck.brand.secondaryTextColor,
                    alignment: "right", autoShrink: false
                ),
                brand: deck.brand,
                in: region,
                verticalAlignment: "top",
                context: context,
                scale: canvas.scale
            )

        case .rect(let color, let region, let cornerRadius):
            let bounds = region.pixels(in: canvas)
            let path = CGPath(
                roundedRect: bounds,
                cornerWidth: min(cornerRadius * canvas.scale, bounds.height / 2),
                cornerHeight: min(cornerRadius * canvas.scale, bounds.height / 2),
                transform: nil
            )
            context.setFillColor((color ?? deck.brand.accentColor).cgColor)
            context.addPath(path)
            context.fillPath()

        case .dots(let color, let region, let spacing, let radius):
            let bounds = region.pixels(in: canvas)
            let step = spacing * canvas.scale
            let r = radius * canvas.scale
            context.saveGState()
            context.clip(to: bounds)
            context.setFillColor(color.cgColor)
            var y = bounds.minY
            while y <= bounds.maxY {
                var x = bounds.minX
                while x <= bounds.maxX {
                    context.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    x += step
                }
                y += step
            }
            context.restoreGState()

        case .pattern(let glyph, let color, let region, let size, let spacing):
            let bounds = region.pixels(in: canvas)
            let step = spacing * canvas.scale
            let font = CTFontCreateWithName("Helvetica Neue" as CFString, size * canvas.scale, nil)
            let attributed = CFAttributedStringCreate(
                kCFAllocatorDefault,
                glyph as CFString,
                [
                    kCTFontAttributeName: font,
                    kCTForegroundColorAttributeName: color.cgColor
                ] as CFDictionary
            )!
            let line = CTLineCreateWithAttributedString(attributed)
            context.saveGState()
            context.clip(to: bounds)
            context.textMatrix = .identity
            var row = 0
            var y = bounds.minY
            while y <= bounds.maxY + step {
                /// Alternate rows offset half a step — tiled, not gridded.
                var x = bounds.minX - (row % 2 == 0 ? 0 : step / 2)
                while x <= bounds.maxX + step {
                    context.textPosition = CGPoint(x: x, y: y)
                    CTLineDraw(line, context)
                    x += step
                }
                y += step
                row += 1
            }
            context.restoreGState()

        case .sticker(let text, let region, let rotationDegrees):
            let bounds = region.pixels(in: canvas)
            context.saveGState()
            context.translateBy(x: bounds.midX, y: bounds.midY)
            context.rotate(by: -rotationDegrees * .pi / 180)
            context.translateBy(x: -bounds.midX, y: -bounds.midY)
            TextDrawer.draw(
                text: text,
                style: TextStyle(
                    size: stickerPointSize(region: region, canvas: canvas),
                    alignment: "center",
                    autoShrink: true
                ),
                brand: deck.brand,
                in: bounds,
                verticalAlignment: "middle",
                context: context,
                scale: canvas.scale
            )
            context.restoreGState()

        case .chip(let text, let region, let size, let alignment, let color):
            let bounds = region.pixels(in: canvas)
            let fill = color ?? deck.brand.accentColor
            let style = TextStyle(
                weight: "bold", size: size,
                color: chipTextColor(for: fill),
                alignment: "center", autoShrink: false
            )
            let measured = TextDrawer.measure(
                text: text, style: style, brand: deck.brand,
                maxWidth: bounds.width, scale: canvas.scale
            )
            /// Padding scales with the label so a big CTA chip keeps the
            /// pill proportions of a small number chip.
            let padding = 22 * canvas.scale * CGFloat(size) / 30
            let width = measured.width + padding * 2

            /// A chip never shrinks its label — the pill grows instead, and
            /// one wider than its region runs off the canvas. Reported, not
            /// clipped: a CTA button missing its last word is exactly the
            /// kind of thing `audit` exists to catch.
            if width > bounds.width, let collector {
                collector.report(.overflow(text: text))
            }
            let x: CGFloat
            switch alignment {
            case "center": x = bounds.midX - width / 2
            case "right": x = bounds.maxX - width
            default: x = bounds.minX
            }
            let chipRect = CGRect(
                x: x,
                y: bounds.maxY - measured.height - padding,
                width: width,
                height: measured.height + padding
            )
            let path = CGPath(
                roundedRect: chipRect,
                cornerWidth: chipRect.height / 2,
                cornerHeight: chipRect.height / 2,
                transform: nil
            )
            context.setFillColor(fill.cgColor)
            context.addPath(path)
            context.fillPath()
            TextDrawer.draw(
                text: text,
                style: style,
                brand: deck.brand,
                in: chipRect.insetBy(dx: padding, dy: padding / 2),
                verticalAlignment: "middle",
                context: context,
                scale: canvas.scale
            )
        }
    }

    /// The point size a sticker wants: 80% of its region's shorter side,
    /// expressed in reference points.
    ///
    /// The height fraction converts through the canvas's own aspect ratio.
    /// It used to hardcode the 4:5 reference height, which sized stickers
    /// on a 9:16 story at about two-thirds of their region and let them
    /// overrun it on a landscape frame before auto-shrink caught them.
    static func stickerPointSize(region: UnitRect, canvas: Canvas) -> Double {
        let width = region.width * 1080
        let height = region.height * 1080 * Double(canvas.height) / Double(canvas.width)
        return min(width, height) * 0.8
    }

    /// `{word}`-shaped survivors in rendered text — visible by design, and
    /// exactly what audit exists to catch.
    private static func reportUnfilledTokens(in text: String, to collector: WarningCollector) {
        var remaining = Substring(text)
        while let open = remaining.firstIndex(of: "{") {
            let afterOpen = remaining[remaining.index(after: open)...]
            guard let close = afterOpen.firstIndex(of: "}") else { return }
            let token = afterOpen[..<close]
            if !token.isEmpty, token.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) {
                collector.report(.unfilledToken(token: "{\(token)}"))
            }
            remaining = afterOpen[afterOpen.index(after: close)...]
        }
    }

    /// Chip label color: black on light fills, white on dark — computed,
    /// so brand authors never think about it.
    private static func chipTextColor(for fill: SlideColor) -> SlideColor {
        let color = fill.cgColor
        let components = color.components ?? [0, 0, 0, 1]
        let luminance = 0.299 * components[0] + 0.587 * components[1] + 0.114 * components[2]
        return luminance > 0.6 ? .black : .white
    }

    // MARK: - Footer

    /// The brand strip every slide in this genre carries: logo in a circle,
    /// name, @handle, bottom-left of the safe area.
    private static func drawFooter(_ brand: BrandKit, in context: CGContext, canvas: Canvas, chrome: CGRect, chromeColor: SlideColor?) throws {
        guard !brand.name.isEmpty || !brand.handle.isEmpty else { return }

        let scale = canvas.scale
        let logoSize = 76 * scale
        var textX = chrome.minX

        if let logoPath = brand.logoPath, let logo = loadImage(at: logoPath) {
            /// The avatar idiom: circle-clipped, aspect-FILLED — a portrait
            /// photo must crop into the circle, never squash to fit it.
            let rect = CGRect(x: chrome.minX, y: chrome.minY, width: logoSize, height: logoSize)
            context.saveGState()
            context.addEllipse(in: rect)
            context.clip()
            drawAspectFilled(logo, in: context, bounds: rect)
            context.restoreGState()
            textX = rect.maxX + 18 * scale
        }

        /// Line regions sized for the tallest faces in the library — a
        /// region shorter than the font's line height makes CoreText drop
        /// the line entirely (Avenir Next at 30pt is taller than 38px).
        let nameRegion = CGRect(
            x: textX, y: chrome.minY + logoSize / 2 - 6 * scale,
            width: chrome.maxX - textX, height: logoSize / 2 + 10 * scale
        )
        TextDrawer.draw(
            text: brand.name,
            style: TextStyle(weight: "bold", size: 30, color: chromeColor, autoShrink: false),
            brand: brand,
            in: nameRegion,
            verticalAlignment: "bottom",
            context: context,
            scale: scale
        )

        let handleRegion = CGRect(
            x: textX, y: chrome.minY - 8 * scale,
            width: chrome.maxX - textX, height: logoSize / 2 + 2 * scale
        )
        TextDrawer.draw(
            text: brand.handle,
            style: TextStyle(size: 26, color: chromeColor?.opacity(0.65) ?? brand.secondaryTextColor, autoShrink: false),
            brand: brand,
            in: handleRegion,
            verticalAlignment: "top",
            context: context,
            scale: scale
        )
    }
}

// MARK: - Lists

extension SlideRenderer {

    /// Draws entries down a region, each with its marker beside it.
    ///
    /// The markers are measured rather than placed. A rule has to be as tall
    /// as the entry it belongs to, and how tall that is depends on where the
    /// text wrapped — which is known here and nowhere else, which is why a
    /// list is a layer rather than a stack of rects somebody positioned by
    /// hand and had to reposition every time the copy changed.
    ///
    /// Entries that do not fit are dropped rather than drawn over the edge,
    /// and the collector is told how many — a slide quietly missing its last
    /// two places is worse than one that says so.
    static func drawList(
        items: [ListItem],
        style: TextStyle,
        marker: ListMarker,
        spacing: Double,
        in region: CGRect,
        deck: SlideDeck,
        context: CGContext,
        scale: CGFloat,
        collector: WarningCollector?
    ) {
        guard !items.isEmpty, region.width > 1, region.height > 1 else { return }

        let gutter = marker.gutter * Double(scale)
        let textWidth = region.width - gutter
        guard textWidth > 1 else { return }

        /// The title takes the accent weight, falling back to something
        /// heavier than the body so a list still reads as a list when the
        /// style has said nothing about accents.
        var titleStyle = style
        titleStyle.weight = style.accentWeight ?? "bold"
        titleStyle.color = style.accentColor ?? style.color
        titleStyle.linePill = nil

        let gap = spacing * Double(scale)
        var cursor = region.maxY
        var drawn = 0

        for (index, item) in items.enumerated() {
            let titleHeight = item.title.map {
                TextDrawer.measure(text: $0, style: titleStyle, brand: deck.brand,
                                   maxWidth: textWidth, scale: scale).height
            } ?? 0
            let bodyHeight = TextDrawer.measure(
                text: item.body, style: style, brand: deck.brand,
                maxWidth: textWidth, scale: scale
            ).height

            let titleGap = titleHeight > 0 ? 6 * Double(scale) : 0
            let entryHeight = titleHeight + titleGap + bodyHeight

            /// One entry past the bottom means every later one is too.
            guard cursor - entryHeight >= region.minY else { break }

            let top = cursor
            let left = region.minX + gutter
            var y = top

            if let title = item.title {
                TextDrawer.draw(
                    text: title, style: titleStyle, brand: deck.brand,
                    in: CGRect(x: left, y: y - titleHeight, width: textWidth, height: titleHeight),
                    verticalAlignment: "top", context: context, scale: scale, collector: collector
                )
                y -= titleHeight + titleGap
            }

            TextDrawer.draw(
                text: item.body, style: style, brand: deck.brand,
                in: CGRect(x: left, y: y - bodyHeight, width: textWidth, height: bodyHeight),
                verticalAlignment: "top", context: context, scale: scale, collector: collector
            )

            drawMarker(
                marker, at: index, entry: CGRect(
                    x: region.minX, y: top - entryHeight, width: gutter, height: entryHeight
                ),
                style: style, deck: deck, context: context, scale: scale
            )

            cursor = top - entryHeight - gap
            drawn += 1
        }

        /// Reported as overflow, which is what it is: a slide quietly
        /// missing its last two places is worse than one that says so.
        for dropped in items.dropFirst(drawn) {
            collector?.report(.overflow(text: dropped.title ?? dropped.body))
        }
    }

    private static func drawMarker(
        _ marker: ListMarker,
        at index: Int,
        entry: CGRect,
        style: TextStyle,
        deck: SlideDeck,
        context: CGContext,
        scale: CGFloat
    ) {
        switch marker {
        case .none:
            return

        case .rule(let color, let width):
            context.setFillColor((color ?? deck.brand.accentColor).cgColor)
            context.fill(CGRect(
                x: entry.minX, y: entry.minY,
                width: width * Double(scale), height: entry.height
            ))

        case .bullet(let color, let radius):
            /// On the first line rather than centred on the entry — a dot
            /// halfway down a four-line entry reads as belonging to the
            /// middle of it — and on that line's *x-height*, which is where
            /// a typographer puts a bullet and where the eye expects it.
            ///
            /// Taken from the face's own metrics rather than a fraction of
            /// the point size: the fraction was a guess, and it sat the dot
            /// visibly high.
            let font = FontResolver.font(
                family: style.fontFamily ?? deck.brand.fontFamily,
                weight: style.weight,
                size: style.size * Double(scale)
            )
            let baseline = entry.maxY - CTFontGetAscent(font)
            let middle = baseline + CTFontGetXHeight(font) / 2

            let r = radius * Double(scale)
            context.setFillColor((color ?? deck.brand.accentColor).cgColor)
            context.fillEllipse(in: CGRect(
                x: entry.minX, y: middle - r, width: r * 2, height: r * 2
            ))

        case .number(let color):
            var numberStyle = style
            numberStyle.weight = style.accentWeight ?? "bold"
            numberStyle.color = color ?? style.accentColor ?? deck.brand.accentColor
            numberStyle.alignment = "left"
            numberStyle.linePill = nil
            numberStyle.autoShrink = false

            /// The number keeps the entry's leading rather than being reset
            /// to single. Leading moves the first baseline within its frame,
            /// so a number set solid beside a title set at 1.18 sits visibly
            /// high — they have to share the measure to share a baseline.
            ///
            /// The frame is measured rather than guessed from the point size,
            /// which is what made this safe: sizing it as `size * 1.3` left
            /// the box shorter than the line at any leading above about 1.15,
            /// and CoreText answered by drawing nothing at all.
            let label = "\(index + 1)"
            let measured = TextDrawer.measure(
                text: label, style: numberStyle, brand: deck.brand,
                maxWidth: entry.width, scale: scale
            ).height

            TextDrawer.draw(
                text: label, style: numberStyle, brand: deck.brand,
                in: CGRect(x: entry.minX, y: entry.maxY - measured,
                           width: entry.width, height: measured),
                verticalAlignment: "top", context: context, scale: scale, collector: nil
            )
        }
    }
}

// MARK: - Contrast

extension SlideRenderer {

    /// Reports text that cannot be read against what is behind it.
    ///
    /// Only where the background is a colour — a photograph is not one colour
    /// and judging it as one would produce a warning that is wrong in half
    /// the frame. See ``Contrast``.
    ///
    /// Stroked text is skipped: a keyline exists precisely to carry its own
    /// contrast, and a yellow headline outlined in black is legible over
    /// anything, which is the point of it.
    ///
    /// A pill is not skipped — it is a backdrop, and the ink is compared to
    /// it rather than to whatever is behind it. Skipping them was the first
    /// version of this, and it missed white text on a white pill in the
    /// shipped library: the highlighter idiom means the pill is exactly where
    /// the wrong ink hides.
    static func reportContrast(
        of style: TextStyle,
        drawing text: String,
        slide: Slide,
        deck: SlideDeck,
        to collector: WarningCollector
    ) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard style.strokeWidth == 0, style.gradientColors == nil else { return }
        guard let ground = Contrast.backdrop(of: slide, in: deck) else { return }

        /// A pill sits between the ink and everything else, so it is what the
        /// ink is read against.
        let backdrop = style.linePill.map { Contrast.composited($0, over: ground) } ?? ground
        let declared = style.color ?? deck.brand.textColor

        /// Faint on purpose: a watermark glyph behind the copy is decoration
        /// and is supposed to be barely there.
        guard Double(declared.cgColor.alpha) >= Contrast.decorative else { return }

        let ink = Contrast.composited(declared, over: backdrop)
        let ratio = Contrast.ratio(ink, on: backdrop)

        guard ratio < Contrast.invisible else { return }
        collector.report(.lowContrast(text: text, ratio: ratio))
    }
}
