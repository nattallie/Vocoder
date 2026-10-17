import SwiftUI

/// App-wide color palette and background treatment. Indigo -> teal rather than a
/// generic default blue, loosely evoking sound/frequency without being literal about
/// it. All colors are dynamic (light/dark adaptive) via a `UIColor` trait provider,
/// so no Asset Catalog is needed just for this.
enum Theme {
    static let indigo = Color(
        light: UIColor(red: 0.40, green: 0.33, blue: 0.91, alpha: 1),
        dark: UIColor(red: 0.58, green: 0.52, blue: 0.99, alpha: 1)
    )
    static let teal = Color(
        light: UIColor(red: 0.00, green: 0.70, blue: 0.62, alpha: 1),
        dark: UIColor(red: 0.22, green: 0.85, blue: 0.76, alpha: 1)
    )

    static let accentGradient = LinearGradient(
        colors: [indigo, teal],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private extension Color {
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

/// Full-screen gradient wash behind content -- a soft indigo/teal tint over the
/// system background, strong enough to read as a deliberate choice rather than
/// a near-invisible accent, but still letting light/dark mode show through.
struct AppBackground: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            LinearGradient(
                colors: [Theme.indigo.opacity(0.28), Theme.teal.opacity(0.16), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// A soft, slightly colored drop shadow for card-like surfaces -- two stacked
    /// shadows (a neutral one for depth, a faint tinted one for warmth) rather than
    /// a single flat black shadow.
    func depthShadow() -> some View {
        self
            .shadow(color: .black.opacity(0.10), radius: 14, x: 0, y: 8)
            .shadow(color: Theme.indigo.opacity(0.12), radius: 3, x: 0, y: 1)
    }
}
