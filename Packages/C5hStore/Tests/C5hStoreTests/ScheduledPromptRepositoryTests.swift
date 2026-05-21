import Foundation
import Testing
@testable import C5hStore
@testable import C5hCore

@Suite("ScheduledPromptRepository")
struct ScheduledPromptRepositoryTests {
    @Test("Atomic claim only succeeds once")
    func atomicClaim() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBScheduledPromptRepository(database: db)

        let prompt = ScheduledPrompt(
            providerID: .claude,
            prompt: "go",
            runAt: Date(timeIntervalSince1970: 1_700_000_000),
            status: .scheduled
        )
        try await repo.create(prompt)

        let claim1 = try await repo.tryClaimAsRunning(id: prompt.id)
        let claim2 = try await repo.tryClaimAsRunning(id: prompt.id)
        #expect(claim1 == true)
        #expect(claim2 == false)

        let fetched = try await repo.fetch(id: prompt.id)
        #expect(fetched?.status == .running)
        #expect(fetched?.attempts == 1)
    }

    @Test("fetchDuePrompts returns only scheduled prompts at-or-before now")
    func duePrompts() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBScheduledPromptRepository(database: db)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let past = now.addingTimeInterval(-3600)
        let future = now.addingTimeInterval(3600)

        try await repo.create(ScheduledPrompt(providerID: .claude, prompt: "p1", runAt: past, status: .scheduled))
        try await repo.create(ScheduledPrompt(providerID: .codex, prompt: "p2", runAt: future, status: .scheduled))
        try await repo.create(ScheduledPrompt(providerID: .claude, prompt: "p3", runAt: past, status: .succeeded))

        let due = try await repo.fetchDuePrompts(now: now)
        #expect(due.count == 1)
        #expect(due.first?.prompt == "p1")
    }

    @Test("Reschedules pending prompts linked to a planned window")
    func reschedulesPendingLinkedPrompts() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let plannedRepo = GRDBPlannedWindowRepository(database: db)
        let promptRepo = GRDBScheduledPromptRepository(database: db)

        let originalRunAt = Date(timeIntervalSince1970: 1_700_000_000)
        let newRunAt = originalRunAt.addingTimeInterval(3600)
        let planned = PlannedWindow(providerID: .claude, startAt: originalRunAt)
        try await plannedRepo.create(planned)

        let pending = ScheduledPrompt(
            providerID: .claude,
            plannedWindowID: planned.id,
            prompt: "pending",
            runAt: originalRunAt,
            status: .scheduled
        )
        let completed = ScheduledPrompt(
            providerID: .claude,
            plannedWindowID: planned.id,
            prompt: "done",
            runAt: originalRunAt,
            status: .succeeded
        )
        try await promptRepo.create(pending)
        try await promptRepo.create(completed)

        try await promptRepo.reschedulePendingPrompts(
            plannedWindowID: planned.id,
            providerID: .codex,
            projectPath: "/tmp/project",
            runAt: newRunAt
        )

        let fetchedPending = try await promptRepo.fetch(id: pending.id)
        #expect(fetchedPending?.providerID == .codex)
        #expect(fetchedPending?.projectPath == "/tmp/project")
        #expect(fetchedPending?.runAt == newRunAt)

        let fetchedCompleted = try await promptRepo.fetch(id: completed.id)
        #expect(fetchedCompleted?.providerID == .claude)
        #expect(fetchedCompleted?.projectPath == nil)
        #expect(fetchedCompleted?.runAt == originalRunAt)
    }

    @Test("Cancels pending linked prompts and detaches all before planned delete")
    func cancelsPendingAndDetachesLinkedPrompts() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let plannedRepo = GRDBPlannedWindowRepository(database: db)
        let promptRepo = GRDBScheduledPromptRepository(database: db)

        let runAt = Date(timeIntervalSince1970: 1_700_000_000)
        let planned = PlannedWindow(providerID: .claude, startAt: runAt)
        try await plannedRepo.create(planned)

        let pending = ScheduledPrompt(
            providerID: .claude,
            plannedWindowID: planned.id,
            prompt: "pending",
            runAt: runAt,
            status: .scheduled
        )
        let completed = ScheduledPrompt(
            providerID: .claude,
            plannedWindowID: planned.id,
            prompt: "done",
            runAt: runAt,
            status: .succeeded
        )
        try await promptRepo.create(pending)
        try await promptRepo.create(completed)

        try await promptRepo.cancelPendingAndDetachPrompts(plannedWindowID: planned.id)

        let fetchedPending = try await promptRepo.fetch(id: pending.id)
        #expect(fetchedPending?.status == .cancelled)
        #expect(fetchedPending?.plannedWindowID == nil)

        let fetchedCompleted = try await promptRepo.fetch(id: completed.id)
        #expect(fetchedCompleted?.status == .succeeded)
        #expect(fetchedCompleted?.plannedWindowID == nil)

        try await plannedRepo.delete(id: planned.id)
        let deleted = try await plannedRepo.fetch(id: planned.id)
        #expect(deleted == nil)
    }
}
