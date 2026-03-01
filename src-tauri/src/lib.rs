use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager, async_runtime,
};
use tauri_plugin_positioner::{Position, WindowExt};
use std::sync::Arc;
use tokio::sync::RwLock;

mod commands;
mod db;
mod models;
mod monitor;
mod services;
mod validation;

// Temporary greet command for testing
#[tauri::command]
fn greet(name: &str) -> String {
    format!("Hello, {}! You've been greeted from Rust!", name)
}

// Command to show the main window from the popover
#[tauri::command]
fn show_main_window(app: AppHandle) -> Result<(), String> {
    if let Some(window) = app.get_webview_window("main") {
        window.show().map_err(|e| e.to_string())?;
        window.set_focus().map_err(|e| e.to_string())?;
    }
    Ok(())
}

// Toggle popover window visibility near the tray icon
fn toggle_popover(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("popover") {
        if window.is_visible().unwrap_or(false) {
            let _ = window.hide();
        } else {
            // Position near tray icon (TrayBottomCenter positions below the tray)
            let _ = window.move_window(Position::TrayBottomCenter);
            let _ = window.show();
            let _ = window.set_focus();
        }
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        // Tauri plugins
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(
            tauri_plugin_autostart::init(
                tauri_plugin_autostart::MacosLauncher::LaunchAgent,
                Some(vec!["--hidden"]),
            )
        )
        .plugin(tauri_plugin_positioner::init())
        // Database pool state (initialized in setup)
        .manage(db::DbPool::default())
        // Process monitor state
        .manage(monitor::ProcessMonitor::default())
        // Command handlers
        .invoke_handler(tauri::generate_handler![
            greet,
            show_main_window,
            // Account commands
            commands::accounts::get_accounts,
            commands::accounts::create_account,
            commands::accounts::update_account,
            commands::accounts::delete_account,
            // Window commands
            commands::windows::get_windows,
            commands::windows::get_current_window,
            commands::windows::create_window,
            commands::windows::end_window,
            // Settings commands
            commands::settings::get_settings,
            commands::settings::save_settings,
            // Scheduler commands
            commands::scheduler::get_schedules,
            commands::scheduler::create_schedule,
            commands::scheduler::delete_schedule,
            commands::scheduler::install_schedule,
            commands::scheduler::uninstall_schedule,
            // Monitor commands
            monitor::start_monitoring,
            monitor::stop_monitoring,
            monitor::get_monitoring_status,
            monitor::update_monitor_config,
            monitor::scan_cli_processes,
            // Notification commands
            commands::notifications::notify_window_ending_soon,
            commands::notifications::notify_scheduled_trigger,
            commands::notifications::notify_weekly_summary,
            commands::notifications::send_notification,
        ])
        .setup(|app| {
            // Initialize database
            let app_data_dir = app.path().app_data_dir()
                .expect("Failed to get app data directory");

            let db_state = app.state::<db::DbPool>();
            let db_pool_arc = db_state.0.clone();

            // Initialize database synchronously using block_on
            let pool = async_runtime::block_on(async {
                db::init_db(app_data_dir).await
            }).expect("Failed to initialize database");

            // Store the pool in state
            async_runtime::block_on(async {
                let mut pool_guard = db_pool_arc.write().await;
                *pool_guard = Some(pool);
            });

            // Create tray menu
            let quit = MenuItem::with_id(app, "quit", "Quit C5h", true, None::<&str>)?;
            let show = MenuItem::with_id(app, "show", "Open C5h", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show, &quit])?;

            // Create tray icon with icon from tauri.conf.json
            let _tray = TrayIconBuilder::new()
                .icon(app.default_window_icon()
                    .ok_or("Default window icon not configured")?
                    .clone())
                .menu(&menu)
                .tooltip("C5h - AI Tool Usage Tracker")
                .on_menu_event(|app, event| {
                    match event.id.as_ref() {
                        "quit" => {
                            app.exit(0);
                        }
                        "show" => {
                            if let Some(window) = app.get_webview_window("main") {
                                let _ = window.show();
                                let _ = window.set_focus();
                            }
                        }
                        _ => {}
                    }
                })
                .on_tray_icon_event(|tray, event| {
                    let app = tray.app_handle();

                    // Update positioner's tray position tracking
                    tauri_plugin_positioner::on_tray_event(app, &event);

                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        toggle_popover(&app);
                    }
                })
                .build(app)?;

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
