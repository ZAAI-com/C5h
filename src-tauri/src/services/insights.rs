//! Local-only usage-pattern detection.
//!
//! No network, no ML libs — pure SQL aggregation over the existing `windows`
//! table. Surface the result as a non-intrusive banner: "You usually start a
//! Claude window around 9:14 AM weekdays. Schedule a wake-trigger?"
//!
//! Algorithm: for each enabled account, group the last 60 days of windows
//! by (weekday, 15-minute bucket of started_at) and count occurrences. A
//! bucket with ≥ 4 occurrences in ~8 same-weekday slots is a "habit"
//! (50%+ confidence). Failure mode is silent (no banner) — better than
//! a wrong banner.
//!
//! Public surface:
//! - `compute_insights(pool)` — pure read, returns top-N undismissed insights.
//! - `dismiss(pool, key)`     — persist a hash so we don't nag.

use serde::Serialize;
use sqlx::SqlitePool;

const LOOKBACK_DAYS: i64 = 60;
const MIN_OCCURRENCES: i64 = 4;
const ASSUMED_WEEKLY_SLOTS: f64 = 8.0; // 60 / 7 ≈ 8.57 → use 8 for confidence
const MAX_INSIGHTS: usize = 3;

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct Insight {
    pub kind: String,
    pub key: String,
    pub account_id: i64,
    pub account_name: String,
    pub weekday: i32,
    pub hour: i32,
    pub minute: i32,
    pub occurrences: i64,
    pub confidence: f64,
}

/// Stable identifier used for dismissal so a recomputed habit at the same
/// (account, weekday, bucket) keeps its dismissed-state across restarts.
pub fn insight_key(kind: &str, account_id: i64, weekday: i32, hour: i32, minute: i32) -> String {
    format!("{}:{}:{}:{:02}:{:02}", kind, account_id, weekday, hour, minute)
}

/// Compute insights across all enabled accounts. Returns at most `MAX_INSIGHTS`
/// undismissed insights, sorted by descending confidence.
pub async fn compute_insights(pool: &SqlitePool) -> Result<Vec<Insight>, String> {
    let rows: Vec<(i64, String, i64, i64, i64, i64)> = sqlx::query_as(
        "SELECT
            w.account_id,
            a.name,
            CAST(strftime('%w', w.started_at, 'localtime') AS INTEGER) AS weekday,
            CAST(strftime('%H', w.started_at, 'localtime') AS INTEGER) AS hour,
            (CAST(strftime('%M', w.started_at, 'localtime') AS INTEGER) / 15) * 15 AS minute,
            COUNT(*) AS occurrences
         FROM windows w
         JOIN accounts a ON a.id = w.account_id
         WHERE a.enabled = 1
           AND w.started_at >= datetime('now', ?)
         GROUP BY w.account_id, weekday, hour, minute
         HAVING occurrences >= ?
         ORDER BY occurrences DESC",
    )
    .bind(format!("-{} days", LOOKBACK_DAYS))
    .bind(MIN_OCCURRENCES)
    .fetch_all(pool)
    .await
    .map_err(|e| format!("compute_insights query: {}", e))?;

    let dismissed_keys: Vec<String> = sqlx::query_scalar(
        "SELECT insight_key FROM dismissed_insights",
    )
    .fetch_all(pool)
    .await
    .map_err(|e| format!("read dismissed_insights: {}", e))?;
    let dismissed: std::collections::HashSet<String> = dismissed_keys.into_iter().collect();

    let mut out = Vec::new();
    for (account_id, account_name, weekday, hour, minute, occurrences) in rows {
        let weekday = weekday as i32;
        let hour = hour as i32;
        let minute = minute as i32;
        let key = insight_key("habit", account_id, weekday, hour, minute);
        if dismissed.contains(&key) {
            continue;
        }

        let confidence = (occurrences as f64 / ASSUMED_WEEKLY_SLOTS).min(1.0);
        out.push(Insight {
            kind: "habit".to_string(),
            key,
            account_id,
            account_name,
            weekday,
            hour,
            minute,
            occurrences,
            confidence,
        });

        if out.len() >= MAX_INSIGHTS {
            break;
        }
    }
    Ok(out)
}

