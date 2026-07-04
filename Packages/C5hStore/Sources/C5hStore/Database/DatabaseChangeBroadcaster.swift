import GRDB

/// Fires `onRelevantCommit` after any transaction that modified one of
/// `observedTables`. Installed once in `Database.open(at:)` so that every process
/// opening the database (the app and the background helper) broadcasts on its own
/// writes, letting other processes learn when to re-read.
///
/// Tables outside `observedTables` are never observed, so high-frequency
/// bookkeeping writes (for example `helper_heartbeats`) do not trigger a signal.
final class DatabaseChangeBroadcaster: TransactionObserver {
    private let observedTables: Set<String>
    private let onRelevantCommit: @Sendable () -> Void
    private var pendingRelevantChange = false

    init(
        observedTables: Set<String>,
        onRelevantCommit: @escaping @Sendable () -> Void
    ) {
        self.observedTables = observedTables
        self.onRelevantCommit = onRelevantCommit
    }

    func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool {
        observedTables.contains(eventKind.tableName)
    }

    func databaseDidChange(with event: DatabaseEvent) {
        // Only reached for events on observed tables (see observes(eventsOfKind:)).
        pendingRelevantChange = true
    }

    func databaseDidCommit(_ db: GRDB.Database) {
        guard pendingRelevantChange else { return }
        pendingRelevantChange = false
        onRelevantCommit()
    }

    func databaseDidRollback(_ db: GRDB.Database) {
        pendingRelevantChange = false
    }
}
