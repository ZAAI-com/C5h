import Foundation

public enum C5hError: LocalizedError, Sendable {
    case providerNotConfigured(String)
    case cliNotFound(String)
    case authMissing(ProviderID)
    case processLaunchFailed(String)
    case processTimedOut
    case databaseError(String)
    case invalidProjectPath(String)
    case schedulerError(String)
    case migrationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .providerNotConfigured(let id):
            "Provider not configured: \(id)"
        case .cliNotFound(let name):
            "CLI not found: \(name)"
        case .authMissing(let provider):
            "Authentication missing for \(provider.displayName)"
        case .processLaunchFailed(let message):
            "Could not launch process: \(message)"
        case .processTimedOut:
            "Command timed out"
        case .databaseError(let message):
            "Database error: \(message)"
        case .invalidProjectPath(let path):
            "Invalid project path: \(path)"
        case .schedulerError(let message):
            "Scheduler error: \(message)"
        case .migrationFailed(let message):
            "Database migration failed: \(message)"
        }
    }
}
