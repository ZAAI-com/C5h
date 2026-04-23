use sqlx::{migrate::MigrateDatabase, Sqlite, SqlitePool};
#[cfg(test)]
use sqlx::sqlite::SqlitePoolOptions;
use std::sync::Arc;
use tauri::State;
use tokio::sync::RwLock;

/// Database pool wrapper for Tauri state management
pub struct DbPool(pub Arc<RwLock<Option<SqlitePool>>>);

impl Default for DbPool {
    fn default() -> Self {
        Self(Arc::new(RwLock::new(None)))
    }
}

/// Get the SQLite connection pool from Tauri's managed state.
///
/// This is a shared helper function used by all command modules to access the database.
pub async fn get_pool(db: &State<'_, DbPool>) -> Result<SqlitePool, String> {
    let pool_guard = db.0.read().await;
    pool_guard
        .clone()
        .ok_or_else(|| "Database connection not initialized. Please restart the application.".to_string())
}

/// Initialize the database pool and run migrations
pub async fn init_db(app_data_dir: std::path::PathBuf) -> Result<SqlitePool, String> {
    // Ensure the data directory exists
    std::fs::create_dir_all(&app_data_dir)
        .map_err(|e| format!("Failed to create data directory: {}", e))?;

    let db_path = app_data_dir.join("c5h.db");
    let db_url = format!("sqlite:{}", db_path.display());

    // Create database if it doesn't exist
    if !Sqlite::database_exists(&db_url).await.unwrap_or(false) {
        Sqlite::create_database(&db_url)
            .await
            .map_err(|e| format!("Failed to create database: {}", e))?;
    }

    // Connect to the database
    let pool = SqlitePool::connect(&db_url)
        .await
        .map_err(|e| format!("Failed to connect to database: {}", e))?;

    // Run migrations
    run_migrations(&pool).await?;

    Ok(pool)
}

/// Run database migrations.
///
/// `raw_sql().execute()` only consumes the first statement's result on SQLite,
/// so we split on `;` and execute each non-empty statement individually.
async fn run_migrations(pool: &SqlitePool) -> Result<(), String> {
    let migration_sql = get_migration_sql();

    for statement in migration_sql.split(';') {
        let trimmed = statement.trim();
        if trimmed.is_empty() {
            continue;
        }
        sqlx::query(trimmed)
            .execute(pool)
            .await
            .map_err(|e| format!("Failed to run migration statement '{}': {}", trimmed, e))?;
    }

    Ok(())
}

/// Initialize an in-memory SQLite pool with migrations applied.
///
/// Each `sqlite::memory:` connection gets its own private database, so we
/// pin the pool to exactly one connection (kept alive forever) to ensure
/// migrations and subsequent queries see the same DB.
#[cfg(test)]
pub async fn init_test_pool() -> SqlitePool {
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .min_connections(1)
        .idle_timeout(None)
        .max_lifetime(None)
        .connect("sqlite::memory:")
        .await
        .expect("Failed to connect to in-memory SQLite");

    run_migrations(&pool)
        .await
        .expect("Failed to run migrations on test pool");

    pool
}

/// Get the migration SQL
fn get_migration_sql() -> String {
    r#"
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
            "#.to_string()
}
