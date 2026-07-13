import Foundation
import Testing
import GRDB
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
            commandName: .prompt,
            command: "/opt/homebrew/bin/claude",
            argumentsJSON: "[\"-p\",\"hi\"]",
            workingDirectory: "/tmp",
            startedAt: Date(timeIntervalSince1970: 1_730_000_000),
            status: .running,
            toolVersion: "claude 1.2.3"
        )
        try await repo.create(run)

        let fetched = try await repo.fetch(id: run.id)
        #expect(fetched?.commandName == .prompt)
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
            commandName: .prompt,
            command: "claude",
            argumentsJSON: "[]",
            status: .running
        ))
        try await repo.create(CommandRun(
            providerID: .codex,
            commandName: .version,
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
            commandName: .prompt,
            command: "claude",
            argumentsJSON: "[]",
            status: .running,
            ownerPID: alivePID
        ))
        try await repo.create(CommandRun(
            id: deadRunID,
            providerID: .claude,
            commandName: .prompt,
            command: "claude",
            argumentsJSON: "[]",
            status: .running,
            ownerPID: deadPID
        ))
        try await repo.create(CommandRun(
            id: legacyRunID,
            providerID: .codex,
            commandName: .prompt,
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

    @Test("fetchRecent skips un-decodable rows instead of failing the whole fetch")
    func skipsUndecodableRows() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        let repo = GRDBCommandRunRepository(database: db)

        let valid = CommandRun(
            providerID: .codex,
            commandName: .usage,
            command: "codex",
            argumentsJSON: "[]",
            startedAt: Date(timeIntervalSince1970: 1_730_000_000),
            status: .succeeded
        )
        try await repo.create(valid)

        // Simulate a row written by an older build: run_type holds the
        // pre-rename raw value "UsageCommand", which no longer maps to a
        // CommandName case, so toCommandRun() would throw for this row.
        let legacyID = UUID().uuidString
        try await db.writer.write { gdb in
            try gdb.execute(
                sql: """
                INSERT INTO command_runs
                (id, provider_id, run_type, command, arguments_json, started_at, status)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    legacyID, "codex", "UsageCommand", "codex", "[]",
                    "2026-07-13T20:45:31.000Z", "succeeded"
                ]
            )
        }

        // The stale row is skipped rather than aborting the entire fetch.
        let recent = try await repo.fetchRecent(limit: 500, filter: CommandRunFilter())
        #expect(recent.count == 1)
        #expect(recent.first?.id == valid.id)
        #expect(!recent.contains { $0.id.uuidString == legacyID })
    }
}
