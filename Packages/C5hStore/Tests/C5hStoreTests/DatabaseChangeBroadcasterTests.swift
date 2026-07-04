import Foundation
import GRDB
import Testing
@testable import C5hStore
@testable import C5hCore

@Suite("DatabaseChangeBroadcaster")
struct DatabaseChangeBroadcasterTests {
    /// Thread-safe counter: the broadcaster fires its closure on GRDB's serialized
    /// writer queue, which is a different thread from the test task.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.lock(); value += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    @Test("Fires for observed-table writes, not for excluded heartbeat writes")
    func firesOnlyForObservedTables() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)

        let counter = Counter()
        let broadcaster = DatabaseChangeBroadcaster(
            observedTables: Database.changeObservedTables
        ) {
            counter.increment()
        }
        db.writer.add(transactionObserver: broadcaster, extent: .databaseLifetime)

        // Observed table -> signals.
        let plannedRepo = GRDBPlannedWindowRepository(database: db)
        try await plannedRepo.create(PlannedWindow(
            providerID: .claude,
            startAt: Date(timeIntervalSince1970: 1_730_000_000)
        ))
        #expect(counter.count == 1)

        // Another observed-table write -> signals again.
        let actualRepo = GRDBActualWindow5hRepository(database: db)
        try await actualRepo.create(ActualWindow5h(
            providerID: .codex,
            startAt: Date(timeIntervalSince1970: 1_730_100_000),
            durationSeconds: 5 * 3600,
            source: .detectedFromUsage,
            confidence: .estimated
        ))
        #expect(counter.count == 2)

        // Excluded table (helper_heartbeats) -> no signal.
        let heartbeatRepo = GRDBHelperHeartbeatRepository(database: db)
        try await heartbeatRepo.writeHeartbeat(version: "0.0.1", pid: 123)
        #expect(counter.count == 2)
    }

    @Test("Database.open posts a Darwin notification another process receives")
    func postsDarwinNotificationCrossProcess() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("c5h-broadcaster-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        // Unique name so a concurrently running C5h app posting the production
        // name can neither satisfy nor steal this test's listener.
        let notificationName = "com.zaai.c5h.databaseDidChange.test.\(UUID().uuidString)"
        let db = try Database.open(
            at: dir.appendingPathComponent("test.sqlite"),
            notificationName: notificationName
        )
        // Seeds providers (satisfies the planned_windows FK) without signaling:
        // the providers table is not in changeObservedTables.
        try await Seed.runIfNeeded(database: db)

        // notifyutil -1 blocks until it receives one notification, then exits.
        let listener = Process()
        listener.executableURL = URL(fileURLWithPath: "/usr/bin/notifyutil")
        listener.arguments = ["-1", notificationName]
        listener.standardOutput = FileHandle.nullDevice
        try listener.run()
        defer { if listener.isRunning { listener.terminate() } }
        // Give it a moment to register with notifyd.
        try await Task.sleep(for: .milliseconds(300))

        // Write planned windows (spaced to avoid overlap rejection) until the
        // listener exits or we time out.
        let repo = GRDBPlannedWindowRepository(database: db)
        var startAt = Date(timeIntervalSince1970: 1_730_000_000)
        let deadline = Date().addingTimeInterval(5)
        while listener.isRunning && Date() < deadline {
            try await repo.create(PlannedWindow(providerID: .claude, startAt: startAt))
            startAt = startAt.addingTimeInterval(6 * 3600)
            try await Task.sleep(for: .milliseconds(200))
        }
        #expect(!listener.isRunning, "listener never received the Darwin notification")
    }
}
