import Foundation

/// One second-order section in the layout `vDSP_biquad` expects: 5 coefficients
/// `[b0, b1, b2, a1, a2]`, `a0` implicit as 1. Empirically verified (impulse-response
/// probe against hand-computed expected output) that vDSP_biquad uses the same sign
/// convention as scipy's `sos`: `y[n] = b0 x[n] + b1 x[n-1] + b2 x[n-2] - a1 y[n-1] - a2 y[n-2]`.
/// So a scipy `sos` row `[b0,b1,b2,a0,a1,a2]` maps directly to `[b0,b1,b2,a1,a2]` here,
/// a0 dropped, no sign flip needed.
struct BiquadSection {
    var b0, b1, b2, a1, a2: Double
}

/// Butterworth filter design via the standard analog-prototype + bilinear-transform
/// method (the same method `scipy.signal.butter` uses internally: `buttap` ->
/// `lp2lp_zpk`/`lp2bp_zpk` -> `bilinear_zpk` -> grouped into second-order sections).
/// Validated against scipy's `sosfreqz` output to ~1e-12 relative error across several
/// orders and bands during development (see CIVocoderKitTests).
///
/// Internally uses scipy's own normalized convention: digital cutoffs are expressed as
/// `Wn` in `[0, 1]` (fraction of Nyquist), pre-warped against a fixed `fs = 2.0`, so the
/// formulas below are independent of the actual sample rate until the final bilinear step.
enum Butterworth {
    private static let fsInternal = 2.0
    private static let fs2 = 2 * fsInternal // bilinear transform constant

    /// Pre-warp a normalized digital cutoff (0...1, fraction of Nyquist) to its analog
    /// equivalent for the bilinear transform.
    private static func warp(_ Wn: Double) -> Double {
        2 * fsInternal * tan(.pi * Wn / fsInternal)
    }

    /// The i-th (0-indexed) analog Butterworth lowpass-prototype pole, taken from the
    /// upper half of the complex plane (m = 1, 3, 5, ...). Its conjugate is the other
    /// pole in the same biquad section -- never computed separately, just implied.
    private static func prototypeHalfPole(_ i: Int, order: Int) -> Complex {
        let m = Double(2 * i + 1)
        let theta = .pi * m / (2 * Double(order))
        return Complex(-cos(theta), -sin(theta))
    }

    /// Digital pole -> monic denominator `a1, a2` for one biquad section (a0 = 1).
    private static func denominatorCoefficients(forAnalogPole p: Complex) -> (a1: Double, a2: Double) {
        let pz = (Complex(fs2) + p) / (Complex(fs2) - p)
        return (-2 * pz.re, pz.magnitudeSquared)
    }

    /// Distribute an overall scalar gain evenly (geometric mean) across all sections'
    /// numerators, for better numeric conditioning than concentrating it in one section.
    private static func applyGain(_ kz: Double, to sections: inout [BiquadSection]) {
        guard !sections.isEmpty else { return }
        let sign = kz < 0 ? -1.0 : 1.0
        let mag = pow(abs(kz), 1.0 / Double(sections.count))
        for i in sections.indices {
            sections[i].b0 *= mag
            sections[i].b1 *= mag
            sections[i].b2 *= mag
        }
        sections[0].b0 *= sign
        sections[0].b1 *= sign
        sections[0].b2 *= sign
    }

    /// Order-`order` Butterworth lowpass, `order/2` biquad sections. `order` must be even
    /// (true for every call site in this project: always 4).
    static func lowpassSections(order: Int, cutoffHz: Double, sampleRate: Double) -> [BiquadSection] {
        precondition(order % 2 == 0, "Butterworth design here only supports even orders")
        let nyquist = sampleRate / 2
        let Wn = cutoffHz / nyquist
        let wo = warp(Wn)

        var sections: [BiquadSection] = []
        var polesForGain: [Complex] = []
        for i in 0..<(order / 2) {
            let pScaled = prototypeHalfPole(i, order: order) * wo
            polesForGain.append(pScaled)
            let (a1, a2) = denominatorCoefficients(forAnalogPole: pScaled)
            // Analog lowpass Butterworth has no zeros; bilinear transform pads `order`
            // zeros at z=-1 to match the pole count, i.e. (z+1)^2 per section.
            sections.append(BiquadSection(b0: 1, b1: 2, b2: 1, a1: a1, a2: a2))
        }

        let kLowpass = pow(wo, Double(order))
        var denom = Complex(1)
        for p in polesForGain {
            denom = denom * (Complex(fs2) - p) * (Complex(fs2) - p.conjugate)
        }
        let kz = kLowpass * (Complex(1) / denom).re
        applyGain(kz, to: &sections)
        return sections
    }

    /// Order-`order` Butterworth bandpass, `order` biquad sections (the lowpass->bandpass
    /// transform doubles the pole count). `order` must be even.
    static func bandpassSections(order: Int, lowHz: Double, highHz: Double, sampleRate: Double) -> [BiquadSection] {
        precondition(order % 2 == 0, "Butterworth design here only supports even orders")
        let nyquist = sampleRate / 2
        let woLow = warp(lowHz / nyquist)
        let woHigh = warp(highHz / nyquist)
        let wo = (woLow * woHigh).squareRoot()
        let bw = woHigh - woLow

        var sections: [BiquadSection] = []
        var polesForGain: [Complex] = []
        for i in 0..<(order / 2) {
            let pScaled = prototypeHalfPole(i, order: order) * (bw / 2)
            let sq = (pScaled * pScaled - Complex(wo * wo)).sqrt()
            for p in [pScaled + sq, pScaled - sq] {
                polesForGain.append(p)
                let (a1, a2) = denominatorCoefficients(forAnalogPole: p)
                // Analog bandpass Butterworth has `order` zeros at the origin (from the
                // lowpass->bandpass transform); bilinear maps those to z=1 and pads an
                // equal number at z=-1. Distributing one of each per section -- rather
                // than replicating scipy's exact internal pairing -- gives an equivalent
                // overall cascade: (z-1)(z+1) = z^2 - 1 per section.
                sections.append(BiquadSection(b0: 1, b1: 0, b2: -1, a1: a1, a2: a2))
            }
        }

        let kBandpass = pow(bw, Double(order))
        let numerator = pow(fs2, Double(order)) // `order` zeros at the origin, each contributing (fs2 - 0)
        var denom = Complex(1)
        for p in polesForGain {
            // Each `p` in polesForGain is only "half" the pole set (the conjugate partner
            // is implied, never stored separately -- see prototypeHalfPole) -- the gain
            // product needs both factors.
            denom = denom * (Complex(fs2) - p) * (Complex(fs2) - p.conjugate)
        }
        let kz = kBandpass * (Complex(numerator) / denom).re
        applyGain(kz, to: &sections)
        return sections
    }
}
