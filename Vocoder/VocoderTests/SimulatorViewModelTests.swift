import Testing
import Foundation
import CIVocoderKit
@testable import Vocoder

@MainActor
private func makeViewModel(
    sources: [AudioSource] = [makeSource(id: "a", name: "A"), makeSource(id: "b", name: "B")]
) -> (viewModel: SimulatorViewModel, library: FakeAudioLibrary, engine: FakeVocoderEngine, recorder: FakeAudioRecorderController) {
    let library = FakeAudioLibrary()
    library.sources = sources
    let engine = FakeVocoderEngine()
    let recorder = FakeAudioRecorderController()
    let viewModel = SimulatorViewModel(library: library, engine: engine, recorder: recorder)
    return (viewModel, library, engine, recorder)
}

@MainActor
@Suite struct SimulatorViewModelChannelsAndDescriptionTests {
    @Test func defaultsToEightChannels() {
        let (viewModel, _, _, _) = makeViewModel()
        #expect(viewModel.channels == 8)
    }

    @Test(arguments: [
        (0, 4, "garbled"), (1, 8, "reduced clarity"), (2, 16, "approaching normal"), (3, 22, "Most channels"),
    ])
    func contextDescriptionNamesTheChannelCount(_ fixture: (index: Int, channels: Int, expectedSubstring: String)) {
        let (viewModel, _, _, _) = makeViewModel()
        viewModel.selectChannelIndex(fixture.index)
        #expect(viewModel.channels == fixture.channels)
        #expect(viewModel.contextDescription.contains(fixture.expectedSubstring))
    }

    @Test func contextDescriptionNamesTheCarrierType() {
        let (viewModel, _, _, _) = makeViewModel()
        #expect(viewModel.contextDescription.contains("noise carrier"))
        viewModel.carrierType = .tone
        #expect(viewModel.contextDescription.contains("tone carrier"))
    }
}

@MainActor
@Suite struct SimulatorViewModelSourceSelectionTests {
    @Test func onAppearChecksPermissionAndSelectsFirstSourceByDefault() {
        let (viewModel, _, _, recorder) = makeViewModel()
        viewModel.onAppear()
        #expect(recorder.checkPermissionCallCount == 1)
        #expect(viewModel.selectedSource?.id == "a")
    }

    @Test func onAppearDoesNotOverrideAnAlreadySelectedSource() {
        let (viewModel, _, _, _) = makeViewModel()
        viewModel.selectSource(makeSource(id: "b", name: "B"))
        viewModel.onAppear()
        #expect(viewModel.selectedSource?.id == "b")
    }

    @Test func selectedSourceFallsBackToFirstWhenSelectionIsMissing() {
        let (viewModel, _, _, _) = makeViewModel()
        #expect(viewModel.selectedSource?.id == "a")
    }

    @Test func selectingASourceUpdatesSelectionAndStopsPlayback() {
        let (viewModel, _, engine, _) = makeViewModel()
        viewModel.selectSource(makeSource(id: "b", name: "B"))
        #expect(viewModel.selectedSource?.id == "b")
        #expect(engine.stopCallCount == 1)
    }

    @Test func reselectingTheSameSourceIsANoOp() {
        let (viewModel, _, engine, _) = makeViewModel()
        viewModel.selectSource(makeSource(id: "a", name: "A"))
        #expect(engine.stopCallCount == 0)
    }

    @Test func deletingTheSelectedSourceClearsSelectionAndForgetsItsBuffer() {
        let (viewModel, library, engine, _) = makeViewModel()
        let source = makeSource(id: "a", name: "A")

        viewModel.deleteSource(source)

        #expect(viewModel.selectedSourceID == nil)
        #expect(engine.forgottenSourceIDs == ["a"])
        #expect(library.deletedSources.map(\.id) == ["a"])
    }

    @Test func deletingAnUnselectedSourceLeavesSelectionAlone() {
        let (viewModel, _, _, _) = makeViewModel()
        viewModel.selectSource(makeSource(id: "b", name: "B"))

        viewModel.deleteSource(makeSource(id: "a", name: "A"))

        #expect(viewModel.selectedSourceID == "b")
    }
}

