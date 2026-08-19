//
//  ChromeZones.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//
//  Where the platforms draw over your slide.
//
//  A safe area keeps text inside the frame; a chrome zone is the sharper
//  fact that certain patches of the frame are OCCUPIED — TikTok's action
//  rail, the caption band, Instagram's carousel dots. A CTA under the dots
//  is a CTA nobody can read, and it looks perfect in the exported PNG,
//  which is exactly the kind of failure the audit exists for.
//
//  Data, not code (`Resources/safe-zones.json`), for the same reason the
//  gradients are: platform chrome moves with app redesigns, and updating a
//  JSON file is not a recompile.
//

import CoreGraphics
import Foundation

/// The platform-chrome zones for the named canvas presets.
enum ChromeZones {

    /// One occupied patch of a platform's frame, in unit coordinates
    /// (origin top-left, like every region in a deck).
    struct Zone: Decodable {
        let name: String
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        var region: UnitRect { UnitRect(x: x, y: y, width: width, height: height) }
    }

    private struct Entry: Decodable {
        let canvas: String
        let zones: [Zone]
    }

    /// Zones by canvas preset name, from the bundled catalog.
    private static let catalog: [String: [Zone]] = {
        guard
            let url = Bundle.module.url(forResource: "safe-zones", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: entries.map { ($0.canvas, $0.zones) })
    }()

    /// The zones that apply to a canvas — matched against the named presets,
    /// because chrome belongs to a platform and the preset is how a deck
    /// says which platform it is dressed for. A custom canvas gets none.
    static func zones(for canvas: Canvas) -> [Zone] {
        guard let preset = Canvas.presets.first(where: { $0.canvas == canvas }) else { return [] }
        return catalog[preset.name] ?? []
    }
}
