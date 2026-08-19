//
//  Contrast.swift
//  CanvasKit
//
//  Created by David Sherlock, 2026.
//
//  Whether the words can be seen against what is behind them.
//
//  The audit already caught a token nobody filled and a line that ran off the
//  edge — both failures you can see. It said "clean" about a slide whose body
//  text was white on cream, which you also can see, and which is the worse
//  failure because the render succeeds and the file is fine and nobody looks
//  at slide four until it is posted.
//
//  It happens most often to a design somebody customised halfway: a dark
//  template given a light background, where the heading was recoloured and
//  the secondary text was not. That is a good bug to catch, because the
//  person who introduced it was being careful.
//
//  ## What this does not do
//
//  Text over a photograph is not checked. The honest reason is that the
//  answer depends on the pixels under each glyph — a caption can be perfectly
//  readable over the dark half of a picture and vanish over the bright half —
//  and a number averaged over the whole plate would be a number that is wrong
//  in both halves. A scrim exists for exactly that, and whether it is deep
//  enough is a judgement about a photograph. Guessing would produce warnings
//  people learn to ignore, which costs more than the warning is worth.
//

import CoreGraphics
import Foundation

enum Contrast {

    /// The WCAG ratio between two colours, 1 (identical) to 21 (black on
    /// white).
    static func ratio(_ one: SlideColor, on other: SlideColor) -> Double {
        let a = luminance(of: one)
        let b = luminance(of: other)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// WCAG relative luminance.
    private static func luminance(of color: SlideColor) -> Double {
        guard let components = color.cgColor.components, components.count >= 3 else { return 0 }

        func linear(_ channel: CGFloat) -> Double {
            let value = Double(channel)
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linear(components[0])
            + 0.7152 * linear(components[1])
            + 0.0722 * linear(components[2])
    }

    /// A colour laid over another at its own alpha — what the eye actually
    /// sees, and what has to be compared.
    ///
    /// Text at 60% on a light ground is a lighter grey than its hex says, and
    /// the commonest way a palette half-changed goes wrong is a translucent
    /// secondary colour that was fine over black.
    static func composited(_ color: SlideColor, over ground: SlideColor) -> SlideColor {
        guard let top = color.cgColor.components, top.count >= 3,
              let bottom = ground.cgColor.components, bottom.count >= 3
        else { return color }

        let alpha = Double(color.cgColor.alpha)
        guard alpha < 1 else { return color }

        func blend(_ index: Int) -> Int {
            let mixed = Double(top[index]) * alpha + Double(bottom[index]) * (1 - alpha)
            return Int((mixed * 255).rounded())
        }

        return SlideColor(String(format: "#%02X%02X%02X", blend(0), blend(1), blend(2)))
    }

    /// The colour behind a slide's text, where that is a colour at all.
    ///
    /// A card counts, and counting it is most of what makes this check
    /// usable: the whole genre puts the words on a light card over a coloured
    /// ground, and comparing the ink to the ground rather than to the card
    /// condemned every one of those designs. The card is composited over
    /// whatever is behind it, because they are often translucent.
    ///
    /// - Returns: `nil` for a photograph or a video under a card that does
    ///   not hide it, which is not one colour and cannot be judged as one.
    static func backdrop(of slide: Slide, in deck: SlideDeck) -> SlideColor? {
        let ground: SlideColor?

        switch deck.resolvedBackground(for: slide) {
        case .solid(let color):
            ground = color

        case .linearGradient(let colors, _):
            /// The worst stop rather than the average: a headline that clears
            /// the light end of a gradient and disappears into the dark end
            /// is not a headline that passes.
            ground = colors.min { luminance(of: $0) < luminance(of: $1) }

        case .image, .video:
            ground = nil
        }

        guard let card = slide.card else { return ground }

        /// An opaque card hides the plate, so a photograph behind one is
        /// judgeable after all.
        guard let ground else {
            return Double(card.color.cgColor.alpha) >= 0.99 ? card.color : nil
        }
        return composited(card.color, over: ground)
    }

    /// Below this, the text cannot be read at all.
    ///
    /// WCAG asks 4.5 for body text and 3 for large, and the first version of
    /// this used 3. It fired on 144 of the 288 built-in templates, which is
    /// not a library that fails an accessibility standard — it is a check
    /// measuring the wrong thing. These are display graphics at forty points
    /// and up over backgrounds somebody chose, and a soft secondary line at
    /// 2.5 is a decision, not a defect. A warning that fires on half the
    /// gallery is a warning people turn off, and then it is not there on the
    /// day it would have helped.
    ///
    /// So this is set where judgement stops and fact starts: below 2 the
    /// words are not dim, they are gone.
    static let invisible = 2.0

    /// Text fainter than this is decoration, not copy.
    ///
    /// The other half of the false positives were oversized glyphs at ten or
    /// fifteen per cent — the giant watermark "?" behind a question slide,
    /// the numeral ghosted behind a step. Those are meant to be barely
    /// visible. Anything a reader is expected to read is set well above this.
    static let decorative = 0.3
}
