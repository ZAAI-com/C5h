//! Weekly summary background task.
//!
//! Fires a system notification every Sunday at 18:00 local time with last-7-day
//! window count and average duration. Drives one of the spec'd notification
//! types that previously had a backend command but no scheduler invoking it.
//!
//! Resilience:
//! - Persists `last_weekly_summary_at` in the `settings` table so a restart in
//!   the same week does not double-fire.
//! - On startup, if the current week's slot has already passed and we have
//!   not fired yet this ISO week, fires immediately (good for "I had the app
//!   closed all weekend" cases).
//! - Skips firing when there are zero windows in the last 7 days, so a fresh
//!   install does not greet the user with an empty summary.

use crate::db::DbPool;
use chrono::{DateTime, Datelike, Duration, Local, NaiveTime, TimeZone, Weekday};
use sqlx::SqlitePool;
use tauri::{AppHandle, Manager};
use tauri_plugin_notification::NotificationExt;

const LAST_RUN_KEY: &str = "last_weekly_summary_at";
const SUMMARY_TIME_LOCAL: (u32, u32) = (18, 0); // 18:00

/// Spawn the background task. Idempotent; call once at app startup.
pub fn spawn_weekly_summary_task(app: AppHandle) {
    tauri::async_runtime::spawn(async move {
        // Drain a "missed slot" first if we owe one.
        if let Err(e) = maybe_fire_missed(&app).await {
            log::warn!("Weekly summary missed-slot check failed: {}", e);
        }

        loop {
            let next = next_run_at(Local::now());
            let until = next - Local::now();
            let sleep = until.to_std().unwrap_or(std::time::Duration::from_secs(60));
            log::info!(
                "Weekly summary next run scheduled for {} ({}s away)",
                next.to_rfc3339(),
                sleep.as_secs()
            );
            tokio::time::sleep(sleep).await;

            if let Err(e) = fire_now(&app).await {
                log::warn!("Weekly summary fire failed: {}", e);
            }
        }
    });
}

/// Returns the next Sunday-at-18:00 local from `now`. If `now` is exactly at
/// the slot, returns the slot one week out (avoids double-firing).
pub fn next_run_at(now: DateTime<Local>) -> DateTime<Local> {
    let target_time = NaiveTime::from_hms_opt(SUMMARY_TIME_LOCAL.0, SUMMARY_TIME_LOCAL.1, 0)
        .expect("constant valid time");

    let today = now.date_naive();
    let days_until_sunday = days_until(now.weekday(), Weekday::Sun) as i64;
    let mut candidate_date = today + Duration::days(days_until_sunday);

    let candidate_naive = candidate_date.and_time(target_time);
    let candidate = Local
        .from_local_datetime(&candidate_naive)
        .single()
        .unwrap_or_else(|| now + Duration::hours(1));

    if candidate <= now {
        candidate_date += Duration::days(7);
        let next_naive = candidate_date.and_time(target_time);
        Local
            .from_local_datetime(&next_naive)
            .single()
            .unwrap_or_else(|| now + Duration::hours(168))
    } else {
        candidate
    }
}

fn days_until(from: Weekday, to: Weekday) -> u32 {
    let from = from.num_days_from_sunday();
    let to = to.num_days_from_sunday();
    (to + 7 - from) % 7
}

async fn maybe_fire_missed(app: &AppHandle) -> Result<(), String> {
    let pool = match pool(app).await {
        Some(p) => p,
        None => return Ok(()),
    };

    // Most recent past Sunday-at-18:00 local.
    let now = Local::now();
    let prev_run = previous_run_at(now);

    let last_run = read_last_run(&pool).await;
    let already_fired_this_week = match last_run {
        Some(t) => t >= prev_run,
        None => false,
    };

    if !already_fired_this_week && now >= prev_run {
        fire_now_with_pool(app, &pool).await?;
    }
    Ok(())
}

fn previous_run_at(now: DateTime<Local>) -> DateTime<Local> {
    next_run_at(now) - Duration::days(7)
}

async fn fire_now(app: &AppHandle) -> Result<(), String> {
    let pool = match pool(app).await {
        Some(p) => p,
        None => return Ok(()),
    };
    fire_now_with_pool(app, &pool).await
}

async fn fire_now_with_pool(app: &AppHandle, pool: &SqlitePool) -> Result<(), String> {
    if !setting_enabled(pool, "notifications_enabled").await {
        return Ok(());
    }
    if !setting_enabled(pool, "notify_weekly_summary").await {
        return Ok(());
    }

    let summary = compute_summary(pool).await?;
    if summary.total_windows == 0 {
        log::info!("Weekly summary skipped: no windows in last 7 days");
        // Still record the run so we don't keep checking every restart.
        write_last_run(pool, &Local::now()).await?;
        return Ok(());
    }

    let body = format!(
        "This week: {} windows used, avg {:.1}h each",
        summary.total_windows, summary.avg_duration_hours
    );
    if let Err(e) = app
        .notification()
        .builder()
        .title("Weekly Summary")
        .body(body)
        .show()
    {
        log::warn!("Failed to emit weekly summary notification: {}", e);
    }

    write_last_run(pool, &Local::now()).await?;
    Ok(())
}

#[derive(Debug)]
pub struct WeeklySummary {
    pub total_windows: i64,
    pub avg_duration_hours: f64,
}

