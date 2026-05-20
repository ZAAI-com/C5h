import Foundation
import Testing
@testable import C5hStore
@testable import C5hCore

@Suite("CommandRunRepository")
struct CommandRunRepositoryTests {
    @Test("Persist and fetch CommandRun including tool_version")
    func persistRun() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBCommandRunRepository(database: db)

        let run = CommandRun(
            providerID: .claude,
            commandName: .promptCommand,
            command: "/opt/homebrew/bin/claude",
            argumentsJSON: "[\"-p\",\"hi\"]",
            workingDirectory: "/tmp",
            startedAt: Date(timeIntervalSince1970: 1_730_000_000),
            status: .running,
            toolVersion: "claude 1.2.3"
        )
        try await repo.create(run)

        let fetched = try await repo.fetch(id: run.id)
        #expect(fetched?.commandName == .promptCommand)
        #expect(fetched?.toolVersion == "claude 1.2.3")
        #expect(fetched?.status == .running)
        #expect(fetched?.workingDirectory == "/tmp")
    }

    @Test("Sweep stale running marks them cancelled")
    func sweepStale() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBCommandRunRepository(database: db)

        try await repo.create(CommandRun(
            providerID: .claude,
            commandName: .promptCommand,
            command: "claude",
            argumentsJSON: "[]",
            status: .running
        ))
        try await repo.create(CommandRun(
            providerID: .codex,
            commandName: .versionCommand,
            command: "codex",
            argumentsJSON: "[]",
            status: .succeeded
        ))

        let swept = try await repo.sweepStaleRunning(message: "orphaned by app restart")
        #expect(swept == 1)

        let recent = try await repo.fetchRecent(limit: 10, filter: CommandRunFilter())
        #expect(recent.count == 2)
        #expect(recent.first { $0.status == .cancelled }?.errorMessage == "orphaned by app restart")
        #expect(recent.contains { $0.status == .succeeded })
    }

    @Test("Sweep only cancels runs whose owner pid is dead or unknown")
    func sweepScopedByOwnerPID() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBCommandRunRepository(database: db)

        let alivePID: Int32 = 1234
        let deadPID: Int32 = 4321
        let liveRunID = UUID()
        let deadRunID = UUID()
        let legacyRunID = UUID()

        try await repo.create(CommandRun(
            id: liveRunID,
            providerID: .claude,
            commandName: .promptCommand,
            command: "claude",
            argumentsJSON: "[]",
            status: .running,
            ownerPID: alivePID
        ))
        try await repo.create(CommandRun(
            id: deadRunID,
            providerID: .claude,
            commandName: .promptCommand,
            command: "claude",
            argumentsJSON: "[]",
            status: .running,
            ownerPID: deadPID
        ))
        try await repo.create(CommandRun(
            id: legacyRunID,
            providerID: .codex,
            commandName: .promptCommand,
            command: "codex",
            argumentsJSON: "[]",
            status: .running,
            ownerPID: nil
        ))

        let swept = try await repo.sweepStaleRunning(
            message: "orphaned",
            isAlive: { pid in pid == alivePID }
        )
        #expect(swept == 2)

        let live = try await repo.fetch(id: liveRunID)
        #expect(live?.status == .running)

        let dead = try await repo.fetch(id: deadRunID)
        #expect(dead?.status == .cancelled)
        #expect(dead?.errorMessage == "orphaned")

        let legacy = try await repo.fetch(id: legacyRunID)
        #expect(legacy?.status == .cancelled)
        #expect(legacy?.errorMessage == "orphaned")
    }
}
