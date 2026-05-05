use crate::db::get_pool;
use crate::errors::db_err;
use crate::models::{NewWindow, Window};
use crate::validation::validate_usage_percent;
use serde_json::Value;
use sqlx::SqlitePool;
use tauri::State;
use crate::db::DbPool;

const DEFAULT_RETENTION_DAYS: i64 = 90;

pub async fn get_windows_impl(
    pool: &SqlitePool,
    from: String,
    to: String,
    account_id: Option<i64>,
    limit: Option<i64>,
    offset: Option<i64>,
) -> Result<Vec<Window>, String> {
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
        .fetch_all(pool)
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
        .fetch_all(pool)
        .await
        .map_err(db_err("fetch windows"))?
    };

    rows
        .into_iter()
        .map(|(v,)| serde_json::from_value(v).map_err(|e| e.to_string()))
        .collect()
}

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
    get_windows_impl(&pool, from, to, account_id, limit, offset).await
}

pub async fn get_current_window_impl(
    pool: &SqlitePool,
    account_id: Option<i64>,
) -> Result<Option<Window>, String> {
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
        .fetch_optional(pool)
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
        .fetch_optional(pool)
        .await
        .map_err(db_err("fetch current window"))?
    };

    row.map(|(v,)| serde_json::from_value(v).map_err(|e| e.to_string()))
        .transpose()
}

#[tauri::command]
pub async fn get_current_window(
    db: State<'_, DbPool>,
    account_id: Option<i64>,
) -> Result<Option<Window>, String> {
    let pool = get_pool(&db).await?;
    get_current_window_impl(&pool, account_id).await
}

