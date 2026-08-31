//
//  UnitGeometry.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//
//  Unit coordinates to pixels — including the flip from design-tool
//  space (origin top-left) to CoreGraphics space (origin bottom-left).
//  That flip is the classic drawing trap, so it lives in exactly one
//  testable place.
//

import CoreGraphics

/// Resolving unit-space regions against a canvas.
enum UnitGeometry {

    /// `rect` in pixels, converted to CoreGraphics coordinates.
    static func pixels(_ rect: UnitRect, in canvas: Canvas) -> CGRect {
        let w = CGFloat(canvas.width)
        let h = CGFloat(canvas.height)
        return CGRect(
            x: w * rect.x,
            y: h * (1 - rect.y - rect.height),
            width: w * rect.width,
            height: h * rect.height
        )
    }
}
