"""
Channel-vocoder cochlear-implant simulation — validated reference implementation.

Extracted from 01_filterbank.ipynb through 04_full_pipeline_compare.ipynb once
the phase-1 exit gate was confirmed by ear (N=4 garbled, N=16-22 intelligible).
This is the implementation Phase 2's Swift CIVocoderKit port is translated from.

Method: Shannon et al. 1995, "Speech Recognition with Primarily Temporal Cues"
(Science, 270(5234), 303-304).
"""
import numpy as np
import soundfile as sf
from scipy import signal


def load_raw(path):
    """Load a WAV file as mono float32, returning (audio, native_sample_rate)."""
    audio, native_sr = sf.read(path)
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    return audio.astype(np.float32), native_sr


def resample_to(audio, native_sr, target_sr):
    """Resample audio to target_sr (no-op if already at that rate)."""
    if native_sr == target_sr:
        return audio
    n_samples = int(len(audio) * target_sr / native_sr)
    return signal.resample(audio, n_samples).astype(np.float32)


def design_filterbank(n_channels, sr, f_min=200, f_max=7000, order=4):
    """Return (sos_list, edges, centers) for N log-spaced Butterworth bandpass filters."""
    edges = np.logspace(np.log10(f_min), np.log10(f_max), n_channels + 1)
    centers = np.sqrt(edges[:-1] * edges[1:])  # geometric mean = center freq per band

    nyquist = sr / 2
    sos_list = [
        signal.butter(order, [lo / nyquist, hi / nyquist], btype="bandpass", output="sos")
        for lo, hi in zip(edges[:-1], edges[1:])
    ]
    return sos_list, edges, centers


def split_into_bands(audio, sos_list):
    """Apply each bandpass filter to audio, zero-phase (sosfiltfilt)."""
    return [signal.sosfiltfilt(sos, audio) for sos in sos_list]


def envelope_rectify_lowpass(band, sr, cutoff=400, order=4):
    """Extract a band's amplitude envelope: full-wave rectify, then lowpass."""
    rectified = np.abs(band)
    nyquist = sr / 2
    sos = signal.butter(order, cutoff / nyquist, btype="lowpass", output="sos")
    return signal.sosfiltfilt(sos, rectified)


def extract_envelopes(bands, sr, cutoff=400, order=4):
    return [envelope_rectify_lowpass(b, sr, cutoff, order) for b in bands]


def generate_noise_carrier(sos, length, sr, rng):
    """White noise filtered through the band's own filter, confining it to that band."""
    white = rng.standard_normal(length).astype(np.float32)
    return signal.sosfiltfilt(sos, white)


def generate_tone_carrier(center_freq, length, sr):
    """Pure sine at the band's center frequency."""
    t = np.arange(length) / sr
    return np.sin(2 * np.pi * center_freq * t).astype(np.float32)


def generate_carriers(carrier_type, filterbank, centers, length, sr, rng):
    if carrier_type == "noise":
        return [generate_noise_carrier(sos, length, sr, rng) for sos in filterbank]
    elif carrier_type == "tone":
        return [generate_tone_carrier(c, length, sr) for c in centers]
    else:
        raise ValueError(f"unknown carrier_type: {carrier_type!r}")


def modulate_bands(envelopes, carriers):
    return [env * car for env, car in zip(envelopes, carriers)]


def mixdown(modulated_bands, headroom=0.95):
    """Sum modulated bands and peak-normalize to `headroom` to avoid clipping."""
    summed = np.sum(modulated_bands, axis=0)
    peak = np.max(np.abs(summed))
    if peak > 0:
        summed = summed / peak * headroom
    return summed.astype(np.float32)


def vocode(audio, sr, n_channels, carrier_type, f_min=200, f_max=7000,
           filter_order=4, env_cutoff=400, rng=None):
    """Channel-vocode `audio` into `n_channels` log-spaced bands using either a
    `noise` or `tone` carrier per band. Returns a normalized, clip-safe float32
    array at the same sample rate as the input.
    """
    if rng is None:
        rng = np.random.default_rng(0)

    filterbank, edges, centers = design_filterbank(n_channels, sr, f_min, f_max, filter_order)
    bands = split_into_bands(audio, filterbank)
    envelopes = extract_envelopes(bands, sr, env_cutoff, filter_order)
    carriers = generate_carriers(carrier_type, filterbank, centers, len(audio), sr, rng)
    modulated = modulate_bands(envelopes, carriers)
    return mixdown(modulated)
