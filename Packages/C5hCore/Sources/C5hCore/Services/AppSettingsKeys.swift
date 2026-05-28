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
}
