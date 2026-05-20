import Foundation
import GRDB
import C5hCore

public final class Database: @unchecked Sendable {
    public let writer: any DatabaseWriter
    public let url: URL?

    private init(writer: any DatabaseWriter, url: URL?) {
        self.writer = writer
        self.url = url
    }

    public static func open(at url: URL) throws -> Database {
        try ensureParentDirectory(for: url)
        var config = Configuration()
        config.busyMode = .timeout(5)
        config.foreignKeysEnabled = true
        config.label = "c5h.db"
        let pool: DatabasePool
        do {
            pool = try DatabasePool(path: url.path, configuration: config)
        } catch {
            throw C5hError.databaseError("Failed to open DatabasePool at \(url.path): \(error)")
        }
        do {
            try Migrator.shared.migrate(pool)
        } catch {
            throw C5hError.migrationFailed(String(describing: error))
        }
        return Database(writer: pool, url: url)
    }

    public static func inMemory() throws -> Database {
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.label = "c5h.db.inmemory"
        let queue = try DatabaseQueue(configuration: config)
        try Migrator.shared.migrate(queue)
        return Database(writer: queue, url: nil)
    }

    private static func ensureParentDirectory(for url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
    }
}
