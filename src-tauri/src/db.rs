use chrono::{Local, Utc};
use sqlx::sqlite::SqliteConnectOptions;
#[cfg(test)]
use sqlx::sqlite::SqlitePoolOptions;
use sqlx::SqlitePool;
use std::fs;
use std::path::Path;
use std::process::Command;
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
    let connect_options = SqliteConnectOptions::new()
        .filename(&db_path)
        .create_if_missing(true)
        .foreign_keys(true);

    // Connect to the database
    let pool = SqlitePool::connect_with(connect_options)
        .await
        .map_err(|e| format!("Failed to connect to database: {}", e))?;

    // Run migrations
    run_migrations(&pool).await?;
    run_post_migrations(&pool).await?;

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

async fn run_post_migrations(pool: &SqlitePool) -> Result<(), String> {
    repair_duplicate_active_windows(pool).await?;
    ensure_active_window_unique_index(pool).await?;
    normalize_future_schedules(pool).await?;
    reset_installed_future_schedules(pool).await?;
    Ok(())
}

async fn repair_duplicate_active_windows(pool: &SqlitePool) -> Result<(), String> {
    sqlx::query(
        "WITH ranked AS (
            SELECT
                id,
                account_id,
                started_at,
                ROW_NUMBER() OVER (
                    PARTITION BY account_id
                    ORDER BY started_at DESC, id DESC
                ) AS row_num,
                FIRST_VALUE(started_at) OVER (
                    PARTITION BY account_id
                    ORDER BY started_at DESC, id DESC
                ) AS newest_started_at
            FROM windows
            WHERE ended_at IS NULL
        )
        UPDATE windows
        SET ended_at = (
            SELECT newest_started_at
            FROM ranked
            WHERE ranked.id = windows.id
        )
        WHERE id IN (SELECT id FROM ranked WHERE row_num > 1)",
    )
    .execute(pool)
    .await
    .map_err(|e| format!("Failed to repair duplicate active windows: {}", e))?;

    Ok(())
}

async fn ensure_active_window_unique_index(pool: &SqlitePool) -> Result<(), String> {
    sqlx::query(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_windows_one_active_per_account
         ON windows(account_id)
         WHERE ended_at IS NULL",
    )
    .execute(pool)
    .await
    .map_err(|e| format!("Failed to create active window uniqueness index: {}", e))?;

    Ok(())
}

fn unload_and_remove_plist(plist_path: &str) {
    let unload_result = Command::new("launchctl")
        .args(["unload", plist_path])
        .output();

    if let Err(error) = unload_result {
        log::warn!(
            "Failed to unload migrated schedule plist '{}': {}",
            plist_path,
            error
        );
    }

    if Path::new(plist_path).exists() {
        if let Err(error) = fs::remove_file(plist_path) {
            log::warn!(
                "Failed to remove migrated schedule plist '{}': {}",
                plist_path,
                error
            );
        }
    }
}

async fn normalize_future_schedules(pool: &SqlitePool) -> Result<(), String> {
    let rows: Vec<(i64, String)> = sqlx::query_as(
        "SELECT id, scheduled_at
         FROM scheduled_triggers",
    )
    .fetch_all(pool)
    .await
    .map_err(|e| format!("Failed to fetch schedules for normalization: {}", e))?;

    for (id, scheduled_at) in rows {
        let parsed = chrono::DateTime::parse_from_rfc3339(&scheduled_at)
            .map_err(|e| format!("Invalid stored schedule '{}': {}", scheduled_at, e))?;
        if parsed.with_timezone(&Utc) <= Utc::now() {
            continue;
        }
        let normalized = parsed.with_timezone(&Local).to_rfc3339();

        if normalized != scheduled_at {
            sqlx::query("UPDATE scheduled_triggers SET scheduled_at = ? WHERE id = ?")
                .bind(normalized)
                .bind(id)
                .execute(pool)
                .await
                .map_err(|e| format!("Failed to normalize schedule {}: {}", id, e))?;
        }
    }

    Ok(())
}

async fn reset_installed_future_schedules(pool: &SqlitePool) -> Result<(), String> {
    let rows: Vec<(i64, String, String)> = sqlx::query_as(
        "SELECT id, scheduled_at, plist_path
         FROM scheduled_triggers
         WHERE plist_path IS NOT NULL",
    )
    .fetch_all(pool)
    .await
    .map_err(|e| format!("Failed to fetch installed future schedules: {}", e))?;

    for (id, scheduled_at, plist_path) in rows {
        let parsed = chrono::DateTime::parse_from_rfc3339(&scheduled_at)
            .map_err(|e| format!("Invalid stored schedule '{}': {}", scheduled_at, e))?;
        if parsed.with_timezone(&Utc) <= Utc::now() {
            continue;
        }
        unload_and_remove_plist(&plist_path);
        sqlx::query(
            "UPDATE scheduled_triggers
             SET plist_path = NULL, status = 'pending'
             WHERE id = ?",
        )
        .bind(id)
        .execute(pool)
        .await
        .map_err(|e| format!("Failed to reset installed schedule {}: {}", id, e))?;
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
    let connect_options = SqliteConnectOptions::new()
        .in_memory(true)
        .foreign_keys(true);

    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .min_connections(1)
        .idle_timeout(None)
        .max_lifetime(None)
        .connect_with(connect_options)
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
                    tool_type TEXT NOT NULL DEFAULT 'claude',
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
                    (1, 'Claude Code', 'claude', 'claude', '-p "1+1"', 5, '#6366f1'),
                    (2, 'Codex', 'codex', 'codex', '-p "1+1"', 5, '#10a37f'),
                    (3, 'Gemini', 'gemini', 'gemini', '', 24, '#4285f4');

                -- Normalize legacy tool naming
                UPDATE accounts SET tool_type = 'claude' WHERE tool_type = 'claude_code';

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
