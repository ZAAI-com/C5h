import Combine
import Foundation
import Observation
import Sparkle

/// Wraps Sparkle's standard updater controller behind the app's observation
/// conventions so the app menu and Settings can bind to update state.
///
/// Sparkle owns persistence for the update preferences (UserDefaults keys
/// seeded from Info.plist: SUEnableAutomaticChecks / SUAutomaticallyUpdate).
/// The stored properties here are observable mirrors that pass writes through
/// to Sparkle, not a second source of truth, so Sparkle's own update alert UI
/// and the Settings toggles stay consistent.
@Observable
@MainActor
final class UpdaterService {
    /// False in Debug: dev-signed builds cannot pass Sparkle's signature
    /// validation and the production feed does not apply, so the updater is
    /// never started (no scheduled checks, no prompts, no doomed installs).
    let isEnabled: Bool

    private(set) var canCheckForUpdates = false
    private(set) var lastUpdateCheckDate: Date?

    var automaticallyChecksForUpdates: Bool {
        didSet {
            guard automaticallyChecksForUpdates != oldValue else { return }
            controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        didSet {
            guard automaticallyDownloadsUpdates != oldValue else { return }
            controller.updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
        }
    }

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []

    init() {
        #if DEBUG
        isEnabled = false
        #else
        isEnabled = true
        #endif
        let controller = SPUStandardUpdaterController(
            startingUpdater: isEnabled,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.controller = controller
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = controller.updater.automaticallyDownloadsUpdates
        lastUpdateCheckDate = controller.updater.lastUpdateCheckDate

        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] canCheck in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.canCheckForUpdates = canCheck
                    self.refreshFromUpdater()
                }
            }
            .store(in: &cancellables)
    }

    /// Presents Sparkle's standard update UI. No-op when the updater is not
    /// running (Debug), where calling into Sparkle would assert.
    func checkForUpdates() {
        guard isEnabled else { return }
        controller.checkForUpdates(nil)
    }

    /// Re-reads the mirrored values from Sparkle. canCheckForUpdates flips at
    /// the start and end of every update session, so wiring this to that KVO
    /// stream also catches Sparkle's own alert UI mutating the preferences
    /// behind the mirrors (the didSet equality guards keep this loop-free).
    func refreshFromUpdater() {
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = controller.updater.automaticallyDownloadsUpdates
        lastUpdateCheckDate = controller.updater.lastUpdateCheckDate
    }
}
