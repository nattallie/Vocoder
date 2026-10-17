import Accelerate
import Foundation

/// Channel-vocoder cochlear-implant simulation -- the Swift/Accelerate port of
/// `notebooks/vocoder.py`'s validated `vocode()`. Same five-stage pipeline (filterbank,
/// envelope extraction, carrier generation, modulation, mixdown), same defaults.
public enum CIVocoder {
    static func modulate(_ envelope: [Float], _ carrier: [Float]) -> [Float] {
        let n = min(envelope.count, carrier.count)
        var result = [Float](repeating: 0, count: n)
        vDSP_vmul(envelope, 1, carrier, 1, &result, 1, vDSP_Length(n))
        return result
    }

    /// Sum all modulated bands and peak-normalize to `headroom`, mirroring `mixdown()`.
    static func mixdown(_ modulatedBands: [[Float]], headroom: Float = 0.95) -> [Float] {
        guard let length = modulatedBands.first?.count else { return [] }
        var summed = [Float](repeating: 0, count: length)
        for band in modulatedBands {
            vDSP_vadd(summed, 1, band, 1, &summed, 1, vDSP_Length(length))
        }

        var peak: Float = 0
        vDSP_maxmgv(summed, 1, &peak, vDSP_Length(length))
        guard peak > 0 else { return summed }

        var scale = headroom / peak
        var output = [Float](repeating: 0, count: length)
        vDSP_vsmul(summed, 1, &scale, &output, 1, vDSP_Length(length))
        return output
    }

    /// Channel-vocode `audio` into `channels` log-spaced bands using either a `.noise`
    /// or `.tone` carrier per band. Returns a normalized, clip-safe array at the same
    /// sample rate as the input. Mirrors `vocode(audio, sr, n_channels, carrier_type)`.
    public static func vocode(
        audio: [Float],
        sampleRate: Double,
        channels: Int,
        carrierType: CarrierType,
        fMin: Double = 200,
        fMax: Double = 7000,
        filterOrder: Int = 4,
        envelopeCutoffHz: Double = 400,
        seed: UInt64 = 0
    ) -> [Float] {
        let filterbank = Filterbank(channels: channels, sampleRate: sampleRate, fMin: fMin, fMax: fMax, order: filterOrder)
        let bands = filterbank.split(audio)
        let envelopes = Envelope.extractAll(bands, sampleRate: sampleRate, cutoffHz: envelopeCutoffHz, order: filterOrder)

        var rng: RandomNumberGenerator = SplitMix64(seed: seed)
        let carriers = Carrier.generate(type: carrierType, filterbank: filterbank, length: audio.count, sampleRate: sampleRate, rng: &rng)

        let modulated = zip(envelopes, carriers).map { modulate($0, $1) }
        return mixdown(modulated)
    }
}
