use crate::db::get_pool;
use crate::errors::db_err;
use crate::models::Settings;
use crate::validation::validate_poll_interval;
use sqlx::SqlitePool;
use tauri::State;
use crate::db::DbPool;

pub async fn get_settings_impl(pool: &SqlitePool) -> Result<Settings, String> {
    let rows: Vec<(String, String)> = sqlx::query_as("SELECT key, value FROM settings")
        .fetch_all(pool)
        .await
        .map_err(db_err("fetch settings"))?;

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
                        log::warn!(
                            "Warning: Invalid poll_interval_minutes value {} (must be 1-60), using default",
                            val
                        );
                        settings.poll_interval_minutes = 15;
                    }
                    Err(e) => {
                        log::warn!(
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
pub async fn get_settings(db: State<'_, DbPool>) -> Result<Settings, String> {
    let pool = get_pool(&db).await?;
    get_settings_impl(&pool).await
}

pub async fn save_settings_impl(pool: &SqlitePool, settings: Settings) -> Result<(), String> {
    validate_poll_interval(settings.poll_interval_minutes)?;

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
            .execute(pool)
            .await
            .map_err(db_err("save settings"))?;
    }

    Ok(())
}

#[tauri::command]
pub async fn save_settings(db: State<'_, DbPool>, settings: Settings) -> Result<(), String> {
    let pool = get_pool(&db).await?;
    save_settings_impl(&pool, settings).await
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::init_test_pool;

    #[tokio::test]
    async fn get_settings_returns_seeded_defaults() {
        let pool = init_test_pool().await;
        let s = get_settings_impl(&pool).await.unwrap();
        assert_eq!(s.launch_at_login, true);
        assert_eq!(s.show_in_menu_bar, true);
        assert_eq!(s.theme, "system");
        assert_eq!(s.poll_interval_minutes, 15);
    }

    #[tokio::test]
    async fn save_settings_round_trips() {
        let pool = init_test_pool().await;
        let custom = Settings {
            launch_at_login: false,
            show_in_menu_bar: false,
            theme: "dark".to_string(),
            notifications_enabled: false,
            notify_ending_soon: false,
            notify_trigger_status: true,
            notify_weekly_summary: true,
            poll_interval_minutes: 30,
        };
        save_settings_impl(&pool, custom.clone()).await.unwrap();

        let loaded = get_settings_impl(&pool).await.unwrap();
        assert_eq!(loaded.launch_at_login, false);
        assert_eq!(loaded.theme, "dark");
        assert_eq!(loaded.poll_interval_minutes, 30);
        assert_eq!(loaded.notify_trigger_status, true);
    }

    #[tokio::test]
    async fn save_settings_rejects_invalid_poll_interval() {
        let pool = init_test_pool().await;
        let bad = Settings {
            poll_interval_minutes: 0,
            ..Settings::default()
        };
        assert!(save_settings_impl(&pool, bad).await.is_err());

        let bad = Settings {
            poll_interval_minutes: 100,
            ..Settings::default()
        };
        assert!(save_settings_impl(&pool, bad).await.is_err());
    }

    #[tokio::test]
    async fn get_settings_clamps_invalid_poll_interval() {
        let pool = init_test_pool().await;
        // Inject a bad value directly (bypasses validation)
        sqlx::query("INSERT OR REPLACE INTO settings (key, value) VALUES ('poll_interval_minutes', '999')")
            .execute(&pool)
            .await
            .unwrap();

        let s = get_settings_impl(&pool).await.unwrap();
        assert_eq!(s.poll_interval_minutes, 15, "should fall back to default");
    }
}
