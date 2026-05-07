use std::sync::{Arc, Mutex};
use std::time::Duration;
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    async_runtime, AppHandle, Emitter, Manager, State,
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

// Update tray icon title to show usage percentage.
//
// Kept as a thin compatibility wrapper over `update_tray_state` so any
// existing callers (including tests) keep working. Prefer `update_tray_state`
// for new call sites — it carries the structured info needed for pulse,
// multi-window, and error variants.
#[tauri::command]
fn update_tray_title(
    app: AppHandle,
    controller: State<'_, TrayController>,
    text: Option<String>,
) -> Result<(), String> {
    let state = match text {
        None => TrayState::Idle,
        Some(s) => {
            let percent = s.trim_end_matches('%').parse::<i32>().ok();
            TrayState::Active {
                percent,
                minutes_remaining: None,
            }
        }
    };
    apply_tray_state(&app, &controller, state, false)
}

/// Visual state of the menu-bar tray icon, derived in the frontend and pushed
/// here so the Rust side can own the pulse animation timer.
#[derive(Debug, Clone, serde::Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum TrayState {
    Idle,
    Active {
        /// 0..=100. None means "active but usage unknown" — show "—%" or skip percent.
        percent: Option<i32>,
        /// When set and < 30, the tray pulses to draw attention.
        minutes_remaining: Option<i32>,
    },
    MultiWindow {
        entries: Vec<TrayWindowEntry>,
    },
    Error {
        message: String,
    },
}

#[derive(Debug, Clone, serde::Deserialize)]
pub struct TrayWindowEntry {
    pub percent: i32,
}

/// Holds the generation counter for tray pulse animations. When the tray
/// state changes, the generation bumps; in-flight pulse tasks notice their
/// generation is stale and exit. Avoids abort-handle bookkeeping.
#[derive(Clone, Default)]
pub struct TrayController {
    pulse_generation: Arc<Mutex<u64>>,
}

impl TrayController {
    fn bump(&self) -> u64 {
        let mut g = self.pulse_generation.lock().expect("poisoned");
        *g += 1;
        *g
    }
}

#[tauri::command]
fn update_tray_state(
    app: AppHandle,
    controller: State<'_, TrayController>,
    state: TrayState,
    reduced_motion: Option<bool>,
) -> Result<(), String> {
    apply_tray_state(&app, &controller, state, reduced_motion.unwrap_or(false))
}

fn apply_tray_state(
    app: &AppHandle,
    controller: &TrayController,
    state: TrayState,
    reduced_motion: bool,
) -> Result<(), String> {
    // Bump the generation to invalidate any in-flight pulse task.
    let my_gen = controller.bump();

    let tray = match app.tray_by_id("main-tray") {
        Some(t) => t,
        None => return Ok(()), // tray not yet built (early startup) — caller is harmless
    };

    match state {
        TrayState::Idle => {
            tray.set_title(None::<&str>).map_err(|e| e.to_string())?;
        }
        TrayState::Active {
            percent,
            minutes_remaining,
        } => {
            let ending_soon = minutes_remaining.map(|m| m > 0 && m < 30).unwrap_or(false);
            let steady = render_active(percent, minutes_remaining, false);
            if ending_soon && !reduced_motion {
                let pulsed = render_active(percent, minutes_remaining, true);
                tray.set_title(Some(&pulsed)).map_err(|e| e.to_string())?;
                spawn_pulse(app.clone(), controller.pulse_generation.clone(), my_gen, steady, pulsed);
            } else {
                tray.set_title(Some(&steady)).map_err(|e| e.to_string())?;
            }
        }
        TrayState::MultiWindow { entries } => {
            let text = if entries.is_empty() {
                String::new()
            } else {
                entries
                    .iter()
                    .map(|e| format!("{}%", e.percent))
                    .collect::<Vec<_>>()
                    .join(" / ")
            };
            tray.set_title(Some(&text)).map_err(|e| e.to_string())?;
        }
        TrayState::Error { .. } => {
            tray.set_title(Some("⚠")).map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

/// Title text for an Active state. `pulsed=true` adds the warning glyph; the
/// pulse animation alternates between this and the un-glyphed form.
fn render_active(percent: Option<i32>, minutes_remaining: Option<i32>, pulsed: bool) -> String {
    let prefix = if pulsed { "⚠ " } else { "" };
    match (percent, minutes_remaining) {
        (Some(p), Some(m)) if m < 60 => format!("{}{}% {}m", prefix, p, m),
        (Some(p), _) => format!("{}{}%", prefix, p),
        (None, Some(m)) if m < 60 => format!("{}{}m", prefix, m),
        (None, _) => format!("{}—", prefix),
    }
}

fn spawn_pulse(
    app: AppHandle,
    generation: Arc<Mutex<u64>>,
    my_gen: u64,
    steady: String,
    pulsed: String,
) {
    tauri::async_runtime::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_millis(1500));
        // First tick fires immediately — skip it so the initial set above stays visible.
        interval.tick().await;
        let mut show_pulsed = true;
        loop {
            interval.tick().await;
            // Bail if a newer state has taken over.
            if *generation.lock().expect("poisoned") != my_gen {
                return;
            }
            show_pulsed = !show_pulsed;
            let text = if show_pulsed { &pulsed } else { &steady };
            if let Some(tray) = app.tray_by_id("main-tray") {
                let _ = tray.set_title(Some(text));
            }
        }
    });
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
        // Tray pulse-animation generation counter
        .manage(TrayController::default())
        // Command handlers
        .invoke_handler(tauri::generate_handler![
            greet,
            show_main_window,
            update_tray_title,
            update_tray_state,
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

            // Daily retention sweep: prunes old window rows and orphan trigger files.
            services::maintenance::spawn_maintenance_task(app.handle().clone());

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