pub async fn dismiss(pool: &SqlitePool, insight_key: &str) -> Result<(), String> {
    sqlx::query(
        "INSERT OR REPLACE INTO dismissed_insights (insight_key, dismissed_at)
         VALUES (?, datetime('now'))",
    )
    .bind(insight_key)
    .execute(pool)
    .await
    .map(|_| ())
    .map_err(|e| format!("dismiss_insight: {}", e))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::init_test_pool;
    use chrono::{Duration, Local, TimeZone};

    /// Insert N synthetic windows for `account_id` at the given local
    /// weekday/time across the last `weeks` weeks. The SQL uses `'localtime'`
    /// to bucket, so seeded times must be expressed in local TZ for the
    /// assertions on hour/minute to be timezone-independent.
    async fn seed_habit(pool: &SqlitePool, account_id: i64, hour: u32, minute: u32, weeks: usize) {
        let now = Local::now();
        for w in 0..weeks {
            let day_offset = (w as i64) * 7;
            let day = (now - Duration::days(day_offset)).date_naive();
            let started_local = Local
                .from_local_datetime(&day.and_hms_opt(hour, minute, 0).unwrap())
                .single()
                .expect("unambiguous local datetime");
            let ended_local = started_local + Duration::hours(2);
            sqlx::query(
                "INSERT INTO windows (account_id, started_at, ended_at, triggered_by)
                 VALUES (?, ?, ?, 'manual')",
            )
            .bind(account_id)
            .bind(started_local.to_rfc3339())
            .bind(ended_local.to_rfc3339())
            .execute(pool)
            .await
            .unwrap();
        }
    }

    #[tokio::test]
    async fn compute_returns_empty_when_no_windows() {
        let pool = init_test_pool().await;
        let insights = compute_insights(&pool).await.unwrap();
        assert!(insights.is_empty());
    }

    #[tokio::test]
    async fn compute_detects_a_habit_with_enough_occurrences() {
        let pool = init_test_pool().await;
        // 6 windows at the same time-of-day → above the 4-occurrence floor.
        seed_habit(&pool, 1, 9, 15, 6).await;

        let insights = compute_insights(&pool).await.unwrap();
        assert!(
            !insights.is_empty(),
            "expected a habit insight, got {:?}",
            insights
        );
        let first = &insights[0];
        assert_eq!(first.kind, "habit");
        assert_eq!(first.account_id, 1);
        assert_eq!(first.hour, 9);
        // strftime quantization in our SQL puts 9:15 in the 15-minute bucket.
        assert_eq!(first.minute, 15);
        assert!(first.occurrences >= 6);
        assert!(first.confidence >= 0.5);
    }

    #[tokio::test]
    async fn compute_skips_dismissed_insights() {
        let pool = init_test_pool().await;
        seed_habit(&pool, 1, 9, 15, 6).await;

        // Compute once to discover the key, then dismiss and re-compute.
        let initial = compute_insights(&pool).await.unwrap();
        let target_key = initial[0].key.clone();
        dismiss(&pool, &target_key).await.unwrap();

        let after = compute_insights(&pool).await.unwrap();
        assert!(after.iter().all(|i| i.key != target_key));
    }

    #[tokio::test]
    async fn random_data_does_not_produce_insights() {
        let pool = init_test_pool().await;
        // Three windows spread across very different times — should not cluster.
        for (h, m) in &[(3u32, 0u32), (14, 30), (21, 45)] {
            seed_habit(&pool, 1, *h, *m, 1).await;
        }
        let insights = compute_insights(&pool).await.unwrap();
        assert!(insights.is_empty(), "got noise: {:?}", insights);
    }

    #[test]
    fn insight_key_is_stable() {
        let a = insight_key("habit", 1, 3, 9, 15);
        let b = insight_key("habit", 1, 3, 9, 15);
        assert_eq!(a, b);
        assert_ne!(a, insight_key("habit", 1, 3, 9, 30));
    }
}
