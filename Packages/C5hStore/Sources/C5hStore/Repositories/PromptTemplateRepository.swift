import Foundation
import GRDB
import C5hCore

public protocol PromptTemplateRepository: Sendable {
    func fetchAll() async throws -> [PromptTemplate]
    func fetch(id: UUID) async throws -> PromptTemplate?
    func upsert(_ template: PromptTemplate) async throws
    func delete(id: UUID) async throws
}

public struct GRDBPromptTemplateRepository: PromptTemplateRepository {
    let writer: any DatabaseWriter

    public init(database: Database) {
        self.writer = database.writer
    }

    public func fetchAll() async throws -> [PromptTemplate] {
        let records = try await writer.read { db in
            try PromptTemplateRecord.order(Column("name")).fetchAll(db)
        }
        return try records.map { try $0.toPromptTemplate() }
    }

    public func fetch(id: UUID) async throws -> PromptTemplate? {
        let record = try await writer.read { db in
            try PromptTemplateRecord.fetchOne(db, key: id.uuidString)
        }
        return try record?.toPromptTemplate()
    }

    public func upsert(_ template: PromptTemplate) async throws {
        let record = PromptTemplateRecord(from: template)
        try await writer.write { db in
            try record.upsert(db)
        }
    }

    public func delete(id: UUID) async throws {
        try await writer.write { db in
            _ = try PromptTemplateRecord.deleteOne(db, key: id.uuidString)
        }
    }
}
