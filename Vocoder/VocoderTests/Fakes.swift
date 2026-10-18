import Foundation
import CIVocoderKit
@testable import Vocoder

/// In-memory stand-in for `AudioLibrary` -- records what was asked of it instead of
/// touching the filesystem, so view model tests stay fast and deterministic.
@MainActor
final class FakeAudioLibrary: AudioLibraryProviding {
    var sources: [AudioSource] = []
    var reloadCallCount = 0
    var deletedSources: [AudioSource] = []

    var addRecordingResult: Result<AudioSource, Error> = .failure(CocoaError(.fileNoSuchFile))
    var addImportedFileResult: Result<AudioSource, Error> = .failure(CocoaError(.fileNoSuchFile))

    func reload() { reloadCallCount += 1 }

    func addRecording(from tempURL: URL) throws -> AudioSource {
        try addRecordingResult.get()
    }

    func addImportedFile(from sourceURL: URL) throws -> AudioSource {
        try addImportedFileResult.get()
    }

    func delete(_ source: AudioSource) {
        deletedSources.append(source)
        sources.removeAll { $0.id == source.id }
    }
}

/// In-memory stand-in for `VocoderEngine` -- records play/stop/forget calls instead of
/// driving real `AVAudioEngine` playback, so view model tests don't touch audio hardware.
@MainActor
final class FakeVocoderEngine: VocoderEngineProviding {
    struct PlayCall: Equatable {
        let sourceID: String
        let original: Bool
        let channels: Int
        let carrierType: CarrierType
    }

    var isPlaying = false
    var isProcessing = false
    var nowPlaying: (sourceID: String, original: Bool)?
    var errorMessage: String?
    private(set) var playCalls: [PlayCall] = []
    private(set) var stopCallCount = 0
    private(set) var forgottenSourceIDs: [String] = []

    func play(_ source: AudioSource, original: Bool, channels: Int, carrierType: CarrierType) {
        playCalls.append(PlayCall(sourceID: source.id, original: original, channels: channels, carrierType: carrierType))
        nowPlaying = (source.id, original)
        isPlaying = true
    }

    func stop() {
        stopCallCount += 1
        isPlaying = false
        nowPlaying = nil
    }

    func forget(_ sourceID: String) {
        forgottenSourceIDs.append(sourceID)
        if nowPlaying?.sourceID == sourceID { stop() }
    }
}

/// In-memory stand-in for `AudioRecorderController` -- lets tests drive every
/// permission branch without a real microphone prompt.
@MainActor
final class FakeAudioRecorderController: AudioRecorderControlling {
    var isRecording = false
    var elapsed: TimeInterval = 0
    var errorMessage: String?
    var permissionState: AudioRecorderController.PermissionState = .undetermined
    /// What `requestPermissionAndStart` resolves to when called.
    var requestPermissionGrants = true
    private(set) var checkPermissionCallCount = 0
    private(set) var startRecordingCallCount = 0
    private(set) var stopRecordingCallCount = 0
    private(set) var cancelRecordingCallCount = 0

    func checkPermission() { checkPermissionCallCount += 1 }

    func requestPermissionAndStart(completion: @escaping (Bool) -> Void) {
        permissionState = requestPermissionGrants ? .granted : .denied
        completion(requestPermissionGrants)
    }

    func startRecording() {
        startRecordingCallCount += 1
        isRecording = true
    }

    func stopRecording() -> URL? {
        stopRecordingCallCount += 1
        isRecording = false
        return nil
    }

    func cancelRecording() {
        cancelRecordingCallCount += 1
        isRecording = false
    }
}

/// Builds a throwaway `AudioSource` for tests -- the URL never needs to resolve to a
/// real file since these tests never touch `AudioFileLoader`.
func makeSource(id: String = "source-1", name: String = "Test Clip", kind: AudioSourceKind = .bundledSpeech) -> AudioSource {
    AudioSource(id: id, name: name, kind: kind, url: URL(fileURLWithPath: "/tmp/\(id).wav"))
}
