use crate::db::{get_pool, DbPool};
use crate::errors::db_err;
use crate::models::{
    AccountBreakdownStat, DayOfWeekStat, DurationTrendPoint, StatsPayload, StatsSummary,
    TimeOfDayStat, WeeklyDayStats,
};
use chrono::{DateTime, Datelike, Duration, Local, LocalResult, TimeZone, Timelike};
use sqlx::SqlitePool;
use std::collections::HashMap;
use tauri::State;

type WindowStatsRow = (i64, String, Option<String>, i32);

fn local_datetime(
    date: chrono::NaiveDate,
    hour: u32,
    minute: u32,
    second: u32,
) -> Result<DateTime<Local>, String> {
    let naive = date
        .and_hms_opt(hour, minute, second)
        .ok_or_else(|| "Failed to build local datetime".to_string())?;

    match Local.from_local_datetime(&naive) {
        LocalResult::Single(dt) => Ok(dt),
        LocalResult::Ambiguous(dt, _) => Ok(dt),
        LocalResult::None => Err("Failed to resolve local datetime".to_string()),
    }
}

fn start_of_local_week(selected_date: &str) -> Result<DateTime<Local>, String> {
    let selected = DateTime::parse_from_rfc3339(selected_date)
        .map_err(|e| format!("Invalid selected date: {}", e))?
        .with_timezone(&Local);
    let weekday_offset = i64::from(selected.weekday().num_days_from_sunday());
    let week_start_date = selected.date_naive() - Duration::days(weekday_offset);
    local_datetime(week_start_date, 0, 0, 0)
}

fn round_one_decimal(value: f64) -> f64 {
    (value * 10.0).round() / 10.0
}

fn parse_local_rfc3339(value: &str) -> Result<DateTime<Local>, String> {
    Ok(
        DateTime::parse_from_rfc3339(value)
            .map_err(|e| format!("Invalid stored datetime '{}': {}", value, e))?
            .with_timezone(&Local),
    )
}

fn effective_end(
    started_at: &str,
    ended_at: Option<&str>,
    window_duration_hours: i32,
) -> Result<DateTime<Local>, String> {
    let start = parse_local_rfc3339(started_at)?;
    let end = match ended_at {
        Some(ended_at) => parse_local_rfc3339(ended_at)?,
        None => start + Duration::hours(i64::from(window_duration_hours)),
    };

    Ok(end)
}

fn window_duration_hours(row: &WindowStatsRow) -> Result<f64, String> {
    let start = parse_local_rfc3339(&row.1)?;
    let end = effective_end(&row.1, row.2.as_deref(), row.3)?;
    Ok((end - start).num_seconds() as f64 / 3600.0)
}

async fn fetch_window_rows(
    pool: &SqlitePool,
    from: &str,
    to: &str,
    account_id: Option<i64>,
) -> Result<Vec<WindowStatsRow>, String> {
    if let Some(account_id) = account_id {
        sqlx::query_as(
            "SELECT w.account_id, w.started_at, w.ended_at, a.window_duration_hours
             FROM windows w
             JOIN accounts a ON a.id = w.account_id
             WHERE w.started_at >= ? AND w.started_at < ? AND w.account_id = ?
             ORDER BY w.started_at ASC",
        )
        .bind(from)
        .bind(to)
        .bind(account_id)
        .fetch_all(pool)
        .await
        .map_err(db_err("fetch filtered stats windows"))
    } else {
        sqlx::query_as(
            "SELECT w.account_id, w.started_at, w.ended_at, a.window_duration_hours
             FROM windows w
             JOIN accounts a ON a.id = w.account_id
             WHERE w.started_at >= ? AND w.started_at < ?
             ORDER BY w.started_at ASC",
        )
        .bind(from)
        .bind(to)
        .fetch_all(pool)
        .await
        .map_err(db_err("fetch stats windows"))
    }
}

