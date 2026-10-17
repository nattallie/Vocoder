import Accelerate

/// Amplitude envelope extraction: full-wave rectify, then lowpass -- mirrors
/// `envelope_rectify_lowpass` in `notebooks/vocoder.py`. 400 Hz sits comfortably
/// above speech-relevant envelope modulation (roughly 2-16 Hz) while staying well
/// below any band's carrier frequency, so it separates envelope from fine structure
/// without bottlenecking intelligibility.
enum Envelope {
    static func extract(_ band: [Float], sampleRate: Double, cutoffHz: Double = 400, order: Int = 4) -> [Float] {
        var rectified = [Float](repeating: 0, count: band.count)
        vDSP_vabs(band, 1, &rectified, 1, vDSP_Length(band.count))

        let sections = Butterworth.lowpassSections(order: order, cutoffHz: cutoffHz, sampleRate: sampleRate)
        return Biquad.filtfilt(sections, rectified)
    }

    static func extractAll(_ bands: [[Float]], sampleRate: Double, cutoffHz: Double = 400, order: Int = 4) -> [[Float]] {
        bands.map { extract($0, sampleRate: sampleRate, cutoffHz: cutoffHz, order: order) }
    }
}