@MainActor
@Suite struct SimulatorViewModelSettingsReprocessingTests {
    @Test func changingChannelsWhileStoppedJustUpdatesState() {
        let (viewModel, _, engine, _) = makeViewModel()
        viewModel.selectChannelIndex(2)
        #expect(viewModel.channels == 16)
        #expect(engine.playCalls.isEmpty)
    }

    @Test func settingTheSameChannelIndexIsANoOp() {
        let (viewModel, _, engine, _) = makeViewModel()
        viewModel.selectChannelIndex(1) // already the default
        #expect(engine.playCalls.isEmpty)
    }

    @Test func changingChannelsWhilePlayingTheOriginalDoesNotReprocess() {
        let (viewModel, _, engine, _) = makeViewModel()
        engine.nowPlaying = ("a", true) // original

        viewModel.selectChannelIndex(2)

        #expect(engine.playCalls.isEmpty)
    }

    @Test func changingChannelsWhilePlayingSimulatedForAnotherSourceDoesNotReprocess() {
        let (viewModel, _, engine, _) = makeViewModel()
        viewModel.selectSource(makeSource(id: "a", name: "A"))
        engine.nowPlaying = ("b", false) // simulated, but a different source than selected

        viewModel.selectChannelIndex(2)

        #expect(engine.playCalls.isEmpty)
    }

    @Test func changingChannelsWhilePlayingSimulatedForTheSelectedSourceRestartsPlayback() {
        let (viewModel, _, engine, _) = makeViewModel()
        viewModel.selectSource(makeSource(id: "a", name: "A"))
        engine.nowPlaying = ("a", false) // simulated, selected source

        viewModel.selectChannelIndex(2)

        #expect(engine.playCalls.last == .init(sourceID: "a", original: false, channels: 16, carrierType: .noise))
    }

    @Test func changingCarrierWhilePlayingSimulatedForTheSelectedSourceRestartsPlayback() {
        let (viewModel, _, engine, _) = makeViewModel()
        viewModel.selectSource(makeSource(id: "a", name: "A"))
        engine.nowPlaying = ("a", false)
        viewModel.carrierType = .tone

        viewModel.carrierTypeChanged()

        #expect(engine.playCalls.last == .init(sourceID: "a", original: false, channels: 8, carrierType: .tone))
    }
}

@MainActor
@Suite struct SimulatorViewModelPlaybackTests {
    @Test func toggleOriginalPlaysTheSelectedSourceAsOriginal() {
        let (viewModel, _, engine, _) = makeViewModel()
        viewModel.toggleOriginal()
        #expect(engine.playCalls == [.init(sourceID: "a", original: true, channels: 8, carrierType: .noise)])
    }

    @Test func toggleOriginalAgainWhilePlayingStops() {
        let (viewModel, _, engine, _) = makeViewModel()
        engine.nowPlaying = ("a", true)
        viewModel.toggleOriginal()
        #expect(engine.stopCallCount == 1)
    }

    @Test func toggleSimulatedPlaysTheSelectedSourceAsSimulated() {
        let (viewModel, _, engine, _) = makeViewModel()
        viewModel.toggleSimulated()
        #expect(engine.playCalls == [.init(sourceID: "a", original: false, channels: 8, carrierType: .noise)])
    }

    @Test func toggleSimulatedAgainWhilePlayingStops() {
        let (viewModel, _, engine, _) = makeViewModel()
        engine.nowPlaying = ("a", false)
        viewModel.toggleSimulated()
        #expect(engine.stopCallCount == 1)
    }

    @Test func settingsAreDisabledWhilePlayingOriginal() {
        let (viewModel, _, engine, _) = makeViewModel()
        engine.nowPlaying = ("a", true)
        #expect(viewModel.settingsEnabled == false)
    }

    @Test func settingsAreDisabledWhileProcessing() {
        let (viewModel, _, engine, _) = makeViewModel()
        engine.isProcessing = true
        #expect(viewModel.settingsEnabled == false)
    }

