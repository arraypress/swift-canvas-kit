//
//  SlideTransition.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//

import Foundation
import VideoGrade

/// How the stitched reel treats a slide boundary.
///
/// Two families. `cut` styles are single-frame envelope effects from
/// VideoGrade's CutRender — the frame at the boundary gets dipped, blurred,
/// glitched — and read as an edit. Cross-frame styles (`crossfade`, `push`,
/// `wipe`) composite the outgoing and incoming slides together across the
/// boundary and read as motion.
public enum SlideTransition: Equatable, Sendable {

    /// Hard cut.
    case none

    /// A CutRender envelope on the boundary frames: `.cut(.whipPan)`,
    /// `.cut(.dipToBlack)`, `.cut(.zoomBlur)`, `.cut(.glitch)`,
    /// `.cut(.punchIn)`, `.cut(.dipToWhite)`.
    case cut(CutStyle)

    /// The incoming slide fades in over the outgoing one.
    case crossfade

    /// A crossfade through a gaussian blur — the soft dissolve.
    case blurDissolve

    /// The incoming slide pushes the outgoing one off the canvas.
    case push(from: Edge)

    /// The incoming slide travels in OVER the outgoing one, which stays put.
    case cover(from: Edge)

    /// The outgoing slide travels away, revealing the incoming one beneath.
    case reveal(to: Edge)

    /// The incoming slide is revealed by a moving edge.
    case wipe(from: Edge)

    /// A growing circle from the center reveals the incoming slide.
    case iris

    /// The incoming slide scales up from the center (`.in`), or the
    /// outgoing slide shrinks away (`.out`).
    case zoom(Direction)

    public enum Direction: String, Equatable, Sendable {
        case `in`, out
    }

    /// Which edge the incoming slide arrives from.
    public enum Edge: String, Equatable, Sendable {
        case leading, trailing, top, bottom
    }

    /// Cross-frame transitions composite two slides and need a wider
    /// window than the cut envelope.
    var needsBothFrames: Bool {
        switch self {
        case .none, .cut: return false
        default: return true
        }
    }
}

import CoreGraphics

extension SlideTransition.Edge {

    /// Where the incoming slide STARTS, as an offset from center
    /// (CoreGraphics coordinates, origin bottom-left): `.trailing` starts
    /// a full width to the right and travels left over the outgoing slide.
    func vector(width: Double, height: Double) -> (dx: Double, dy: Double) {
        switch self {
        case .trailing: return (width, 0)
        case .leading: return (-width, 0)
        case .top: return (0, height)
        case .bottom: return (0, -height)
        }
    }

    /// The revealed region at `progress`, growing from this edge.
    func revealRect(progress: Double, in bounds: CGRect) -> CGRect {
        let w = bounds.width * progress
        let h = bounds.height * progress
        switch self {
        case .trailing: return CGRect(x: bounds.maxX - w, y: 0, width: w, height: bounds.height)
        case .leading: return CGRect(x: 0, y: 0, width: w, height: bounds.height)
        case .top: return CGRect(x: 0, y: bounds.maxY - h, width: bounds.width, height: h)
        case .bottom: return CGRect(x: 0, y: 0, width: bounds.width, height: h)
        }
    }
}


/// What still slides do with their time in a stitched reel.
///
/// A held frame reads as a slideshow of frozen images; the Ken Burns
/// drift — the plate slowly moving under pinned text — is what makes
/// photo decks read as video. Video-backed slides already move and are
/// left alone.
public enum SlideMotion: Equatable, Sendable {

    /// Hold every still exactly as rendered.
    case none

    /// The plate drifts over the slide: `intensity` is the fraction of
    /// zoom applied across the slide's duration (0.07 reads as cinematic,
    /// 0.15 as energetic), `direction` pushes in or pulls out, and `pan`
    /// adds a slow drift toward that edge.
    case kenBurns(intensity: Double, direction: Direction, pan: Edge?)

    /// Ken Burns with the direction flipping per slide — even slides push
    /// in, odd slides pull out. The polished-slideshow default rhythm.
    case kenBurnsAlternating(intensity: Double)

    /// The default: a centered 7% push-in.
    public static let kenBurns = SlideMotion.kenBurns(intensity: 0.07, direction: .in, pan: nil)

    public typealias Direction = SlideTransition.Direction
    public typealias Edge = SlideTransition.Edge

    /// The drift a given slide gets, or `nil` to hold the frame.
    func drift(forSlide index: Int) -> (intensity: Double, direction: Direction, pan: Edge?)? {
        switch self {
        case .none:
            return nil
        case .kenBurns(let intensity, let direction, let pan):
            return (intensity, direction, pan)
        case .kenBurnsAlternating(let intensity):
            return (intensity, index.isMultiple(of: 2) ? .in : .out, nil)
        }
    }
}


/// The sound under each slide boundary, mixed into the composition pass.
public enum TransitionSound: Equatable, Sendable {

    /// Silence.
    case none

    /// Synthesized band-swept whoosh, centered on the cut.
    case whoosh

    /// Synthesized pitch-drop blip, right on the cut.
    case pop

    /// Synthesized noise crescendo landing exactly on the cut.
    case riser

    /// A caller-supplied file, started shortly before the cut.
    case file(String)

    /// The audio to place, and how far before the cut it starts so its
    /// energy peaks on the boundary.
    func resolve() throws -> (url: URL, lead: Double)? {
        switch self {
        case .none:
            return nil
        case .whoosh:
            return (try SFXSynth.url(for: .whoosh), 0.28)
        case .pop:
            return (try SFXSynth.url(for: .pop), 0)
        case .riser:
            return (try SFXSynth.url(for: .riser), 0.78)
        case .file(let path):
            return (URL(fileURLWithPath: (path as NSString).expandingTildeInPath), 0.15)
        }
    }
}
