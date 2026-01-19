use crate::models::{NewWindow, Window};
use serde_json::Value;
use sqlx::SqlitePool;
use tauri::State;
use tauri_plugin_sql::DbInstances;

#[tauri::command]
pub async fn get_windows(
    db: State<'_, DbInstances>,
    from: String,
    to: String,
    account_id: Option<i64>,
) -> Result<Vec<Window>, String> {
    let pool = get_pool(&db).await?;

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
            ORDER BY started_at DESC"
        )
        .bind(&from)
        .bind(&to)
        .bind(aid)
        .fetch_all(&pool)
        .await
        .map_err(|e| e.to_string())?
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
            ORDER BY started_at DESC"
        )
        .bind(&from)
        .bind(&to)
        .fetch_all(&pool)
        .await
        .map_err(|e| e.to_string())?
    };

    let windows: Vec<Window> = rows
        .into_iter()
        .filter_map(|(v,)| serde_json::from_value(v).ok())
        .collect();

    Ok(windows)
}

#[tauri::command]
pub async fn get_current_window(
    db: State<'_, DbInstances>,
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
            ORDER BY started_at DESC LIMIT 1"
        )
        .bind(aid)
        .fetch_optional(&pool)
        .await
        .map_err(|e| e.to_string())?
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
            ORDER BY started_at DESC LIMIT 1"
        )
        .fetch_optional(&pool)
        .await
        .map_err(|e| e.to_string())?
    };

    Ok(row.and_then(|(v,)| serde_json::from_value(v).ok()))
}

#[tauri::command]
pub async fn create_window(
    db: State<'_, DbInstances>,
    window: NewWindow,
) -> Result<Window, String> {
    let pool = get_pool(&db).await?;
    let now = chrono::Utc::now().to_rfc3339();

    let result = sqlx::query(
        "INSERT INTO windows (account_id, started_at, triggered_by) VALUES (?, ?, ?)"
    )
    .bind(window.account_id)
    .bind(&now)
    .bind(&window.triggered_by)
    .execute(&pool)
    .await
    .map_err(|e| e.to_string())?;

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
    db: State<'_, DbInstances>,
    id: i64,
    usage_percent: Option<i32>,
) -> Result<(), String> {
    let pool = get_pool(&db).await?;
    let now = chrono::Utc::now().to_rfc3339();

    sqlx::query("UPDATE windows SET ended_at = ?, usage_percent = ? WHERE id = ?")
        .bind(&now)
        .bind(usage_percent)
        .bind(id)
        .execute(&pool)
        .await
        .map_err(|e| e.to_string())?;

    Ok(())
}

async fn get_pool(db: &State<'_, DbInstances>) -> Result<SqlitePool, String> {
    let instances = db.0.read().await;
    let db_pool = instances
        .get("sqlite:c5h.db")
        .ok_or_else(|| "Database not found".to_string())?;

    match db_pool {
        tauri_plugin_sql::DbPool::Sqlite(pool) => Ok(pool.clone()),
        #[allow(unreachable_patterns)]
        _ => Err("Expected SQLite database".to_string()),
    }
}
