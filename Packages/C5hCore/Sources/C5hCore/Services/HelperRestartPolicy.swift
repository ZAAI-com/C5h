import Foundation

/// Decides when a long-running helper process should restart itself. The helper
/// exits on a true result and lets its launchd `KeepAlive` relaunch a fresh copy
/// from the current app bundle, so a periodic restart also self-heals version
/// skew after the app is rebuilt (the relaunched helper picks up the new binary).
public enum HelperRestartPolicy {
    /// Restart after this much uptime by default (24h).
    public static let defaultMaxUptimeSeconds: TimeInterval = 24 * 60 * 60

    /// True once `now` is at least `maxUptimeSeconds` past the process start.
    public static func shouldRestart(
        startedAt: Date,
        now: Date,
        maxUptimeSeconds: TimeInterval = defaultMaxUptimeSeconds
    ) -> Bool {
        now.timeIntervalSince(startedAt) >= maxUptimeSeconds
    }
}
