export type ToolType =
  | "claude"
  | "codex"
  | "gemini"
  | "other"
  | "claude_code";

// TypeScript types matching Rust models

export interface Account {
  id?: number;
  name: string;
  tool_type: ToolType;
  cli_command: string;
  cli_args?: string;
  window_duration_hours: number;
  color: string;
  enabled: boolean;
  created_at?: string;
}

export interface NewAccount {
  name: string;
  tool_type: ToolType;
  cli_command: string;
  cli_args?: string;
  window_duration_hours: number;
  color: string;
  enabled: boolean;
}

export interface Window {
  id?: number;
  account_id: number;
  started_at: string;
  ended_at?: string;
  triggered_by: string;
  usage_percent?: number;
  notes?: string;
  created_at?: string;
}

export interface NewWindow {
  account_id: number;
  triggered_by: string;
}

export interface ScheduledTrigger {
  id?: number;
  account_id: number;
  scheduled_at: string;
  status: string;
  plist_path?: string;
  created_at?: string;
}

export interface NewScheduledTrigger {
  account_id: number;
  scheduled_at: string;
}

export interface Settings {
  launch_at_login: boolean;
  show_in_menu_bar: boolean;
  theme: string;
  notifications_enabled: boolean;
  notify_ending_soon: boolean;
  notify_trigger_status: boolean;
  notify_weekly_summary: boolean;
  poll_interval_minutes: number;
}

// Usage data from CLI polling
export interface UsageInfo {
  session_percent: number | null;
  weekly_percent: number | null;
  reset_time: string | null;
  weekly_reset_time: string | null;
}

// CLI availability check result
export interface CliAvailability {
  command: string;
  available: boolean;
  resolved_path: string | null;
}

export interface WindowWithAccount extends Window {
  account?: Account;
}

export interface StatsSummary {
  total_windows: number;
  avg_duration_hours: number;
  total_hours: number;
}

export interface WeeklyDayStats {
  day: string;
  date: string;
  window_count: number;
  account_counts: Record<string, number>;
}

export interface DayOfWeekStat {
  day: string;
  count: number;
  intensity: number;
}

export interface TimeOfDayStat {
  hour: string;
  count: number;
}

export interface DurationTrendPoint {
  week: string;
  avg_hours: number;
  windows: number;
}

export interface AccountBreakdownStat {
  account_id: number;
  window_count: number;
  total_hours: number;
}

export interface StatsPayload {
  summary: StatsSummary;
  week_data: WeeklyDayStats[];
  day_of_week: DayOfWeekStat[];
  time_of_day: TimeOfDayStat[];
  duration_trend: DurationTrendPoint[];
  account_breakdown: AccountBreakdownStat[];
  selected_week_label: string;
  is_current_week: boolean;
}
