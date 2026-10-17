import Accelerate

enum Biquad {
    /// Apply a cascaded biquad filter (`sections`) to `signal` once, via `vDSP_biquad`,
    /// starting from a zero initial state.
    static func apply(_ sections: [BiquadSection], to signal: [Float]) -> [Float] {
        guard !sections.isEmpty, !signal.isEmpty else { return signal }

        var coefficients: [Double] = []
        coefficients.reserveCapacity(sections.count * 5)
        for s in sections {
            coefficients.append(contentsOf: [s.b0, s.b1, s.b2, s.a1, s.a2])
        }

        guard let setup = vDSP_biquad_CreateSetup(coefficients, vDSP_Length(sections.count)) else {
            fatalError("vDSP_biquad_CreateSetup failed")
        }
        defer { vDSP_biquad_DestroySetup(setup) }

        var delay = [Float](repeating: 0, count: 2 * sections.count + 2)
        var output = [Float](repeating: 0, count: signal.count)

        signal.withUnsafeBufferPointer { x in
            output.withUnsafeMutableBufferPointer { y in
                delay.withUnsafeMutableBufferPointer { d in
                    vDSP_biquad(setup, d.baseAddress!, x.baseAddress!, 1, y.baseAddress!, 1, vDSP_Length(signal.count))
                }
            }
        }
        return output
    }

    /// Zero-phase (forward-backward) filtering, mirroring `scipy.signal.sosfiltfilt`'s
    /// default behavior: odd-reflection padding at both ends (padlen matching scipy's
    /// default formula `3 * (2 * n_sections + 1)`) before the forward/reverse/forward/
    /// reverse passes, trimmed back off afterward. This keeps bands/envelopes time-aligned
    /// (no net phase shift) so they recombine correctly during mixdown -- a single-pass
    /// filter would shift each band's phase by a different amount, smearing transients
    /// across bands once they're summed.
    ///
    /// scipy starts each pass from a steady-state initial condition (`sosfilt_zi`, solved
    /// algebraically per section) rather than zero, which minimizes the startup transient.
    /// `vDSP_biquad`'s internal delay-state layout isn't part of its documented contract,
    /// so rather than reverse-engineer it to inject that state directly, each pass here is
    /// preceded by a constant "run-in" (held at the pass's boundary sample) long enough for
    /// the filter to settle close to the same steady state on its own, then discarded --
    /// same effect, without depending on undocumented internals. `warmupSamples: 600` was
    /// enough to bring the match against scipy's `sosfiltfilt` down to float32 noise level
    /// (~1e-5 absolute, full array including edges) for this project's filter orders
    /// (always 4) -- see CIVocoderKitTests.
    static func filtfilt(_ sections: [BiquadSection], _ signal: [Float], warmupSamples: Int = 600) -> [Float] {
        guard !sections.isEmpty, signal.count > 1 else { return signal }

        let padlen = min(3 * (2 * sections.count + 1), signal.count - 1)
        let padded = oddExtend(signal, padlen: padlen)

        var y = applyWithWarmup(sections, to: padded, warmup: warmupSamples)
        y.reverse()
        y = applyWithWarmup(sections, to: y, warmup: warmupSamples)
        y.reverse()

        guard padlen > 0 else { return y }
        return Array(y[padlen..<(y.count - padlen)])
    }

    private static func applyWithWarmup(_ sections: [BiquadSection], to signal: [Float], warmup: Int) -> [Float] {
        guard warmup > 0, let first = signal.first else { return apply(sections, to: signal) }
        let runIn = [Float](repeating: first, count: warmup)
        let filtered = apply(sections, to: runIn + signal)
        return Array(filtered[warmup...])
    }

    /// scipy's `odd_ext`: reflect each end through the boundary sample so the padded
    /// signal's slope/level continues smoothly instead of jumping.
    private static func oddExtend(_ x: [Float], padlen: Int) -> [Float] {
        guard padlen > 0 else { return x }
        let left = (1...padlen).reversed().map { 2 * x[0] - x[$0] }
        let right = (1...padlen).map { 2 * x[x.count - 1] - x[x.count - 1 - $0] }
        return left + x + right
    }
}
