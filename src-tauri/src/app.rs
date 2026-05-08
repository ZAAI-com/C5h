use tauri::{async_runtime, Manager};
use tauri_plugin_autostart::MacosLauncher;
use tauri_plugin_global_shortcut::ShortcutState;

use crate::{
    app_window, autostart, commands, db, monitor, services, shortcuts, tray,
};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    #[allow(unused_mut)]
    let mut builder = tauri::Builder::default()
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
                    if shortcut == &shortcuts::popover_shortcut()
                        && event.state() == ShortcutState::Pressed
                    {
                        tray::toggle_popover(app);
                    }
                })
                .build(),
        );

    #[cfg(feature = "e2e")]
    {
        builder = builder.plugin(tauri_plugin_pilot::init());
    }

    builder
        .manage(db::DbPool::default())
        .manage(monitor::ProcessMonitor::default())
        .manage(tray::TrayController::default())
        .invoke_handler(tauri::generate_handler![
            app_window::greet,
            app_window::show_main_window,
            app_window::quit_app,
            tray::update_tray_title,
            tray::update_tray_state,
            autostart::set_autostart,
            autostart::is_autostart_enabled,
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
            // Onboarding completion flag
            commands::onboarding::is_onboarding_completed,
            commands::onboarding::mark_onboarding_completed,
            // Predictive insights (local-only)
            commands::insights::get_insights,
            commands::insights::dismiss_insight,
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
            let app_data_dir = app
                .path()
                .app_data_dir()
                .map_err(|e| Box::new(e) as Box<dyn std::error::Error>)?;

            let db_state = app.state::<db::DbPool>();
            let db_pool_arc = db_state.0.clone();

            let pool = async_runtime::block_on(async { db::init_db(app_data_dir).await })
                .map_err(Box::<dyn std::error::Error>::from)?;

            // Reconcile macOS login-item with the persisted launch_at_login
            // setting. Default true so first run registers the app.
            let launch_at_login =
                async_runtime::block_on(async { commands::settings::get_settings_impl(&pool).await })
                    .map(|s| s.launch_at_login)
                    .unwrap_or(true);
            autostart::reconcile_autostart(app.handle(), launch_at_login);

            shortcuts::register_popover_shortcut(app.handle());

            async_runtime::block_on(async {
                let mut pool_guard = db_pool_arc.write().await;
                *pool_guard = Some(pool);
            });

            services::trigger_results::spawn_polling_task(app.handle().clone());
            services::weekly_summary::spawn_weekly_summary_task(app.handle().clone());
            services::maintenance::spawn_maintenance_task(app.handle().clone());

            tray::create_tray(app.handle())?;

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
