import Foundation
import GRDB
import C5hCore

enum Migrator {
    static let shared: DatabaseMigrator = {
        var migrator = DatabaseMigrator()
        Migrations.register(into: &migrator)
        return migrator
    }()
}
