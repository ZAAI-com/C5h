//! Daily maintenance: window-history retention + orphan trigger-result cleanup.
//!
//! Runs once at startup and every 24h thereafter. Failures only log so the
//! main app keeps working when, say, the disk is full.
//!
//! Two responsibilities right now:
//! 1. Delete `windows` rows older than the retention window (90 days default).
//! 2. Delete result/stderr files in the triggers/ dir whose mtime is older
//!    than 30 days. The normal happy path is the trigger_results poller
//!    deleting them on ingest; this is a safety net for orphaned files
//!    (e.g. account row deleted before ingest, or write race).

use crate::commands::windows::purge_old_windows_impl;
use crate::db::DbPool;
use crate::services::trigger_results;
use std::time::SystemTime;
use tauri::{AppHandle, Manager};

const DAILY_INTERVAL: std::time::Duration = std::time::Duration::from_secs(60 * 60 * 24);
const ORPHAN_FILE_AGE_SECS: u64 = 60 * 60 * 24 * 30; // 30 days

pub fn spawn_maintenance_task(app: AppHandle) {
    tauri::async_runtime::spawn(async move {
        let mut interval = tokio::time::interval(DAILY_INTERVAL);
        loop {
            interval.tick().await;
            if let Err(e) = run_once(&app).await {
                log::warn!("Daily maintenance sweep failed: {}", e);
            }
        }
    });
}

async fn run_once(app: &AppHandle) -> Result<(), String> {
    if let Some(pool) = pool(app).await {
        match purge_old_windows_impl(&pool, None).await {
            Ok(deleted) if deleted > 0 => {
                log::info!("Maintenance: purged {} old window rows", deleted);
            }
            Ok(_) => {}
            Err(e) => log::warn!("Maintenance: purge_old_windows failed: {}", e),
        }
    }

    if let Err(e) = sweep_orphan_trigger_files(app) {
        log::warn!("Maintenance: orphan trigger-file sweep failed: {}", e);
    }
    Ok(())
}

fn sweep_orphan_trigger_files(app: &AppHandle) -> Result<usize, String> {
    let dir = trigger_results::results_dir(app)?;
    let entries = match std::fs::read_dir(&dir) {
        Ok(e) => e,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(0),
        Err(e) => return Err(format!("read_dir({}): {}", dir.display(), e)),
    };

    let cutoff = SystemTime::now() - std::time::Duration::from_secs(ORPHAN_FILE_AGE_SECS);
    let mut removed = 0usize;
    for entry in entries.filter_map(Result::ok) {
        let metadata = match entry.metadata() {
            Ok(m) => m,
            Err(_) => continue,
        };
        let mtime = metadata.modified().unwrap_or_else(|_| SystemTime::now());
        if mtime < cutoff {
            if let Err(e) = std::fs::remove_file(entry.path()) {
                log::warn!("Failed to remove orphan {}: {}", entry.path().display(), e);
            } else {
                removed += 1;
            }
        }
    }
    Ok(removed)
}

async fn pool(app: &AppHandle) -> Option<sqlx::SqlitePool> {
    let state = app.state::<DbPool>();
    let guard = state.0.read().await;
    guard.clone()
}
