use tauri::AppHandle;
use tauri_plugin_notification::NotificationExt;

/// Send notification when window is ending soon
#[tauri::command]
pub async fn notify_window_ending_soon(
    app: AppHandle,
    account_name: String,
    minutes_remaining: i32,
) -> Result<(), String> {
    app.notification()
        .builder()
        .title("Window Ending Soon")
        .body(&format!(
            "Your {} window expires in {} minutes",
            account_name, minutes_remaining
        ))
        .show()
        .map_err(|e| e.to_string())?;

    Ok(())
}

/// Send notification about scheduled trigger result
#[tauri::command]
pub async fn notify_scheduled_trigger(
    app: AppHandle,
    account_name: String,
    success: bool,
) -> Result<(), String> {
    let (title, body) = if success {
        (
            "Window Started",
            format!("New {} window started successfully", account_name),
        )
    } else {
        (
            "Trigger Failed",
            format!("Failed to start {} window - check CLI", account_name),
        )
    };

    app.notification()
        .builder()
        .title(title)
        .body(&body)
        .show()
        .map_err(|e| e.to_string())?;

    Ok(())
}

/// Send weekly summary notification
#[tauri::command]
pub async fn notify_weekly_summary(
    app: AppHandle,
    total_windows: i32,
    avg_duration: f32,
) -> Result<(), String> {
    app.notification()
        .builder()
        .title("Weekly Summary")
        .body(&format!(
            "This week: {} windows used, avg {:.1}h each",
            total_windows, avg_duration
        ))
        .show()
        .map_err(|e| e.to_string())?;

    Ok(())
}

/// Send a generic notification
#[tauri::command]
pub async fn send_notification(
    app: AppHandle,
    title: String,
    body: String,
) -> Result<(), String> {
    app.notification()
        .builder()
        .title(&title)
        .body(&body)
        .show()
        .map_err(|e| e.to_string())?;

    Ok(())
}
