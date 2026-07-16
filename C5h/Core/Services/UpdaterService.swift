import Combine
import Foundation
import Observation
@preconcurrency import Sparkle

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
    // Sparkle references the updater delegate weakly, so it must be retained here.
    @ObservationIgnored private let feedFailover: FeedFailoverController
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []

    init() {
        #if DEBUG
        isEnabled = false
        #else
        isEnabled = Self.isSparkleConfigured()
        #endif
        let feedFailover = FeedFailoverController(feeds: Self.configuredFeeds())
        self.feedFailover = feedFailover
        // Never pass startingUpdater: true — SPUStandardUpdaterController shows a
        // modal "Unable to Check For Updates" alert when startUpdater fails.
        // Call SPUUpdater.start() directly so misconfiguration is logged only.
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: feedFailover,
            userDriverDelegate: nil
        )
        self.controller = controller
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = controller.updater.automaticallyDownloadsUpdates
        lastUpdateCheckDate = controller.updater.lastUpdateCheckDate
        feedFailover.updateCycleDidFinish = { [weak self] in
            self?.refreshFromUpdater()
        }

        if isEnabled {
            startUpdaterQuietly()
        }

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

    /// Re-reads the mirrored values from Sparkle. Update-cycle completion keeps
    /// lastUpdateCheckDate current, while the canCheckForUpdates KVO stream also
    /// catches Sparkle's own alert UI mutating the preferences behind the
    /// mirrors (the didSet equality guards keep this loop-free).
    func refreshFromUpdater() {
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = controller.updater.automaticallyDownloadsUpdates
        lastUpdateCheckDate = controller.updater.lastUpdateCheckDate
    }

    /// Starts Sparkle without surfacing SPUStandardUpdaterController's fatal
    /// misconfiguration alert. Failures are logged and leave canCheckForUpdates
    /// false so menu items stay disabled.
    private func startUpdaterQuietly() {
        do {
            try controller.updater.start()
        } catch {
            NSLog("UpdaterService: Sparkle failed to start: \(error)")
        }
    }

    /// Release builds only run the updater when Info.plist has real Sparkle keys.
    private static func isSparkleConfigured() -> Bool {
        guard let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !publicKey.isEmpty,
              publicKey != "REPLACE_WITH_GENERATE_KEYS_PUBLIC_KEY" else {
            return false
        }
        guard let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              !feedURL.isEmpty else {
            return false
        }
        return true
    }

    /// The primary feed (SUFeedURL) followed by any C5hFallbackFeedURLs, in
    /// order. Kept in Info.plist so the hosts can move without a code change.
    private static func configuredFeeds() -> [String] {
        var feeds: [String] = []
        if let primary = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
           !primary.isEmpty {
            feeds.append(primary)
        }
        if let fallbacks = Bundle.main.object(forInfoDictionaryKey: "C5hFallbackFeedURLs") as? [String] {
            feeds.append(contentsOf: fallbacks.filter { !$0.isEmpty })
        }
        return feeds
    }
}

/// Drives Sparkle across an ordered list of mirror feeds that serve the same
/// signed appcast. Sparkle only checks one feed per session, so when the
/// current feed cannot be loaded (host unreachable, DNS failure, 404, malformed
/// or unsigned XML) this restarts the check against the next mirror.
///
/// It fails over only when a feed never loaded: a successful load, including
/// "you are up to date", ends the sequence, and so does an error after the
/// feed loaded (a download failure on an identical mirror would not help). This
/// is transparent for the automatic background checks, which surface no error
/// UI.
///
/// The current feed is sticky: after failing over to a mirror it stays there
/// until that mirror also fails, then advances (wrapping back to the primary).
/// Resetting to the primary after every success would make Sparkle's "feed URL
/// changed since last check" heuristic (`SPUUpdater`) fire an immediate
/// re-check, which during a sustained primary outage becomes a tight no-backoff
/// loop against both hosts. Since the mirrors serve identical signed content,
/// which one is current does not affect correctness. Sparkle invokes
/// SPUUpdaterDelegate methods on the main thread.
@MainActor
private final class FeedFailoverController: NSObject, SPUUpdaterDelegate {
    private let feeds: [String]
    var updateCycleDidFinish: (@MainActor () -> Void)?
    private var activeIndex = 0
    private var appcastLoadedThisCycle = false
    // Advances taken within the current triggered check, capped so a round
    // where every mirror is down tries each once and then waits for the next
    // scheduled check rather than looping.
    private var advancesThisSequence = 0
    // Held so the deferred failover re-check can reach the updater without
    // capturing the non-Sendable SPUUpdater in a Task closure.
    private weak var updater: SPUUpdater?

    init(feeds: [String]) {
        self.feeds = feeds
        super.init()
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        self.updater = updater
        appcastLoadedThisCycle = false
        // With no configured mirror, defer to Sparkle's own SUFeedURL handling
        // (returning nil) so behavior is unchanged when the list is absent.
        guard feeds.count > 1, activeIndex < feeds.count else { return nil }
        return feeds[activeIndex]
    }

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        appcastLoadedThisCycle = true
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        updateCycleDidFinish?()
        // Fail over only when the feed itself never loaded and we have not
        // already tried every mirror this round. Otherwise the sequence ends:
        // the current feed stays sticky for the next check.
        let feedUnreachable = error != nil && !appcastLoadedThisCycle
        guard feedUnreachable, feeds.count > 1, advancesThisSequence < feeds.count - 1 else {
            advancesThisSequence = 0
            return
        }
        activeIndex = (activeIndex + 1) % feeds.count
        advancesThisSequence += 1
        // Re-issue the same kind of check against the next mirror after the
        // current session has finished tearing down.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard let self, let updater = self.updater, !updater.sessionInProgress else { return }
            switch updateCheck {
            case .updates:
                updater.checkForUpdates()
            case .updatesInBackground:
                updater.checkForUpdatesInBackground()
            case .updateInformation:
                updater.checkForUpdateInformation()
            @unknown default:
                updater.checkForUpdatesInBackground()
            }
        }
    }
}
