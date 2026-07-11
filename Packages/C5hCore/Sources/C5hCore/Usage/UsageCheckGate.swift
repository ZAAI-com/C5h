import Foundation

/// Decides, per provider, whether a usage check should run right now.
///
/// A check always runs while the provider has an active 5h window or a pending
/// planned window. Beyond that, the provider's "check when idle" setting
/// applies, with one crucial distinction: for providers whose probe itself
/// consumes quota (`ProviderID.usageProbeConsumesQuota`, i.e. Claude, whose
/// REPL probe opens a fresh 5h window on an idle account), an idle check may
/// only run when read-only local evidence (`hasRecentLocalActivity`) says a
/// window is already open. Otherwise C5h's own polling would anchor a new 5h
/// window the moment the previous one expires and chain windows around the
/// clock. Providers with read-only probes (Codex) check unconditionally while
/// the idle setting is on.
///
/// Built from closures (not repository protocols) because C5hCore cannot depend
/// on C5hStore; both the app and the helper wire the closures to their repos.
/// Mirrors the closure style of `ActiveWindowResolver`.
public struct UsageCheckGate: Sendable {
    public typealias IsIdleCheckEnabled = @Sendable (ProviderID) async -> Bool
    public typealias HasActiveWindow = @Sendable (ProviderID, Date) async throws -> Bool
    public typealias HasPendingPlannedWindow = @Sendable (ProviderID, Date) async throws -> Bool
    public typealias HasRecentLocalActivity = @Sendable (ProviderID, Date) async -> Bool

    /// End-of-window safety margin for providers whose probe consumes quota: a
    /// probe launched in the final seconds of a believed window can fire its
    /// startup request after the real expiry and open a new window. 90s covers
    /// the probe timeout (30s) plus realistic clock skew between the local
    /// clock and the server-reported reset time.
    public static let consumingProbeEndMargin: TimeInterval = 90

    public let isIdleCheckEnabled: IsIdleCheckEnabled
    public let hasActiveWindow: HasActiveWindow
    public let hasPendingPlannedWindow: HasPendingPlannedWindow
    public let hasRecentLocalActivity: HasRecentLocalActivity

    public init(
        isIdleCheckEnabled: @escaping IsIdleCheckEnabled,
        hasActiveWindow: @escaping HasActiveWindow,
        hasPendingPlannedWindow: @escaping HasPendingPlannedWindow,
        hasRecentLocalActivity: @escaping HasRecentLocalActivity
    ) {
        self.isIdleCheckEnabled = isIdleCheckEnabled
        self.hasActiveWindow = hasActiveWindow
        self.hasPendingPlannedWindow = hasPendingPlannedWindow
        self.hasRecentLocalActivity = hasRecentLocalActivity
    }

    /// Whether usage should be checked for `providerID` at `now`. Repo errors are
    /// treated as "no window" (fail-closed): a transient read failure skips the
    /// check and the next tick retries. For a quota-consuming probe, skipping
    /// only costs tracking freshness; probing wrongly costs a 5h window.
    public func shouldCheck(providerID: ProviderID, now: Date = .now) async -> Bool {
        if (try? await hasActiveWindow(providerID, now)) == true {
            return true
        }
        if (try? await hasPendingPlannedWindow(providerID, now)) == true {
            return true
        }
        guard await isIdleCheckEnabled(providerID) else {
            return false
        }
        if providerID.usageProbeConsumesQuota {
            // The probe would open a fresh 5h window on an idle account. Only
            // run it when local evidence says a window is already open.
            return await hasRecentLocalActivity(providerID, now)
        }
        return true
    }
}
