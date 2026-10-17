import Foundation

/// Minimal complex-number arithmetic for Butterworth filter design (pole placement,
/// the lowpass->bandpass transform, and the bilinear transform). Accelerate has no
/// filter-design API to reuse here -- only `vDSP_biquad` to *apply* coefficients once
/// designed -- so this small amount of textbook complex math is unavoidable.
struct Complex {
    var re: Double
    var im: Double

    init(_ re: Double, _ im: Double = 0) {
        self.re = re
        self.im = im
    }

    static func + (l: Complex, r: Complex) -> Complex { Complex(l.re + r.re, l.im + r.im) }
    static func - (l: Complex, r: Complex) -> Complex { Complex(l.re - r.re, l.im - r.im) }
    static prefix func - (r: Complex) -> Complex { Complex(-r.re, -r.im) }

    static func * (l: Complex, r: Complex) -> Complex {
        Complex(l.re * r.re - l.im * r.im, l.re * r.im + l.im * r.re)
    }
    static func * (l: Complex, r: Double) -> Complex { Complex(l.re * r, l.im * r) }

    static func / (l: Complex, r: Complex) -> Complex {
        let denom = r.re * r.re + r.im * r.im
        return Complex((l.re * r.re + l.im * r.im) / denom, (l.im * r.re - l.re * r.im) / denom)
    }

    var conjugate: Complex { Complex(re, -im) }
    var magnitudeSquared: Double { re * re + im * im }

    /// Principal branch square root (matches numpy's `csqrt` convention).
    func sqrt() -> Complex {
        let r = (re * re + im * im).squareRoot()
        let theta = Foundation.atan2(im, re)
        let sqrtR = r.squareRoot()
        return Complex(sqrtR * Foundation.cos(theta / 2), sqrtR * Foundation.sin(theta / 2))
    }
}
