use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Manager,
};

mod commands;
mod db;
mod models;
mod monitor;

// Temporary greet command for testing
#[tauri::command]
fn greet(name: &str) -> String {
    format!("Hello, {}! You've been greeted from Rust!", name)
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
        // SQLite plugin with migrations
        .plugin(
            tauri_plugin_sql::Builder::default()
                .add_migrations("sqlite:c5h.db", db::get_migrations())
                .build(),
        )
        // Process monitor state
        .manage(monitor::ProcessMonitor::default())
        // Command handlers
        .invoke_handler(tauri::generate_handler![
            greet,
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
        ])
        .setup(|app| {
            // Create tray menu
            let quit = MenuItem::with_id(app, "quit", "Quit C5h", true, None::<&str>)?;
            let show = MenuItem::with_id(app, "show", "Open C5h", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show, &quit])?;

            // Create tray icon with icon from tauri.conf.json
            let _tray = TrayIconBuilder::new()
                .icon(app.default_window_icon().unwrap().clone())
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
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        let app = tray.app_handle();
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
                })
                .build(app)?;

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
