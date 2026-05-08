use std::sync::{Arc, Mutex};
use std::time::Duration;
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager, State,
};
use tauri_plugin_positioner::{Position, WindowExt};

#[derive(Debug, Clone, serde::Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum TrayState {
    Idle,
    Active {
        percent: Option<i32>,
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

// Kept as a thin compatibility wrapper over `update_tray_state` so any
// existing callers (including tests) keep working. Prefer `update_tray_state`
// for new call sites — it carries the structured info needed for pulse,
// multi-window, and error variants.
#[tauri::command]
pub fn update_tray_title(
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

#[tauri::command]
pub fn update_tray_state(
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
    let my_gen = controller.bump();

    let tray = match app.tray_by_id("main-tray") {
        Some(t) => t,
        None => return Ok(()),
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
        interval.tick().await;
        let mut show_pulsed = true;
        loop {
            interval.tick().await;
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

pub fn toggle_popover(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("popover") {
        if window.is_visible().unwrap_or(false) {
            let _ = window.hide();
        } else {
            let _ = window.move_window(Position::TrayBottomCenter);
            let _ = window.show();
            let _ = window.set_focus();
        }
    }
}

pub fn create_tray(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let quit = MenuItem::with_id(app, "quit", "Quit C5h", true, None::<&str>)?;
    let show = MenuItem::with_id(app, "show", "Open C5h", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&show, &quit])?;

    let _tray = TrayIconBuilder::with_id("main-tray")
        .icon(
            app.default_window_icon()
                .ok_or("Default window icon not configured")?
                .clone(),
        )
        .menu(&menu)
        .tooltip("C5h - AI Tool Usage Tracker")
        .on_menu_event(|app, event| match event.id.as_ref() {
            "quit" => app.exit(0),
            "show" => {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            }
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            let app = tray.app_handle();
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
}
