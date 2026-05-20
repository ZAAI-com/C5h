import Foundation
import GRDB
import C5hCore

public enum Seed {
    public static func runIfNeeded(database: Database) async throws {
        try await database.writer.write { db in
            let providerCount = try ProviderRecord.fetchCount(db)
            if providerCount == 0 {
                try seedProviders(db)
            }
            let templateCount = try PromptTemplateRecord.fetchCount(db)
            if templateCount == 0 {
                try seedTemplates(db)
            }
        }
    }

    private static func seedProviders(_ db: GRDB.Database) throws {
        let now = Date()
        let claude = Provider(
            id: .claude,
            displayName: ProviderID.claude.displayName,
            isEnabled: true,
            brandColorHex: "#D96E40",
            createdAt: now,
            updatedAt: now
        )
        let codex = Provider(
            id: .codex,
            displayName: ProviderID.codex.displayName,
            isEnabled: true,
            brandColorHex: "#2664EB",
            createdAt: now,
            updatedAt: now
        )
        try ProviderRecord(from: claude).insert(db)
        try ProviderRecord(from: codex).insert(db)
    }

    private static func seedTemplates(_ db: GRDB.Database) throws {
        let now = Date()
        let templates: [PromptTemplate] = [
            PromptTemplate(
                name: "Start 5h coding window",
                providerID: nil,
                body: "Begin a 5-hour focused coding session. Pick up the active task and continue.",
                createdAt: now,
                updatedAt: now
            ),
            PromptTemplate(
                name: "Continue previous task",
                providerID: nil,
                body: "Continue the previous task from where we left off.",
                createdAt: now,
                updatedAt: now
            ),
            PromptTemplate(
                name: "Resume project context",
                providerID: nil,
                body: "Re-read the project README, recent commits, and TODOs, then suggest next steps.",
                createdAt: now,
                updatedAt: now
            )
        ]
        for t in templates {
            try PromptTemplateRecord(from: t).insert(db)
        }
    }
}
