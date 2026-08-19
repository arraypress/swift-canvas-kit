//
//  Exports.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//

/// One import for consumers: `import CanvasKit` brings the grading
/// vocabulary (`VideoGrade`, `GradeFilter`, `CutRender`, the shipped looks)
/// with it, because a `Background` carries a grade and a kit that has to
/// remember a second import to name one has a leaky seam.
///
/// VideoGrade stays its own package underneath — the color layer is a
/// sharp, standalone-valuable tool, and this line is the whole of the
/// coupling.
@_exported import VideoGrade
