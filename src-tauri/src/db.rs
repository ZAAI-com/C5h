use tauri_plugin_sql::{Migration, MigrationKind};

pub fn get_migrations() -> Vec<Migration> {
    vec![
        Migration {
            version: 1,
            description: "create_initial_tables",
            sql: r#"
                -- Accounts table for multi-tool/multi-account support
                CREATE TABLE IF NOT EXISTS accounts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    tool_type TEXT NOT NULL DEFAULT 'claude_code',
                    cli_command TEXT NOT NULL DEFAULT 'claude',
                    cli_args TEXT DEFAULT '-p "1+1"',
                    window_duration_hours INTEGER NOT NULL DEFAULT 5,
                    color TEXT NOT NULL DEFAULT '#6366f1',
                    enabled INTEGER NOT NULL DEFAULT 1,
                    created_at TEXT NOT NULL DEFAULT (datetime('now'))
                );

                -- Windows table for tracking usage windows
                CREATE TABLE IF NOT EXISTS windows (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    account_id INTEGER NOT NULL,
                    started_at TEXT NOT NULL,
                    ended_at TEXT,
                    triggered_by TEXT NOT NULL DEFAULT 'detected',
                    usage_percent INTEGER,
                    notes TEXT,
                    created_at TEXT NOT NULL DEFAULT (datetime('now')),
                    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
                );

                -- Settings table for key-value configuration
                CREATE TABLE IF NOT EXISTS settings (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );

                -- Scheduled triggers table (one-time schedules)
                CREATE TABLE IF NOT EXISTS scheduled_triggers (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    account_id INTEGER NOT NULL,
                    scheduled_at TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'pending',
                    plist_path TEXT,
                    created_at TEXT NOT NULL DEFAULT (datetime('now')),
                    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
                );

                -- Insert default accounts
                INSERT OR IGNORE INTO accounts (id, name, tool_type, cli_command, cli_args, window_duration_hours, color) VALUES
                    (1, 'Claude Code', 'claude_code', 'claude', '-p "1+1"', 5, '#6366f1'),
                    (2, 'Codex', 'codex', 'codex', '-p "1+1"', 5, '#10a37f'),
                    (3, 'Gemini', 'gemini', 'gemini', '', 24, '#4285f4');

                -- Insert default settings
                INSERT OR IGNORE INTO settings (key, value) VALUES
                    ('launch_at_login', 'true'),
                    ('show_in_menu_bar', 'true'),
                    ('theme', 'system'),
                    ('notifications_enabled', 'true'),
                    ('notify_ending_soon', 'true'),
                    ('notify_trigger_status', 'true'),
                    ('notify_weekly_summary', 'true'),
                    ('poll_interval_minutes', '15');

                -- Create indexes for performance
                CREATE INDEX IF NOT EXISTS idx_windows_account_id ON windows(account_id);
                CREATE INDEX IF NOT EXISTS idx_windows_started_at ON windows(started_at);
                CREATE INDEX IF NOT EXISTS idx_scheduled_triggers_account_id ON scheduled_triggers(account_id);
                CREATE INDEX IF NOT EXISTS idx_scheduled_triggers_status ON scheduled_triggers(status);
            "#,
            kind: MigrationKind::Up,
        },
    ]
}