pub async fn create_window_impl(
    pool: &SqlitePool,
    window: NewWindow,
) -> Result<Window, String> {
    if let Some(existing_window) = get_current_window_impl(pool, Some(window.account_id)).await? {
        return Ok(existing_window);
    }

    let now = chrono::Utc::now().to_rfc3339();

    let result =
        sqlx::query("INSERT INTO windows (account_id, started_at, triggered_by) VALUES (?, ?, ?)")
            .bind(window.account_id)
            .bind(&now)
            .bind(&window.triggered_by)
            .execute(pool)
            .await;

    let result = match result {
        Ok(result) => result,
        Err(error)
            if error
                .as_database_error()
                .map(|database_error| database_error.is_unique_violation())
                .unwrap_or(false) =>
        {
            return get_current_window_impl(pool, Some(window.account_id))
                .await?
                .ok_or_else(|| "Failed to recover active window after duplicate start".to_string());
        }
        Err(error) => return Err(db_err("create window")(error)),
    };

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
pub async fn create_window(
    db: State<'_, DbPool>,
    window: NewWindow,
) -> Result<Window, String> {
    let pool = get_pool(&db).await?;
    create_window_impl(&pool, window).await
}

pub async fn end_window_impl(
    pool: &SqlitePool,
    id: i64,
    usage_percent: Option<i32>,
) -> Result<(), String> {
    validate_usage_percent(usage_percent)?;

    let now = chrono::Utc::now().to_rfc3339();

    sqlx::query("UPDATE windows SET ended_at = ?, usage_percent = ? WHERE id = ?")
        .bind(&now)
        .bind(usage_percent)
        .bind(id)
        .execute(pool)
        .await
        .map_err(db_err("end window"))?;

    Ok(())
}

#[tauri::command]
pub async fn end_window(
    db: State<'_, DbPool>,
    id: i64,
    usage_percent: Option<i32>,
) -> Result<(), String> {
    let pool = get_pool(&db).await?;
    end_window_impl(&pool, id, usage_percent).await
}

pub async fn purge_old_windows_impl(
    pool: &SqlitePool,
    retention_days: Option<i64>,
) -> Result<u64, String> {
    let days = retention_days.unwrap_or(DEFAULT_RETENTION_DAYS);
    let cutoff = chrono::Utc::now() - chrono::Duration::days(days);
    let cutoff_str = cutoff.to_rfc3339();

    let result = sqlx::query(
        "DELETE FROM windows WHERE ended_at IS NOT NULL AND started_at < ?",
    )
    .bind(&cutoff_str)
    .execute(pool)
    .await
    .map_err(db_err("purge old windows"))?;

    Ok(result.rows_affected())
}

/// Purge completed windows older than the retention period.
/// Only deletes windows that have ended (ended_at IS NOT NULL).
#[tauri::command]
pub async fn purge_old_windows(
    db: State<'_, DbPool>,
    retention_days: Option<i64>,
) -> Result<u64, String> {
    let pool = get_pool(&db).await?;
    purge_old_windows_impl(&pool, retention_days).await
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::init_test_pool;

    async fn seed_window(pool: &SqlitePool, account_id: i64, started_at: &str, ended_at: Option<&str>) -> i64 {
        let result = sqlx::query(
            "INSERT INTO windows (account_id, started_at, ended_at, triggered_by) VALUES (?, ?, ?, 'manual')",
        )
        .bind(account_id)
        .bind(started_at)
        .bind(ended_at)
        .execute(pool)
        .await
        .unwrap();
        result.last_insert_rowid()
    }

    #[tokio::test]
    async fn create_window_sets_started_at_now() {
        let pool = init_test_pool().await;
        let w = create_window_impl(&pool, NewWindow {
            account_id: 1,
            triggered_by: "manual".to_string(),
        })
        .await
        .unwrap();
        assert!(w.id.is_some());
        assert_eq!(w.account_id, 1);
        assert_eq!(w.triggered_by, "manual");
        assert!(w.ended_at.is_none());
        // started_at should parse as RFC3339
        chrono::DateTime::parse_from_rfc3339(&w.started_at).unwrap();
    }

    #[tokio::test]
    async fn create_window_is_idempotent_per_account() {
        let pool = init_test_pool().await;

        let first = create_window_impl(
            &pool,
            NewWindow {
                account_id: 1,
                triggered_by: "manual".to_string(),
            },
        )
        .await
        .unwrap();

        let second = create_window_impl(
            &pool,
            NewWindow {
                account_id: 1,
                triggered_by: "auto-detected".to_string(),
            },
        )
        .await
        .unwrap();

        assert_eq!(first.id, second.id);

        let active_rows: Vec<(i64,)> =
            sqlx::query_as("SELECT id FROM windows WHERE account_id = 1 AND ended_at IS NULL")
                .fetch_all(&pool)
                .await
                .unwrap();
        assert_eq!(active_rows.len(), 1);
    }

    #[tokio::test]
    async fn end_window_sets_ended_at_and_percent() {
        let pool = init_test_pool().await;
        let w = create_window_impl(&pool, NewWindow {
            account_id: 1,
            triggered_by: "manual".to_string(),
        })
        .await
        .unwrap();

        end_window_impl(&pool, w.id.unwrap(), Some(75)).await.unwrap();

        let current = get_current_window_impl(&pool, Some(1)).await.unwrap();
        assert!(current.is_none(), "window should no longer be 'current' after ending");
    }

    #[tokio::test]
    async fn end_window_rejects_invalid_percent() {
        let pool = init_test_pool().await;
        let err = end_window_impl(&pool, 1, Some(150)).await.unwrap_err();
        assert!(err.contains("0 and 100"), "got: {err}");
    }

    #[tokio::test]
    async fn get_windows_filters_by_date_range() {
        let pool = init_test_pool().await;
        seed_window(&pool, 1, "2026-01-01T10:00:00Z", Some("2026-01-01T15:00:00Z")).await;
        seed_window(&pool, 1, "2026-02-01T10:00:00Z", Some("2026-02-01T15:00:00Z")).await;
        seed_window(&pool, 1, "2026-03-01T10:00:00Z", Some("2026-03-01T15:00:00Z")).await;

        let jan_only = get_windows_impl(
            &pool,
            "2026-01-01T00:00:00Z".to_string(),
            "2026-01-31T23:59:59Z".to_string(),
            None,
            None,
            None,
        )
        .await
        .unwrap();
        assert_eq!(jan_only.len(), 1);
    }

    #[tokio::test]
    async fn get_windows_filters_by_account_id() {
        let pool = init_test_pool().await;
        seed_window(&pool, 1, "2026-01-01T10:00:00Z", None).await;
        seed_window(&pool, 2, "2026-01-01T11:00:00Z", None).await;

        let acct1 = get_windows_impl(
            &pool,
            "2026-01-01T00:00:00Z".to_string(),
            "2026-12-31T23:59:59Z".to_string(),
            Some(1),
            None,
            None,
        )
        .await
        .unwrap();
        assert_eq!(acct1.len(), 1);
        assert_eq!(acct1[0].account_id, 1);
    }

    #[tokio::test]
    async fn get_windows_pagination_works() {
        let pool = init_test_pool().await;
        for i in 0..10 {
            // Pagination test uses historical (ended) windows. The
            // partial unique index on windows(account_id) WHERE ended_at IS NULL
            // forbids more than one active window per account.
            let started = format!("2026-01-{:02}T10:00:00Z", i + 1);
            let ended = format!("2026-01-{:02}T11:00:00Z", i + 1);
            seed_window(&pool, 1, &started, Some(&ended)).await;
        }

        let page1 = get_windows_impl(
            &pool,
            "2026-01-01T00:00:00Z".to_string(),
            "2026-12-31T23:59:59Z".to_string(),
            None,
            Some(3),
            Some(0),
        )
        .await
        .unwrap();
        let page2 = get_windows_impl(
            &pool,
            "2026-01-01T00:00:00Z".to_string(),
            "2026-12-31T23:59:59Z".to_string(),
            None,
            Some(3),
            Some(3),
        )
        .await
        .unwrap();
        assert_eq!(page1.len(), 3);
        assert_eq!(page2.len(), 3);
        // ORDER BY started_at DESC, so page1 has later dates
        assert!(page1[0].started_at > page2[0].started_at);
    }

    #[tokio::test]
    async fn get_current_window_returns_unended() {
        let pool = init_test_pool().await;
        seed_window(&pool, 1, "2026-01-01T10:00:00Z", Some("2026-01-01T15:00:00Z")).await;
        let id = seed_window(&pool, 1, "2026-02-01T10:00:00Z", None).await;

        let current = get_current_window_impl(&pool, Some(1)).await.unwrap();
        assert_eq!(current.unwrap().id, Some(id));
    }

    #[tokio::test]
    async fn purge_old_windows_only_deletes_ended_past_cutoff() {
        let pool = init_test_pool().await;
        // Old + ended → should delete
        let old_ended = chrono::Utc::now() - chrono::Duration::days(100);
        seed_window(&pool, 1, &old_ended.to_rfc3339(), Some(&old_ended.to_rfc3339())).await;
        // Old + still active → keep
        seed_window(&pool, 1, &old_ended.to_rfc3339(), None).await;
        // Recent + ended → keep
        let recent = chrono::Utc::now() - chrono::Duration::days(10);
        seed_window(&pool, 1, &recent.to_rfc3339(), Some(&recent.to_rfc3339())).await;

        let deleted = purge_old_windows_impl(&pool, Some(90)).await.unwrap();
        assert_eq!(deleted, 1);

        let remaining = get_windows_impl(
            &pool,
            "2020-01-01T00:00:00Z".to_string(),
            "2030-12-31T23:59:59Z".to_string(),
            None,
            None,
            None,
        )
        .await
        .unwrap();
        assert_eq!(remaining.len(), 2);
    }
}
