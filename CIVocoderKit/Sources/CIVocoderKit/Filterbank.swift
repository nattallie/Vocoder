import Foundation

/// Log-spaced (Greenwood-style) bandpass filterbank -- mirrors `design_filterbank` /
/// `split_into_bands` in `notebooks/vocoder.py`. Narrower bands at low frequencies,
/// wider at high frequencies, matching how frequency resolution degrades with a real
/// cochlear implant's limited electrode count (Greenwood, 1990).
struct Filterbank {
    let bands: [[BiquadSection]]
    let edges: [Double]
    let centers: [Double]

    init(channels: Int, sampleRate: Double, fMin: Double = 200, fMax: Double = 7000, order: Int = 4) {
        // fMax defaults to 7000 Hz, which assumes a >=14kHz-ish sample rate (true for the
        // bundled clips and the recorder's fixed 44.1kHz, but not guaranteed for an
        // imported file). A band edge at or past Nyquist sends Butterworth's bilinear-
        // transform prewarping (a tangent) past its valid domain -- the result can go
        // negative, and the bandpass gain calculation then takes the square root of a
        // negative product, i.e. NaN filter coefficients. Clamping here keeps every edge
        // inside the frequencies this sample rate can actually represent.
        let nyquist = sampleRate / 2
        let safeFMax = max(fMin + 1, min(fMax, nyquist * 0.98))
        let logMin = log10(fMin)
        let logMax = log10(safeFMax)
        var edges: [Double] = []
        edges.reserveCapacity(channels + 1)
        for i in 0...channels {
            let t = Double(i) / Double(channels)
            edges.append(pow(10, logMin + t * (logMax - logMin)))
        }
        self.edges = edges
        self.centers = (0..<channels).map { (edges[$0] * edges[$0 + 1]).squareRoot() }
        self.bands = (0..<channels).map {
            Butterworth.bandpassSections(order: order, lowHz: edges[$0], highHz: edges[$0 + 1], sampleRate: sampleRate)
        }
    }

    /// Zero-phase split of `audio` into each band.
    func split(_ audio: [Float]) -> [[Float]] {
        bands.map { Biquad.filtfilt($0, audio) }
    }
}
