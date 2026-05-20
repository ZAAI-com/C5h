import Foundation
import Testing
import GRDB
@testable import C5hStore
@testable import C5hCore

@Suite("Migrations")
struct MigrationsTests {
    @Test("In-memory database creates all expected tables and indexes")
    func allTablesExist() async throws {
        let db = try Database.inMemory()
        let names: Set<String> = try await db.writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type IN ('table','index')
                """)
            return Set(rows.compactMap { $0["name"] as String? })
        }

        let expectedTables: Set<String> = [
            "providers",
            "planned_windows",
            "actual_windows",
            "scheduled_prompts",
            "command_runs",
            "usage_snapshots",
            "prompt_templates",
            "app_settings",
            "helper_heartbeats"
        ]
        #expect(expectedTables.isSubset(of: names))

        let expectedIndexes: Set<String> = [
            "idx_planned_windows_provider_start",
            "idx_actual_windows_provider_start",
            "idx_scheduled_prompts_status_run_at",
            "idx_command_runs_provider_started",
            "idx_command_runs_status_started",
            "idx_usage_snapshots_provider_captured"
        ]
        #expect(expectedIndexes.isSubset(of: names))
    }

    @Test("Seed inserts providers and templates")
    func seedInserts() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)

        let providers = try await GRDBProviderRepository(database: db).fetchAll()
        #expect(providers.count == 2)
        #expect(providers.contains(where: { $0.id == .claude }))
        #expect(providers.contains(where: { $0.id == .codex }))

        let templates = try await GRDBPromptTemplateRepository(database: db).fetchAll()
        #expect(templates.count == 3)
    }

    @Test("Seed is idempotent")
    func seedIdempotent() async throws {
        let db = try Database.inMemory()
        try await Seed.runIfNeeded(database: db)
        try await Seed.runIfNeeded(database: db)
        let providers = try await GRDBProviderRepository(database: db).fetchAll()
        #expect(providers.count == 2)
    }
}
