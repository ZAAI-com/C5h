use crate::db::get_pool;
use crate::models::{NewWindow, Window};
use crate::validation::validate_usage_percent;
use serde_json::Value;
use tauri::State;
use crate::db::DbPool;

#[tauri::command]
pub async fn get_windows(
    db: State<'_, DbPool>,
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
            ORDER BY started_at DESC",
        )
        .bind(&from)
        .bind(&to)
        .bind(aid)
        .fetch_all(&pool)
        .await
        .map_err(|e| {
            eprintln!("Database error in get_windows: {:?}", e);
            "Failed to fetch windows".to_string()
        })?
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
            ORDER BY started_at DESC",
        )
        .bind(&from)
        .bind(&to)
        .fetch_all(&pool)
        .await
        .map_err(|e| {
            eprintln!("Database error in get_windows: {:?}", e);
            "Failed to fetch windows".to_string()
        })?
    };

    let windows: Vec<Window> = rows
        .into_iter()
        .filter_map(|(v,)| match serde_json::from_value(v.clone()) {
            Ok(window) => Some(window),
            Err(e) => {
                eprintln!("Failed to deserialize window: {:?}, data: {:?}", e, v);
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
        .map_err(|e| {
            eprintln!("Database error in get_current_window: {:?}", e);
            "Failed to fetch current window".to_string()
        })?
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
        .map_err(|e| {
            eprintln!("Database error in get_current_window: {:?}", e);
            "Failed to fetch current window".to_string()
        })?
    };

    Ok(row.and_then(|(v,)| match serde_json::from_value(v.clone()) {
        Ok(window) => Some(window),
        Err(e) => {
            eprintln!("Failed to deserialize current window: {:?}, data: {:?}", e, v);
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
            .map_err(|e| {
                eprintln!("Database error in create_window: {:?}", e);
                "Failed to create window".to_string()
            })?;

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
        .map_err(|e| {
            eprintln!("Database error in end_window: {:?}", e);
            "Failed to end window".to_string()
        })?;

    Ok(())
}
