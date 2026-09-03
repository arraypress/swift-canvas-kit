//
//  Gradients.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Curated gradients — the palette philosophy applied to backgrounds.
///
/// Two kinds of entry, and the difference matters when picking one.
///
/// The first nine are **colours** — saturated enough to be the subject, with
/// white type over them. The three `-wash` entries are **grounds**: near-white
/// washes that let a device and black type sit on them, which is the look the
/// App Store pages that actually convert are using. `candy-wash` carries
/// exactly those hues at four times the saturation and reads as a poster
/// rather than a page, so the pale tier had to be its own entries rather than
/// a lightened version of what was there.
///
/// The catalog lives in `Resources/gradients.json`, not code: every entry
/// is hand-tuned (stops chosen together, angles considered, contrast held
/// for the library's text colors), and adding one is editing JSON, not
/// recompiling. Never generate gradients from hue math.
public extension Background {

    /// The catalog, in file order — for pickers and CLI listings.
    static let curatedGradients: [(name: String, background: Background)] = {
        struct Entry: Decodable {
            let name: String
            let colors: [SlideColor]
            let angle: Double?
        }
        guard
            let url = Bundle.module.url(forResource: "gradients", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return entries.map {
            ($0.name, Background.linearGradient(colors: $0.colors, angle: $0.angle ?? 180))
        }
    }()

    /// A curated gradient by name. Unknown names return solid magenta —
    /// visible in the render, never a crash, exactly like an unparseable
    /// color. A gradient you can see is wrong beats one that silently
    /// becomes something else.
    static func gradient(named name: String) -> Background {
        curatedGradients.first { $0.name == name }?.background
            ?? .solid(SlideColor("#FF00FF"))
    }
}
