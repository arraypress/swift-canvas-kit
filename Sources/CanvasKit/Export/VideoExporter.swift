//
//  VideoExporter.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//

import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import VideoToolbox

/// Slide → MP4: the reel export.
///
/// Every frame comes from `SlideRenderer.render` — the parity rule extends to
/// motion. A slide with a video background gets its frames decoded and passed
/// through the renderer's `backgroundFrame` hook; any other background renders
/// once and holds. Narration audio (`slide.narrationAudioPath`) is muxed in as
/// AAC; where the file came from — TTS, a microphone — is the caller's
/// business, per the AI-agnostic rule.
public enum VideoExporter {

    public enum ExportError: Error, CustomStringConvertible {
        case slideIndexOutOfRange(Int)
        case writerCreationFailed(String)
        case unreadableAudio(String)
        case unreadableVideo(String)
        case unusableGrade(String)

        public var description: String {
            switch self {
            case .slideIndexOutOfRange(let index):
                return "Slide index \(index) is out of range."
            case .writerCreationFailed(let reason):
                return "Could not start the video writer: \(reason)"
            case .unreadableAudio(let path):
                return "Could not read narration audio at '\(path)'."
            case .unreadableVideo(let path):
                return "Could not read background video at '\(path)'."
            case .unusableGrade(let reason):
                return "A background's grade could not be built: \(reason)"
            }
        }
    }

    /// Refuses a deck whose grades cannot be built, before a frame renders.
    ///
    /// The still renderer degrades to the ungraded plate and reports a
    /// warning, which suits a picture somebody is about to look at. A video
    /// export is minutes of encoding; discovering the look never applied
    /// after the render is the worst version, so here a broken grade is an
    /// error up front.
    private static func validateGrades(of deck: SlideDeck) throws {
        for slide in deck.slides {
            switch deck.resolvedBackground(for: slide) {
            case .image(_, _, _, let grade, _, _, _), .video(_, _, _, let grade, _, _, _):
                guard let grade else { continue }
                do { _ = try GradeFilter(grade: grade) } catch {
                    throw ExportError.unusableGrade("\(error)")
                }
            case .solid, .linearGradient:
                continue
            }
        }
    }

    // MARK: - High level

