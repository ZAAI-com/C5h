import Foundation
import Testing
@testable import C5hCore

actor RecordingSchedulerDriver: SchedulerDriver {
    var duePrompts: [ScheduledPrompt] = []
    var claimableIDs: Set<UUID> = []
    var triggerOutcome: TriggerOutcome = .succeed

    enum TriggerOutcome: Sendable {
        case succeed
        case fail(message: String)
    }

    var registeredWindows: [ActualWindow] = []
    var marks: [(id: UUID, status: ScheduledPromptStatus, error: String?)] = []
    var claims: [UUID] = []
    var triggers: [UUID] = []

    func setDue(_ prompts: [ScheduledPrompt]) {
        duePrompts = prompts
        claimableIDs = Set(prompts.map { $0.id })
    }

    func appendDuplicateDue(_ prompt: ScheduledPrompt) {
        duePrompts.append(prompt)
    }

    func setTrigger(_ outcome: TriggerOutcome) {
        triggerOutcome = outcome
    }

    func fetchDuePrompts(now: Date) async throws -> [ScheduledPrompt] {
        duePrompts
    }

    func claimAsRunning(id: UUID) async throws -> Bool {
        claims.append(id)
        if claimableIDs.contains(id) {
            claimableIDs.remove(id)
            return true
        }
        return false
    }

    func markSucceeded(id: UUID) async throws {
        marks.append((id, .succeeded, nil))
    }

    func markFailed(id: UUID, error: String) async throws {
        marks.append((id, .failed, error))
    }

    func markMissed(id: UUID) async throws {
        marks.append((id, .missed, nil))
    }

    func registerActualWindow(_ window: ActualWindow) async throws {
        registeredWindows.append(window)
    }

    func trigger(prompt: ScheduledPrompt) async throws -> CommandRun {
        triggers.append(prompt.id)
        switch triggerOutcome {
        case .succeed:
            return CommandRun(
                providerID: prompt.providerID,
                commandName: .promptCommand,
                command: "claude",
                argumentsJSON: "[]",
                status: .succeeded
            )
        case .fail(let message):
            throw C5hError.processLaunchFailed(message)
        }
    }
}

@Suite("SchedulerService")
struct SchedulerServiceTests {
    @Test("Due prompt is claimed, triggered, registers actual window, and marked succeeded")
    func happyPath() async throws {
        let driver = RecordingSchedulerDriver()
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        let prompt = ScheduledPrompt(
            providerID: .claude,
            prompt: "do work",
            runAt: now.addingTimeInterval(-30)
        )
        await driver.setDue([prompt])
        let scheduler = SchedulerService(driver: driver)
        let report = await scheduler.tick(now: now)
        #expect(report.succeeded == 1)
        #expect(report.failed == 0)
        #expect(report.missed == 0)

        let claims = await driver.claims
        let triggers = await driver.triggers
        let windows = await driver.registeredWindows
        let marks = await driver.marks
        #expect(claims == [prompt.id])
        #expect(triggers == [prompt.id])
        #expect(windows.count == 1)
        #expect(windows.first?.source == .c5hTriggered)
        #expect(marks.last?.status == .succeeded)
    }

    @Test("Already-claimed prompt is skipped (no double-run)")
    func doubleRunGuard() async throws {
        let driver = RecordingSchedulerDriver()
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        let prompt = ScheduledPrompt(
            providerID: .claude,
            prompt: "go",
            runAt: now.addingTimeInterval(-10)
        )
        await driver.setDue([prompt])
        await driver.appendDuplicateDue(prompt)  // appears twice as if two ticks raced
        let scheduler = SchedulerService(driver: driver)
        let report = await scheduler.tick(now: now)
        let triggers = await driver.triggers
        #expect(triggers.count == 1)
        #expect(report.succeeded == 1)
    }

    @Test("Overdue prompt past grace is marked missed without triggering")
    func missed() async throws {
        let driver = RecordingSchedulerDriver()
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        let prompt = ScheduledPrompt(
            providerID: .codex,
            prompt: "late",
            runAt: now.addingTimeInterval(-3600)
        )
        await driver.setDue([prompt])
        let scheduler = SchedulerService(
            driver: driver,
            policy: MissedPromptPolicy(graceSeconds: 60)
        )
        let report = await scheduler.tick(now: now)
        let triggers = await driver.triggers
        let marks = await driver.marks
        #expect(triggers.isEmpty)
        #expect(marks.last?.status == .missed)
        #expect(report.missed == 1)
    }

    @Test("Trigger failure marks the prompt failed with error")
    func triggerFailureMarksFailed() async throws {
        let driver = RecordingSchedulerDriver()
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        let prompt = ScheduledPrompt(
            providerID: .claude,
            prompt: "boom",
            runAt: now
        )
        await driver.setDue([prompt])
        await driver.setTrigger(.fail(message: "denied"))
        let scheduler = SchedulerService(driver: driver)
        let report = await scheduler.tick(now: now)
        let marks = await driver.marks
        #expect(report.failed == 1)
        #expect(marks.last?.status == .failed)
    }
}
