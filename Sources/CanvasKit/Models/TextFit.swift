//
//  TextFit.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import Foundation

/// Where a block of text went and at what size, as ``TextDrawer`` laid it out.
/// Rectangles are in the drawing context's coordinates (origin bottom-left).
public struct TextFit: Equatable, Sendable {

    /// The point size drawn, in pixels — after auto-shrink.
    public let pointSize: Double

    /// Whether the text fitted its region (height, a single word on one line,
    /// and `maxLines`) at that size.
    public let fits: Bool

    /// How many lines it wrapped to.
    public let lineCount: Int

    /// The frame the text was set in: the region's width, the text's height,
    /// placed by vertical alignment.
    public let frame: CGRect

    /// Each line's typographic bounds — what a plate or pill is sized to.
    public let lineRects: [CGRect]

    public init(pointSize: Double, fits: Bool, lineCount: Int, frame: CGRect, lineRects: [CGRect]) {
        self.pointSize = pointSize
        self.fits = fits
        self.lineCount = lineCount
        self.frame = frame
        self.lineRects = lineRects
    }

    /// The union of the lines.
    public var linesBounds: CGRect? {
        lineRects.isEmpty ? nil : lineRects.dropFirst().reduce(lineRects[0]) { $0.union($1) }
    }
}
