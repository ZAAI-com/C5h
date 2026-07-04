import Foundation
import GRDB
import C5hCore

public final class Database: @unchecked Sendable {
    public let writer: any DatabaseWriter
    public let url: URL?
    /// Retained so the installed change broadcaster lives as long as the database.
    private let changeBroadcaster: DatabaseChangeBroadcaster?

    /// Darwin notification posted after a committed transaction that touched one of
    /// `changeObservedTables`. Observed cross-process so the UI knows when to
    /// re-read (see `DatabaseChangeMonitor` in the app target).
    public static let changeNotificationName = "com.zaai.c5h.databaseDidChange"

    /// Tables whose changes should wake observers. Deliberately excluded:
    /// `helper_heartbeats` (written every 30s) and `command_runs` (written on
    /// every probe attempt, including failures; observing it would let a failing
    /// usage probe re-signal its own retry into a CLI-spawn loop).
    public static let changeObservedTables: Set<String> = [
        "planned_windows",
        "actual_windows_5h",
        "actual_windows_7d",
        "usage_snapshots",
        "scheduled_prompts",
    ]

    private init(
        writer: any DatabaseWriter,
        url: URL?,
        changeBroadcaster: DatabaseChangeBroadcaster?
    ) {
        self.writer = writer
        self.url = url
        self.changeBroadcaster = changeBroadcaster
    }

    /// `notificationName` exists for tests, which need a unique name so a
    /// concurrently running C5h app cannot satisfy (or steal) their listener.
    public static func open(
        at url: URL,
        notificationName: String = Database.changeNotificationName
    ) throws -> Database {
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
        let broadcaster = DatabaseChangeBroadcaster(
            observedTables: changeObservedTables
        ) {
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName(notificationName as CFString),
                nil,
                nil,
                true
            )
        }
        pool.add(transactionObserver: broadcaster, extent: .databaseLifetime)
        return Database(writer: pool, url: url, changeBroadcaster: broadcaster)
    }

    public static func inMemory() throws -> Database {
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.label = "c5h.db.inmemory"
        let queue = try DatabaseQueue(configuration: config)
        try Migrator.shared.migrate(queue)
        return Database(writer: queue, url: nil, changeBroadcaster: nil)
    }

    private static func ensureParentDirectory(for url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
    }
}