    @Test func settingsAreEnabledWhilePlayingSimulatedOrStopped() {
        let (viewModel, _, engine, _) = makeViewModel()
        #expect(viewModel.settingsEnabled == true)
        engine.nowPlaying = ("a", false)
        #expect(viewModel.settingsEnabled == true)
    }
}

@MainActor
@Suite struct SimulatorViewModelRecordAndImportTests {
    @Test func beginRecordFlowShowsSheetDirectlyWhenAlreadyGranted() {
        let (viewModel, _, _, recorder) = makeViewModel()
        recorder.permissionState = .granted
        viewModel.beginRecordFlow()
        #expect(viewModel.showingRecordSheet == true)
    }

    @Test func beginRecordFlowShowsDeniedAlertWhenAlreadyDenied() {
        let (viewModel, _, _, recorder) = makeViewModel()
        recorder.permissionState = .denied
        viewModel.beginRecordFlow()
        #expect(viewModel.showingPermissionDeniedAlert == true)
        #expect(viewModel.showingRecordSheet == false)
    }

    @Test func beginRecordFlowRequestsPermissionWhenUndeterminedAndShowsSheetOnGrant() {
        let (viewModel, _, _, recorder) = makeViewModel()
        recorder.permissionState = .undetermined
        recorder.requestPermissionGrants = true
        viewModel.beginRecordFlow()
        #expect(viewModel.showingRecordSheet == true)
        #expect(viewModel.showingPermissionDeniedAlert == false)
    }

    @Test func beginRecordFlowRequestsPermissionWhenUndeterminedAndShowsAlertOnDenial() {
        let (viewModel, _, _, recorder) = makeViewModel()
        recorder.permissionState = .undetermined
        recorder.requestPermissionGrants = false
        viewModel.beginRecordFlow()
        #expect(viewModel.showingRecordSheet == false)
        #expect(viewModel.showingPermissionDeniedAlert == true)
    }

    @Test func beginImportFlowShowsFileImporter() {
        let (viewModel, _, _, _) = makeViewModel()
        viewModel.beginImportFlow()
        #expect(viewModel.showingFileImporter == true)
    }

    @Test func recordingFinishedSelectsTheAddedSource() {
        let (viewModel, library, _, _) = makeViewModel()
        let added = makeSource(id: "new-recording", name: "01 Recording")
        library.addRecordingResult = .success(added)

        viewModel.recordingFinished(tempURL: URL(fileURLWithPath: "/tmp/temp.m4a"))

        #expect(viewModel.selectedSourceID == "new-recording")
    }

    @Test func recordingFinishedSurfacesLibraryErrors() {
        let (viewModel, library, engine, _) = makeViewModel()
        library.addRecordingResult = .failure(CocoaError(.fileWriteUnknown))

        viewModel.recordingFinished(tempURL: URL(fileURLWithPath: "/tmp/temp.m4a"))

        #expect(viewModel.selectedSourceID != "new-recording")
        #expect(engine.errorMessage != nil)
    }

    @Test func fileImportFinishedSelectsTheAddedSourceOnSuccess() {
        let (viewModel, library, _, _) = makeViewModel()
        let added = makeSource(id: "new-import", name: "01 Import")
        library.addImportedFileResult = .success(added)

        viewModel.fileImportFinished(.success(URL(fileURLWithPath: "/tmp/picked.wav")))

        #expect(viewModel.selectedSourceID == "new-import")
    }

    @Test func fileImportFinishedSurfacesPickerErrors() {
        let (viewModel, _, engine, _) = makeViewModel()

        viewModel.fileImportFinished(.failure(CocoaError(.userCancelled)))

        #expect(engine.errorMessage != nil)
    }

    @Test func fileImportFinishedSurfacesLibraryErrorsOnSuccessfulPick() {
        let (viewModel, library, engine, _) = makeViewModel()
        library.addImportedFileResult = .failure(CocoaError(.fileWriteUnknown))

        viewModel.fileImportFinished(.success(URL(fileURLWithPath: "/tmp/picked.wav")))

        #expect(engine.errorMessage != nil)
    }
}
