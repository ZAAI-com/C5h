use crate::db::get_pool;
use crate::errors::db_err;
use crate::models::{NewScheduledTrigger, ScheduledTrigger};
use crate::validation::{escape_for_plist, validate_cli_command, validate_scheduled_at};
use chrono::{Datelike, Timelike};
use serde_json::Value;
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use tauri::State;
use crate::db::DbPool;

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

/// Get the LaunchAgents directory path.
///
/// Returns an error if HOME is not set instead of panicking.
fn get_launch_agents_dir() -> Result<PathBuf, String> {
    let home = std::env::var("HOME")
        .map_err(|_| "HOME environment variable not set. Cannot locate LaunchAgents directory.".to_string())?;
    Ok(PathBuf::from(home).join("Library").join("LaunchAgents"))
}

fn get_plist_path(id: i64) -> Result<PathBuf, String> {
    let launch_agents_dir = get_launch_agents_dir()?;
    Ok(launch_agents_dir.join(format!("com.zaai.c5h.trigger.{}.plist", id)))
}

/// Convert a PathBuf to a string, with proper error handling.
fn path_to_string(path: &PathBuf) -> Result<String, String> {
    path.to_str()
        .ok_or_else(|| "Path contains invalid UTF-8 characters".to_string())
        .map(|s| s.to_string())
}

#[tauri::command]
pub async fn get_schedules(
    db: State<'_, DbPool>,
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
        .map_err(db_err("fetch schedules"))?
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
        .map_err(db_err("fetch schedules"))?
    };

    let schedules: Vec<ScheduledTrigger> = rows
        .into_iter()
        .filter_map(|(v,)| {
            match serde_json::from_value(v.clone()) {
                Ok(schedule) => Some(schedule),
                Err(e) => {
                    eprintln!("Skipping malformed schedule record: {}", e);
                    None
                }
            }
        })
        .collect();

    Ok(schedules)
}