pub async fn get_stats_impl(
    pool: &SqlitePool,
    selected_date: String,
    account_id: Option<i64>,
) -> Result<StatsPayload, String> {
    let week_start_local = start_of_local_week(&selected_date)?;
    let week_end_local = week_start_local + Duration::days(7);
    let trend_start_local = week_start_local - Duration::weeks(7);

    let week_rows = fetch_window_rows(
        pool,
        &week_start_local.with_timezone(&chrono::Utc).to_rfc3339(),
        &week_end_local.with_timezone(&chrono::Utc).to_rfc3339(),
        account_id,
    )
    .await?;

    let trend_rows = fetch_window_rows(
        pool,
        &trend_start_local.with_timezone(&chrono::Utc).to_rfc3339(),
        &week_end_local.with_timezone(&chrono::Utc).to_rfc3339(),
        account_id,
    )
    .await?;

    let day_names = [
        "Sunday",
        "Monday",
        "Tuesday",
        "Wednesday",
        "Thursday",
        "Friday",
        "Saturday",
    ];

    let mut week_data = Vec::with_capacity(7);
    let mut day_counts = [0_i64; 7];
    let mut hour_counts = [0_i64; 24];
    let mut account_breakdown: HashMap<i64, (i64, f64)> = HashMap::new();
    let mut total_hours = 0.0_f64;

    for day_offset in 0..7 {
        let day_start = week_start_local + Duration::days(day_offset);
        week_data.push(WeeklyDayStats {
            day: day_start.format("%a").to_string(),
            date: day_start.format("%b %-d").to_string(),
            window_count: 0,
            account_counts: HashMap::new(),
        });
    }

    for row in &week_rows {
        let start = parse_local_rfc3339(&row.1)?;
        let day_index = start.weekday().num_days_from_sunday() as usize;
        let hour_index = start.hour() as usize;
        let duration_hours = window_duration_hours(row)?;

        week_data[day_index].window_count += 1;
        *week_data[day_index]
            .account_counts
            .entry(format!("account_{}", row.0))
            .or_insert(0) += 1;

        day_counts[day_index] += 1;
        hour_counts[hour_index] += 1;
        total_hours += duration_hours;

        let entry = account_breakdown.entry(row.0).or_insert((0, 0.0));
        entry.0 += 1;
        entry.1 += duration_hours;
    }

    let max_day_count = day_counts.iter().copied().max().unwrap_or(0).max(1) as f64;
    let day_of_week = day_names
        .iter()
        .enumerate()
        .map(|(index, day)| DayOfWeekStat {
            day: day.to_string(),
            count: day_counts[index],
            intensity: day_counts[index] as f64 / max_day_count,
        })
        .collect();

    let time_of_day = hour_counts
        .iter()
        .enumerate()
        .map(|(hour, count)| TimeOfDayStat {
            hour: match hour {
                0 => "12am".to_string(),
                12 => "12pm".to_string(),
                13..=23 => format!("{}pm", hour - 12),
                _ => format!("{}am", hour),
            },
            count: *count,
        })
        .collect();

    let mut duration_trend = Vec::with_capacity(8);
    for week_offset in 0..8 {
        let current_week_start = trend_start_local + Duration::weeks(week_offset);
        let current_week_end = current_week_start + Duration::days(7);
        let mut total_week_hours = 0.0_f64;
        let mut total_week_windows = 0_i64;

        for row in &trend_rows {
            let start = parse_local_rfc3339(&row.1)?;
            if start >= current_week_start && start < current_week_end {
                total_week_windows += 1;
                total_week_hours += window_duration_hours(row)?;
            }
        }

        let avg_hours = if total_week_windows > 0 {
            round_one_decimal(total_week_hours / total_week_windows as f64)
        } else {
            0.0
        };

        duration_trend.push(DurationTrendPoint {
            week: current_week_start.format("%b %-d").to_string(),
            avg_hours,
            windows: total_week_windows,
        });
    }

    let account_breakdown = account_breakdown
        .into_iter()
        .map(|(account_id, (window_count, total_hours))| AccountBreakdownStat {
            account_id,
            window_count,
            total_hours: round_one_decimal(total_hours),
        })
        .collect();

    let total_windows = week_rows.len() as i64;
    let avg_duration_hours = if total_windows > 0 {
        round_one_decimal(total_hours / total_windows as f64)
    } else {
        0.0
    };

    let current_week_start = start_of_local_week(&Local::now().to_rfc3339())?;

    Ok(StatsPayload {
        summary: StatsSummary {
            total_windows,
            avg_duration_hours,
            total_hours: round_one_decimal(total_hours),
        },
        week_data,
        day_of_week,
        time_of_day,
        duration_trend,
        account_breakdown,
        selected_week_label: format!(
            "{} - {}",
            week_start_local.format("%b %-d"),
            (week_end_local - Duration::days(1)).format("%b %-d")
        ),
        is_current_week: week_start_local == current_week_start,
    })
}

#[tauri::command]
pub async fn get_stats(
    db: State<'_, DbPool>,
    selected_date: String,
    account_id: Option<i64>,
) -> Result<StatsPayload, String> {
    let pool = get_pool(&db).await?;
    get_stats_impl(&pool, selected_date, account_id).await
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::init_test_pool;

    async fn seed_window(
        pool: &SqlitePool,
        account_id: i64,
        started_at: &str,
        ended_at: Option<&str>,
    ) {
        sqlx::query(
            "INSERT INTO windows (account_id, started_at, ended_at, triggered_by) VALUES (?, ?, ?, 'manual')",
        )
        .bind(account_id)
        .bind(started_at)
        .bind(ended_at)
        .execute(pool)
        .await
        .unwrap();
    }

    #[tokio::test]
    async fn get_stats_returns_selected_week_and_trend_data() {
        let pool = init_test_pool().await;
        seed_window(
            &pool,
            1,
            "2026-01-11T10:00:00Z",
            Some("2026-01-11T15:00:00Z"),
        )
        .await;
        seed_window(
            &pool,
            1,
            "2026-01-15T10:00:00Z",
            Some("2026-01-15T14:00:00Z"),
        )
        .await;
        seed_window(
            &pool,
            1,
            "2025-12-28T10:00:00Z",
            Some("2025-12-28T15:00:00Z"),
        )
        .await;

        let stats = get_stats_impl(&pool, "2026-01-15T12:00:00Z".to_string(), None)
            .await
            .unwrap();

        assert_eq!(stats.summary.total_windows, 2);
        assert_eq!(stats.week_data.len(), 7);
        assert_eq!(stats.duration_trend.len(), 8);
        assert_eq!(
            stats.account_breakdown[0].window_count, 2,
            "selected-week account breakdown should ignore older windows"
        );
    }
}
