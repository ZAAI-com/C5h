import Foundation

/// Canonical settings keys shared between the main app and the helper.
public enum AppSettingsKeys {
    /// Path override for a provider's CLI binary.
    public static func cliPath(for providerID: ProviderID) -> String {
        "providers.\(providerID.rawValue).cliPath"
    }

    /// The default prompt sent to a provider when a planned window's start time
    /// arrives — used to "wake" the actual 5h limit window without typing.
    public static func defaultWakePrompt(for providerID: ProviderID) -> String {
        "providers.\(providerID.rawValue).defaultWakePrompt"
    }

    /// Fallback wake prompt when the user hasn't set one. Picked for being
    /// fast to evaluate ("1+1" → "2", short tokens both directions).
    public static let defaultWakePromptFallback = "1+1"

    /// Minimum seconds between usage refreshes for a provider. Drives both the
    /// background helper's poll cadence and the dashboard's on-appearance
    /// throttle, so a provider is never re-checked more often than this.
    public static func usageRefreshIntervalSeconds(for providerID: ProviderID) -> String {
        "providers.\(providerID.rawValue).usageRefreshIntervalSeconds"
    }

    /// Default refresh interval when the user hasn't picked one (5 minutes).
    public static let defaultUsageRefreshIntervalSeconds: Int = 300

    /// Whether C5h checks a provider's usage even when it has no active 5h window
    /// and no pending planned window. When false, idle providers are skipped so
    /// the CLI isn't spawned when there's nothing to track.
    public static func checkUsageWhenIdle(for providerID: ProviderID) -> String {
        "providers.\(providerID.rawValue).checkUsageWhenIdle"
    }

    /// Default when the user hasn't chosen: keep checking even when idle.
    public static let defaultCheckUsageWhenIdle = true
}
