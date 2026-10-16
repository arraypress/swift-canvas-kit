//
//  TextDrawer.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import CoreText
import Foundation

/// CoreText layout and drawing for one styled text block.
///
/// Handles the three things templates rely on: `**accent**` span markup,
/// auto-shrink so variable-length content stays inside its region, and
/// vertical alignment within the region. Pure CoreText — no AppKit/UIKit.
public enum TextDrawer {

    /// Draw `text` inside `region` (a CoreGraphics rect, origin bottom-left)
    /// at `scale` pixels per style point, with no brand: a style's unset
    /// colours fall back to ``BrandKit``'s defaults. Returns where the text
    /// went and whether it fitted.
    @discardableResult
    public static func draw(
        text: String,
        style: TextStyle,
        in region: CGRect,
        verticalAlignment: String,
        context: CGContext,
        scale: CGFloat
    ) -> TextFit? {
        draw(text: text, style: style, brand: BrandKit(), in: region,
             verticalAlignment: verticalAlignment, context: context, scale: scale)
    }

    /// Where `text` would go inside `region` and at what size, without
    /// drawing it — for a caller that draws something behind the words (a
    /// plate sized to the lines) before the words themselves.
    public static func layout(
        text: String,
        style: TextStyle,
        in region: CGRect,
        verticalAlignment: String,
        scale: CGFloat
    ) -> TextFit? {
        fitted(text: text, style: style, brand: BrandKit(), in: region,
               verticalAlignment: verticalAlignment, scale: scale)?.fit
    }

