use serde::{Deserialize, Deserializer, Serialize};
use std::fmt;

/// Deserialize a bool from either a JSON boolean or a SQLite INTEGER (0/1).
///
/// SQLite stores booleans as integers, and `json_object()` reflects that —
/// without this shim, `serde_json::from_value` rejects `Number(1)` for `bool`.
fn bool_from_int<'de, D: Deserializer<'de>>(d: D) -> Result<bool, D::Error> {
    use serde::de::Error;
    let v = serde_json::Value::deserialize(d)?;
    match v {
        serde_json::Value::Bool(b) => Ok(b),
        serde_json::Value::Number(n) => n
            .as_i64()
            .map(|i| i != 0)
            .ok_or_else(|| D::Error::custom(format!("expected integer for bool, got {}", n))),
        other => Err(D::Error::custom(format!(
            "expected bool or integer, got {:?}",
            other
        ))),
    }
}

/// Supported AI tool types
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "snake_case")]
pub enum ToolType {
    #[default]
    #[serde(alias = "claude_code")]
    Claude,
    Codex,
    Gemini,
    Other,
}

impl ToolType {
    pub fn as_str(&self) -> &'static str {
        match self {
            ToolType::Claude => "claude",
            ToolType::Codex => "codex",
            ToolType::Gemini => "gemini",
            ToolType::Other => "other",
        }
    }
}

impl fmt::Display for ToolType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// Account configuration for tracking AI tool usage
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Account {
    pub id: Option<i64>,
    pub name: String,
    pub tool_type: ToolType,
    pub cli_command: String,
    pub cli_args: Option<String>,
    pub window_duration_hours: i32,
    pub color: String,
    #[serde(deserialize_with = "bool_from_int")]
    pub enabled: bool,
    pub created_at: Option<String>,
}

/// Input for creating a new account
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NewAccount {
    pub name: String,
    pub tool_type: ToolType,
    pub cli_command: String,
    pub cli_args: Option<String>,
    pub window_duration_hours: i32,
    pub color: String,
    pub enabled: bool,
}

/// Usage window tracking
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Window {
    pub id: Option<i64>,
    pub account_id: i64,
    pub started_at: String,
    pub ended_at: Option<String>,
    pub triggered_by: String,
    pub usage_percent: Option<i32>,
    pub notes: Option<String>,
    pub created_at: Option<String>,
}

/// Input for creating a new window
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NewWindow {
    pub account_id: i64,
    pub triggered_by: String,
}

/// Application settings
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Settings {
    pub launch_at_login: bool,
    pub show_in_menu_bar: bool,
    pub theme: String,
    pub notifications_enabled: bool,
    pub notify_ending_soon: bool,
    pub notify_trigger_status: bool,
    pub notify_weekly_summary: bool,
    pub poll_interval_minutes: i32,
}

impl Default for Settings {
    fn default() -> Self {
        Settings {
            launch_at_login: true,
            show_in_menu_bar: true,
            theme: "system".to_string(),
            notifications_enabled: true,
            notify_ending_soon: true,
            notify_trigger_status: true,
            notify_weekly_summary: true,
            poll_interval_minutes: 15,
        }
    }
}

/// Scheduled trigger for automatic window starts
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScheduledTrigger {
    pub id: Option<i64>,
    pub account_id: i64,
    pub scheduled_at: String,
    pub status: String,
    pub plist_path: Option<String>,
    pub created_at: Option<String>,
    /// Exit code from the wrapper-script run (None until launchd has fired).
    #[serde(default)]
    pub exit_code: Option<i32>,
    /// UTC timestamp the wrapper started executing the CLI.
    #[serde(default)]
    pub started_at: Option<String>,
    /// UTC timestamp the wrapper finished.
    #[serde(default)]
    pub finished_at: Option<String>,
    /// Last 4KB of stderr from the CLI invocation, truncated for display.
    #[serde(default)]
    pub stderr_tail: Option<String>,
}

/// Input for creating a new scheduled trigger
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NewScheduledTrigger {
    pub account_id: i64,
    pub scheduled_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StatsSummary {
    pub total_windows: i64,
    pub avg_duration_hours: f64,
    pub total_hours: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WeeklyDayStats {
    pub day: String,
    pub date: String,
    pub window_count: i64,
    pub account_counts: std::collections::HashMap<String, i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DayOfWeekStat {
    pub day: String,
    pub count: i64,
    pub intensity: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimeOfDayStat {
    pub hour: String,
    pub count: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DurationTrendPoint {
    pub week: String,
    pub avg_hours: f64,
    pub windows: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AccountBreakdownStat {
    pub account_id: i64,
    pub window_count: i64,
    pub total_hours: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StatsPayload {
    pub summary: StatsSummary,
    pub week_data: Vec<WeeklyDayStats>,
    pub day_of_week: Vec<DayOfWeekStat>,
    pub time_of_day: Vec<TimeOfDayStat>,
    pub duration_trend: Vec<DurationTrendPoint>,
    pub account_breakdown: Vec<AccountBreakdownStat>,
    pub selected_week_label: String,
    pub is_current_week: bool,
}
