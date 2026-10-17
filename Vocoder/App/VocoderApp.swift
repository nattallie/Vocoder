import SwiftUI

@main
struct VocoderApp: App {
    @State private var appViewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if appViewModel.hasOnboarded {
                    SimulatorView()
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        ))
                } else {
                    OnboardingView(onGetStarted: {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            appViewModel.completeOnboarding()
                        }
                    })
                    .transition(.opacity)
                }
            }
        }
    }
}
