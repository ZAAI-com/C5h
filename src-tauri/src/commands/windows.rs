use crate::db::get_pool;
use crate::errors::db_err;
use crate::models::{NewWindow, Window};
use crate::validation::validate_usage_percent;
use serde_json::Value;
use tauri::State;
use crate::db::DbPool;

const DEFAULT_RETENTION_DAYS: i64 = 90;

#[tauri::command]
pub async fn get_windows(
    db: State<'_, DbPool>,
    from: String,
    to: String,
    account_id: Option<i64>,
    limit: Option<i64>,
    offset: Option<i64>,
) -> Result<Vec<Window>, String> {
    let pool = get_pool(&db).await?;
    let limit = limit.unwrap_or(500);
    let offset = offset.unwrap_or(0);

    let rows: Vec<(Value,)> = if let Some(aid) = account_id {
        sqlx::query_as(
            "SELECT json_object(
                'id', id,
                'account_id', account_id,
                'started_at', started_at,
                'ended_at', ended_at,
                'triggered_by', triggered_by,
                'usage_percent', usage_percent,
                'notes', notes,
                'created_at', created_at
            ) FROM windows
            WHERE started_at >= ? AND started_at <= ? AND account_id = ?
            ORDER BY started_at DESC
            LIMIT ? OFFSET ?",
        )
        .bind(&from)
        .bind(&to)
        .bind(aid)
        .bind(limit)
        .bind(offset)
        .fetch_all(&pool)
        .await
        .map_err(db_err("fetch windows"))?
    } else {
        sqlx::query_as(
            "SELECT json_object(
                'id', id,
                'account_id', account_id,
                'started_at', started_at,
                'ended_at', ended_at,
                'triggered_by', triggered_by,
                'usage_percent', usage_percent,
                'notes', notes,
                'created_at', created_at
            ) FROM windows
            WHERE started_at >= ? AND started_at <= ?
            ORDER BY started_at DESC
            LIMIT ? OFFSET ?",
        )
        .bind(&from)
        .bind(&to)
        .bind(limit)
        .bind(offset)
        .fetch_all(&pool)
        .await
        .map_err(db_err("fetch windows"))?
    };

    let windows: Vec<Window> = rows
        .into_iter()
        .filter_map(|(v,)| match serde_json::from_value(v.clone()) {
            Ok(window) => Some(window),
            Err(e) => {
                log::warn!("Skipping malformed window record: {}", e);
                None
            }
        })
        .collect();

    Ok(windows)
}

#[tauri::command]
pub async fn get_current_window(
    db: State<'_, DbPool>,
    account_id: Option<i64>,
) -> Result<Option<Window>, String> {
    let pool = get_pool(&db).await?;

    let row: Option<(Value,)> = if let Some(aid) = account_id {
        sqlx::query_as(
            "SELECT json_object(
                'id', id,
                'account_id', account_id,
                'started_at', started_at,
                'ended_at', ended_at,
                'triggered_by', triggered_by,
                'usage_percent', usage_percent,
                'notes', notes,
                'created_at', created_at
            ) FROM windows
            WHERE ended_at IS NULL AND account_id = ?
            ORDER BY started_at DESC LIMIT 1",
        )
        .bind(aid)
        .fetch_optional(&pool)
        .await
        .map_err(db_err("fetch current window"))?
    } else {
        sqlx::query_as(
            "SELECT json_object(
                'id', id,
                'account_id', account_id,
                'started_at', started_at,
                'ended_at', ended_at,
                'triggered_by', triggered_by,
                'usage_percent', usage_percent,
                'notes', notes,
                'created_at', created_at
            ) FROM windows
            WHERE ended_at IS NULL
            ORDER BY started_at DESC LIMIT 1",
        )
        .fetch_optional(&pool)
        .await
        .map_err(db_err("fetch current window"))?
    };

    Ok(row.and_then(|(v,)| match serde_json::from_value(v.clone()) {
        Ok(window) => Some(window),
        Err(e) => {
            log::warn!("Skipping malformed current window record: {}", e);
            None
        }
    }))
}

#[tauri::command]
pub async fn create_window(
    db: State<'_, DbPool>,
    window: NewWindow,
) -> Result<Window, String> {
    let pool = get_pool(&db).await?;
    let now = chrono::Utc::now().to_rfc3339();

    let result =
        sqlx::query("INSERT INTO windows (account_id, started_at, triggered_by) VALUES (?, ?, ?)")
            .bind(window.account_id)
            .bind(&now)
            .bind(&window.triggered_by)
            .execute(&pool)
            .await
            .map_err(db_err("create window"))?;

    let id = result.last_insert_rowid();

    Ok(Window {
        id: Some(id),
        account_id: window.account_id,
        started_at: now,
        ended_at: None,
        triggered_by: window.triggered_by,
        usage_percent: None,
        notes: None,
        created_at: None,
    })
}

#[tauri::command]
pub async fn end_window(
    db: State<'_, DbPool>,
    id: i64,
    usage_percent: Option<i32>,
) -> Result<(), String> {
    // Validate usage percent if provided
    validate_usage_percent(usage_percent)?;

    let pool = get_pool(&db).await?;
    let now = chrono::Utc::now().to_rfc3339();

    sqlx::query("UPDATE windows SET ended_at = ?, usage_percent = ? WHERE id = ?")
        .bind(&now)
        .bind(usage_percent)
        .bind(id)
        .execute(&pool)
        .await
        .map_err(db_err("end window"))?;

    Ok(())
}

/// Purge completed windows older than the retention period.
/// Only deletes windows that have ended (ended_at IS NOT NULL).
#[tauri::command]
pub async fn purge_old_windows(
    db: State<'_, DbPool>,
    retention_days: Option<i64>,
) -> Result<u64, String> {
    let pool = get_pool(&db).await?;
    let days = retention_days.unwrap_or(DEFAULT_RETENTION_DAYS);
    let cutoff = chrono::Utc::now() - chrono::Duration::days(days);
    let cutoff_str = cutoff.to_rfc3339();

    let result = sqlx::query(
        "DELETE FROM windows WHERE ended_at IS NOT NULL AND started_at < ?",
    )
    .bind(&cutoff_str)
    .execute(&pool)
    .await
    .map_err(db_err("purge old windows"))?;

    Ok(result.rows_affected())
}
