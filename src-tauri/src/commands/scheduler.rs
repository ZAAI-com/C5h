use crate::models::{NewScheduledTrigger, ScheduledTrigger};
use chrono::{Datelike, Timelike};
use serde_json::Value;
use sqlx::SqlitePool;
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use tauri::State;
use tauri_plugin_sql::DbInstances;

const PLIST_TEMPLATE: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.zaai.c5h.trigger.{ID}</string>
    <key>ProgramArguments</key>
    <array>
        <string>{CLI_COMMAND}</string>
        <string>-p</string>
        <string>1+1</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>{HOUR}</integer>
        <key>Minute</key>
        <integer>{MINUTE}</integer>
        <key>Day</key>
        <integer>{DAY}</integer>
        <key>Month</key>
        <integer>{MONTH}</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/c5h-trigger-{ID}.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/c5h-trigger-{ID}.log</string>
</dict>
</plist>"#;

fn get_launch_agents_dir() -> PathBuf {
    let home = std::env::var("HOME").expect("HOME not set");
    PathBuf::from(home).join("Library").join("LaunchAgents")
}

fn get_plist_path(id: i64) -> PathBuf {
    get_launch_agents_dir().join(format!("com.zaai.c5h.trigger.{}.plist", id))
}

#[tauri::command]
pub async fn get_schedules(
    db: State<'_, DbInstances>,
    account_id: Option<i64>,
) -> Result<Vec<ScheduledTrigger>, String> {
    let pool = get_pool(&db).await?;

    let rows: Vec<(Value,)> = if let Some(aid) = account_id {
        sqlx::query_as(
            "SELECT json_object(
                'id', id,
                'account_id', account_id,
                'scheduled_at', scheduled_at,
                'status', status,
                'plist_path', plist_path,
                'created_at', created_at
            ) FROM scheduled_triggers
            WHERE account_id = ? AND status = 'pending'
            ORDER BY scheduled_at ASC"
        )
        .bind(aid)
        .fetch_all(&pool)
        .await
        .map_err(|e| e.to_string())?
    } else {
        sqlx::query_as(
            "SELECT json_object(
                'id', id,
                'account_id', account_id,
                'scheduled_at', scheduled_at,
                'status', status,
                'plist_path', plist_path,
                'created_at', created_at
            ) FROM scheduled_triggers
            WHERE status = 'pending'
            ORDER BY scheduled_at ASC"
        )
        .fetch_all(&pool)
        .await
        .map_err(|e| e.to_string())?
    };

    let schedules: Vec<ScheduledTrigger> = rows
        .into_iter()
        .filter_map(|(v,)| serde_json::from_value(v).ok())
        .collect();

    Ok(schedules)
}

#[tauri::command]
pub async fn create_schedule(
    db: State<'_, DbInstances>,
    schedule: NewScheduledTrigger,
) -> Result<ScheduledTrigger, String> {
    let pool = get_pool(&db).await?;

    let result = sqlx::query(
        "INSERT INTO scheduled_triggers (account_id, scheduled_at, status) VALUES (?, ?, 'pending')"
    )
    .bind(schedule.account_id)
    .bind(&schedule.scheduled_at)
    .execute(&pool)
    .await
    .map_err(|e| e.to_string())?;

    let id = result.last_insert_rowid();

    Ok(ScheduledTrigger {
        id: Some(id),
        account_id: schedule.account_id,
        scheduled_at: schedule.scheduled_at,
        status: "pending".to_string(),
        plist_path: None,
        created_at: None,
    })
}

#[tauri::command]
pub async fn delete_schedule(db: State<'_, DbInstances>, id: i64) -> Result<(), String> {
    // First uninstall if installed
    let _ = uninstall_schedule_impl(id);

    let pool = get_pool(&db).await?;

    sqlx::query("DELETE FROM scheduled_triggers WHERE id = ?")
        .bind(id)
        .execute(&pool)
        .await
        .map_err(|e| e.to_string())?;

    Ok(())
}

#[tauri::command]
pub async fn install_schedule(
    db: State<'_, DbInstances>,
    id: i64,
    cli_command: String,
) -> Result<String, String> {
    let pool = get_pool(&db).await?;

    // Get the schedule
    let row: Option<(String,)> = sqlx::query_as(
        "SELECT scheduled_at FROM scheduled_triggers WHERE id = ?"
    )
    .bind(id)
    .fetch_optional(&pool)
    .await
    .map_err(|e| e.to_string())?;

    let scheduled_at = row.ok_or("Schedule not found")?.0;

    // Parse the datetime
    let dt = chrono::DateTime::parse_from_rfc3339(&scheduled_at)
        .map_err(|e| format!("Invalid datetime: {}", e))?;

    // Create plist content
    let plist_content = PLIST_TEMPLATE
        .replace("{ID}", &id.to_string())
        .replace("{CLI_COMMAND}", &cli_command)
        .replace("{HOUR}", &dt.hour().to_string())
        .replace("{MINUTE}", &dt.minute().to_string())
        .replace("{DAY}", &dt.day().to_string())
        .replace("{MONTH}", &dt.month().to_string());

    let plist_path = get_plist_path(id);

    // Ensure LaunchAgents directory exists
    let launch_agents_dir = get_launch_agents_dir();
    if !launch_agents_dir.exists() {
        fs::create_dir_all(&launch_agents_dir)
            .map_err(|e| format!("Failed to create LaunchAgents dir: {}", e))?;
    }

    // Unload existing if present
    let _ = Command::new("launchctl")
        .args(["unload", plist_path.to_str().unwrap()])
        .output();

    // Write plist file
    fs::write(&plist_path, plist_content)
        .map_err(|e| format!("Failed to write plist: {}", e))?;

    // Load the plist
    Command::new("launchctl")
        .args(["load", plist_path.to_str().unwrap()])
        .output()
        .map_err(|e| format!("Failed to load plist: {}", e))?;

    // Update database with plist path
    let plist_path_str = plist_path.to_str().unwrap().to_string();
    sqlx::query("UPDATE scheduled_triggers SET plist_path = ? WHERE id = ?")
        .bind(&plist_path_str)
        .bind(id)
        .execute(&pool)
        .await
        .map_err(|e| e.to_string())?;

    Ok(plist_path_str)
}

#[tauri::command]
pub async fn uninstall_schedule(id: i64) -> Result<(), String> {
    uninstall_schedule_impl(id)
}

fn uninstall_schedule_impl(id: i64) -> Result<(), String> {
    let plist_path = get_plist_path(id);

    if plist_path.exists() {
        // Unload
        let _ = Command::new("launchctl")
            .args(["unload", plist_path.to_str().unwrap()])
            .output();

        // Delete file
        fs::remove_file(&plist_path)
            .map_err(|e| format!("Failed to delete plist: {}", e))?;
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
