//
//  StillExporter.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Deck → numbered PNGs in a folder: the photo-mode carousel export.
///
/// Filenames sort in swipe order (`01-hook.png`, `02-content.png`, …) so
/// dropping the folder into TikTok or Instagram keeps the deck's sequence
/// without any renaming.
public enum StillExporter {

    public enum ExportError: Error, CustomStringConvertible {
        case destinationCreationFailed(URL)

        public var description: String {
            switch self {
            case .destinationCreationFailed(let url):
                return "Could not write image to '\(url.path)'."
            }
        }
    }

    /// Render every slide and write the PNGs. Returns the written files in
    /// slide order.
    @discardableResult
    public static func export(deck: SlideDeck, to directory: URL) throws -> [URL] {
        try exportAuditing(deck: deck, to: directory).files
    }

    /// The same render, with the audit's findings from the very pass that
    /// made the files.
    ///
    /// `reel new` used to export and then call `audit`, which laid every
    /// slide out twice — text layout being the expensive half of a render.
    /// One pass produces both the pixels and the report about them.
    public static func exportAuditing(
        deck: SlideDeck, to directory: URL
    ) throws -> (files: [URL], warnings: [RenderWarning]) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let collector = WarningCollector()
        var written: [URL] = []
        for (index, slide) in deck.slides.enumerated() {
            collector.slideIndex = index
            let image = try SlideRenderer.render(deck: deck, slideIndex: index, collector: collector)
            let name = String(format: "%02d-%@.png", index + 1, slide.role)
            let url = directory.appendingPathComponent(name)
            try write(image, to: url)
            written.append(url)
        }
        return (written, collector.warnings)
    }

    private static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw ExportError.destinationCreationFailed(url)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.destinationCreationFailed(url)
        }
    }
}
