use crate::models::Settings;
use sqlx::SqlitePool;
use tauri::State;
use tauri_plugin_sql::DbInstances;

#[tauri::command]
pub async fn get_settings(db: State<'_, DbInstances>) -> Result<Settings, String> {
    let pool = get_pool(&db).await?;

    let rows: Vec<(String, String)> = sqlx::query_as("SELECT key, value FROM settings")
        .fetch_all(&pool)
        .await
        .map_err(|e| e.to_string())?;

    let mut settings = Settings::default();

    for (key, value) in rows {
        match key.as_str() {
            "launch_at_login" => settings.launch_at_login = value == "true",
            "show_in_menu_bar" => settings.show_in_menu_bar = value == "true",
            "theme" => settings.theme = value,
            "notifications_enabled" => settings.notifications_enabled = value == "true",
            "notify_ending_soon" => settings.notify_ending_soon = value == "true",
            "notify_trigger_status" => settings.notify_trigger_status = value == "true",
            "notify_weekly_summary" => settings.notify_weekly_summary = value == "true",
            "poll_interval_minutes" => {
                settings.poll_interval_minutes = value.parse().unwrap_or(15)
            }
            _ => {}
        }
    }

    Ok(settings)
}

#[tauri::command]
pub async fn save_settings(
    db: State<'_, DbInstances>,
    settings: Settings,
) -> Result<(), String> {
    let pool = get_pool(&db).await?;

    let pairs = vec![
        ("launch_at_login", settings.launch_at_login.to_string()),
        ("show_in_menu_bar", settings.show_in_menu_bar.to_string()),
        ("theme", settings.theme),
        (
            "notifications_enabled",
            settings.notifications_enabled.to_string(),
        ),
        ("notify_ending_soon", settings.notify_ending_soon.to_string()),
        (
            "notify_trigger_status",
            settings.notify_trigger_status.to_string(),
        ),
        (
            "notify_weekly_summary",
            settings.notify_weekly_summary.to_string(),
        ),
        (
            "poll_interval_minutes",
            settings.poll_interval_minutes.to_string(),
        ),
    ];

    for (key, value) in pairs {
        sqlx::query("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)")
            .bind(key)
            .bind(value)
            .execute(&pool)
            .await
            .map_err(|e| e.to_string())?;
    }

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
