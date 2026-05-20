import Foundation
import GRDB
import C5hCore

public protocol ProviderRepository: Sendable {
    func fetchAll() async throws -> [Provider]
    func fetch(id: ProviderID) async throws -> Provider?
    func upsert(_ provider: Provider) async throws
}

public struct GRDBProviderRepository: ProviderRepository {
    let writer: any DatabaseWriter

    public init(database: Database) {
        self.writer = database.writer
    }

    public func fetchAll() async throws -> [Provider] {
        try await writer.read { db in
            try ProviderRecord.fetchAll(db)
        }.map { try $0.toProvider() }
    }

    public func fetch(id: ProviderID) async throws -> Provider? {
        let record = try await writer.read { db in
            try ProviderRecord.fetchOne(db, key: id.rawValue)
        }
        return try record?.toProvider()
    }

    public func upsert(_ provider: Provider) async throws {
        let record = ProviderRecord(from: provider)
        try await writer.write { db in
            try record.upsert(db)
        }
    }
}
