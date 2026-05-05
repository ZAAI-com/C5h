use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    async_runtime, AppHandle, Emitter, Manager,
};
use tauri_plugin_autostart::{ManagerExt, MacosLauncher};
use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutState};
use tauri_plugin_positioner::{Position, WindowExt};

mod commands;
mod db;
mod errors;
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
fn show_main_window(app: AppHandle, tab: Option<String>) -> Result<(), String> {
    if let Some(window) = app.get_webview_window("main") {
        window.show().map_err(|e| e.to_string())?;
        window.set_focus().map_err(|e| e.to_string())?;
        if let Some(tab) = tab {
            window
                .emit("navigate-to-tab", tab)
                .map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

// Update tray icon title to show usage percentage
#[tauri::command]
fn update_tray_title(app: AppHandle, text: Option<String>) -> Result<(), String> {
    if let Some(tray) = app.tray_by_id("main-tray") {
        tray.set_title(text.as_deref())
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

// Sync the macOS login-item registration with the user's preference.
// Called when the user toggles "Launch at login" and at app startup
// to reconcile the actual OS state with the persisted setting.
#[tauri::command]
fn set_autostart(app: AppHandle, enabled: bool) -> Result<(), String> {
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
fn is_autostart_enabled(app: AppHandle) -> Result<bool, String> {
    app.autolaunch().is_enabled().map_err(|e| e.to_string())
}

// Quit the application. Used by Cmd+Q so a tray-only app (no app menu)
// can still honor the macOS quit convention.
#[tauri::command]
fn quit_app(app: AppHandle) {
    app.exit(0);
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

fn popover_shortcut() -> Shortcut {
    Shortcut::new(Some(Modifiers::SUPER | Modifiers::SHIFT), Code::Digit5)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    #[allow(unused_mut)]
    let mut builder = tauri::Builder::default()
        // Tauri plugins
        .plugin(tauri_plugin_log::Builder::new().build())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_positioner::init())
        .plugin(tauri_plugin_autostart::init(
            MacosLauncher::LaunchAgent,
            None,
        ))
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(|app, shortcut, event| {
                    if shortcut == &popover_shortcut() && event.state() == ShortcutState::Pressed {
                        toggle_popover(app);
                    }
                })
                .build(),
        );

    #[cfg(feature = "e2e")]
    {
        builder = builder.plugin(tauri_plugin_pilot::init());
    }

    builder
        // Database pool state (initialized in setup)
        .manage(db::DbPool::default())
        // Process monitor state
        .manage(monitor::ProcessMonitor::default())
        // Command handlers
        .invoke_handler(tauri::generate_handler![
            greet,
            show_main_window,
            update_tray_title,
            set_autostart,
            is_autostart_enabled,
            quit_app,
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
            commands::windows::purge_old_windows,
            // Settings commands
            commands::settings::get_settings,
            commands::settings::save_settings,
            // Stats commands
            commands::stats::get_stats,
            // Scheduler commands
            commands::scheduler::get_schedules,
            commands::scheduler::create_schedule,
            commands::scheduler::delete_schedule,
            commands::scheduler::install_schedule,
            commands::scheduler::uninstall_schedule,
            // Polling commands
            commands::polling::poll_account,
            commands::polling::poll_all_accounts,
            commands::polling::check_cli_availability,
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
                .map_err(|e| Box::new(e) as Box<dyn std::error::Error>)?;

            let db_state = app.state::<db::DbPool>();
            let db_pool_arc = db_state.0.clone();

            // Initialize database synchronously using block_on
            let pool = async_runtime::block_on(async {
                db::init_db(app_data_dir).await
            }).map_err(Box::<dyn std::error::Error>::from)?;

            // Reconcile macOS login-item with the persisted launch_at_login
            // setting. Setting defaults to true so first run will register the
            // app as a login item. Failures only log; we do not block startup.
            let launch_at_login = async_runtime::block_on(async {
                commands::settings::get_settings_impl(&pool).await
            })
            .map(|s| s.launch_at_login)
            .unwrap_or(true);
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

            // Register the global shortcut now that the plugin is initialized.
            if let Err(e) = app.global_shortcut().register(popover_shortcut()) {
                log::warn!("Failed to register Cmd+Shift+5 popover shortcut: {}", e);
            }

            // Store the pool in state
            async_runtime::block_on(async {
                let mut pool_guard = db_pool_arc.write().await;
                *pool_guard = Some(pool);
            });

            // Start the background poller that ingests scheduler-trigger result
            // files written by c5h-trigger.sh (the launchd plist wrapper).
            services::trigger_results::spawn_polling_task(app.handle().clone());

            // Schedule the recurring weekly summary notification (Sunday 18:00 local).
            services::weekly_summary::spawn_weekly_summary_task(app.handle().clone());

            // Create tray menu
            let quit = MenuItem::with_id(app, "quit", "Quit C5h", true, None::<&str>)?;
            let show = MenuItem::with_id(app, "show", "Open C5h", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show, &quit])?;

            // Create tray icon with icon from tauri.conf.json
            let _tray = TrayIconBuilder::with_id("main-tray")
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
                        toggle_popover(app);
                    }
                })
                .build(app)?;

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
