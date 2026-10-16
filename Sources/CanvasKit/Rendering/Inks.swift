//
//  Inks.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//
//  The colour space ink is put down in. Normally sRGB, as every colour is
//  written; a print file in CMYK sets `space` for the drawing and every
//  colour TextDrawer uses is converted into it by ColorSync first, so the
//  words in the file are CMYK too.
//

import CoreGraphics
import Foundation

public enum Inks {

    /// The space colours are converted into while drawing; `nil` leaves them as written.
    @TaskLocal public static var space: CGColorSpace?

    /// `color` in ``space`` (relative colorimetric), or unchanged when no space is set.
    public static func converted(_ color: CGColor) -> CGColor {
        guard let space, color.colorSpace?.model != space.model || color.colorSpace?.name != space.name else { return color }
        return color.converted(to: space, intent: .relativeColorimetric, options: nil) ?? color
    }
}

/// Character (grapheme) positions in a string, as the UTF-16 ranges CoreText counts in.
struct CharacterOffsets {
    /// The UTF-16 offset each character starts at, and the string's UTF-16 length last.
    let starts: [Int]

    init(_ text: String) {
        var starts: [Int] = []
        var offset = 0
        for character in text {
            starts.append(offset)
            offset += character.utf16.count
        }
        starts.append(offset)
        self.starts = starts
    }

    /// How many characters.
    var count: Int { starts.count - 1 }

    /// The UTF-16 range of `length` characters from `start`, clipped to the
    /// text; `nil` when nothing of it is in the text.
    func utf16Range(start: Int, length: Int) -> CFRange? {
        let first = max(0, start), last = min(count, start + length)
        guard first < last else { return nil }
        return CFRange(location: starts[first], length: starts[last] - starts[first])
    }

    /// The character a UTF-16 offset falls in.
    func character(atUTF16 offset: Int) -> Int {
        var low = 0, high = count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return max(0, low)
    }
}
