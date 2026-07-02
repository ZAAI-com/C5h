import Foundation
import Testing
@testable import C5hCore
@testable import C5hStore

@Suite("UsageCheckGate factory")
struct UsageCheckGateFactoryTests {
    @Test("Pending planned windows must overlap now when idle checking is disabled")
    func pendingPlannedWindowsMustOverlapNow() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let settings = GRDBAppSettingsRepository(database: db)
        let plannedRepo = GRDBPlannedWindowRepository(database: db)
        let actualRepo = GRDBActualWindow5hRepository(database: db)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try await settings.set(AppSettingsKeys.checkUsageWhenIdle(for: .claude), value: false)

        try await plannedRepo.create(PlannedWindow(
            providerID: .claude,
            startAt: now.addingTimeInterval(-10 * 3600),
            status: .scheduled
        ))
        try await plannedRepo.create(PlannedWindow(
            providerID: .claude,
            startAt: now.addingTimeInterval(10 * 3600),
            status: .scheduled
        ))

        let gate = UsageCheckGate.make(
            appSettings: settings,
            actual5hRepository: actualRepo,
            plannedWindowRepository: plannedRepo
        )
        #expect(await gate.shouldCheck(providerID: .claude, now: now) == false)

        try await plannedRepo.create(PlannedWindow(
            providerID: .claude,
            startAt: now.addingTimeInterval(-60),
            status: .scheduled
        ))
        #expect(await gate.shouldCheck(providerID: .claude, now: now))
    }
}