/// Compute window stats for the last 7 days. Public for tests.
pub async fn compute_summary(pool: &SqlitePool) -> Result<WeeklySummary, String> {
    let cutoff = (Local::now() - Duration::days(7)).to_rfc3339();
    // Closed windows in the window get exact duration. Active (no ended_at)
    // windows fall back to the account's window_duration_hours, mirroring the
    // calculation the stats view uses.
    let row: (Option<i64>, Option<f64>) = sqlx::query_as(
        "SELECT
            COUNT(*) AS total_windows,
            AVG(
                COALESCE(
                    (julianday(ended_at) - julianday(started_at)) * 24.0,
                    a.window_duration_hours
                )
            ) AS avg_hours
         FROM windows w
         JOIN accounts a ON a.id = w.account_id
         WHERE w.started_at >= ?",
    )
    .bind(&cutoff)
    .fetch_one(pool)
    .await
    .map_err(|e| format!("compute weekly summary: {}", e))?;

    Ok(WeeklySummary {
        total_windows: row.0.unwrap_or(0),
        avg_duration_hours: row.1.unwrap_or(0.0),
    })
}

async fn pool(app: &AppHandle) -> Option<SqlitePool> {
    let state = app.state::<DbPool>();
    let guard = state.0.read().await;
    guard.clone()
}

async fn setting_enabled(pool: &SqlitePool, key: &str) -> bool {
    let row: Option<(String,)> = sqlx::query_as("SELECT value FROM settings WHERE key = ?")
        .bind(key)
        .fetch_optional(pool)
        .await
        .ok()
        .flatten();
    matches!(row, Some((v,)) if v == "true")
}

async fn read_last_run(pool: &SqlitePool) -> Option<DateTime<Local>> {
    let row: Option<(String,)> =
        sqlx::query_as("SELECT value FROM settings WHERE key = ?")
            .bind(LAST_RUN_KEY)
            .fetch_optional(pool)
            .await
            .ok()
            .flatten();
    row.and_then(|(s,)| {
        DateTime::parse_from_rfc3339(&s)
            .ok()
            .map(|dt| dt.with_timezone(&Local))
    })
}

async fn write_last_run(pool: &SqlitePool, when: &DateTime<Local>) -> Result<(), String> {
    sqlx::query("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)")
        .bind(LAST_RUN_KEY)
        .bind(when.to_rfc3339())
        .execute(pool)
        .await
        .map(|_| ())
        .map_err(|e| format!("persist last_weekly_summary_at: {}", e))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::init_test_pool;
    use chrono::{TimeZone, Timelike};

    fn local(year: i32, month: u32, day: u32, hour: u32, minute: u32) -> DateTime<Local> {
        Local
            .with_ymd_and_hms(year, month, day, hour, minute, 0)
            .single()
            .unwrap()
    }

    #[test]
    fn next_run_is_upcoming_sunday_18_when_called_midweek() {
        // 2026-05-06 is a Wednesday.
        let now = local(2026, 5, 6, 12, 0);
        let next = next_run_at(now);
        assert_eq!(next.weekday(), Weekday::Sun);
        assert_eq!(next.hour(), 18);
        assert!(next > now);
        assert!(next - now < Duration::days(7));
    }

    #[test]
    fn next_run_skips_to_following_sunday_when_called_at_slot() {
        // 2026-05-10 is a Sunday at 18:00.
        let now = local(2026, 5, 10, 18, 0);
        let next = next_run_at(now);
        assert_eq!(next.weekday(), Weekday::Sun);
        assert_eq!((next - now).num_days(), 7);
    }

    #[test]
    fn next_run_when_called_after_slot_returns_next_week() {
        // 2026-05-10 is a Sunday at 19:00 (after slot).
        let now = local(2026, 5, 10, 19, 0);
        let next = next_run_at(now);
        assert_eq!(next.weekday(), Weekday::Sun);
        assert!((next - now).num_days() >= 6);
    }

    #[test]
    fn previous_run_is_one_week_before_next() {
        let now = local(2026, 5, 6, 12, 0);
        let next = next_run_at(now);
        let prev = previous_run_at(now);
        assert_eq!(next - prev, Duration::days(7));
    }

    #[tokio::test]
    async fn compute_summary_zero_when_no_recent_windows() {
        let pool = init_test_pool().await;
        let s = compute_summary(&pool).await.unwrap();
        assert_eq!(s.total_windows, 0);
    }

    #[tokio::test]
    async fn compute_summary_counts_recent_windows() {
        let pool = init_test_pool().await;

        // Insert two windows: one yesterday (in range), one 10 days ago (out of range).
        let yesterday = (Local::now() - Duration::days(1)).to_rfc3339();
        let yesterday_end = (Local::now() - Duration::days(1) + Duration::hours(3)).to_rfc3339();
        let ten_days = (Local::now() - Duration::days(10)).to_rfc3339();
        let ten_days_end = (Local::now() - Duration::days(10) + Duration::hours(2)).to_rfc3339();

        sqlx::query(
            "INSERT INTO windows (account_id, started_at, ended_at, triggered_by) VALUES
             (1, ?, ?, 'manual'),
             (1, ?, ?, 'manual')",
        )
        .bind(&yesterday)
        .bind(&yesterday_end)
        .bind(&ten_days)
        .bind(&ten_days_end)
        .execute(&pool)
        .await
        .unwrap();

        let s = compute_summary(&pool).await.unwrap();
        assert_eq!(s.total_windows, 1, "only the in-range window counts");
        assert!((s.avg_duration_hours - 3.0).abs() < 0.01);
    }
}
