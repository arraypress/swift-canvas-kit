//
//  BeatDetector.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//  Ported from CaptionKit (same author); now the one copy the kits share.
//

import AVFoundation
import Foundation

/// On-device beat detection: energy-flux onset picking over a downmixed
/// envelope. Pure signal math — no ML, no cloud — good enough to land
/// punch-ins and pops on the groove of a music bed.
public enum BeatDetector {

    /// Onset/beat times in seconds from the start of `url`.
    ///
    /// Method: 512-sample hop energies → positive flux (energy rising) →
    /// adaptive threshold (local mean × factor) → peak picking with a
    /// minimum gap so rolls don't double-fire.
    public static func detect(url: URL, minimumGap: TimeInterval = 0.28) throws -> [TimeInterval] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0, file.length > 0 else { return [] }

        let hop = 512
        var energies: [Float] = []
        energies.reserveCapacity(Int(file.length) / hop + 1)

        /// Read in the file's own processing format and downmix by hand.
        /// Handing `read(into:)` a mono buffer against a stereo file throws
        /// (error -50) — which meant beat sync failed on every real piece
        /// of music, since music is stereo. The mono path never noticed
        /// because every test clicked in mono.
        let chunkFrames: AVAudioFrameCount = 1 << 16
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else { return [] }
        let channelCount = Int(format.channelCount)
        var carry: [Float] = []
        while file.framePosition < file.length {
            try file.read(into: buffer)
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { break }
            let frames = Int(buffer.frameLength)
            carry.reserveCapacity(carry.count + frames)
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += channels[channel][frame]
                }
                carry.append(sum / Float(channelCount))
            }
            var start = 0
            while carry.count - start >= hop {
                var sum: Float = 0
                for index in start..<(start + hop) {
                    sum += carry[index] * carry[index]
                }
                energies.append(sum / Float(hop))
                start += hop
            }
            carry.removeFirst(start)
        }
        guard energies.count > 8 else { return [] }

        // Positive flux: only energy RISES mark onsets.
        let flux = zip(energies.dropFirst(), energies).map { max(0, $0 - $1) }

        // Adaptive threshold: local mean over ±23 hops (~0.27s each side).
        let window = 23
        var beats: [TimeInterval] = []
        var lastBeat = -minimumGap
        for index in flux.indices {
            let lower = max(0, index - window)
            let upper = min(flux.count - 1, index + window)
            let mean = flux[lower...upper].reduce(0, +) / Float(upper - lower + 1)
            let isPeak = flux[index] > mean * 1.6 + 1e-9
                && (index == 0 || flux[index] >= flux[index - 1])
                && (index == flux.count - 1 || flux[index] > flux[index + 1])
            guard isPeak else { continue }
            let time = TimeInterval(index + 1) * TimeInterval(hop) / sampleRate
            if time - lastBeat >= minimumGap {
                beats.append(time)
                lastBeat = time
            }
        }
        return beats
    }
}
