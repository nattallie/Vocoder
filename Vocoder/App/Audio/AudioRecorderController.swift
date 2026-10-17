import AVFoundation
import AVFAudio
import Observation

/// Drives a single mic recording session into a temp file. The caller (AudioLibrary)
/// takes ownership of that file once the user chooses to save it; `cancelRecording`
/// deletes it instead. Not a vocoder input -- the recording becomes a new source clip
/// processed like any other, not live-vocoded while speaking into the mic.
@Observable
@MainActor
final class AudioRecorderController: NSObject {
    enum PermissionState {
        case undetermined
        case granted
        case denied
    }

    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    var errorMessage: String?
    private(set) var permissionState: PermissionState = .undetermined

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var startDate: Date?
    @ObservationIgnored private var tempURL: URL?

    override init() {
        super.init()
        checkPermission()
    }

    func checkPermission() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: permissionState = .granted
        case .denied: permissionState = .denied
        case .undetermined: permissionState = .undetermined
        @unknown default: permissionState = .undetermined
        }
    }

    func requestPermissionAndStart(completion: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                self?.permissionState = granted ? .granted : .denied
                completion(granted)
            }
        }
    }

    func startRecording() {
        errorMessage = nil
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        tempURL = tmp

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)

            let newRecorder = try AVAudioRecorder(url: tmp, settings: settings)
            newRecorder.delegate = self
            newRecorder.record()
            recorder = newRecorder
            isRecording = true
            startDate = Date()
            elapsed = 0

            let newTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let start = self.startDate else { return }
                    self.elapsed = Date().timeIntervalSince(start)
                }
            }
            RunLoop.main.add(newTimer, forMode: .common)
            timer = newTimer
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// Stop and hand back the temp file URL for the caller to keep (or discard).
    @discardableResult
    func stopRecording() -> URL? {
        recorder?.stop()
        recorder = nil
        timer?.invalidate()
        timer = nil
        isRecording = false
        let url = tempURL
        tempURL = nil
        return url
    }

    func cancelRecording() {
        recorder?.stop()
        recorder = nil
        timer?.invalidate()
        timer = nil
        isRecording = false
        if let url = tempURL {
            try? FileManager.default.removeItem(at: url)
        }
        tempURL = nil
    }
}

extension AudioRecorderController: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard !flag else { return }
        Task { @MainActor [weak self] in
            self?.errorMessage = "Recording did not finish successfully."
        }
    }
}
