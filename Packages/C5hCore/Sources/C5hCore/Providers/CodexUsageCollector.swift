import Foundation

/// Fetches a Codex usage snapshot via the `codex app-server` JSON-RPC bridge.
/// Used by both the main app's `CodexProviderAdapter` and the background
/// `C5hHelper` polling loop.
public struct CodexUsageCollector: Sendable {
    public let executableURL: URL
    public let environment: [String: String]
    public let timeoutSeconds: TimeInterval
    public let clientVersion: String

    public init(
        executableURL: URL,
        environment: [String: String] = EnvironmentResolver.defaultEnvironment(),
        timeoutSeconds: TimeInterval = 30,
        clientVersion: String = "dev"
    ) {
        self.executableURL = executableURL
        self.environment = environment
        self.timeoutSeconds = timeoutSeconds
        self.clientVersion = clientVersion
    }

    public func collect() async throws -> UsageSnapshot {
        let client = CodexAppServerClient(
            executableURL: executableURL,
            environment: environment,
            timeoutSeconds: timeoutSeconds,
            clientVersion: clientVersion
        )
        let capturedAt = Date()
        let rawResult = try await client.fetchRateLimitsResult()
        let status = try CodexUsageStatus.parseAppServerResponse(rawResult, capturedAt: capturedAt)
        return UsageSnapshot(
            providerID: .codex,
            capturedAt: capturedAt,
            rawJSON: rawResult,
            normalizedJSON: UsageNormalizer.encode(
                status.normalizedUsage(providerID: .codex, capturedAt: capturedAt)
            )
        )
    }
}
