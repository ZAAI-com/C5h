import Foundation
import Testing
@testable import C5hCore
@testable import C5hStore

@Suite("UsageSnapshotRepository weekly block rule")
struct WeeklyWindowBlocksRuleTests {
    private static let fiveHourAndWeekly = """
        {"rateLimits":{"primary":{"usedPercent":12,"windowDurationMins":300,"resetsAt":1780003600},"secondary":{"usedPercent":73,"windowDurationMins":10080,"resetsAt":1780500000}}}
        """
    private static let weeklyOnly = """
        {"rateLimits":{"primary":{"usedPercent":73,"windowDurationMins":10080,"resetsAt":1780500000}}}
        """

    @Test("Codex weekly blocks show with or without a 5h limit")
    func codexAlwaysShows() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBUsageSnapshotRepository(database: db)

        #expect(await repo.showsWeeklyWindowBlocks(providerID: .codex))

        try await repo.create(snapshot(.codex, rawJSON: Self.fiveHourAndWeekly))
        #expect(await repo.isWeeklyOnly(providerID: .codex) == false)
        #expect(await repo.showsWeeklyWindowBlocks(providerID: .codex))

        try await repo.create(snapshot(.codex, rawJSON: Self.weeklyOnly, offset: 60))
        #expect(await repo.isWeeklyOnly(providerID: .codex))
        #expect(await repo.showsWeeklyWindowBlocks(providerID: .codex))
    }

    @Test("Claude weekly blocks stay hidden without a weekly-only snapshot")
    func claudeHiddenByDefault() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBUsageSnapshotRepository(database: db)

        #expect(await repo.showsWeeklyWindowBlocks(providerID: .claude) == false)
    }

    private func snapshot(_ providerID: ProviderID, rawJSON: String, offset: TimeInterval = 0) -> UsageSnapshot {
        UsageSnapshot(
            providerID: providerID,
            capturedAt: Date(timeIntervalSince1970: 1_780_000_000 + offset),
            rawJSON: rawJSON,
            normalizedJSON: "{}"
        )
    }
}
