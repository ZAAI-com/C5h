import Foundation

/// Decides, per provider, whether a usage check should run right now.
///
/// A check always runs while the provider has a recorded active 5h window or a
/// pending planned window. Beyond that, the provider's "check when idle"
/// setting applies, with one crucial distinction: for providers whose probe
/// itself consumes quota (`ProviderID.usageProbeConsumesQuota`, i.e. Claude,
/// whose REPL probe opens a fresh 5h window on an idle account), an idle check
/// may only run when snapshot evidence (`isBelievedActiveFromSnapshot`) or
/// read-only local evidence (`hasRecentLocalActivity`) says a window is
/// already open. Otherwise C5h's own polling would anchor a new 5h window the
/// moment the previous one expires and chain windows around the clock.
/// Providers with read-only probes (Codex) check unconditionally while the
/// idle setting is on.
///
/// On top of that, quota-consuming probes observe a pre-window quiet period:
/// when the next planned window starts within `preWindowQuietHorizon` and no
/// recorded window is active, no probe runs at all, regardless of snapshot or
/// local-activity evidence. The provider chains a new 5h window onto the old
/// one's end whenever the account shows activity in that stretch, so staying
/// completely silent gives the boundary its best chance to decay and lets the
/// planned wake prompt anchor a fresh window at its own start.
///
/// Built from closures (not repository protocols) because C5hCore cannot depend
/// on C5hStore; both the app and the helper wire the closures to their repos.
/// Mirrors the closure style of `ActiveWindowResolver`.
public struct UsageCheckGate: Sendable {
    public typealias IsIdleCheckEnabled = @Sendable (ProviderID) async -> Bool
    public typealias HasActiveWindow = @Sendable (ProviderID, Date) async throws -> Bool
    public typealias HasPendingPlannedWindow = @Sendable (ProviderID, Date) async throws -> Bool
    public typealias HasRecentLocalActivity = @Sendable (ProviderID, Date) async -> Bool
    public typealias IsBelievedActiveFromSnapshot = @Sendable (ProviderID, Date) async throws -> Bool
    public typealias HasUpcomingPlannedWindow = @Sendable (ProviderID, Date) async throws -> Bool
    public typealias IsSnapshotWindowExpiring = @Sendable (ProviderID, Date) async throws -> Bool

    /// End-of-window safety margin for providers whose probe consumes quota: a
    /// probe launched in the final seconds of a believed window can fire its
    /// startup request after the real expiry and open a new window. 90s covers
    /// the probe timeout (30s) plus realistic clock skew between the local
    /// clock and the server-reported reset time.
    public static let consumingProbeEndMargin: TimeInterval = 90

    /// How far ahead an upcoming planned window suppresses quota-consuming
    /// probes (the pre-window quiet period). One window length: chained slots
    /// advance in 5h steps, so only account activity in the final 5h before a
    /// planned start can keep a boundary alive that would swallow it. A larger
    /// horizon adds no protection and only degrades tracking freshness.
    public static let preWindowQuietHorizon: TimeInterval = 5 * 60 * 60

    public let isIdleCheckEnabled: IsIdleCheckEnabled
    public let hasActiveWindow: HasActiveWindow
    public let hasPendingPlannedWindow: HasPendingPlannedWindow
    public let hasRecentLocalActivity: HasRecentLocalActivity
    public let isBelievedActiveFromSnapshot: IsBelievedActiveFromSnapshot
    public let hasUpcomingPlannedWindow: HasUpcomingPlannedWindow
    public let isSnapshotWindowExpiring: IsSnapshotWindowExpiring

    /// The last three closures default to `false` so existing constructions keep
    /// their behavior: no snapshot fallback, no quiet period, and no expiring-
    /// window suppression unless wired (the factory in C5hStore wires all three).
    public init(
        isIdleCheckEnabled: @escaping IsIdleCheckEnabled,
        hasActiveWindow: @escaping HasActiveWindow,
        hasPendingPlannedWindow: @escaping HasPendingPlannedWindow,
        hasRecentLocalActivity: @escaping HasRecentLocalActivity,
        isBelievedActiveFromSnapshot: @escaping IsBelievedActiveFromSnapshot = { _, _ in false },
        hasUpcomingPlannedWindow: @escaping HasUpcomingPlannedWindow = { _, _ in false },
        isSnapshotWindowExpiring: @escaping IsSnapshotWindowExpiring = { _, _ in false }
    ) {
        self.isIdleCheckEnabled = isIdleCheckEnabled
        self.hasActiveWindow = hasActiveWindow
        self.hasPendingPlannedWindow = hasPendingPlannedWindow
        self.hasRecentLocalActivity = hasRecentLocalActivity
        self.isBelievedActiveFromSnapshot = isBelievedActiveFromSnapshot
        self.hasUpcomingPlannedWindow = hasUpcomingPlannedWindow
        self.isSnapshotWindowExpiring = isSnapshotWindowExpiring
    }

    /// Whether usage should be checked for `providerID` at `now`. Repo errors
    /// in window checks are treated as "no window" (fail-closed): a transient
    /// read failure skips the check and the next tick retries. For a
    /// quota-consuming probe, skipping only costs tracking freshness; probing
    /// wrongly costs a 5h window. The quiet-period lookup is the one exception:
    /// an error there must not suppress (fail-open), or a transient DB error
    /// would silence probing that every other rule allows.
    public func shouldCheck(providerID: ProviderID, now: Date = .now) async -> Bool {
        if (try? await hasActiveWindow(providerID, now)) == true {
            return true
        }
        if (try? await hasPendingPlannedWindow(providerID, now)) == true {
            return true
        }
        // Pre-window quiet period: checked before the believed-active snapshot
        // fallback on purpose. That fallback ignores used percentage, so a
        // single idle 0% rolling snapshot would otherwise arm up to 5h of
        // probing right through the run-up to the planned start.
        if providerID.usageProbeConsumesQuota,
           (try? await hasUpcomingPlannedWindow(providerID, now)) == true {
            return false
        }
        if (try? await isBelievedActiveFromSnapshot(providerID, now)) == true {
            return true
        }
        guard await isIdleCheckEnabled(providerID) else {
            return false
        }
        if providerID.usageProbeConsumesQuota {
            // A believed window in its final `consumingProbeEndMargin` was
            // already rejected by isBelievedActiveFromSnapshot above; suppress
            // here too so recent local activity cannot re-open probing in that
            // tail, where the probe's startup request could land after the real
            // expiry and anchor a fresh window. Fail-open on error (treat as not
            // expiring) so a transient read failure reverts to the local-activity
            // fallback rather than silencing all probing.
            if (try? await isSnapshotWindowExpiring(providerID, now)) == true {
                return false
            }
            // The probe would open a fresh 5h window on an idle account. Only
            // run it when local evidence says a window is already open.
            return await hasRecentLocalActivity(providerID, now)
        }
        return true
    }
}
