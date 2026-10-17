import Accelerate
import Foundation

public enum CarrierType {
    case noise
    case tone
}

/// Deterministic, seedable PRNG (SplitMix64) so carrier noise can be reproduced in
/// tests. Not intended to match Python's `numpy` RNG bit-for-bit -- only needs to
/// produce a valid band-limited noise carrier, per notebooks/vocoder.py's own
/// `generate_noise_carrier`.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

enum Carrier {
    /// Band-limited noise: white (Gaussian) noise filtered through the band's own
    /// filter, so its energy lands in the same range the original band occupied --
    /// mirrors `generate_noise_carrier`.
    static func noise(sectionsForBand sections: [BiquadSection], length: Int, rng: inout RandomNumberGenerator) -> [Float] {
        var white = [Float](repeating: 0, count: length)
        var i = 0
        while i < length {
            // Box-Muller: two independent standard-normal samples per pair of uniforms.
            let u1 = max(Double.random(in: 0..<1, using: &rng), .leastNormalMagnitude)
            let u2 = Double.random(in: 0..<1, using: &rng)
            let r = (-2 * Foundation.log(u1)).squareRoot()
            let theta = 2 * Double.pi * u2
            white[i] = Float(r * cos(theta))
            if i + 1 < length { white[i + 1] = Float(r * sin(theta)) }
            i += 2
        }
        return Biquad.filtfilt(sections, white)
    }

    /// Pure sine at the band's center frequency -- mirrors `generate_tone_carrier`.
    /// Phase accumulated in double precision (matching numpy's float64 `t = arange/sr`)
    /// before the final cast to Float, to avoid phase-drift error over long signals.
    static func tone(centerFrequencyHz: Double, length: Int, sampleRate: Double) -> [Float] {
        guard length > 0 else { return [] }
        var phase = [Double](repeating: 0, count: length)
        let increment = 2 * Double.pi * centerFrequencyHz / sampleRate
        var start = 0.0
        var inc = increment
        vDSP_vrampD(&start, &inc, &phase, 1, vDSP_Length(length))

        var sineD = [Double](repeating: 0, count: length)
        var n = Int32(length)
        vvsin(&sineD, phase, &n)

        var result = [Float](repeating: 0, count: length)
        vDSP_vdpsp(sineD, 1, &result, 1, vDSP_Length(length))
        return result
    }

    static func generate(type: CarrierType, filterbank: Filterbank, length: Int, sampleRate: Double, rng: inout RandomNumberGenerator) -> [[Float]] {
        switch type {
        case .noise:
            return filterbank.bands.map { noise(sectionsForBand: $0, length: length, rng: &rng) }
        case .tone:
            return filterbank.centers.map { tone(centerFrequencyHz: $0, length: length, sampleRate: sampleRate) }
        }
    }
}
