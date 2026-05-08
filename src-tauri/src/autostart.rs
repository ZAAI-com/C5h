use tauri::AppHandle;
use tauri_plugin_autostart::ManagerExt;

#[tauri::command]
pub fn set_autostart(app: AppHandle, enabled: bool) -> Result<(), String> {
    let manager = app.autolaunch();
    let already = manager.is_enabled().map_err(|e| e.to_string())?;
    if enabled && !already {
        manager.enable().map_err(|e| e.to_string())?;
    } else if !enabled && already {
        manager.disable().map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
pub fn is_autostart_enabled(app: AppHandle) -> Result<bool, String> {
    app.autolaunch().is_enabled().map_err(|e| e.to_string())
}

/// Reconcile the macOS login-item registration with the user's persisted
/// preference. Failures only log; we do not block startup.
pub fn reconcile_autostart(app: &AppHandle, launch_at_login: bool) {
    let manager = app.autolaunch();
    match manager.is_enabled() {
        Ok(currently_enabled) => {
            if launch_at_login && !currently_enabled {
                if let Err(e) = manager.enable() {
                    log::warn!("Failed to enable autostart at startup: {}", e);
                }
            } else if !launch_at_login && currently_enabled {
                if let Err(e) = manager.disable() {
                    log::warn!("Failed to disable autostart at startup: {}", e);
                }
            }
        }
        Err(e) => log::warn!("Failed to query autostart state at startup: {}", e),
    }
}
