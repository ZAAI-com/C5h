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
}
