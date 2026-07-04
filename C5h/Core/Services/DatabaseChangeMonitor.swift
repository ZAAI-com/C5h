import Foundation
import Observation
import C5hStore

/// Listens for the cross-process Darwin notification posted by
/// `C5hStore.Database` after a relevant write commits (from the app itself or the
/// background helper) and exposes a debounced, observable `changeToken`. Views
/// reload when the token changes, so a screen left open stays live without
/// polling.
@Observable
@MainActor
final class DatabaseChangeMonitor {
    /// Bumped (after debouncing) whenever the database reports a relevant change.
    /// Views observe this to trigger a reload.
    private(set) var changeToken: Int = 0

    private var registered = false
    private var debounce: Task<Void, Never>?

    /// Coalesce a burst of commits (the helper writes several rows per tick) into
    /// a single reload.
    private let debounceInterval: Duration = .milliseconds(300)

    deinit {
        // Safety net against a dangling registration: the Darwin center holds
        // only a raw pointer to self. Thread-safe and harmless when never
        // registered.
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    func start() {
        guard !registered else { return }
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let monitor = Unmanaged<DatabaseChangeMonitor>
                    .fromOpaque(observer)
                    .takeUnretainedValue()
                Task { @MainActor in monitor.scheduleBump() }
            },
            Database.changeNotificationName as CFString,
            nil,
            .deliverImmediately
        )
        registered = true
    }

    func stop() {
        guard registered else { return }
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            CFNotificationName(Database.changeNotificationName as CFString),
            nil
        )
        registered = false
        debounce?.cancel()
        debounce = nil
    }

    private func scheduleBump() {
        debounce?.cancel()
        debounce = Task { [weak self, debounceInterval] in
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }
            self?.changeToken &+= 1
        }
    }
}
