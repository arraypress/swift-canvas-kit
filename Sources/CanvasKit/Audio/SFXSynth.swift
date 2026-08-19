//
//  SFXSynth.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//  Ported from CaptionKit (same author); now the one copy the kits share.
//

import AVFoundation
import Foundation

/// Procedurally synthesized sound effects — whoosh, pop, riser — rendered
/// once to CAF files in the caches folder. Filtered noise and envelopes,
/// deterministic seed: no bundled assets, no licensing, byte-identical on
/// every machine.
public enum SFXSynth {

    public enum Effect: String, CaseIterable, Sendable {
        /// Band-swept noise, rise-and-fall — title entrances, movement.
        case whoosh
        /// A pitch-dropping blip with a click — emoji pops, taps.
        case pop
        /// A noise crescendo — tension into a cut or reveal.
        case riser

        public var displayName: String { rawValue.capitalized }
    }

    private static let sampleRate = 44_100.0

    /// The CAF for an effect, synthesizing it on first use.
    public static func url(for effect: Effect) throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CanvasKitSFX", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(effect.rawValue)-v1.caf")
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        try write(samples: render(effect), to: url)
        return url
    }

    private static func render(_ effect: Effect) -> [Float] {
        switch effect {
        case .whoosh: return whoosh()
        case .pop: return pop()
        case .riser: return riser()
        }
    }

    /// Deterministic white noise (seeded LCG) — reproducible files.
    private static func noise(_ count: Int) -> [Float] {
        var seed: UInt64 = 0x2545_F491_4F6C_DD1D
        var samples = [Float](repeating: 0, count: count)
        for index in 0..<count {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            samples[index] = Float(seed >> 40) / Float(1 << 24) * 2 - 1
        }
        return samples
    }

    /// 0.45s of band-swept noise under a rise-and-fall envelope.
    private static func whoosh() -> [Float] {
        let count = Int(0.45 * sampleRate)
        var samples = noise(count)
        var lowPass: Float = 0
        for index in 0..<count {
            let progress = Float(index) / Float(count)
            let cutoff = 300.0 + 3200.0 * Double(progress)
            let alpha = Float(1 - exp(-2 * .pi * cutoff / sampleRate))
            lowPass += alpha * (samples[index] - lowPass)
            let envelope = sinf(.pi * progress)
            samples[index] = lowPass * envelope * envelope * 0.8
        }
        return samples
    }

    /// 90ms pitch-dropping sine blip with a click transient.
    private static func pop() -> [Float] {
        let count = Int(0.09 * sampleRate)
        var samples = [Float](repeating: 0, count: count)
        var phase = 0.0
        for index in 0..<count {
            let progress = Double(index) / Double(count)
            let frequency = 520.0 - 300.0 * progress
            phase += 2 * .pi * frequency / sampleRate
            samples[index] = Float(sin(phase) * exp(-6 * progress)) * 0.9
        }
        for index in 0..<min(40, count) {
            samples[index] += Float(exp(-Double(index) / 6)) * 0.35
        }
        return samples
    }

    /// 0.8s noise crescendo with a rising band, faded at the very end so
    /// it lands clean on the cut.
    private static func riser() -> [Float] {
        let count = Int(0.8 * sampleRate)
        var samples = noise(count)
        var lowPass: Float = 0
        for index in 0..<count {
            let progress = Float(index) / Float(count)
            let cutoff = 200.0 + 2600.0 * Double(progress * progress)
            let alpha = Float(1 - exp(-2 * .pi * cutoff / sampleRate))
            lowPass += alpha * (samples[index] - lowPass)
            samples[index] = lowPass * progress * progress * 0.7
        }
        let tail = min(Int(0.02 * sampleRate), count)
        for index in 0..<tail {
            samples[count - 1 - index] *= Float(index) / Float(tail)
        }
        return samples
    }

    private static func write(samples: [Float], to url: URL) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData
        else {
            throw VideoExporter.ExportError.writerCreationFailed("could not allocate SFX buffer")
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            channel[0].update(from: source.baseAddress!, count: samples.count)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
