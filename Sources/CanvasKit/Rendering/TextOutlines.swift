//
//  TextOutlines.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//
//  The same layout TextDrawer draws, handed back as shapes and lines rather
//  than pixels: every glyph's outline where it lands, in its colour, and
//  every line's words, face and position — for a caller that bends words
//  along a path, extrudes them, strokes inside them, or writes them into a
//  vector file (SVG) as text.
//

import CoreGraphics
import CoreText
import Foundation

/// One glyph as drawn: its outline at the drawn size, where its baseline
/// starts in the context, its advance, its ink and the character it draws.
public struct GlyphOutline {
    /// The outline, origin at the glyph's baseline start.
    public let path: CGPath
    /// Where that origin is, in the context's coordinates (CoreGraphics, origin bottom-left).
    public let origin: CGPoint
    public let advance: CGFloat
    public let color: CGColor
    /// The character (grapheme) of the drawn text it belongs to.
    public let character: Int

    public init(path: CGPath, origin: CGPoint, advance: CGFloat, color: CGColor, character: Int) {
        self.path = path
        self.origin = origin
        self.advance = advance
        self.color = color
        self.character = character
    }

    /// The outline moved to where it lands.
    public var placed: CGPath {
        var transform = CGAffineTransform(translationX: origin.x, y: origin.y)
        return path.copy(using: &transform) ?? path
    }
}

/// One run of a line: a stretch in one face and one colour.
public struct TextRunLayout {
    public let text: String
    /// The face's PostScript name and family.
    public let fontName: String
    public let family: String
    public let size: CGFloat
    /// CoreText's weight trait, −1…1 (0 regular, 0.4 bold).
    public let weight: Double
    public let italic: Bool
    public let color: CGColor
    /// Where the run starts, from the line's origin.
    public let x: CGFloat
    /// How far the run sits above the line's baseline.
    public let rise: CGFloat
    /// Extra space after each character, in pixels.
    public let tracking: CGFloat
}

/// One line as drawn.
public struct TextLineLayout {
    public let text: String
    /// The baseline's start, in the context's coordinates.
    public let origin: CGPoint
    public let width: CGFloat
    public let ascent: CGFloat
    public let descent: CGFloat
    public let runs: [TextRunLayout]
}

/// A text block's layout as shapes and lines.
public struct TextOutlines {
    public let fit: TextFit
    public let glyphs: [GlyphOutline]
    public let lines: [TextLineLayout]
    /// The text as drawn (markup removed, cased).
    public let text: String

    public init(fit: TextFit, glyphs: [GlyphOutline], lines: [TextLineLayout], text: String) {
        self.fit = fit
        self.glyphs = glyphs
        self.lines = lines
        self.text = text
    }

    /// Every glyph outline where it lands, as one path.
    public var path: CGPath {
        let combined = CGMutablePath()
        for glyph in glyphs { combined.addPath(glyph.placed) }
        return combined
    }
}

extension TextDrawer {

    /// `text` laid out in `region` exactly as ``draw(text:style:in:verticalAlignment:context:scale:)``
    /// draws it, as outlines and lines instead of pixels.
    public static func outlines(
        text: String,
        style: TextStyle,
        in region: CGRect,
        verticalAlignment: String,
        scale: CGFloat
    ) -> TextOutlines? {
        guard let fitted = fitted(text: text, style: style, brand: BrandKit(), in: region,
                                  verticalAlignment: verticalAlignment, scale: scale) else { return nil }
        guard let lines = CTFrameGetLines(fitted.frame) as? [CTLine] else { return nil }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(fitted.frame, CFRange(location: 0, length: 0), &origins)
        let absolute = origins.map { CGPoint(x: fitted.frameRect.minX + $0.x, y: fitted.frameRect.minY + $0.y) }
        return collect(lines: lines, origins: absolute, attributed: fitted.attributed, fit: fitted.fit)
    }

    /// `text` on one line at `pointSize` (pixels), never wrapped or shrunk,
    /// its baseline starting at (0, 0) — for words set along a path.
    public static func line(text: String, style: TextStyle, pointSize: Double) -> TextOutlines? {
        guard !text.isEmpty else { return nil }
        let attributed = attributedString(text: text, style: style, brand: BrandKit(), pointSize: pointSize)
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let rect = CGRect(x: 0, y: -descent, width: width, height: ascent + descent)
        let fit = TextFit(pointSize: pointSize, fits: true, lineCount: 1, frame: rect, lineRects: [rect])
        return collect(lines: [line], origins: [.zero], attributed: attributed, fit: fit)
    }

    private static func collect(lines: [CTLine], origins: [CGPoint], attributed: CFAttributedString, fit: TextFit) -> TextOutlines {
        let string = CFAttributedStringGetString(attributed) as String
        let utf16 = Array(string.utf16)
        let offsets = CharacterOffsets(string)
        func substring(_ range: CFRange) -> String {
            let start = max(0, min(utf16.count, range.location)), end = max(start, min(utf16.count, range.location + range.length))
            return String(decoding: utf16[start..<end], as: UTF16.self)
        }
        var glyphs: [GlyphOutline] = []
        var layouts: [TextLineLayout] = []
        for (line, origin) in zip(lines, origins) {
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            var runs: [TextRunLayout] = []
            for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                let font = attributes[kCTFontAttributeName] as! CTFont
                let color = (attributes[kCTForegroundColorAttributeName]).map { $0 as! CGColor } ?? CGColor(gray: 0, alpha: 1)
                let count = CTRunGetGlyphCount(run)
                guard count > 0 else { continue }
                var ids = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                var advances = [CGSize](repeating: .zero, count: count)
                var indices = [CFIndex](repeating: 0, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &ids)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
                CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
                let rise = (attributes[kCTBaselineOffsetAttributeName] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
                for index in 0..<count {
                    guard let path = CTFontCreatePathForGlyph(font, ids[index], nil) else { continue }
                    glyphs.append(GlyphOutline(path: path,
                                               origin: CGPoint(x: origin.x + positions[index].x, y: origin.y + positions[index].y),
                                               advance: advances[index].width, color: color,
                                               character: offsets.character(atUTF16: indices[index])))
                }
                let traits = CTFontCopyTraits(font) as NSDictionary
                let weight = (traits[kCTFontWeightTrait] as? NSNumber)?.doubleValue ?? 0
                runs.append(TextRunLayout(
                    text: substring(CTRunGetStringRange(run)),
                    fontName: CTFontCopyPostScriptName(font) as String,
                    family: CTFontCopyFamilyName(font) as String,
                    size: CTFontGetSize(font), weight: weight,
                    italic: CTFontGetSymbolicTraits(font).contains(.traitItalic),
                    color: color, x: positions[0].x, rise: rise,
                    tracking: (attributes[kCTKernAttributeName] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0))
            }
            layouts.append(TextLineLayout(text: substring(CTLineGetStringRange(line)), origin: origin, width: width,
                                          ascent: ascent, descent: descent, runs: runs))
        }
        return TextOutlines(fit: fit, glyphs: glyphs, lines: layouts, text: string)
    }
}
