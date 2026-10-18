import AVFoundation
import CIVocoderKit
import Observation

/// Owns the `AVAudioEngine` graph and exposes simple play/stop controls for the
/// original vs. vocoded A/B comparison. One player node, buffers swapped per-play
/// rather than kept connected simultaneously, since only one plays at a time.
@Observable
@MainActor
final class VocoderEngine {
    private(set) var isPlaying = false
    /// True while a `vocode()` call is running on a background task for a `play()`
    /// that hasn't started audio yet -- lets the UI show a loading state instead of
    /// the main thread just going quiet for the duration of the DSP work.
    private(set) var isProcessing = false
    /// What's currently playing (nil when stopped) -- lets the UI decide whether
    /// changing a setting mid-playback should reprocess + restart (only makes sense
    /// while playing the *simulated* version of something).
    private(set) var nowPlaying: (sourceID: String, original: Bool)?
    var errorMessage: String?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private var originalBuffers: [String: AVAudioPCMBuffer] = [:]
    @ObservationIgnored private var engineStarted = false
    /// Sample rate/channel count the player->mixer connection is currently wired for.
    /// Bundled clips alone span two sample rates (speech 16kHz, music 44.1kHz), and any
    /// imported file could carry a third -- without tracking this, the connection (made
    /// once, lazily) stayed locked to whichever format played first, so a later clip at
    /// a different rate fed a mismatched buffer into it: wrong-speed audio or a hard
    /// AVAudioEngine crash.
    @ObservationIgnored private var connectedSampleRate: Double?
    @ObservationIgnored private var connectedChannelCount: AVAudioChannelCount?
    /// Identifies the most recent `play()` call, so a stale completion handler from a
    /// buffer `stop()` just cancelled can't be mistaken for the new one that replaced
    /// it -- (sourceID, original) alone isn't unique enough: changing *just* the channel
    /// count mid-playback calls play() again with the same source/original, so the old
    /// handler's guard would otherwise match the new state and wipe it out immediately.
    @ObservationIgnored private var currentPlaybackToken: UUID?

    init() {
        engine.attach(player)
    }

    private func ensureEngineRunning(format: AVAudioFormat) throws {
        let formatChanged = connectedSampleRate != format.sampleRate || connectedChannelCount != format.channelCount
        if formatChanged {
            if engine.isRunning { engine.stop() }
            if !engine.outputConnectionPoints(for: player, outputBus: 0).isEmpty {
                engine.disconnectNodeOutput(player)
            }
            engine.connect(player, to: engine.mainMixerNode, format: format)
            connectedSampleRate = format.sampleRate
            connectedChannelCount = format.channelCount
        }

        // Recording (AudioRecorderController) switches the session to .playAndRecord and
        // never switches it back; re-asserting .playback on every play() -- not just the
        // first one ever -- is what actually guarantees correct output routing after a
        // recording, since engine.isRunning alone would otherwise skip this forever once
        // true. Cheap to call even when already set.
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)

        if !engine.isRunning {
            try engine.start()
            engineStarted = true
        }
    }

    private func buffer(for source: AudioSource) throws -> AVAudioPCMBuffer {
        if let cached = originalBuffers[source.id] { return cached }
        let loaded = try AudioFileLoader.load(url: source.url)
        originalBuffers[source.id] = loaded
        return loaded
    }

    /// Stop whatever's playing, then play either the original clip or a vocoded version.
    /// Always a clean stop-and-restart (never overlapping playback) to avoid clicks/pops
    /// when switching settings mid-playback. The vocode() call -- the actual CPU-bound
    /// DSP work, and the thing that was making the UI feel frozen on tap -- runs on a
    /// background task; `isProcessing` is true for exactly that window, so the UI can
    /// show a loading state instead of just going unresponsive for however long it takes.
    func play(_ source: AudioSource, original: Bool, channels: Int, carrierType: CarrierType) {
        stop()
        do {
            let sourceBuffer = try buffer(for: source)
            if original {
                startPlayback(sourceBuffer, source: source, original: true)
                return
            }

            isProcessing = true
            let token = UUID()
            currentPlaybackToken = token
            Task.detached(priority: .userInitiated) { [weak self] in
                let vocoded = CIVocoder.vocode(buffer: sourceBuffer, channels: channels, carrierType: carrierType)
                await MainActor.run {
                    guard let self, self.currentPlaybackToken == token else { return } // superseded while processing
                    self.isProcessing = false
                    self.startPlayback(vocoded, source: source, original: false)
                }
            }
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// State is set *before* touching the engine, not after: `ensureEngineRunning` can
    /// block the main thread for tens of milliseconds on the first play of a session
    /// (activating the audio session, starting the engine) -- setting isPlaying/
    /// nowPlaying only once that returns meant the UI had no chance to render "now
    /// playing" until right as (or after) audio had already started. Setting it first
    /// gives SwiftUI the earliest possible opportunity to update before sound begins;
    /// on failure, the optimistic state is rolled back.
    private func startPlayback(_ bufferToPlay: AVAudioPCMBuffer, source: AudioSource, original: Bool) {
        let token = UUID()
        currentPlaybackToken = token
        isPlaying = true
        nowPlaying = (source.id, original)
        do {
            try ensureEngineRunning(format: bufferToPlay.format)
            player.scheduleBuffer(bufferToPlay, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.currentPlaybackToken == token else { return }
                    self.isPlaying = false
                    self.nowPlaying = nil
                }
            }
            player.play()
        } catch {
            guard currentPlaybackToken == token else { return }
            currentPlaybackToken = nil
            isPlaying = false
            nowPlaying = nil
            errorMessage = "\(error)"
        }
    }

    func stop() {
        currentPlaybackToken = nil
        player.stop()
        isPlaying = false
        isProcessing = false
        nowPlaying = nil
    }

    /// Drop a cached decoded buffer (e.g. after the user deletes that source) and stop
    /// playback if it's the thing currently playing.
    func forget(_ sourceID: String) {
        originalBuffers[sourceID] = nil
        if nowPlaying?.sourceID == sourceID {
            stop()
        }
    }
}
