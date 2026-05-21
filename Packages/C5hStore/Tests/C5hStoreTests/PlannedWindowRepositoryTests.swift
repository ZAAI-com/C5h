import Foundation
import Testing
@testable import C5hStore
@testable import C5hCore

@Suite("PlannedWindowRepository")
struct PlannedWindowRepositoryTests {
    @Test("CRUD round-trip")
    func crud() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBPlannedWindowRepository(database: db)

        let original = PlannedWindow(
            providerID: .claude,
            startAt: Date(timeIntervalSince1970: 1_730_000_000),
            durationSeconds: 5 * 3600,
            projectPath: "/tmp/foo",
            status: .scheduled
        )
        try await repo.create(original)

        let fetched = try await repo.fetch(id: original.id)
        #expect(fetched != nil)
        #expect(fetched?.providerID == .claude)
        #expect(fetched?.durationSeconds == 5 * 3600)
        #expect(fetched?.status == .scheduled)
        #expect(fetched?.projectPath == "/tmp/foo")

        var updated = original
        updated.status = .triggered
        try await repo.update(updated)
        let refetched = try await repo.fetch(id: original.id)
        #expect(refetched?.status == .triggered)

        try await repo.delete(id: original.id)
        let gone = try await repo.fetch(id: original.id)
        #expect(gone == nil)
    }

    @Test("fetchWindows filters by interval")
    func intervalFilter() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBPlannedWindowRepository(database: db)

        let day1 = Date(timeIntervalSince1970: 1_730_000_000)
        let day2 = day1.addingTimeInterval(86_400)
        let day3 = day1.addingTimeInterval(86_400 * 2)

        try await repo.create(PlannedWindow(providerID: .claude, startAt: day1))
        try await repo.create(PlannedWindow(providerID: .codex, startAt: day2))
        try await repo.create(PlannedWindow(providerID: .claude, startAt: day3))

        let onlyDay2 = try await repo.fetchWindows(
            for: DateInterval(start: day2, end: day2.addingTimeInterval(86_400))
        )
        #expect(onlyDay2.count == 1)
        #expect(onlyDay2.first?.providerID == .codex)
    }

    @Test("Same-provider overlapping create is rejected")
    func rejectsSameProviderOverlapOnCreate() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBPlannedWindowRepository(database: db)

        let base = Date(timeIntervalSince1970: 1_730_000_000)
        try await repo.create(PlannedWindow(providerID: .claude, startAt: base))

        do {
            try await repo.create(PlannedWindow(
                providerID: .claude,
                startAt: base.addingTimeInterval(3600)
            ))
            Issue.record("Same-provider overlapping planned window should be rejected")
        } catch {
            #expect(String(describing: error).contains("cannot overlap"))
        }
    }

    @Test("Same-provider overlapping update is rejected")
    func rejectsSameProviderOverlapOnUpdate() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBPlannedWindowRepository(database: db)

        let base = Date(timeIntervalSince1970: 1_730_000_000)
        let first = PlannedWindow(providerID: .claude, startAt: base)
        var second = PlannedWindow(providerID: .claude, startAt: base.addingTimeInterval(6 * 3600))
        try await repo.create(first)
        try await repo.create(second)

        second.startAt = base.addingTimeInterval(3600)
        do {
            try await repo.update(second)
            Issue.record("Same-provider overlapping planned-window update should be rejected")
        } catch {
            #expect(String(describing: error).contains("cannot overlap"))
        }
    }

    @Test("Different-provider overlap and same-provider boundary touch are allowed")
    func allowsDifferentProviderOverlapAndBoundaryTouch() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBPlannedWindowRepository(database: db)

        let base = Date(timeIntervalSince1970: 1_730_000_000)
        let first = PlannedWindow(providerID: .claude, startAt: base)
        try await repo.create(first)
        try await repo.create(PlannedWindow(providerID: .codex, startAt: base))
        try await repo.create(PlannedWindow(providerID: .claude, startAt: first.endAt))

        let windows = try await repo.fetchWindows(
            for: DateInterval(start: base, end: first.endAt.addingTimeInterval(5 * 3600))
        )
        #expect(windows.count == 3)
    }
}
