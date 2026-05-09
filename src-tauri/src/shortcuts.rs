use tauri::AppHandle;
use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut};

pub fn popover_shortcut() -> Shortcut {
    Shortcut::new(Some(Modifiers::SUPER | Modifiers::SHIFT), Code::Digit5)
}

pub fn register_popover_shortcut(app: &AppHandle) {
    if let Err(e) = app.global_shortcut().register(popover_shortcut()) {
        log::warn!("Failed to register Cmd+Shift+5 popover shortcut: {}", e);
    }
}
