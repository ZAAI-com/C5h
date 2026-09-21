import Foundation

public enum ProviderID: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case claude
    case codex

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    public var executableName: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        }
    }

    public var plannedWindowSnapMinutes: Int {
        switch self {
        case .claude: 10
        case .codex: 5
        }
    }

    /// Whether this provider's usage probe itself consumes quota. Claude's probe
    /// PTY-drives the interactive `claude` REPL, whose startup makes a real API
    /// request; on an idle account that request opens a fresh 5h rate-limit
    /// window (anchored at the previous window's expiry bucket), so an idle poll
    /// is never free. Codex's probe is a read-only `codex app-server`
    /// `account/rateLimits/read` RPC and never opens a window.
    public var usageProbeConsumesQuota: Bool {
        switch self {
        case .claude: true
        case .codex: false
        }
    }
}
