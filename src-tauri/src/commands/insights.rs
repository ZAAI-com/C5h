//! Tauri command surface for the insights feature.

use crate::db::{get_pool, DbPool};
use crate::services::insights::{compute_insights, dismiss, Insight};
use tauri::State;

#[tauri::command]
pub async fn get_insights(db: State<'_, DbPool>) -> Result<Vec<Insight>, String> {
    let pool = get_pool(&db).await?;
    compute_insights(&pool).await
}

#[tauri::command]
pub async fn dismiss_insight(
    db: State<'_, DbPool>,
    insight_key: String,
) -> Result<(), String> {
    let pool = get_pool(&db).await?;
    dismiss(&pool, &insight_key).await
}
