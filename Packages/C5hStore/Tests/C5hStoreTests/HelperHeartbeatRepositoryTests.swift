import Foundation
import Testing
@testable import C5hStore

@Suite("HelperHeartbeatRepository")
struct HelperHeartbeatRepositoryTests {
    @Test("Write and read latest heartbeat")
    func writeReadLatestHeartbeat() async throws {
        let db = try Database.inMemory()
        let repo = GRDBHelperHeartbeatRepository(database: db)

        try await repo.writeHeartbeat(version: "0.0.1", pid: 123)

        let latest = try await repo.latest()
        #expect(latest?.id == "singleton")
        #expect(latest?.helperVersion == "0.0.1")
        #expect(latest?.pid == 123)
        #expect(latest?.startedAt != nil)
        #expect(latest?.lastSeenAt != nil)
    }

    @Test("Same pid preserves startedAt")
    func samePIDPreservesStartedAt() async throws {
        let db = try Database.inMemory()
        let repo = GRDBHelperHeartbeatRepository(database: db)

        try await repo.writeHeartbeat(version: "0.0.1", pid: 123)
        let first = try #require(await repo.latest())

        try await Task.sleep(nanoseconds: 10_000_000)
        try await repo.writeHeartbeat(version: "0.0.2", pid: 123)
        let second = try #require(await repo.latest())

        #expect(second.startedAt == first.startedAt)
        #expect(second.lastSeenAt > first.lastSeenAt)
        #expect(second.helperVersion == "0.0.2")
    }

    @Test("Changed pid resets startedAt")
    func changedPIDResetsStartedAt() async throws {
        let db = try Database.inMemory()
        let repo = GRDBHelperHeartbeatRepository(database: db)

        try await repo.writeHeartbeat(version: "0.0.1", pid: 123)
        let first = try #require(await repo.latest())

        try await Task.sleep(nanoseconds: 10_000_000)
        try await repo.writeHeartbeat(version: "0.0.1", pid: 456)
        let second = try #require(await repo.latest())

        #expect(second.startedAt > first.startedAt)
        #expect(second.lastSeenAt > first.lastSeenAt)
        #expect(second.pid == 456)
    }
}
