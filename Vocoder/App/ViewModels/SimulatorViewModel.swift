import Foundation
import CIVocoderKit
import Observation

/// Owns all Simulator-screen state and behavior: clip selection, channel/carrier
/// settings, the record/import flows, and the playback decisions that follow from
/// them. `SimulatorView` reads this and calls its methods -- it holds no business
/// logic of its own, only layout and animation-only UI state (nothing here persists
/// across launches; that's a reasonable scope boundary for a fun demo app's settings).
@Observable
@MainActor
final class SimulatorViewModel {
    static let channelOptions = [4, 8, 16, 22]

    let library = AudioLibrary()
    let engine = VocoderEngine()
    let recorder = AudioRecorderController()

    var selectedSourceID: String?
    var channelIndex = 1 // index into channelOptions, default N=8
    var carrierType: CarrierType = .noise

    var showingRecordSheet = false
    var showingFileImporter = false
    var showingPermissionDeniedAlert = false

    var channels: Int { Self.channelOptions[channelIndex] }

    var selectedSource: AudioSource? {
        library.sources.first { $0.id == selectedSourceID } ?? library.sources.first
    }

    var isPlayingOriginal: Bool { engine.nowPlaying?.original == true }
    var isPlayingSimulated: Bool { engine.nowPlaying?.original == false }

    /// Channel/carrier settings only affect the *simulated* playback -- they're inert
    /// while Original is playing (or about to), so the controls are disabled then
    /// rather than left interactive but meaningless.
    var settingsEnabled: Bool { !isPlayingOriginal && !engine.isProcessing }

    var contextDescription: String {
        let channelDescription: String
        switch channels {
        case 4: channelDescription = "Very few channels — expect garbled, hard-to-follow speech"
        case 8: channelDescription = "Few channels — reduced clarity, still effortful"
        case 16: channelDescription = "Many channels — approaching normal clarity"
        default: channelDescription = "Most channels — close to intelligible speech"
        }
        let carrierDescription = carrierType == .noise
            ? "noise carrier (textured, hiss-like)"
            : "tone carrier (buzzy, whistle-like)"
        return "\(channelDescription), \(carrierDescription)."
    }

    func onAppear() {
        recorder.checkPermission()
        if selectedSourceID == nil { selectedSourceID = library.sources.first?.id }
    }

    // MARK: - Clip selection

    func selectSource(_ source: AudioSource) {
        guard source.id != selectedSource?.id else { return }
        Haptics.selection()
        selectedSourceID = source.id
        engine.stop()
    }

    func deleteSource(_ source: AudioSource) {
        if selectedSourceID == source.id { selectedSourceID = nil }
        engine.forget(source.id)
        library.delete(source)
    }

    // MARK: - Settings (reprocess mid-playback when relevant)

    func selectChannelIndex(_ index: Int) {
        guard channelIndex != index else { return }
        Haptics.selection()
        channelIndex = index
        reprocessIfPlayingSimulated()
    }

    func carrierTypeChanged() {
        Haptics.selection()
        reprocessIfPlayingSimulated()
    }

    /// Changing a setting while the simulated version of the *currently selected* source
    /// is playing restarts playback with the new settings (clean stop-and-restart, no
    /// overlapping buffers/clicks). Changing a setting while stopped, or while the
    /// original is playing, just updates state -- no surprise audio from merely tapping
    /// a bar or toggling the carrier.
    private func reprocessIfPlayingSimulated() {
        guard let source = selectedSource,
              let nowPlaying = engine.nowPlaying,
              nowPlaying.original == false,
              nowPlaying.sourceID == source.id else { return }
        engine.play(source, original: false, channels: channels, carrierType: carrierType)
    }

    // MARK: - Playback (each button toggles: tap to play, tap again to stop)

    func toggleOriginal() {
        if isPlayingOriginal {
            stopPlayback()
        } else {
            guard let source = selectedSource else { return }
            Haptics.impact(.light)
            engine.play(source, original: true, channels: channels, carrierType: carrierType)
        }
    }

    func toggleSimulated() {
        if isPlayingSimulated {
            stopPlayback()
        } else {
            guard let source = selectedSource else { return }
            Haptics.impact(.medium)
            engine.play(source, original: false, channels: channels, carrierType: carrierType)
        }
    }

    private func stopPlayback() {
        Haptics.impact(.light)
        engine.stop()
    }

    // MARK: - Record / import

    func beginRecordFlow() {
        switch recorder.permissionState {
        case .granted:
            showingRecordSheet = true
        case .undetermined:
            recorder.requestPermissionAndStart { [weak self] granted in
                if granted {
                    self?.showingRecordSheet = true
                } else {
                    self?.showingPermissionDeniedAlert = true
                }
            }
        case .denied:
            showingPermissionDeniedAlert = true
        }
    }

    func beginImportFlow() {
        showingFileImporter = true
    }

    func recordingFinished(tempURL: URL) {
        do {
            let added = try library.addRecording(from: tempURL)
            selectedSourceID = added.id
            Haptics.success()
        } catch {
            engine.errorMessage = "\(error)"
        }
    }

    func fileImportFinished(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let added = try library.addImportedFile(from: url)
                selectedSourceID = added.id
                Haptics.success()
            } catch {
                engine.errorMessage = "\(error)"
            }
        case .failure(let error):
            engine.errorMessage = "\(error)"
        }
    }
}
