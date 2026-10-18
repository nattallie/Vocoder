import Testing
import Foundation
@testable import Vocoder

@MainActor
@Suite struct AppViewModelTests {
    /// A fresh, isolated `UserDefaults` suite per test so these never read or leave
    /// behind state in the simulator's real `hasOnboarded` default.
    private func makeDefaults() -> UserDefaults {
        let suiteName = "AppViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func startsNotOnboardedWhenNoStoredValue() {
        let viewModel = AppViewModel(defaults: makeDefaults())
        #expect(viewModel.hasOnboarded == false)
    }

    @Test func readsPreviouslyStoredOnboardedState() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "hasOnboarded")
        let viewModel = AppViewModel(defaults: defaults)
        #expect(viewModel.hasOnboarded == true)
    }

    @Test func completeOnboardingUpdatesStateAndPersists() {
        let defaults = makeDefaults()
        let viewModel = AppViewModel(defaults: defaults)

        viewModel.completeOnboarding()

        #expect(viewModel.hasOnboarded == true)
        #expect(defaults.bool(forKey: "hasOnboarded") == true)
    }

    @Test func onboardingStatePersistsAcrossInstancesSharingDefaults() {
        let defaults = makeDefaults()
        AppViewModel(defaults: defaults).completeOnboarding()

        let secondLaunch = AppViewModel(defaults: defaults)

        #expect(secondLaunch.hasOnboarded == true)
    }
}