    /// Export one slide as a video.
    ///
    /// Duration is the slide's, stretched to cover the narration (plus a
    /// beat of air) when the audio runs longer — a cut-off voiceover is
    /// never the right trade.
    public static func export(
        deck: SlideDeck,
        slideIndex: Int,
        to url: URL,
        framesPerSecond: Int = 30
    ) async throws {
        guard deck.slides.indices.contains(slideIndex) else {
            throw ExportError.slideIndexOutOfRange(slideIndex)
        }
        try validateGrades(of: deck)
        let slide = deck.slides[slideIndex]

        var duration = slide.duration
        var narrationURL: URL?
        if let narrationPath = slide.narrationAudioPath {
            let audioURL = URL(fileURLWithPath: (narrationPath as NSString).expandingTildeInPath)
            let audioDuration = try await AVURLAsset(url: audioURL).load(.duration).seconds
            guard audioDuration.isFinite, audioDuration > 0 else {
                throw ExportError.unreadableAudio(narrationPath)
            }
            duration = max(duration, audioDuration + 0.4)
            narrationURL = audioURL
        }

        /// With a music bed, the writer's output is an intermediate: a
        /// mixdown pass lays the music under the narration afterwards.
        let writerTarget: URL
        if deck.musicPath != nil {
            writerTarget = url.deletingLastPathComponent()
                .appendingPathComponent(".mix-\(url.lastPathComponent)")
        } else {
            writerTarget = url
        }

        /// Sequential frame source: decoded background video (restarted when
        /// it runs out, so short loops cover long narrations) or a single
        /// held still.
        defer { if writerTarget != url { try? FileManager.default.removeItem(at: writerTarget) } }

        if case .video(let path, let dim, let scrim, let grade, let edge, let blur, _) = deck.resolvedBackground(for: slide) {
            let videoURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            let frames = try await BackgroundFrameSource(url: videoURL)

            /// Text layout is the expensive part of a frame and it doesn't
            /// change while the background moves — the overlay renders once
            /// and each frame is just decode + three draws. The dim and
            /// scrim washes bake into one constant image, and the grade's
            /// filter into one bake, for the same reason.
            let overlay = try SlideRenderer.renderOverlay(deck: deck, slideIndex: slideIndex)
            let width = deck.canvas.width
            let height = deck.canvas.height
            /// Measured once from the poster when the scrim is adaptive — a
            /// scrim that breathed per frame would flicker.
            let treatment = SlideRenderer.washTreatment(
                for: deck.resolvedBackground(for: slide), slide: slide, canvas: deck.canvas
            ) ?? (dim, scrim, edge)
            let washes = SlideRenderer.renderWashes(
                dim: treatment.dim, scrim: treatment.scrim, edge: treatment.edge,
                width: width, height: height
            )
            let filter = try grade.map { try GradeFilter(grade: $0) }

            try await write(
                width: width,
                height: height,
                duration: duration,
                framesPerSecond: framesPerSecond,
                narrationURL: narrationURL,
                to: writerTarget
            ) { time in
                guard let context = CGContext(
                    data: nil, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else {
                    throw ExportError.writerCreationFailed("no compose context")
                }
                let bounds = CGRect(x: 0, y: 0, width: width, height: height)
                var plate = try frames.next()
                if let filter {
                    plate = SlideRenderer.graded(plate, using: filter, time: time)
                }
                /// The still export blurs a video's poster frame; parity
                /// says the moving frames blur too, or the same deck ships
                /// sharp as MP4 and soft as PNG.
                if blur > 0 {
                    plate = SlideRenderer.blurred(plate, radius: blur * Double(height) / 1920)
                }
                SlideRenderer.drawAspectFilled(plate, in: context, bounds: bounds)
                if let washes {
                    context.draw(washes, in: bounds)
                }
                context.draw(overlay, in: bounds)
                guard let image = context.makeImage() else {
                    throw ExportError.writerCreationFailed("no composed frame")
                }
                return image
            }
        } else {
            let still = try SlideRenderer.render(deck: deck, slideIndex: slideIndex)
            try await write(
                width: deck.canvas.width,
                height: deck.canvas.height,
                duration: duration,
                framesPerSecond: framesPerSecond,
                narrationURL: narrationURL,
                to: writerTarget
            ) { _ in still }
        }

        if let musicPath = deck.musicPath {
            let musicURL = URL(fileURLWithPath: (musicPath as NSString).expandingTildeInPath)
            try await mixMusic(bed: musicURL, into: writerTarget, output: url)
        }
    }

    // MARK: - Deck stitch

    /// One segment of the stitched reel: a slide, its place on the clock,
    /// and how to draw it at a moment in its own local time.
    private struct Segment {
        let start: Double
        let duration: Double
        let narrationURL: URL?
        let makeFrame: (Double) throws -> CGImage
    }

    /// Export the whole deck as one video: each slide plays for its
    /// duration (stretched over its narration), narrations land at their
    /// slide's start, the music bed runs under everything, and `transition`
    /// dresses the boundaries — CutRender envelopes (`.cut(.whipPan)`) or
    /// cross-frame motion (`.crossfade`, `.push`, `.wipe`). This is what
    /// turns a carousel into a reel.
    public static func export(
        deck: SlideDeck,
        to url: URL,
        transition: SlideTransition = .none,
        transitionDuration: Double = 0.5,
        motion: SlideMotion = .kenBurns,
        transitionSound: TransitionSound = .none,
        framesPerSecond: Int = 30
    ) async throws {
        guard !deck.slides.isEmpty else { throw ExportError.slideIndexOutOfRange(0) }
        try validateGrades(of: deck)

        let width = deck.canvas.width
        let height = deck.canvas.height

        var segments: [Segment] = []
        var cursor = 0.0
        for (index, slide) in deck.slides.enumerated() {
            var duration = slide.duration
            var narrationURL: URL?
            if let narrationPath = slide.narrationAudioPath {
                let audioURL = URL(fileURLWithPath: (narrationPath as NSString).expandingTildeInPath)
                let audioDuration = try await AVURLAsset(url: audioURL).load(.duration).seconds
                guard audioDuration.isFinite, audioDuration > 0 else {
                    throw ExportError.unreadableAudio(narrationPath)
                }
                duration = max(duration, audioDuration + 0.4)
                narrationURL = audioURL
            }

            /// While an entrance is playing, the overlay is a function of
            /// time and re-renders per frame; once settled, the cached
            /// overlay takes over and frames go back to composite-only.
            let entrance = slide.entrance ?? deck.entrance
            let animatedLayers = slide.layers.filter(SlideRenderer.isAnimatable).count
            let settle = entrance?.settleTime(layerCount: animatedLayers) ?? 0

            let makeFrame: (Double) throws -> CGImage

            /// Slides with video LAYERS — a device screen playing footage —
            /// re-render in full per frame: the screen changes every frame,
            /// so the cached-overlay shortcut does not apply. Layer sources
            /// loop the way background video does.
            let videoLayers = slide.layers.enumerated().compactMap { pair -> (index: Int, path: String)? in
                if case .video(let path, _, _, _, _) = pair.element { return (pair.offset, path) }
                return nil
            }
            if !videoLayers.isEmpty {
                var sources: [Int: BackgroundFrameSource] = [:]
                for layer in videoLayers {
                    let url = URL(fileURLWithPath: (layer.path as NSString).expandingTildeInPath)
                    sources[layer.index] = try await BackgroundFrameSource(url: url)
                }
                makeFrame = { time in
                    var frames: [Int: CGImage] = [:]
                    for (index, source) in sources {
                        frames[index] = try source.next()
                    }
                    return try SlideRenderer.render(deck: deck, slideIndex: index, at: time, layerFrames: frames)
                }
            } else if case .video(let path, let dim, let scrim, let grade, let edge, let blur, _) = deck.resolvedBackground(for: slide) {
                let videoURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                let frames = try await BackgroundFrameSource(url: videoURL)
                let overlay = try SlideRenderer.renderOverlay(deck: deck, slideIndex: index)
                let treatment = SlideRenderer.washTreatment(
                    for: deck.resolvedBackground(for: slide), slide: slide, canvas: deck.canvas
                ) ?? (dim, scrim, edge)
                let washes = SlideRenderer.renderWashes(
                    dim: treatment.dim, scrim: treatment.scrim, edge: treatment.edge,
                    width: width, height: height
                )
                /// One filter per segment: building one bakes the tone cube,
                /// and per-frame that cost multiplies by every second of reel.
                let filter = try grade.map { try GradeFilter(grade: $0) }
                makeFrame = { time in
                    var plate = try frames.next()
                    if let filter {
                        plate = SlideRenderer.graded(plate, using: filter, time: time)
                    }
                    if blur > 0 {
                        plate = SlideRenderer.blurred(plate, radius: blur * Double(height) / 1920)
                    }
                    return try composeFrame(
                        background: plate,
                        washes: washes,
                        overlay: time < settle
                            ? try SlideRenderer.renderOverlay(deck: deck, slideIndex: index, at: time)
                            : overlay,
                        width: width, height: height
                    )
                }
            } else if let drift = motion.drift(forSlide: index) {
                /// Ken Burns: the plate (background and washes) renders once
                /// and drifts slowly; the card, text and chrome ride in the
                /// pinned overlay on top. This is what separates a photo
                /// reel from a slideshow of frozen frames.
                var plateDeck = deck
                plateDeck.slides[index].layers = []
                plateDeck.slides[index].card = nil
                plateDeck.brand.showsFooter = false
                let plate = try SlideRenderer.render(deck: plateDeck, slideIndex: index)
                let overlay = try SlideRenderer.renderOverlay(deck: deck, slideIndex: index)
                let slideDuration = duration
                makeFrame = { time in
                    let progress = min(max(time / slideDuration, 0), 1)
                    /// Pull-out plays the same travel in reverse.
                    let travel = drift.direction == .in ? progress : 1 - progress
                    let zoom = 1 + drift.intensity * travel
                    guard let context = CGContext(
                        data: nil, width: width, height: height,
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    ) else { throw ExportError.writerCreationFailed("no motion context") }
                    let w = Double(width) * zoom
                    let h = Double(height) * zoom
                    var x = (Double(width) - w) / 2
                    var y = (Double(height) - h) / 2
                    if let pan = drift.pan {
                        /// Drift toward the pan edge, spending the zoom
                        /// headroom so the plate never shows its border.
                        let vector = pan.vector(width: 1, height: 1)
                        x -= vector.dx * (w - Double(width)) / 2 * travel
                        y -= vector.dy * (h - Double(height)) / 2 * travel
                    }
                    context.draw(plate, in: CGRect(x: x, y: y, width: w, height: h))
                    let frameOverlay = time < settle
                        ? try SlideRenderer.renderOverlay(deck: deck, slideIndex: index, at: time)
                        : overlay
                    context.draw(frameOverlay, in: CGRect(x: 0, y: 0, width: width, height: height))
                    guard let image = context.makeImage() else {
                        throw ExportError.writerCreationFailed("no motion frame")
                    }
                    return image
                }
            } else {
                /// A held still — the cheap case, except while entering.
                let still = try SlideRenderer.render(deck: deck, slideIndex: index)
                makeFrame = { time in
                    time < settle
                        ? try SlideRenderer.render(deck: deck, slideIndex: index, at: time)
                        : still
                }
            }

            segments.append(Segment(start: cursor, duration: duration, narrationURL: narrationURL, makeFrame: makeFrame))
            cursor += duration
        }

        let total = cursor
        let cuts = segments.dropFirst().map(\.start)
        let narrations = segments.compactMap { segment in
            segment.narrationURL.map { (url: $0, at: segment.start) }
        }

        let soundEffects: [(url: URL, at: Double)]
        if let sfx = try transitionSound.resolve() {
            soundEffects = cuts.map { (url: sfx.url, at: max(0, $0 - sfx.lead)) }
        } else {
            soundEffects = []
        }

        let needsAudioPass = !narrations.isEmpty || deck.musicPath != nil || !soundEffects.isEmpty
        let writerTarget = needsAudioPass
            ? url.deletingLastPathComponent().appendingPathComponent(".mix-\(url.lastPathComponent)")
            : url
        defer { if writerTarget != url { try? FileManager.default.removeItem(at: writerTarget) } }

        try await write(
            width: width, height: height,
            duration: total, framesPerSecond: framesPerSecond,
            to: writerTarget
        ) { time in
            let index = (segments.lastIndex { $0.start <= time }) ?? 0
            let segment = segments[index]

            /// A segment can be asked for a frame slightly outside its own
            /// range during a cross-frame overlap — video sources just keep
            /// decoding (looping at the end), stills hold.
            func frame(of other: Segment) throws -> CGImage {
                try other.makeFrame(max(0, time - other.start))
            }

            if transition.needsBothFrames {
                /// Cross-frame window centered on the cut, progress 0 → 1
                /// as the incoming slide takes over.
                let window = max(0.1, transitionDuration)
                if index > 0, time < segment.start + window / 2 {
                    let progress = 0.5 + (time - segment.start) / window
                    return try composeCross(
                        transition,
                        outgoing: frame(of: segments[index - 1]),
                        incoming: frame(of: segment),
                        progress: progress, width: width, height: height
                    )
                }
                if index < segments.count - 1 {
                    let cut = segments[index + 1].start
                    if time > cut - window / 2 {
                        let progress = (time - (cut - window / 2)) / window
                        return try composeCross(
                            transition,
                            outgoing: frame(of: segment),
                            incoming: frame(of: segments[index + 1]),
                            progress: progress, width: width, height: height
                        )
                    }
                }
                return try segment.makeFrame(time - segment.start)
            }

            var composed = try segment.makeFrame(time - segment.start)

            /// The cut envelope: strength rises to 1 at the boundary frame
            /// and falls away over half the transition duration each side —
            /// CutRender's contract.
            let envelope = max(0.05, transitionDuration / 2)
            if case .cut(let style) = transition,
               let cut = cuts.min(by: { abs($0 - time) < abs($1 - time) }),
               abs(time - cut) < envelope {
                composed = applyTransition(style, strength: 1 - abs(time - cut) / envelope, to: composed)
            }
            return composed
        }

        if needsAudioPass {
            let bed = deck.musicPath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            try await composeAudio(video: writerTarget, narrations: narrations, bed: bed, soundEffects: soundEffects, output: url)
        }
    }

    /// Background + washes + overlay, one frame.
    private static func composeFrame(
        background: CGImage, washes: CGImage?, overlay: CGImage, width: Int, height: Int
    ) throws -> CGImage {
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ExportError.writerCreationFailed("no compose context") }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        SlideRenderer.drawAspectFilled(background, in: context, bounds: bounds)
        if let washes { context.draw(washes, in: bounds) }
        context.draw(overlay, in: bounds)
        guard let image = context.makeImage() else {
            throw ExportError.writerCreationFailed("no composed frame")
        }
        return image
    }

