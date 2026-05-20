import Foundation
import GRDB
import C5hCore

enum Migrations {
    static func register(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_initial_schema") { db in
            try db.create(table: "providers") { t in
                t.column("id", .text).primaryKey()
                t.column("display_name", .text).notNull()
                t.column("cli_path", .text)
                t.column("enabled", .integer).notNull()
                t.column("brand_color", .text).notNull()
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }

            try db.create(table: "planned_windows") { t in
                t.column("id", .text).primaryKey()
                t.column("provider_id", .text).notNull().references("providers")
                t.column("start_at", .text).notNull()
                t.column("duration_seconds", .integer).notNull()
                t.column("prompt_template_id", .text)
                t.column("project_path", .text)
                t.column("status", .text).notNull()
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
            try db.create(
                index: "idx_planned_windows_provider_start",
                on: "planned_windows",
                columns: ["provider_id", "start_at"]
            )

            try db.create(table: "actual_windows") { t in
                t.column("id", .text).primaryKey()
                t.column("provider_id", .text).notNull().references("providers")
                t.column("start_at", .text).notNull()
                t.column("duration_seconds", .integer).notNull()
                t.column("source", .text).notNull()
                t.column("confidence", .text).notNull()
                t.column("command_run_id", .text)
                t.column("usage_start_snapshot_id", .text)
                t.column("usage_end_snapshot_id", .text)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
            try db.create(
                index: "idx_actual_windows_provider_start",
                on: "actual_windows",
                columns: ["provider_id", "start_at"]
            )

            try db.create(table: "scheduled_prompts") { t in
                t.column("id", .text).primaryKey()
                t.column("provider_id", .text).notNull().references("providers")
                t.column("planned_window_id", .text).references("planned_windows")
                t.column("prompt", .text).notNull()
                t.column("project_path", .text)
                t.column("run_at", .text).notNull()
                t.column("status", .text).notNull()
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("last_error", .text)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
            try db.create(
                index: "idx_scheduled_prompts_status_run_at",
                on: "scheduled_prompts",
                columns: ["status", "run_at"]
            )

            try db.create(table: "command_runs") { t in
                t.column("id", .text).primaryKey()
                t.column("provider_id", .text).notNull().references("providers")
                t.column("run_type", .text).notNull()
                t.column("command", .text).notNull()
                t.column("arguments_json", .text).notNull()
                t.column("cwd", .text)
                t.column("started_at", .text).notNull()
                t.column("ended_at", .text)
                t.column("exit_code", .integer)
                t.column("status", .text).notNull()
                t.column("stdout_path", .text)
                t.column("stderr_path", .text)
                t.column("parsed_events_json", .text)
                t.column("error", .text)
                t.column("tool_version", .text)
            }
            try db.create(
                index: "idx_command_runs_provider_started",
                on: "command_runs",
                columns: ["provider_id", "started_at"]
            )
            try db.create(
                index: "idx_command_runs_status_started",
                on: "command_runs",
                columns: ["status", "started_at"]
            )

            try db.create(table: "usage_snapshots") { t in
                t.column("id", .text).primaryKey()
                t.column("provider_id", .text).notNull().references("providers")
                t.column("captured_at", .text).notNull()
                t.column("raw_json", .text).notNull()
                t.column("normalized_json", .text).notNull()
            }
            try db.create(
                index: "idx_usage_snapshots_provider_captured",
                on: "usage_snapshots",
                columns: ["provider_id", "captured_at"]
            )

            try db.create(table: "prompt_templates") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("provider_id", .text).references("providers")
                t.column("body", .text).notNull()
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }

            try db.create(table: "app_settings") { t in
                t.column("key", .text).primaryKey()
                t.column("value_json", .text).notNull()
                t.column("updated_at", .text).notNull()
            }

            try db.create(table: "helper_heartbeats") { t in
                t.column("id", .text).primaryKey()
                t.column("helper_version", .text).notNull()
                t.column("started_at", .text).notNull()
                t.column("last_seen_at", .text).notNull()
                t.column("pid", .integer)
            }
        }

        migrator.registerMigration("v2_command_run_owner") { db in
            try db.alter(table: "command_runs") { t in
                t.add(column: "owner_pid", .integer)
            }
        }
    }
}
