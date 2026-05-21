import Foundation

public protocol SchedulerDriver: Sendable {
    func fetchDuePrompts(now: Date) async throws -> [ScheduledPrompt]
    func claimAsRunning(id: UUID) async throws -> Bool
    func markSucceeded(id: UUID) async throws
    func markFailed(id: UUID, error: String) async throws
    func markMissed(id: UUID) async throws
    func trigger(prompt: ScheduledPrompt) async throws -> CommandRun

    /// Resolves and persists the provider's *real* current rolling 5h window
    /// after a prompt has fired, by reading upstream usage data. Returning
    /// `nil` signals that no `ActualWindow5h` should be written for this trigger
    /// — preferred over persisting a fictitious `[now, +5h]` placeholder when
    /// the upstream `resetsAt` is unknown. The returned row (when non-nil) is
    /// purely informational; the driver has already written it.
    func resolveActualWindow(
        for providerID: ProviderID,
        commandRun: CommandRun
    ) async throws -> ActualWindow5h?
}

public struct SchedulerTickReport: Sendable {
    public let now: Date
    public let duePromptCount: Int
    public let succeeded: Int
    public let failed: Int
    public let missed: Int
    public let lastError: String?
}

public actor SchedulerService {
    private let driver: any SchedulerDriver
    private let policy: MissedPromptPolicy
    private(set) public var lastReport: SchedulerTickReport?

    public init(
        driver: any SchedulerDriver,
        policy: MissedPromptPolicy = .default
    ) {
        self.driver = driver
        self.policy = policy
    }

    @discardableResult
    public func tick(now: Date = .now) async -> SchedulerTickReport {
        var succeeded = 0
        var failed = 0
        var missed = 0
        var lastErr: String?

        let prompts: [ScheduledPrompt]
        do {
            prompts = try await driver.fetchDuePrompts(now: now)
        } catch {
            let report = SchedulerTickReport(
                now: now,
                duePromptCount: 0,
                succeeded: 0,
                failed: 0,
                missed: 0,
                lastError: String(describing: error)
            )
            lastReport = report
            return report
        }

        for prompt in prompts {
            if policy.isOverdue(runAt: prompt.runAt, now: now) {
                do {
                    try await driver.markMissed(id: prompt.id)
                    missed += 1
                } catch {
                    lastErr = String(describing: error)
                }
                continue
            }
            do {
                let claimed = try await driver.claimAsRunning(id: prompt.id)
                if !claimed {
                    continue
                }
                let commandRun = try await driver.trigger(prompt: prompt)
                // `resolveActualWindow` is expected to persist the resolved
                // window itself (it knows whether to insert, update, or do
                // nothing). Returning a non-nil row is purely informational so
                // tests / future callers can observe what was written.
                _ = try await driver.resolveActualWindow(
                    for: prompt.providerID,
                    commandRun: commandRun
                )
                try await driver.markSucceeded(id: prompt.id)
                succeeded += 1
            } catch {
                let message = String(describing: error)
                lastErr = message
                try? await driver.markFailed(id: prompt.id, error: message)
                failed += 1
            }
        }

        let report = SchedulerTickReport(
            now: now,
            duePromptCount: prompts.count,
            succeeded: succeeded,
            failed: failed,
            missed: missed,
            lastError: lastErr
        )
        lastReport = report
        return report
    }
}
