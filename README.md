# Vocoder

A channel-vocoder simulation of cochlear implant (CI) hearing — hear what music or speech sounds like through a CI, with adjustable channel count (4/8/16/22) and carrier type (noise/tone). Built in two stages: a validated Python/NumPy prototype of the DSP pipeline, then a native Swift port — a reusable `CIVocoderKit` package (Accelerate/vDSP) plus a SwiftUI demo app (AVAudioEngine).

**Disclaimer:** educational simulation, not a medical device or an accurate representation of any individual's hearing.

## Demo

[▶ Speech through the simulator](media/demo-speech.mp4) — 22 channels, tone carrier.

## How it works

A channel vocoder splits audio into N log-spaced frequency bands, extracts each band's amplitude envelope (the loudness-over-time contour — roughly what a CI electrode can actually transmit), and re-synthesizes the sound from just that envelope applied to a synthetic carrier (filtered noise or a pure tone) per band. Discarding the fine spectral detail within each band and keeping only coarse frequency + envelope information approximates what a real CI listener receives. This reconstructs the classic method from Shannon et al. (1995) — see [References](#references).

## Repository structure

```
notebooks/       Jupyter prototype of the DSP pipeline
samples/         Test audio: a short speech clip, a short music clip
CIVocoderKit/    The reusable Swift Package (DSP core)
Vocoder/         The SwiftUI demo app
media/           Demo clips
```

## References

This project reconstructs the classic CI-simulation method and its design choices from:

- Shannon, R. V., Zeng, F.-G., Kamath, V., Wygonski, J., & Ekelid, M. (1995). Speech recognition with primarily temporal cues. *Science*, 270(5234), 303–304. https://doi.org/10.1126/science.270.5234.303
- Greenwood, D. D. (1990). A cochlear frequency-position function for several species — 29 years later. *Journal of the Acoustical Society of America*, 87(6), 2592–2605. https://doi.org/10.1121/1.399052 — basis for log-spacing the filterbank.
- Drullman, R., Festen, J. M., & Plomp, R. (1994). Effect of temporal envelope smearing on speech reception. *Journal of the Acoustical Society of America*, 95(2), 1053–1064. — basis for the envelope lowpass cutoff.
- Cychosz, M., Winn, M. B., & Goupell, M. J. (2024). How to vocode: Using channel vocoders for cochlear-implant research. *Journal of the Acoustical Society of America*, 155(4), 2407–2437. https://doi.org/10.1121/10.0025274

`samples/music.wav` is an excerpt of Chopin's Nocturne Op. 9 No. 2, performed by Aaron Dunn, from the [Musopen Chopin Collection](https://archive.org/details/musopen-chopin) (CC0 1.0 Universal).
