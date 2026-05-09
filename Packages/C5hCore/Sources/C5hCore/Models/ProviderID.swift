import Foundation

public enum ProviderID: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case claude
    case codex

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "OpenAI Codex"
        }
    }

    public var executableName: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        }
    }
}
