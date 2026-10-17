/// Channel-vocoder cochlear-implant simulation core.
///
/// Mirrors the validated Python prototype in `notebooks/vocoder.py`: a five-stage
/// pipeline (filterbank, envelope extraction, carrier generation, modulation,
/// mixdown) built on `vDSP`/Accelerate rather than hand-rolled DSP primitives.
public enum CIVocoderKit {
    public static let version = "0.1.0"
}
