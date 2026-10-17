import AVFoundation

/// `AVAudioPCMBuffer` convenience wrapper around `CIVocoder.vocode(audio:sampleRate:...)`,
/// for callers wiring this into `AVAudioEngine` rather than working with raw `[Float]`.
extension CIVocoder {
    /// Channel-vocode `buffer`, returning a new mono Float32 buffer at the same sample
    /// rate. Multi-channel input is downmixed to mono first (channel average), mirroring
    /// `load_raw`'s `audio.mean(axis=1)` in `notebooks/vocoder.py`.
    public static func vocode(
        buffer: AVAudioPCMBuffer,
        channels: Int,
        carrierType: CarrierType,
        fMin: Double = 200,
        fMax: Double = 7000,
        filterOrder: Int = 4,
        envelopeCutoffHz: Double = 400,
        seed: UInt64 = 0
    ) -> AVAudioPCMBuffer {
        let sampleRate = buffer.format.sampleRate
        let mono = buffer.monoFloatSamples()

        let result = vocode(
            audio: mono,
            sampleRate: sampleRate,
            channels: channels,
            carrierType: carrierType,
            fMin: fMin,
            fMax: fMax,
            filterOrder: filterOrder,
            envelopeCutoffHz: envelopeCutoffHz,
            seed: seed
        )

        return AVAudioPCMBuffer.make(fromMonoFloatSamples: result, sampleRate: sampleRate)
    }
}

extension AVAudioPCMBuffer {
    /// Downmix (channel average) to a plain `[Float]`, regardless of input channel count.
    func monoFloatSamples() -> [Float] {
        guard let data = floatChannelData else { return [] }
        let frameCount = Int(frameLength)
        let channelCount = Int(format.channelCount)
        guard frameCount > 0, channelCount > 0 else { return [] }

        if channelCount == 1 {
            return Array(UnsafeBufferPointer(start: data[0], count: frameCount))
        }

        var mono = [Float](repeating: 0, count: frameCount)
        for c in 0..<channelCount {
            let channel = UnsafeBufferPointer(start: data[c], count: frameCount)
            for i in 0..<frameCount { mono[i] += channel[i] }
        }
        let scale = 1.0 / Float(channelCount)
        for i in 0..<frameCount { mono[i] *= scale }
        return mono
    }

    /// Build a mono Float32 PCM buffer from plain samples at the given sample rate.
    static func make(fromMonoFloatSamples samples: [Float], sampleRate: Double) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = buffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { src in
                channel.update(from: src.baseAddress!, count: samples.count)
            }
        }
        return buffer
    }
}
