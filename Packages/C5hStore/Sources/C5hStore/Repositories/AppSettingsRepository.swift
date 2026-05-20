import Foundation
import GRDB
import C5hCore

public protocol AppSettingsRepository: Sendable {
    func get<T: Decodable & Sendable>(_ key: String, as type: T.Type) async throws -> T?
    func set<T: Encodable & Sendable>(_ key: String, value: T) async throws
    func remove(_ key: String) async throws
}

public struct GRDBAppSettingsRepository: AppSettingsRepository {
    let writer: any DatabaseWriter

    public init(database: Database) {
        self.writer = database.writer
    }

    public func get<T: Decodable & Sendable>(_ key: String, as type: T.Type) async throws -> T? {
        let record = try await writer.read { db in
            try AppSettingRecord.fetchOne(db, key: key)
        }
        guard let json = record?.valueJson, let data = json.data(using: .utf8) else {
            return nil
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    public func set<T: Encodable & Sendable>(_ key: String, value: T) async throws {
        let data = try JSONEncoder().encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw C5hError.databaseError("AppSettingsRepository: failed to encode \(key) value as UTF-8")
        }
        let record = AppSettingRecord(
            key: key,
            valueJson: json,
            updatedAt: DateTimeService.formatUTC(.now)
        )
        try await writer.write { db in
            try record.upsert(db)
        }
    }

    public func remove(_ key: String) async throws {
        try await writer.write { db in
            _ = try AppSettingRecord.deleteOne(db, key: key)
        }
    }
}
