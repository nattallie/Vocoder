import SwiftUI

struct RecordSheetView: View {
    var recorder: AudioRecorderController
    let onSave: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.18))
                    .frame(width: 150, height: 150)
                    .scaleEffect(pulse ? 1.12 : 0.88)
                    .opacity(recorder.isRecording ? 1 : 0)
                    .animation(
                        .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                        value: pulse
                    )
                Circle()
                    .fill(Color.red)
                    .frame(width: 92, height: 92)
                Image(systemName: "mic.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white)
            }

            Text(timeString(recorder.elapsed))
                .font(.system(.title, design: .monospaced))
                .foregroundStyle(.secondary)

            if let error = recorder.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            HStack(spacing: 16) {
                Button {
                    recorder.cancelRecording()
                    dismiss()
                } label: {
                    Text("Cancel")
                }
                .buttonStyle(BouncyBorderedButtonStyle())

                Button {
                    if let url = recorder.stopRecording() {
                        onSave(url)
                    }
                    dismiss()
                } label: {
                    Text("Save")
                }
                .buttonStyle(BouncyProminentButtonStyle(tint: .red, useGradient: false))
                .disabled(!recorder.isRecording)
            }
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .interactiveDismissDisabled(recorder.isRecording)
        .onAppear {
            pulse = true
            if !recorder.isRecording {
                recorder.startRecording()
            }
        }
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let totalTenths = Int((interval * 10).rounded())
        let minutes = totalTenths / 600
        let seconds = (totalTenths / 10) % 60
        let tenths = totalTenths % 10
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}
