// TypeScript types matching Rust models

export interface Account {
  id?: number;
  name: string;
  tool_type: string;
  cli_command: string;
  cli_args?: string;
  window_duration_hours: number;
  color: string;
  enabled: boolean;
  created_at?: string;
}

export interface NewAccount {
  name: string;
  tool_type: string;
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

// Utility types
export type ToolType = "claude" | "codex" | "gemini";

export interface WindowWithAccount extends Window {
  account?: Account;
}

// Statistics types
export interface DayStats {
  date: string;
  windows_count: number;
  total_hours: number;
}

export interface WindowStats {
  total_windows: number;
  avg_duration_hours: number;
  total_hours: number;
  windows_this_week: number;
}
