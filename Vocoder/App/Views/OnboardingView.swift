import SwiftUI

struct OnboardingView: View {
    let onGetStarted: () -> Void

    @State private var appear = false

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 28) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Theme.accentGradient.opacity(0.22))
                        .frame(width: 150, height: 150)
                    Circle()
                        .strokeBorder(Theme.accentGradient, lineWidth: 2.5)
                        .frame(width: 140, height: 140)
                    Image(systemName: "ear")
                        .font(.system(size: 54))
                        .foregroundStyle(Theme.accentGradient)
                }
                .shadow(color: Theme.indigo.opacity(0.3), radius: 20, x: 0, y: 10)
                .scaleEffect(appear ? 1.0 : 0.6)
                .opacity(appear ? 1 : 0)

                Text("Vocoder")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 10)

                VStack(spacing: 14) {
                    Text("Hear what music and speech sound like through a cochlear implant.")
                    Text("Adjust the channel count and carrier type to explore how spectral detail affects clarity.")
                    Text("A classic hearing-research technique (Shannon et al., 1995), reconstructed for your phone.")
                }
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 16)

                Spacer()

                Button(action: onGetStarted) {
                    Text("Get Started")
                }
                .buttonStyle(BouncyProminentButtonStyle())
                .padding(.horizontal, 48)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 16)

                Text("Educational simulation, not a medical device or an accurate representation of any individual's hearing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 16)
                    .opacity(appear ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.1)) {
                appear = true
            }
        }
    }
}

#Preview {
    OnboardingView(onGetStarted: {})
}
