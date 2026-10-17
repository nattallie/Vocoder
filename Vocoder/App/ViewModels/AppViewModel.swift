import Foundation
import Observation

/// Top-level app state: just whether onboarding is done. Persisted in `UserDefaults`
/// so it's asked once, not on every launch -- `VocoderApp` previously held this as
/// plain `@State` that always started `false`, so onboarding reappeared every time.
@Observable
@MainActor
final class AppViewModel {
    private(set) var hasOnboarded: Bool

    @ObservationIgnored private let defaults: UserDefaults
    private let hasOnboardedKey = "hasOnboarded"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasOnboarded = defaults.bool(forKey: hasOnboardedKey)
    }

    func completeOnboarding() {
        hasOnboarded = true
        defaults.set(true, forKey: hasOnboardedKey)
    }
}
