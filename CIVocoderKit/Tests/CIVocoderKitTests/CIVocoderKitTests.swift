import Testing
import Foundation
@testable import CIVocoderKit

@Test func versionExists() {
    #expect(!CIVocoderKit.version.isEmpty)
}

// MARK: - Reference-data fixture (dumped from the validated Python notebooks/vocoder.py)

private struct Reference: Decodable {
    let sampleRate: Double
    let testSignal: [Float]
    let n4_edges: [Double]
    let n4_centers: [Double]
    let n4_bands: [[Float]]
    let n4_envelopes: [[Float]]
    let vocode_n4_tone: [Float]
    let vocode_n4_noise_peak: Float
    let vocode_n4_noise_length: Int
}

private func loadReference() throws -> Reference {
    let url = Bundle.module.url(forResource: "reference", withExtension: "json")!
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(Reference.self, from: data)
}

/// Max absolute error, and max absolute error over the "interior" (excluding the first/last
/// `edge` samples, where the simplified zero-phase filtering transient documented in
/// Biquad.swift is expected to concentrate).
private func errorStats(_ a: [Float], _ b: [Float], edge: Int) -> (full: Float, interior: Float) {
    precondition(a.count == b.count)
    var full: Float = 0
    for i in 0..<a.count { full = max(full, abs(a[i] - b[i])) }
    guard a.count > 2 * edge else { return (full, full) }
    var interior: Float = 0
    for i in edge..<(a.count - edge) { interior = max(interior, abs(a[i] - b[i])) }
    return (full, interior)
}

// MARK: - Numeric validation against scipy

@Suite struct ReferenceComparisonTests {
    /// Edge-sample window reported separately for diagnostic visibility. With the
    /// zero-phase run-in warmup (see Biquad.filtfilt), edge and interior error both land
    /// at float32 noise level in practice (~1e-5), so the same tight tolerance applies to
    /// both -- this is purely informative now, not compensating for a known gap.
    private let edgeWindow = 30

    /// scipy computes in float64 throughout and only casts to float32 at the very end;
    /// this Swift port stays in Float32 end-to-end (matching the audio buffers it'll
    /// eventually process), so some accumulated float32 rounding is expected even with
    /// the algorithm itself matching exactly. 1e-3 gives ~100x headroom over the ~1e-5
    /// actually observed during development, while still being a meaningful check (the
    /// gain bug caught during development produced errors of 1e5-1e8, not a few 1e-3).
    private let tolerance: Float = 1e-3

    @Test func filterbankSplitMatchesScipy() throws {
        let ref = try loadReference()
        let filterbank = Filterbank(channels: 4, sampleRate: ref.sampleRate)

        #expect(filterbank.edges.count == ref.n4_edges.count)
        for (mine, theirs) in zip(filterbank.edges, ref.n4_edges) {
            #expect(abs(mine - theirs) <= 1e-6, "band edge mismatch")
        }
        for (mine, theirs) in zip(filterbank.centers, ref.n4_centers) {
            #expect(abs(mine - theirs) <= 1e-6, "band center mismatch")
        }

        let bands = filterbank.split(ref.testSignal)
        #expect(bands.count == ref.n4_bands.count)
        for (i, (mine, theirs)) in zip(bands, ref.n4_bands).enumerated() {
            let (full, interior) = errorStats(mine, theirs, edge: edgeWindow)
            #expect(interior < tolerance, "band \(i) interior samples diverge from scipy (\(interior))")
            #expect(full < tolerance, "band \(i) diverges from scipy including edges (\(full))")
        }
    }

    @Test func envelopeExtractionMatchesScipy() throws {
        let ref = try loadReference()
        let filterbank = Filterbank(channels: 4, sampleRate: ref.sampleRate)
        let bands = filterbank.split(ref.testSignal)
        let envelopes = Envelope.extractAll(bands, sampleRate: ref.sampleRate)

        #expect(envelopes.count == ref.n4_envelopes.count)
        for (i, (mine, theirs)) in zip(envelopes, ref.n4_envelopes).enumerated() {
            let (full, interior) = errorStats(mine, theirs, edge: edgeWindow)
            #expect(interior < tolerance, "envelope \(i) interior samples diverge from scipy (\(interior))")
            #expect(full < tolerance, "envelope \(i) diverges from scipy including edges (\(full))")
        }
    }

    /// Tone carrier generation is deterministic (no RNG), so the full vocode() pipeline
    /// with .tone can be compared value-for-value against scipy's output.
    @Test func vocodeToneMatchesScipy() throws {
        let ref = try loadReference()
        let out = CIVocoder.vocode(audio: ref.testSignal, sampleRate: ref.sampleRate, channels: 4, carrierType: .tone)

        #expect(out.count == ref.vocode_n4_tone.count)
        let (full, interior) = errorStats(out, ref.vocode_n4_tone, edge: edgeWindow)
        #expect(interior < tolerance, "vocode(tone) interior samples diverge from scipy (\(interior))")
        #expect(full < tolerance, "vocode(tone) diverges from scipy including edges (\(full))")
    }

    /// Noise-carrier output can't be compared value-for-value (different RNG), but
    /// mixdown's peak-normalize is RNG-independent: whenever the pre-normalize peak is
    /// nonzero (always true here), the result is scaled to exactly `headroom` (0.95).
    @Test func vocodeNoisePeakMatchesHeadroomRegardlessOfRNG() throws {
        let ref = try loadReference()
        let out = CIVocoder.vocode(audio: ref.testSignal, sampleRate: ref.sampleRate, channels: 4, carrierType: .noise)
        #expect(out.count == ref.vocode_n4_noise_length)
        let peak = out.map { abs($0) }.max() ?? 0
        #expect(abs(peak - ref.vocode_n4_noise_peak) <= 1e-4)
    }
}

// MARK: - Sanity sweep, mirroring 04_full_pipeline_compare.ipynb's validation grid

@Test(
    "vocode() stays sane across N x carrier combinations",
    arguments: [4, 8, 16, 22], [CarrierType.noise, CarrierType.tone]
)
func vocodeSanity(channels: Int, carrierType: CarrierType) throws {
    let ref = try loadReference()
    let out = CIVocoder.vocode(audio: ref.testSignal, sampleRate: ref.sampleRate, channels: channels, carrierType: carrierType)
    #expect(out.count == ref.testSignal.count, "N=\(channels) \(carrierType): wrong length")
    #expect(!out.contains { $0.isNaN }, "N=\(channels) \(carrierType): contains NaN")
    let peak = out.map { abs($0) }.max() ?? 0
    #expect(peak <= 0.951, "N=\(channels) \(carrierType): exceeds headroom")
}
