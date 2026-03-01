use crate::db::get_pool;
use crate::models::Settings;
use crate::validation::validate_poll_interval;
use tauri::State;
use crate::db::DbPool;

#[tauri::command]
pub async fn get_settings(db: State<'_, DbPool>) -> Result<Settings, String> {
    let pool = get_pool(&db).await?;

    let rows: Vec<(String, String)> = sqlx::query_as("SELECT key, value FROM settings")
        .fetch_all(&pool)
        .await
        .map_err(|e| {
            eprintln!("Database error in get_settings: {:?}", e);
            "Failed to fetch settings".to_string()
        })?;

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
                match value.parse::<i32>() {
                    Ok(val) if val >= 1 && val <= 60 => {
                        settings.poll_interval_minutes = val;
                    }
                    Ok(val) => {
                        eprintln!(
                            "Warning: Invalid poll_interval_minutes value {} (must be 1-60), using default",
                            val
                        );
                        settings.poll_interval_minutes = 15;
                    }
                    Err(e) => {
                        eprintln!(
                            "Warning: Failed to parse poll_interval_minutes '{}': {}, using default",
                            value, e
                        );
                        settings.poll_interval_minutes = 15;
                    }
                }
            }
            _ => {}
        }
    }

    Ok(settings)
}

#[tauri::command]
pub async fn save_settings(db: State<'_, DbPool>, settings: Settings) -> Result<(), String> {
    // Validate poll interval
    validate_poll_interval(settings.poll_interval_minutes)?;

    let pool = get_pool(&db).await?;

    let pairs = vec![
        ("launch_at_login", settings.launch_at_login.to_string()),
        ("show_in_menu_bar", settings.show_in_menu_bar.to_string()),
        ("theme", settings.theme),
        (
            "notifications_enabled",
            settings.notifications_enabled.to_string(),
        ),
        (
            "notify_ending_soon",
            settings.notify_ending_soon.to_string(),
        ),
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
            .map_err(|e| {
                eprintln!("Database error in save_settings for key '{}': {:?}", key, e);
                "Failed to save settings".to_string()
            })?;
    }

    Ok(())
}