    /// The fitted block: the auto-shrink loop, then the frame placed by
    /// vertical alignment.
    static func fitted(
        text: String,
        style: TextStyle,
        brand: BrandKit,
        in region: CGRect,
        verticalAlignment: String,
        scale: CGFloat
    ) -> (fit: TextFit, attributed: CFAttributedString, frame: CTFrame, frameRect: CGRect, size: Double)? {
        guard !text.isEmpty, region.width > 1, region.height > 1 else { return nil }

        var size = style.size * Double(scale)
        let minimum = style.minimumSize * Double(scale)
        var attributed = attributedString(text: text, style: style, brand: brand, pointSize: size)
        var height = measuredHeight(attributed, width: region.width)

        /// Auto-shrink: step the point size down until the block fits, or the
        /// floor is reached. Steps of 6% keep the loop short and the size
        /// changes invisible. A single word must additionally fit on ONE
        /// line — height-only fitting happily wraps "Ubiquitou / s" and
        /// calls it done, which is worse than a smaller word. A style with
        /// `maxLines` must also wrap to no more lines than that.
        let mustNotWrap = !text.contains(where: \.isWhitespace)
        let words = style.keepsWordsWhole ? text.split(whereSeparator: \.isWhitespace).map(String.init) : []
        func fits() -> Bool {
            if height > region.height { return false }
            if mustNotWrap, measuredWidth(attributed) > region.width { return false }
            if let maxLines = style.maxLines, lineCount(attributed, width: region.width) > maxLines { return false }
            if style.keepsWordsWhole, !mustNotWrap {
                for word in words where measuredWidth(attributedString(text: word, style: style, brand: brand, pointSize: size)) > region.width {
                    return false
                }
            }
            return true
        }
        while style.autoShrink, !fits(), size > minimum {
            size = max(minimum, size * 0.94)
            attributed = attributedString(text: text, style: style, brand: brand, pointSize: size)
            height = measuredHeight(attributed, width: region.width)
        }
        let fitted = fits()

        let textHeight = min(height, region.height)
        let y: CGFloat
        switch verticalAlignment {
        case "middle": y = region.minY + (region.height - textHeight) / 2
        case "bottom": y = region.minY
        default: y = region.maxY - textHeight
        }

        let frameRect = CGRect(x: region.minX, y: y, width: region.width, height: textHeight + 2)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: 0),
            CGPath(rect: frameRect, transform: nil),
            nil
        )
        let fit = TextFit(pointSize: size, fits: fitted, lineCount: lineCount(attributed, width: region.width),
                          frame: frameRect, lineRects: lineRects(of: frame, in: frameRect))
        return (fit, attributed, frame, frameRect, size)
    }

    /// Draw `text` inside `region` (a CoreGraphics rect, origin bottom-left).
    @discardableResult
    static func draw(
        text: String,
        style: TextStyle,
        brand: BrandKit,
        in region: CGRect,
        verticalAlignment: String,
        context: CGContext,
        scale: CGFloat,
        collector: WarningCollector? = nil
    ) -> TextFit? {
        guard let fitted = fitted(text: text, style: style, brand: brand, in: region,
                                  verticalAlignment: verticalAlignment, scale: scale) else { return nil }
        if !fitted.fit.fits, let collector {
            collector.report(style.autoShrink ? .shrunkToFloor(text: text) : .overflow(text: text))
        }
        let size = fitted.size
        let frameRect = fitted.frameRect
        let frame = fitted.frame

        context.saveGState()
        context.textMatrix = .identity

        /// Line pills draw first: one rounded rect per rendered line, sized
        /// to that line's typographic bounds — the highlighter/sticker idiom.
        if let pill = style.linePill {
            drawLinePills(for: frame, in: frameRect, color: pill, context: context, scale: scale)
        }

        /// Shadow applies to the glyphs only, never the pills — a glowing
        /// pill reads as a rendering bug, a glowing glyph reads as neon.
        if let shadow = style.shadowColor {
            context.setShadow(
                offset: CGSize(width: 0, height: -style.shadowOffsetY * scale),
                blur: style.shadowBlur * scale,
                color: Inks.converted(shadow.cgColor)
            )
        }

        if let gradient = style.gradientColors, gradient.count >= 2 {
            /// Gradient glyphs: when a glow is declared, a normal pass draws
            /// it first (the gradient pass clips, and clipped drawing casts
            /// no shadow), then the glyph outlines become the clip and the
            /// gradient fills them top to bottom.
            if style.shadowColor != nil {
                CTFrameDraw(frame, context)
                context.setShadow(offset: .zero, blur: 0, color: nil)
            }
            context.saveGState()
            context.textMatrix = .identity
            context.setTextDrawingMode(.clip)
            CTFrameDraw(frame, context)
            if let fill = CGGradient(
                colorsSpace: Inks.space ?? CGColorSpace(name: CGColorSpace.sRGB),
                colors: gradient.map { Inks.converted($0.cgColor) } as CFArray,
                locations: nil
            ) {
                context.drawLinearGradient(
                    fill,
                    start: CGPoint(x: frameRect.midX, y: frameRect.maxY),
                    end: CGPoint(x: frameRect.midX, y: frameRect.minY),
                    options: []
                )
            }
            context.restoreGState()
        } else if style.strokeStyle == .outlined, style.strokeWidth > 0 {
            /// Two passes, because CoreText's fill-and-stroke mode cannot do
            /// this cleanly. A glyph outline is often several overlapping
            /// subpaths — the diagonal of an N laid across its stems, the
            /// bowls of a B across its spine — and filling hides the seams
            /// while stroking draws every one of them. The result is a
            /// lightning bolt through the N and a ghost letter inside the A.
            ///
            /// So the keyline goes down first as stroke-only, and the fill
            /// covers it: what is left showing is the part of the stroke
            /// outside the glyph, which is the keyline that was wanted, and
            /// the seams inside are painted over.
            /// Twice the asked-for width, because CoreText centres a stroke
            /// on the outline: the fill pass covers the inner half, so a
            /// keyline drawn at the nominal width comes back half as heavy as
            /// the same number produces in hollow. Doubling here makes
            /// `strokeWidth` mean the same thickness in both treatments.
            let keyline = attributedString(
                text: text, style: style, brand: brand,
                pointSize: size, strokeOverride: style.strokeWidth * 2
            )
            CTFrameDraw(
                CTFramesetterCreateFrame(
                    CTFramesetterCreateWithAttributedString(keyline),
                    CFRange(location: 0, length: 0),
                    CGPath(rect: frameRect, transform: nil), nil
                ),
                context
            )

            /// The shadow belongs to the keyline pass only — casting it again
            /// from the fill doubles it into a smear.
            context.setShadow(offset: .zero, blur: 0, color: nil)

            let fill = attributedString(
                text: text, style: style, brand: brand,
                pointSize: size, strokeOverride: 0
            )
            CTFrameDraw(
                CTFramesetterCreateFrame(
                    CTFramesetterCreateWithAttributedString(fill),
                    CFRange(location: 0, length: 0),
                    CGPath(rect: frameRect, transform: nil), nil
                ),
                context
            )
        } else {
            CTFrameDraw(frame, context)
        }
        context.restoreGState()
        return fitted.fit
    }

    /// How many lines `attributed` wraps to at `width`.
    static func lineCount(_ attributed: CFAttributedString, width: CGFloat) -> Int {
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let frame = CTFramesetterCreateFrame(
            framesetter, CFRange(location: 0, length: 0),
            CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 1_000_000), transform: nil), nil
        )
        return (CTFrameGetLines(frame) as? [CTLine])?.count ?? 0
    }

    /// Each drawn line's typographic bounds, in the context's coordinates.
    static func lineRects(of frame: CTFrame, in frameRect: CGRect) -> [CGRect] {
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return [] }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        return zip(lines, origins).map { line, origin in
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            return CGRect(x: frameRect.minX + origin.x, y: frameRect.minY + origin.y - descent,
                          width: width, height: ascent + descent)
        }
    }

    /// One rounded background per line, padded a little beyond the glyphs.
    private static func drawLinePills(
        for frame: CTFrame,
        in frameRect: CGRect,
        color: SlideColor,
        context: CGContext,
        scale: CGFloat
    ) {
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)

        let paddingX = 18 * scale
        let paddingY = 8 * scale

        /// Translucent pills on adjacent lines overlap, and overlapping
        /// translucency doubles into a seam band. Drawing every pill
        /// OPAQUE inside one transparency layer, then compositing the
        /// layer at the pill's alpha, keeps the block one even tone and
        /// merges touching pills into a single clean shape.
        let pillColor = Inks.converted(color.cgColor)
        let pillAlpha = pillColor.alpha
        context.saveGState()
        if pillAlpha < 1 {
            context.setAlpha(pillAlpha)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.setFillColor(pillColor.copy(alpha: 1) ?? pillColor)
        } else {
            context.setFillColor(pillColor)
        }

        for (line, origin) in zip(lines, origins) {
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            guard width > 1 else { continue }

            /// Line origins are relative to the frame's path origin.
            let rect = CGRect(
                x: frameRect.minX + origin.x - paddingX,
                y: frameRect.minY + origin.y - descent - paddingY,
                width: width + paddingX * 2,
                height: ascent + descent + paddingY * 2
            )
            let path = CGPath(
                roundedRect: rect,
                cornerWidth: min(12 * scale, rect.height / 2),
                cornerHeight: min(12 * scale, rect.height / 2),
                transform: nil
            )
            context.addPath(path)
            context.fillPath()
        }

        if pillAlpha < 1 {
            context.endTransparencyLayer()
        }
        context.restoreGState()
    }

    /// The size a text block wants, for callers that size decoration around
    /// text (chips).
    static func measure(
        text: String,
        style: TextStyle,
        brand: BrandKit,
        maxWidth: CGFloat,
        scale: CGFloat
    ) -> CGSize {
        let attributed = attributedString(
            text: text, style: style, brand: brand,
            pointSize: style.size * Double(scale)
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        return CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            nil
        )
    }

    // MARK: - Attributed string assembly

    /// The unconstrained single-line width — what a word needs to not wrap.
    private static func measuredWidth(_ attributed: CFAttributedString) -> CGFloat {
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        return CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            nil
        ).width
    }

    private static func measuredHeight(_ attributed: CFAttributedString, width: CGFloat) -> CGFloat {
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        return CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: width, height: .greatestFiniteMagnitude),
            nil
        ).height
    }

    /// Build the attributed string: base run plus `**accent**` spans in the
    /// accent color. Markup is stripped from the drawn text.
    /// - Parameter strokeOverride: Replaces the style's stroke width for
    ///   this pass. `outlined` text is drawn twice — a keyline pass and a
    ///   fill pass — and each needs a different width from the same style.
    static func attributedString(
        text: String,
        style: TextStyle,
        brand: BrandKit,
        pointSize: Double,
        strokeOverride: Double? = nil
    ) -> CFAttributedString {
        let content = style.uppercased ? text.uppercased() : text
        let segments = parseAccents(in: content)

        let upright = FontResolver.font(
            family: style.fontFamily ?? brand.fontFamily,
            weight: style.weight,
            size: pointSize
        )
        let font = FontResolver.applying(variations: style.variations, features: style.features, to: upright)
        /// The italic face, made once — CoreText falls back to the upright
        /// font when the family has no oblique.
        let italicFont = FontResolver.applying(
            variations: style.variations, features: style.features,
            to: CTFontCreateCopyWithSymbolicTraits(upright, 0, nil, .traitItalic, .traitItalic) ?? upright
        )

        /// The accent face, when emphasis means heavier rather than another
        /// colour — the magazine idiom, where a phrase inside a paragraph is
        /// picked out in the same ink and a heavier weight.
        let accentUpright = style.accentWeight.map {
            FontResolver.font(
                family: style.fontFamily ?? brand.fontFamily,
                weight: $0,
                size: pointSize
            )
        }
        let accentFont = accentUpright.map {
            FontResolver.applying(variations: style.variations, features: style.features, to: $0)
        }
        let accentItalicFont = accentUpright.map {
            FontResolver.applying(variations: style.variations, features: style.features,
                                  to: CTFontCreateCopyWithSymbolicTraits($0, 0, nil, .traitItalic, .traitItalic) ?? $0)
        }

        let baseColor = Inks.converted((style.color ?? brand.textColor).cgColor)

        /// A weight was asked for and a colour was not: emphasis is the
        /// weight, and the run keeps the body's ink. Asking to embolden is
        /// not asking to recolour as well.
        let accentColor = style.accentColor.map { Inks.converted($0.cgColor) }
            ?? (style.accentWeight == nil ? Inks.converted(brand.accentColor.cgColor) : baseColor)

        /// No fallback to a computed grey: a tier the style has not defined
        /// leaves `~spans~` at the body colour, so the marker is inert rather
        /// than silently introducing a colour nobody chose.
        let mutedColor = style.mutedColor.map { Inks.converted($0.cgColor) }

        let alignment: CTTextAlignment
        switch style.alignment {
        case "center": alignment = .center
        case "right": alignment = .right
        default: alignment = .left
        }

        /// The settings take raw pointers that must outlive `CTParagraphStyleCreate`,
        /// so the values live in explicitly managed allocations for the call's duration.
        let alignmentPointer = UnsafeMutablePointer<CTTextAlignment>.allocate(capacity: 1)
        alignmentPointer.initialize(to: alignment)
        defer { alignmentPointer.deinitialize(count: 1); alignmentPointer.deallocate() }

        let lineHeightPointer = UnsafeMutablePointer<CGFloat>.allocate(capacity: 1)
        lineHeightPointer.initialize(to: CGFloat(style.lineHeight))
        defer { lineHeightPointer.deinitialize(count: 1); lineHeightPointer.deallocate() }

        let settings: [CTParagraphStyleSetting] = [
            CTParagraphStyleSetting(
                spec: .alignment,
                valueSize: MemoryLayout<CTTextAlignment>.size,
                value: alignmentPointer
            ),
            CTParagraphStyleSetting(
                spec: .lineHeightMultiple,
                valueSize: MemoryLayout<CGFloat>.size,
                value: lineHeightPointer
            )
        ]
        let paragraph = CTParagraphStyleCreate(settings, settings.count)

        let result = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0)!
        CFAttributedStringBeginEditing(result)

        for segment in segments {
            let range = CFRange(
                location: CFAttributedStringGetLength(result),
                length: segment.text.utf16.count
            )
            CFAttributedStringReplaceString(
                result,
                CFRange(location: CFAttributedStringGetLength(result), length: 0),
                segment.text as CFString
            )
            let face: CTFont
            if segment.accented, let accentFont, let accentItalicFont {
                face = segment.italic ? accentItalicFont : accentFont
            } else {
                face = segment.italic ? italicFont : font
            }
            CFAttributedStringSetAttribute(result, range, kCTFontAttributeName, face)
            /// Accent wins over muted where both are asked for: a span marked
            /// as the loud tier and the quiet one at once is a caller
            /// contradicting themselves, and the emphasis is the thing they
            /// were more deliberate about.
            let ink: CGColor
            if segment.accented { ink = accentColor }
            else if segment.muted { ink = mutedColor ?? baseColor }
            else { ink = baseColor }
            CFAttributedStringSetAttribute(result, range, kCTForegroundColorAttributeName, ink)
            CFAttributedStringSetAttribute(result, range, kCTParagraphStyleAttributeName, paragraph)
            let strokeWidth = strokeOverride ?? style.strokeWidth
            if strokeWidth > 0 {
                /// CoreText reads the sign as the mode: positive strokes and
                /// does not fill (hollow), negative does both (a keyline
                /// around filled text). The sign is not something a caller
                /// should have to know, so the style names the treatment and
                /// this converts.
                CFAttributedStringSetAttribute(
                    result, range, kCTStrokeWidthAttributeName,
                    strokeWidth as CFNumber
                )
                CFAttributedStringSetAttribute(
                    result, range, kCTStrokeColorAttributeName,
                    segment.accented
                        ? accentColor
                        : Inks.converted((style.strokeColor ?? style.color ?? brand.textColor).cgColor)
                )
            }
            if segment.accented, style.underlineAccents {
                CFAttributedStringSetAttribute(
                    result, range, kCTUnderlineStyleAttributeName,
                    CTUnderlineStyle.single.rawValue as CFNumber
                )
            } else {
                /// Inserted text inherits the preceding run's attributes, so a
                /// plain segment after an underlined accent arrives already
                /// underlined — clear it explicitly.
                CFAttributedStringRemoveAttribute(result, range, kCTUnderlineStyleAttributeName)
            }
            if style.kerning != 0 {
                /// Scaled to the auto-shrunk size — but a declared size of
                /// zero would make the ratio NaN, and NaN in a CoreText
                /// attribute is undefined behaviour with a canvas.
                let scaled = style.size > 0
                    ? style.kerning * Double(pointSize) / style.size
                    : style.kerning
                CFAttributedStringSetAttribute(
                    result, range, kCTKernAttributeName,
                    scaled as CFNumber
                )
            }
        }

        if let characterStyles = style.characterStyles, !characterStyles.isEmpty {
            applyCharacterStyles(characterStyles, to: result, style: style, brand: brand, pointSize: pointSize,
                                 strokeWidth: strokeOverride ?? style.strokeWidth)
        }
        CFAttributedStringEndEditing(result)
        return result
    }

    /// Ranges of characters restyled: colour, size, weight, baseline,
    /// tracking. Positions count characters (graphemes) of the drawn text.
    private static func applyCharacterStyles(
        _ styles: [CharacterStyle],
        to result: CFMutableAttributedString,
        style: TextStyle,
        brand: BrandKit,
        pointSize: Double,
        strokeWidth: Double
    ) {
        let drawn = CFAttributedStringGetString(result) as String
        let offsets = CharacterOffsets(drawn)
        for character in styles {
            guard let range = offsets.utf16Range(start: character.start, length: character.length) else { continue }
            if let color = character.color {
                CFAttributedStringSetAttribute(result, range, kCTForegroundColorAttributeName, Inks.converted(color.cgColor))
                if strokeWidth > 0, style.strokeColor == nil {
                    CFAttributedStringSetAttribute(result, range, kCTStrokeColorAttributeName, Inks.converted(color.cgColor))
                }
            }
            if character.scale != nil || character.weight != nil {
                /// Each font run inside the range keeps its own face (italic,
                /// accent) and takes the new size and weight.
                var location = range.location
                while location < range.location + range.length {
                    var effective = CFRange(location: 0, length: 0)
                    let existing = CFAttributedStringGetAttribute(result, location, kCTFontAttributeName, &effective)
                    let end = min(range.location + range.length, effective.location + effective.length)
                    let run = CFRange(location: location, length: max(1, end - location))
                    let size = pointSize * (character.scale ?? 1)
                    var face: CTFont
                    if let weight = character.weight {
                        face = FontResolver.font(family: style.fontFamily ?? brand.fontFamily, weight: weight, size: size)
                        if let existing, CFGetTypeID(existing) == CTFontGetTypeID(),
                           CTFontGetSymbolicTraits(existing as! CTFont).contains(.traitItalic) {
                            face = CTFontCreateCopyWithSymbolicTraits(face, size, nil, .traitItalic, .traitItalic) ?? face
                        }
                        face = FontResolver.applying(variations: style.variations, features: style.features, to: face)
                    } else if let existing, CFGetTypeID(existing) == CTFontGetTypeID() {
                        face = CTFontCreateCopyWithAttributes(existing as! CTFont, size, nil, nil)
                    } else {
                        face = FontResolver.font(family: style.fontFamily ?? brand.fontFamily, weight: style.weight, size: size)
                    }
                    CFAttributedStringSetAttribute(result, run, kCTFontAttributeName, face)
                    location = end > location ? end : location + 1
                }
            }
            if let baseline = character.baseline, baseline != 0 {
                CFAttributedStringSetAttribute(result, range, kCTBaselineOffsetAttributeName, (baseline * pointSize) as CFNumber)
            }
            if let tracking = character.tracking {
                CFAttributedStringSetAttribute(result, range, kCTKernAttributeName, (tracking / 1000 * pointSize) as CFNumber)
            }
        }
    }

    struct Run: Equatable {
        var text: String
        var accented = false
        var italic = false
        /// A tier BELOW the body — quieter, not another accent.
        var muted = false
    }

    /// Split `"~Native~ and **Fast**"` into runs: `**accent**` spans colour
    /// from the brand, `~muted~` spans take a tier BELOW the body, `*italic*`
    /// spans slant, and `#hashtags` take the accent colour the way every
    /// platform renders them.
    ///
    /// Three tiers rather than two because that is what the headlines this is
    /// asked to set actually use: "Native and Fast" is grey, black, purple —
    /// a quieter word, the body, and the accent. With only base and accent the
    /// quiet word has to borrow the accent, and the emphasis collapses into
    /// two words fighting.
    ///
    /// `~` is a single tilde on purpose: `*` and `**` are taken, and markdown
    /// spells strikethrough with two, so one is free.
    static func parseAccents(in text: String) -> [Run] {
        var segments: [Run] = []

        func appendPlain(_ plain: Substring) {
            /// Within a plain stretch: ~muted~ spans, then *italic*, then
            /// hashtags. Muted is taken first so `~a *b* c~` keeps the whole
            /// span quiet rather than the italic escaping the tier.
            var remaining = plain
            while let open = remaining.range(of: "~") {
                let afterOpen = remaining[open.upperBound...]
                guard let close = afterOpen.range(of: "~"), !afterOpen[..<close.lowerBound].isEmpty else { break }
                appendItalicised(remaining[..<open.lowerBound], muted: false)
                appendItalicised(afterOpen[..<close.lowerBound], muted: true)
                remaining = afterOpen[close.upperBound...]
            }
            appendItalicised(remaining, muted: false)
        }

        func appendItalicised(_ plain: Substring, muted: Bool) {
            var remaining = plain
            while let open = remaining.range(of: "*") {
                let afterOpen = remaining[open.upperBound...]
                guard let close = afterOpen.range(of: "*"), afterOpen[..<close.lowerBound].count > 0 else { break }
                appendHashtagged(remaining[..<open.lowerBound], italic: false, muted: muted)
                segments.append(Run(text: String(afterOpen[..<close.lowerBound]), italic: true, muted: muted))
                remaining = afterOpen[close.upperBound...]
            }
            appendHashtagged(remaining, italic: false, muted: muted)
        }

        func appendHashtagged(_ plain: Substring, italic: Bool, muted: Bool = false) {
            var remaining = plain
            while let hash = remaining.firstIndex(of: "#") {
                let tag = remaining[remaining.index(after: hash)...].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                guard !tag.isEmpty else {
                    if !remaining[..<remaining.index(after: hash)].isEmpty {
                        segments.append(Run(text: String(remaining[..<remaining.index(after: hash)]), italic: italic, muted: muted))
                    }
                    remaining = remaining[remaining.index(after: hash)...]
                    continue
                }
                if hash > remaining.startIndex {
                    segments.append(Run(text: String(remaining[..<hash]), italic: italic, muted: muted))
                }
                segments.append(Run(text: "#" + tag, accented: true, italic: italic, muted: muted))
                remaining = remaining[tag.endIndex...]
            }
            if !remaining.isEmpty {
                segments.append(Run(text: String(remaining), italic: italic, muted: muted))
            }
        }

        var remaining = Substring(text)
        while let open = remaining.range(of: "**") {
            let afterOpen = remaining[open.upperBound...]
            guard let close = afterOpen.range(of: "**") else { break }

            if remaining.startIndex < open.lowerBound {
                appendPlain(remaining[..<open.lowerBound])
            }
            segments.append(Run(text: String(afterOpen[..<close.lowerBound]), accented: true))
            remaining = afterOpen[close.upperBound...]
        }
        if !remaining.isEmpty {
            appendPlain(remaining)
        }
        return segments.isEmpty ? [Run(text: text)] : segments
    }
}
