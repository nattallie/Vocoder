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
        let logMin = log10(fMin)
        let logMax = log10(fMax)
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
