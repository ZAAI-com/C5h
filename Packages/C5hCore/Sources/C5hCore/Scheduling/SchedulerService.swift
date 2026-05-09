import Foundation

public protocol SchedulerDriver: Sendable {
    func fetchDuePrompts(now: Date) async throws -> [ScheduledPrompt]
    func claimAsRunning(id: UUID) async throws -> Bool
    func markSucceeded(id: UUID) async throws
    func markFailed(id: UUID, error: String) async throws
    func markMissed(id: UUID) async throws
    func registerActualWindow(_ window: ActualWindow) async throws
    func trigger(prompt: ScheduledPrompt) async throws -> CommandRun
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
                let actualWindow = ActualWindow(
                    providerID: prompt.providerID,
                    startAt: commandRun.startedAt,
                    durationSeconds: 5 * 3600,
                    source: .c5hTriggered,
                    confidence: .exact,
                    commandRunID: commandRun.id
                )
                try await driver.registerActualWindow(actualWindow)
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
