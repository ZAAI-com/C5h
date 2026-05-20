import Foundation

public protocol ProviderAdapter: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }

    func runVersionCommand() async -> ProviderStatus
    func runAuthStatusCommand() async -> ProviderStatus
    func runUsageCommand() async throws -> UsageSnapshot
    func runPromptCommand(_ input: TriggerPromptInput) async throws -> CommandRun
}

public struct ProviderStatus: Codable, Sendable, Hashable {
    public var providerID: ProviderID
    public var isInstalled: Bool
    public var cliPath: String?
    public var version: String?
    public var isAuthenticated: Bool?
    public var lastCheckedAt: Date
    public var errorMessage: String?

    public init(
        providerID: ProviderID,
        isInstalled: Bool,
        cliPath: String? = nil,
        version: String? = nil,
        isAuthenticated: Bool? = nil,
        lastCheckedAt: Date = .now,
        errorMessage: String? = nil
    ) {
        self.providerID = providerID
        self.isInstalled = isInstalled
        self.cliPath = cliPath
        self.version = version
        self.isAuthenticated = isAuthenticated
        self.lastCheckedAt = lastCheckedAt
        self.errorMessage = errorMessage
    }
}

public enum ProviderHealthState: Sendable, Hashable {
    case unknown
    case ready
    case cliMissing
    case authMissing
    case error(String)

    public init(from status: ProviderStatus) {
        if !status.isInstalled {
            self = .cliMissing
            return
        }
        if let auth = status.isAuthenticated, !auth {
            self = .authMissing
            return
        }
        if let err = status.errorMessage, !err.isEmpty {
            self = .error(err)
            return
        }
        if status.isAuthenticated == true {
            self = .ready
            return
        }
        self = .unknown
    }

    public var label: String {
        switch self {
        case .unknown: "Unknown"
        case .ready: "Ready"
        case .cliMissing: "CLI missing"
        case .authMissing: "Authentication missing"
        case .error(let msg): "Error: \(msg)"
        }
    }
}

public struct TriggerPromptInput: Codable, Sendable {
    public var prompt: String
    public var projectPath: String?
    public var mode: TriggerPromptMode

    public init(prompt: String, projectPath: String? = nil, mode: TriggerPromptMode = .newSession) {
        self.prompt = prompt
        self.projectPath = projectPath
        self.mode = mode
    }
}

public enum TriggerPromptMode: String, Codable, Sendable {
    case newSession
    case continueLast
    case resumeSession
}
