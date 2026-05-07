//! Onboarding completion tracking.
//!
//! Lives in the `settings` k/v table under `onboarding_completed_at`. Stored
//! as an RFC3339 timestamp once finished; empty string until then. Kept out
//! of the strongly-typed `Settings` struct because it's an internal flag,
//! not a user-facing preference.

use crate::db::{get_pool, DbPool};
use crate::errors::db_err;
use tauri::State;

#[tauri::command]
pub async fn is_onboarding_completed(db: State<'_, DbPool>) -> Result<bool, String> {
    let pool = get_pool(&db).await?;
    let row: Option<(String,)> =
        sqlx::query_as("SELECT value FROM settings WHERE key = 'onboarding_completed_at'")
            .fetch_optional(&pool)
            .await
            .map_err(db_err("read onboarding flag"))?;
    Ok(row.map(|(v,)| !v.is_empty()).unwrap_or(false))
}

#[tauri::command]
pub async fn mark_onboarding_completed(db: State<'_, DbPool>) -> Result<(), String> {
    let pool = get_pool(&db).await?;
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query("INSERT OR REPLACE INTO settings (key, value) VALUES ('onboarding_completed_at', ?)")
        .bind(&now)
        .execute(&pool)
        .await
        .map_err(db_err("mark onboarding completed"))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::init_test_pool;

    #[tokio::test]
    async fn flag_starts_false_after_init() {
        let pool = init_test_pool().await;
        let row: Option<(String,)> =
            sqlx::query_as("SELECT value FROM settings WHERE key = 'onboarding_completed_at'")
                .fetch_optional(&pool)
                .await
                .unwrap();
        // Either no row or empty string == not completed.
        assert!(row.map(|(v,)| v.is_empty()).unwrap_or(true));
    }

    #[tokio::test]
    async fn marking_completed_writes_timestamp() {
        let pool = init_test_pool().await;

        // Direct DB write to mirror what the command does, since we can't
        // easily build a real Tauri State<DbPool> in unit tests.
        let now = chrono::Utc::now().to_rfc3339();
        sqlx::query(
            "INSERT OR REPLACE INTO settings (key, value)
             VALUES ('onboarding_completed_at', ?)",
        )
        .bind(&now)
        .execute(&pool)
        .await
        .unwrap();

        let (value,): (String,) =
            sqlx::query_as("SELECT value FROM settings WHERE key = 'onboarding_completed_at'")
                .fetch_one(&pool)
                .await
                .unwrap();
        assert!(!value.is_empty());
        chrono::DateTime::parse_from_rfc3339(&value).unwrap();
    }
}
