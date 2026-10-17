import AVFoundation

enum AudioFileLoader {
    enum LoadError: Error {
        case cannotLoad(URL)
    }

    /// Load any AVFoundation-readable audio file (WAV, M4A/AAC, MP3, AIFF, CAF, ...)
    /// into a Float32 `AVAudioPCMBuffer` at its native sample rate. Used uniformly for
    /// bundled, recorded, and imported sources -- they're all just a URL by the time
    /// they reach here.
    static func load(url: URL) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw LoadError.cannotLoad(url)
        }
        try file.read(into: buffer)
        return buffer
    }
}