    /// One transition frame. Dips and the punch are plain CoreGraphics;
    /// the rest go through CutRender's CoreImage pipeline.
    private static func applyTransition(_ style: CutStyle, strength: Double, to frame: CGImage) -> CGImage {
        if CutRender.needsCoreImage(style) {
            let input = CIImage(cgImage: frame)
            let output = CutRender.apply(style: style, strength: strength, to: input)
            return SlideRenderer.ciContext.createCGImage(output, from: input.extent) ?? frame
        }

        guard let context = CGContext(
            data: nil, width: frame.width, height: frame.height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return frame }
        let bounds = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)

        switch style {
        case .punchIn:
            let zoom = 1 + 0.08 * strength
            let size = CGSize(width: bounds.width * zoom, height: bounds.height * zoom)
            context.draw(frame, in: CGRect(
                x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                width: size.width, height: size.height
            ))
        case .dipToBlack, .dipToWhite:
            context.draw(frame, in: bounds)
            let dip: CGFloat = style == .dipToWhite ? 1 : 0
            context.setFillColor(CGColor(red: dip, green: dip, blue: dip, alpha: strength))
            context.fill(bounds)
        default:
            return frame
        }
        return context.makeImage() ?? frame
    }

    /// One cross-frame transition frame: both slides composited by
    /// progress. Push and wipe move with an ease-in-out so the motion
    /// reads as a gesture, not a linear slide.
    private static func composeCross(
        _ transition: SlideTransition,
        outgoing: CGImage,
        incoming: CGImage,
        progress: Double,
        width: Int,
        height: Int
    ) throws -> CGImage {
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ExportError.writerCreationFailed("no transition context") }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let p = min(max(progress, 0), 1)
        /// Smoothstep — starts and lands gently.
        let eased = p * p * (3 - 2 * p)

        switch transition {
        case .crossfade:
            context.draw(outgoing, in: bounds)
            context.setAlpha(CGFloat(p))
            context.draw(incoming, in: bounds)

        case .blurDissolve:
            /// Blur peaks mid-transition and relaxes as the incoming slide
            /// lands — the soft dissolve.
            let radius = sin(p * .pi) * 24
            context.draw(blurred(outgoing, radius: radius), in: bounds)
            context.setAlpha(CGFloat(p))
            context.draw(blurred(incoming, radius: radius), in: bounds)

        case .push(let edge):
            let (dx, dy) = edge.vector(width: Double(width), height: Double(height))
            context.draw(outgoing, in: bounds.offsetBy(dx: -dx * eased, dy: -dy * eased))
            context.draw(incoming, in: bounds.offsetBy(dx: dx * (1 - eased), dy: dy * (1 - eased)))

        case .cover(let edge):
            let (dx, dy) = edge.vector(width: Double(width), height: Double(height))
            context.draw(outgoing, in: bounds)
            context.draw(incoming, in: bounds.offsetBy(dx: dx * (1 - eased), dy: dy * (1 - eased)))

        case .reveal(let edge):
            let (dx, dy) = edge.vector(width: Double(width), height: Double(height))
            context.draw(incoming, in: bounds)
            context.draw(outgoing, in: bounds.offsetBy(dx: dx * eased, dy: dy * eased))

        case .wipe(let edge):
            context.draw(outgoing, in: bounds)
            context.saveGState()
            context.clip(to: edge.revealRect(progress: eased, in: bounds))
            context.draw(incoming, in: bounds)
            context.restoreGState()

        case .iris:
            context.draw(outgoing, in: bounds)
            let radius = hypot(bounds.width, bounds.height) / 2 * eased
            context.saveGState()
            context.addEllipse(in: CGRect(
                x: bounds.midX - radius, y: bounds.midY - radius,
                width: radius * 2, height: radius * 2
            ))
            context.clip()
            context.draw(incoming, in: bounds)
            context.restoreGState()

        case .zoom(let direction):
            switch direction {
            case .in:
                context.draw(outgoing, in: bounds)
                let scale = 0.65 + 0.35 * eased
                let w = bounds.width * scale
                let h = bounds.height * scale
                context.setAlpha(CGFloat(p))
                context.draw(incoming, in: CGRect(
                    x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h
                ))
            case .out:
                context.draw(incoming, in: bounds)
                let scale = 1 - 0.35 * eased
                let w = bounds.width * scale
                let h = bounds.height * scale
                context.setAlpha(CGFloat(1 - p))
                context.draw(outgoing, in: CGRect(
                    x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h
                ))
            }

        case .none, .cut:
            context.draw(incoming, in: bounds)
        }

        guard let image = context.makeImage() else {
            throw ExportError.writerCreationFailed("no transition frame")
        }
        return image
    }

    /// Gaussian blur via the shared Core Image context — the blur
    /// dissolve's working part.
    private static func blurred(_ image: CGImage, radius: Double) -> CGImage {
        guard radius > 0.5 else { return image }
        let input = CIImage(cgImage: image)
        let output = input
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: input.extent)
        return SlideRenderer.ciContext.createCGImage(output, from: input.extent) ?? image
    }

    /// Narrations at their offsets, the bed looped under the whole cut —
    /// a real mixdown, since platforms re-encode uploads and keep only the
    /// mixed result.
    private static func composeAudio(
        video: URL,
        narrations: [(url: URL, at: Double)],
        bed: URL?,
        soundEffects: [(url: URL, at: Double)] = [],
        output: URL
    ) async throws {
        let source = AVURLAsset(url: video)
        let composition = AVMutableComposition()
        let duration = try await source.load(.duration)

        guard let sourceVideo = try await source.loadTracks(withMediaType: .video).first,
              let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ExportError.writerCreationFailed("no video track to mix over")
        }
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideo, at: .zero)

        var mixParameters: [AVMutableAudioMixInputParameters] = []

        if !narrations.isEmpty,
           let narrationTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            for narration in narrations {
                let asset = AVURLAsset(url: narration.url)
                guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
                    throw ExportError.unreadableAudio(narration.url.path)
                }
                let narrationDuration = try await asset.load(.duration)
                try narrationTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: narrationDuration),
                    of: track,
                    at: CMTime(seconds: narration.at, preferredTimescale: 600)
                )
            }
            let parameters = AVMutableAudioMixInputParameters(track: narrationTrack)
            parameters.setVolume(1.0, at: .zero)
            mixParameters.append(parameters)
        }

        if !soundEffects.isEmpty,
           let sfxTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            for effect in soundEffects {
                let asset = AVURLAsset(url: effect.url)
                guard let track = try await asset.loadTracks(withMediaType: .audio).first else { continue }
                let effectDuration = try await asset.load(.duration)
                try sfxTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: effectDuration),
                    of: track,
                    at: CMTime(seconds: effect.at, preferredTimescale: 600)
                )
            }
            let parameters = AVMutableAudioMixInputParameters(track: sfxTrack)
            parameters.setVolume(0.55, at: .zero)
            mixParameters.append(parameters)
        }

        if let bed {
            let music = AVURLAsset(url: bed)
            guard let musicSource = try await music.loadTracks(withMediaType: .audio).first,
                  let musicTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw ExportError.unreadableAudio(bed.path)
            }
            let musicDuration = try await music.load(.duration)
            var bedCursor = CMTime.zero
            while bedCursor < duration {
                let remaining = CMTimeSubtract(duration, bedCursor)
                let chunk = CMTimeMinimum(musicDuration, remaining)
                try musicTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: chunk),
                    of: musicSource,
                    at: bedCursor
                )
                bedCursor = CMTimeAdd(bedCursor, chunk)
            }
            let bedParameters = AVMutableAudioMixInputParameters(track: musicTrack)
            bedParameters.setVolume(0.22, at: .zero)
            mixParameters.append(bedParameters)
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = mixParameters

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.writerCreationFailed("no export session")
        }
        session.audioMix = audioMix
        try? FileManager.default.removeItem(at: output)
        do {
            try await session.export(to: output, as: .mp4)
        } catch {
            /// A failed mixdown must not leave a half-written file where the
            /// finished reel was promised.
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    // MARK: - Music bed

    /// Lay a music bed under whatever audio the intermediate already carries.
    ///
    /// A real mixdown, not a second raw track — platforms re-encode uploads
    /// and reliably keep only the mixed result. Narration stays at full
    /// volume; the bed sits well under it, looped or trimmed to the video's
    /// length.
    private static func mixMusic(bed: URL, into intermediate: URL, output: URL) async throws {
        let source = AVURLAsset(url: intermediate)
        let music = AVURLAsset(url: bed)

        let composition = AVMutableComposition()
        let duration = try await source.load(.duration)

        guard let sourceVideo = try await source.loadTracks(withMediaType: .video).first,
              let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ExportError.writerCreationFailed("no video track to mix over")
        }
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideo, at: .zero)

        var mixParameters: [AVMutableAudioMixInputParameters] = []

        if let narration = try await source.loadTracks(withMediaType: .audio).first,
           let narrationTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try narrationTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: narration, at: .zero)
            let parameters = AVMutableAudioMixInputParameters(track: narrationTrack)
            parameters.setVolume(1.0, at: .zero)
            mixParameters.append(parameters)
        }

        guard let musicSource = try await music.loadTracks(withMediaType: .audio).first,
              let musicTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ExportError.unreadableAudio(bed.path)
        }
        /// Loop the bed until it covers the video.
        let musicDuration = try await music.load(.duration)
        var cursor = CMTime.zero
        while cursor < duration {
            let remaining = CMTimeSubtract(duration, cursor)
            let chunk = CMTimeMinimum(musicDuration, remaining)
            try musicTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: chunk),
                of: musicSource,
                at: cursor
            )
            cursor = CMTimeAdd(cursor, chunk)
        }
        let bedParameters = AVMutableAudioMixInputParameters(track: musicTrack)
        bedParameters.setVolume(0.22, at: .zero)
        mixParameters.append(bedParameters)

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = mixParameters

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.writerCreationFailed("no export session")
        }
        session.audioMix = audioMix
        try? FileManager.default.removeItem(at: output)
        do {
            try await session.export(to: output, as: .mp4)
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    // MARK: - Frame-source primitive

    /// Write a video from a frame closure — the primitive the high-level
    /// export sits on, public so callers can synthesize footage (the spike
    /// builds its motion background with it, every frame still coming from
    /// the one renderer).
    public static func write(
        width: Int,
        height: Int,
        duration: Double,
        framesPerSecond: Int = 30,
        narrationURL: URL? = nil,
        to url: URL,
        frame: @escaping (Double) throws -> CGImage
    ) async throws {
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        /// A failed export must not leave a half-written MP4 behind: it
        /// opens, plays a few seconds, and passes for the real thing in
        /// any pipeline that only checks the file exists.
        do {
            try await writeOrLeavePartial(
                width: width, height: height, duration: duration,
                framesPerSecond: framesPerSecond, narrationURL: narrationURL,
                to: url, frame: frame
            )
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private static func writeOrLeavePartial(
        width: Int,
        height: Int,
        duration: Double,
        framesPerSecond: Int,
        narrationURL: URL?,
        to url: URL,
        frame: @escaping (Double) throws -> CGImage
    ) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        /// Tagged BT.709: the frames are drawn sRGB, and an untagged H.264
        /// stream is guessed at by every player — the same reel washed out
        /// in one app and not another is the classic untagged-color bug.
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        ])
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        writer.add(videoInput)

        /// Narration goes in as mono AAC; the writer transcodes whatever PCM
        /// the reader hands it, so `say`'s AIFF and a studio WAV both work.
        var audioReader: AVAssetReader?
        var audioOutput: AVAssetReaderTrackOutput?
        var audioInput: AVAssetWriterInput?
        if let narrationURL {
            let asset = AVURLAsset(url: narrationURL)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
                throw ExportError.unreadableAudio(narrationURL.path)
            }
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM
            ])
            reader.add(output)

            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 96_000
            ])
            input.expectsMediaDataInRealTime = false
            writer.add(input)

            audioReader = reader
            audioOutput = output
            audioInput = input
        }

        guard writer.startWriting() else {
            throw ExportError.writerCreationFailed(writer.error?.localizedDescription ?? "unknown")
        }
        writer.startSession(atSourceTime: .zero)

        /// The writer pumps inputs via `requestMediaDataWhenReady` — the one
        /// documented contract; bare readiness-polling stopped being serviced
        /// on macOS 27. Both pumps run CONCURRENTLY: with more than one input
        /// the writer interleaves media, refusing more video until matching
        /// audio arrives — pumping one to completion first starves the other
        /// and the export hangs at zero bytes.
        let queue = DispatchQueue(label: "slidekit.video-export")
        let frameCount = max(1, Int((duration * Double(framesPerSecond)).rounded()))

        if let reader = audioReader {
            guard reader.startReading() else {
                throw ExportError.unreadableAudio(narrationURL?.path ?? "?")
            }
        }

        /// Boxed on this side of the concurrency boundary — see `UncheckedBox`.
        let videoBox = UncheckedBox((input: videoInput, adaptor: adaptor, frame: frame))
        async let videoDone: Void = pumpVideo(
            box: videoBox,
            frameCount: frameCount, framesPerSecond: framesPerSecond,
            width: width, height: height, queue: queue
        )
        if let output = audioOutput, let input = audioInput {
            let audioBox = UncheckedBox((input: input, output: output))
            async let audioDone: Void = pumpAudio(box: audioBox, queue: queue)
            try await videoDone
            await audioDone
        } else {
            try await videoDone
        }

        /// A decode error and a clean end of file both come back as "no more
        /// samples" from the reader — only the status tells them apart, and
        /// mistaking one for the other ships a reel whose narration stops
        /// mid-sentence.
        if let reader = audioReader, reader.status == .failed {
            throw ExportError.unreadableAudio(narrationURL?.path ?? "?")
        }

        await writer.finishWriting()
        if let error = writer.error {
            throw ExportError.writerCreationFailed(error.localizedDescription)
        }
    }

    // MARK: - Pumps

    /// Frames in, on the writer's schedule. State lives in a box confined to
    /// the pump queue.
    private static func pumpVideo(
        box: UncheckedBox<(input: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor, frame: (Double) throws -> CGImage)>,
        frameCount: Int,
        framesPerSecond: Int,
        width: Int,
        height: Int,
        queue: DispatchQueue
    ) async throws {
        final class Pump: @unchecked Sendable {
            var index = 0
            var done = false
        }
        let pump = Pump()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            box.value.input.requestMediaDataWhenReady(on: queue) {
                guard !pump.done else { return }
                while box.value.input.isReadyForMoreMediaData {
                    if pump.index >= frameCount {
                        pump.done = true
                        box.value.input.markAsFinished()
                        continuation.resume()
                        return
                    }

                    do {
                        let image = try box.value.frame(Double(pump.index) / Double(framesPerSecond))
                        guard let pool = box.value.adaptor.pixelBufferPool else {
                            throw ExportError.writerCreationFailed("no pixel buffer pool")
                        }
                        var pixelBuffer: CVPixelBuffer?
                        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
                        guard let buffer = pixelBuffer else {
                            throw ExportError.writerCreationFailed("no pixel buffer")
                        }

                        CVPixelBufferLockBaseAddress(buffer, [])
                        if let bitmap = CGContext(
                            data: CVPixelBufferGetBaseAddress(buffer),
                            width: width,
                            height: height,
                            bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
                        ) {
                            bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                        }
                        CVPixelBufferUnlockBaseAddress(buffer, [])

                        /// A refused append is the writer saying it has
                        /// already failed; pressing on drops frames silently
                        /// and ships a shorter reel than the deck describes.
                        guard box.value.adaptor.append(
                            buffer,
                            withPresentationTime: CMTime(value: CMTimeValue(pump.index), timescale: CMTimeScale(framesPerSecond))
                        ) else {
                            throw ExportError.writerCreationFailed(
                                "the writer refused frame \(pump.index)"
                            )
                        }
                        pump.index += 1
                    } catch {
                        pump.done = true
                        box.value.input.markAsFinished()
                        continuation.resume(throwing: error)
                        return
                    }
                }
            }
        }
    }

    /// Narration samples in, same schedule.
    private static func pumpAudio(
        box: UncheckedBox<(input: AVAssetWriterInput, output: AVAssetReaderTrackOutput)>,
        queue: DispatchQueue
    ) async {
        final class Pump: @unchecked Sendable {
            var done = false
        }
        let pump = Pump()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            box.value.input.requestMediaDataWhenReady(on: queue) {
                guard !pump.done else { return }
                while box.value.input.isReadyForMoreMediaData {
                    guard let sample = box.value.output.copyNextSampleBuffer(),
                          box.value.input.append(sample) else {
                        /// End of samples, or an append the writer refused —
                        /// either way this pump is done; the reader's status
                        /// and the writer's error are checked by the caller.
                        pump.done = true
                        box.value.input.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }
    }

    /// AVFoundation's writer types predate Sendable; every touch happens on
    /// the single pump queue, which is the actual safety argument.
    private final class UncheckedBox<Value>: @unchecked Sendable {
        let value: Value
        init(_ value: Value) { self.value = value }
    }

    // MARK: - Background decode

    /// Sequential frames from a background video, looping when it ends —
    /// a four-second loop happily backs a twelve-second narration.
    private final class BackgroundFrameSource {

        private let url: URL
        private let asset: AVURLAsset
        private let track: AVAssetTrack
        private var reader: AVAssetReader
        private var output: AVAssetReaderTrackOutput

        /// Track loading is async and happens exactly once — the synchronous
        /// `tracks(withMediaType:)` deadlocks when awaited-upon machinery and
        /// the caller share an actor, which is precisely how this class gets
        /// used. Loop rewinds reuse the loaded track; only the reader is new.
        init(url: URL) async throws {
            self.url = url
            asset = AVURLAsset(url: url)
            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                throw ExportError.unreadableVideo(url.path)
            }
            track = videoTrack
            (reader, output) = try Self.openReader(asset: asset, track: track, url: url)
        }

        func next() throws -> CGImage {
            if let sample = output.copyNextSampleBuffer(),
               let image = Self.image(from: sample) {
                return image
            }
            /// End of the loop — rewind by reopening the reader over the
            /// already-loaded track.
            reader.cancelReading()
            (reader, output) = try Self.openReader(asset: asset, track: track, url: url)
            guard let sample = output.copyNextSampleBuffer(),
                  let image = Self.image(from: sample) else {
                throw ExportError.unreadableVideo(url.path)
            }
            return image
        }

        private static func openReader(
            asset: AVURLAsset,
            track: AVAssetTrack,
            url: URL
        ) throws -> (AVAssetReader, AVAssetReaderTrackOutput) {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ])
            reader.add(output)
            guard reader.startReading() else {
                throw ExportError.unreadableVideo(url.path)
            }
            return (reader, output)
        }

        private static func image(from sample: CMSampleBuffer) -> CGImage? {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
            var image: CGImage?
            VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image)
            return image
        }
    }
}
