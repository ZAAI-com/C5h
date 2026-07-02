import Foundation

/// Decides, per provider, whether a usage check should run right now. When the
/// provider's "check when idle" setting is on, checks always run. When it's off,
/// a check runs only while the provider has an active 5h window or a pending
/// planned window, so C5h stops spawning the CLI when there's nothing to track.
///
/// Built from closures (not repository protocols) because C5hCore cannot depend
/// on C5hStore; both the app and the helper wire the closures to their repos.
/// Mirrors the closure style of `ActiveWindowResolver`.
public struct UsageCheckGate: Sendable {
    public typealias IsIdleCheckEnabled = @Sendable (ProviderID) async -> Bool
    public typealias HasActiveWindow = @Sendable (ProviderID, Date) async throws -> Bool
    public typealias HasPendingPlannedWindow = @Sendable (ProviderID, Date) async throws -> Bool

    public let isIdleCheckEnabled: IsIdleCheckEnabled
    public let hasActiveWindow: HasActiveWindow
    public let hasPendingPlannedWindow: HasPendingPlannedWindow

    public init(
        isIdleCheckEnabled: @escaping IsIdleCheckEnabled,
        hasActiveWindow: @escaping HasActiveWindow,
        hasPendingPlannedWindow: @escaping HasPendingPlannedWindow
    ) {
        self.isIdleCheckEnabled = isIdleCheckEnabled
        self.hasActiveWindow = hasActiveWindow
        self.hasPendingPlannedWindow = hasPendingPlannedWindow
    }

    /// Whether usage should be checked for `providerID` at `now`. Repo errors are
    /// treated as "no window" (fail-closed): when idle checks are off, a transient
    /// read failure skips the check and the next tick retries.
    public func shouldCheck(providerID: ProviderID, now: Date = .now) async -> Bool {
        if await isIdleCheckEnabled(providerID) {
            return true
        }
        if (try? await hasActiveWindow(providerID, now)) == true {
            return true
        }
        if (try? await hasPendingPlannedWindow(providerID, now)) == true {
            return true
        }
        return false
    }
}