#[tauri::command]
pub async fn create_schedule(
    db: State<'_, DbPool>,
    schedule: NewScheduledTrigger,
) -> Result<ScheduledTrigger, String> {
    // Validate scheduled_at datetime
    validate_scheduled_at(&schedule.scheduled_at)?;

    let pool = get_pool(&db).await?;

    // Check for schedule conflicts: overlapping windows for the same account
    let new_dt = chrono::DateTime::parse_from_rfc3339(&schedule.scheduled_at)
        .map_err(|e| format!("Invalid datetime: {}", e))?;

    // Get the account's window_duration_hours for overlap calculation
    let duration_row: Option<(i32,)> = sqlx::query_as(
        "SELECT window_duration_hours FROM accounts WHERE id = ?",
    )
    .bind(schedule.account_id)
    .fetch_optional(&pool)
    .await
    .map_err(db_err("fetch account duration"))?;

    let window_duration_hours = duration_row.map(|(h,)| h).unwrap_or(5) as i64;

    // Check existing pending schedules for the same account that would overlap
    let existing: Vec<(String,)> = sqlx::query_as(
        "SELECT scheduled_at FROM scheduled_triggers WHERE account_id = ? AND status = 'pending'",
    )
    .bind(schedule.account_id)
    .fetch_all(&pool)
    .await
    .map_err(db_err("check schedule conflicts"))?;

    for (existing_at,) in &existing {
        if let Ok(existing_dt) = chrono::DateTime::parse_from_rfc3339(existing_at) {
            let diff_hours = (new_dt.signed_duration_since(existing_dt)).num_hours().abs();
            if diff_hours < window_duration_hours {
                return Err(format!(
                    "Schedule conflict: an existing schedule at {} is within {}h of the requested time. \
                     Windows are {}h long, so these would overlap.",
                    existing_dt.format("%b %d at %H:%M"),
                    diff_hours,
                    window_duration_hours,
                ));
            }
        }
    }

    let result = sqlx::query(
        "INSERT INTO scheduled_triggers (account_id, scheduled_at, status) VALUES (?, ?, 'pending')"
    )
    .bind(schedule.account_id)
    .bind(&schedule.scheduled_at)
    .execute(&pool)
    .await
    .map_err(db_err("create schedule"))?;

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
pub async fn delete_schedule(db: State<'_, DbPool>, id: i64) -> Result<(), String> {
    // First uninstall if installed (ignore errors - file may not exist)
    if let Err(e) = uninstall_schedule_impl(id) {
        eprintln!("Warning: Failed to uninstall schedule during delete: {}", e);
    }

    let pool = get_pool(&db).await?;

    sqlx::query("DELETE FROM scheduled_triggers WHERE id = ?")
        .bind(id)
        .execute(&pool)
        .await
        .map_err(db_err("delete schedule"))?;

    Ok(())
}

#[tauri::command]
pub async fn install_schedule(
    db: State<'_, DbPool>,
    id: i64,
    cli_command: String,
) -> Result<String, String> {
    // Validate CLI command to prevent command injection
    validate_cli_command(&cli_command)?;

    let pool = get_pool(&db).await?;

    // Get the schedule
    let row: Option<(String,)> = sqlx::query_as(
        "SELECT scheduled_at FROM scheduled_triggers WHERE id = ?"
    )
    .bind(id)
    .fetch_optional(&pool)
    .await
    .map_err(db_err("fetch schedule for install"))?;

    let scheduled_at = row.ok_or("Schedule not found")?.0;

    // Parse the datetime
    let dt = chrono::DateTime::parse_from_rfc3339(&scheduled_at)
        .map_err(|e| format!("Invalid datetime in database: {}", e))?;

    // Escape CLI command for safe plist inclusion
    let safe_cli_command = escape_for_plist(&cli_command);

    // Create plist content with escaped values
    let plist_content = PLIST_TEMPLATE
        .replace("{ID}", &id.to_string())
        .replace("{CLI_COMMAND}", &safe_cli_command)
        .replace("{HOUR}", &dt.hour().to_string())
        .replace("{MINUTE}", &dt.minute().to_string())
        .replace("{DAY}", &dt.day().to_string())
        .replace("{MONTH}", &dt.month().to_string());

    let plist_path = get_plist_path(id)?;
    let plist_path_str = path_to_string(&plist_path)?;

    // Ensure LaunchAgents directory exists
    let launch_agents_dir = get_launch_agents_dir()?;
    if !launch_agents_dir.exists() {
        fs::create_dir_all(&launch_agents_dir)
            .map_err(|e| format!("Failed to create LaunchAgents directory: {}", e))?;
    }

    // Unload existing if present (ignore errors - may not be loaded)
    let unload_result = Command::new("launchctl")
        .args(["unload", &plist_path_str])
        .output();

    if let Err(e) = unload_result {
        eprintln!("Warning: Failed to unload existing plist: {}", e);
    }

    // Write plist file
    fs::write(&plist_path, plist_content)
        .map_err(|e| format!("Failed to write plist file: {}", e))?;

    // Load the plist
    let load_output = Command::new("launchctl")
        .args(["load", &plist_path_str])
        .output()
        .map_err(|e| format!("Failed to execute launchctl load: {}", e))?;

    if !load_output.status.success() {
        let stderr = String::from_utf8_lossy(&load_output.stderr);
        return Err(format!("launchctl load failed: {}", stderr));
    }

    // Update database with plist path
    sqlx::query("UPDATE scheduled_triggers SET plist_path = ? WHERE id = ?")
        .bind(&plist_path_str)
        .bind(id)
        .execute(&pool)
        .await
        .map_err(db_err("update schedule plist path"))?;

    Ok(plist_path_str)
}

#[tauri::command]
pub async fn uninstall_schedule(id: i64) -> Result<(), String> {
    uninstall_schedule_impl(id)
}

fn uninstall_schedule_impl(id: i64) -> Result<(), String> {
    let plist_path = get_plist_path(id)?;

    if plist_path.exists() {
        let plist_path_str = path_to_string(&plist_path)?;

        // Unload from launchd (ignore errors - may not be loaded)
        let unload_result = Command::new("launchctl")
            .args(["unload", &plist_path_str])
            .output();

        if let Ok(output) = unload_result {
            if !output.status.success() {
                let stderr = String::from_utf8_lossy(&output.stderr);
                eprintln!("Warning: launchctl unload failed: {}", stderr);
            }
        } else if let Err(e) = unload_result {
            eprintln!("Warning: Failed to execute launchctl unload: {}", e);
        }

        // Delete plist file
        fs::remove_file(&plist_path)
            .map_err(|e| format!("Failed to delete plist file: {}", e))?;
    }

    Ok(())
}
