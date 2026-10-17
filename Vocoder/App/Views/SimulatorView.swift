import SwiftUI
import CIVocoderKit
import UniformTypeIdentifiers

struct SimulatorView: View {
    @State private var viewModel = SimulatorViewModel()

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 22) {
                    Text("Simulator")
                        .font(.largeTitle.bold())
                        .padding(.top, 8)

                    Text("Choose a recording or sample")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    clipPicker

                    Card {
                        Text("Channels: \(viewModel.channels)")
                            .font(.headline)
                        ChannelBarsControl(
                            options: SimulatorViewModel.channelOptions,
                            selectedIndex: Binding(
                                get: { viewModel.channelIndex },
                                set: { viewModel.selectChannelIndex($0) }
                            )
                        )
                        .disabled(!viewModel.settingsEnabled)
                    }
                    .opacity(viewModel.settingsEnabled ? 1.0 : 0.45)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.settingsEnabled)

                    Card {
                        Text("Carrier")
                            .font(.headline)
                        Picker("Carrier", selection: $viewModel.carrierType) {
                            Text("Noise").tag(CarrierType.noise)
                            Text("Tone").tag(CarrierType.tone)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: viewModel.carrierType) { _, _ in
                            viewModel.carrierTypeChanged()
                        }
                        .disabled(!viewModel.settingsEnabled)
                    }
                    .opacity(viewModel.settingsEnabled ? 1.0 : 0.45)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.settingsEnabled)

                    Text(viewModel.contextDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .padding(.horizontal, 8)
                        .animation(.default, value: viewModel.contextDescription)

                    playbackControls

                    if let error = viewModel.engine.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Text("Educational simulation, not a medical device or an accurate representation of any individual's hearing.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                        .padding(.bottom, 20)
                }
                .padding(.horizontal, 20)
            }
        }
        .onAppear { viewModel.onAppear() }
        .sheet(isPresented: $viewModel.showingRecordSheet, onDismiss: { viewModel.recorder.checkPermission() }) {
            RecordSheetView(recorder: viewModel.recorder) { tempURL in
                viewModel.recordingFinished(tempURL: tempURL)
            }
        }
        .fileImporter(isPresented: $viewModel.showingFileImporter, allowedContentTypes: [.audio]) { result in
            viewModel.fileImportFinished(result)
        }
        .alert("Microphone Access Needed", isPresented: $viewModel.showingPermissionDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow microphone access in Settings to record a clip.")
        }
    }

    private var clipPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(viewModel.library.sources) { source in
                    ClipChip(
                        source: source,
                        isSelected: source.id == viewModel.selectedSource?.id,
                        action: { viewModel.selectSource(source) },
                        onDelete: source.isDeletable ? { viewModel.deleteSource(source) } : nil
                    )
                }

                Menu {
                    Button {
                        viewModel.beginRecordFlow()
                    } label: {
                        Label("Record", systemImage: "mic.fill")
                    }
                    Button {
                        viewModel.beginImportFlow()
                    } label: {
                        Label("Import File", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.title2)
                        Text("Add")
                            .font(.caption)
                    }
                    .frame(width: 88, height: 66)
                    .foregroundStyle(Theme.indigo)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.regularMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.indigo.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                    )
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 14)
        }
        .scrollClipDisabled()
    }

    /// Each button is its own play/stop toggle: tap to play, tap again (same button)
    /// to stop -- no separate "Playing X" label or Stop link needed, since the lit/
    /// dimmed state plus the in-button Stop content already says which is active.
    private var playbackControls: some View {
        HStack(spacing: 16) {
            Button {
                viewModel.toggleOriginal()
            } label: {
                PlaybackButtonLabel(
                    icon: viewModel.isPlayingOriginal ? "stop.fill" : "waveform",
                    text: viewModel.isPlayingOriginal ? "Stop" : "Original",
                    accessory: viewModel.isPlayingOriginal ? .equalizer(Theme.indigo) : .none
                )
            }
            .buttonStyle(BouncyBorderedButtonStyle())
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.indigo, lineWidth: viewModel.isPlayingOriginal ? 2 : 0)
            )
            .opacity(viewModel.isPlayingSimulated || viewModel.engine.isProcessing ? 0.4 : 1.0)
            .disabled(viewModel.selectedSource == nil || viewModel.isPlayingSimulated || viewModel.engine.isProcessing)

            Button {
                viewModel.toggleSimulated()
            } label: {
                if viewModel.engine.isProcessing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .controlSize(.small) // else it inherits .controlSize(.large) below and looks oversized
                } else {
                    PlaybackButtonLabel(
                        icon: viewModel.isPlayingSimulated ? "stop.fill" : "ear",
                        text: viewModel.isPlayingSimulated ? "Stop" : "Simulated",
                        accessory: viewModel.isPlayingSimulated ? .equalizer(.white) : .none
                    )
                }
            }
            .buttonStyle(BouncyProminentButtonStyle())
            .opacity(viewModel.isPlayingOriginal ? 0.4 : 1.0)
            .disabled(viewModel.selectedSource == nil || viewModel.isPlayingOriginal || viewModel.engine.isProcessing)
        }
        .controlSize(.large)
    }
}

#Preview {
    SimulatorView()
}
