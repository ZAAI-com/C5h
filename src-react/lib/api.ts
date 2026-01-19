import { invoke } from "@tauri-apps/api/core";
import type {
  Account,
  NewAccount,
  Window,
  NewWindow,
  ScheduledTrigger,
  NewScheduledTrigger,
  Settings,
} from "./types";

// Account commands
export async function getAccounts(): Promise<Account[]> {
  return invoke<Account[]>("get_accounts");
}

export async function createAccount(account: NewAccount): Promise<Account> {
  return invoke<Account>("create_account", { account });
}

export async function updateAccount(account: Account): Promise<void> {
  return invoke<void>("update_account", { account });
}

export async function deleteAccount(id: number): Promise<void> {
  return invoke<void>("delete_account", { id });
}

// Window commands
export async function getWindows(
  from: string,
  to: string,
  accountId?: number
): Promise<Window[]> {
  return invoke<Window[]>("get_windows", {
    from,
    to,
    accountId: accountId ?? null,
  });
}

export async function getCurrentWindow(
  accountId?: number
): Promise<Window | null> {
  return invoke<Window | null>("get_current_window", {
    accountId: accountId ?? null,
  });
}

export async function createWindow(window: NewWindow): Promise<Window> {
  return invoke<Window>("create_window", { window });
}

export async function endWindow(
  id: number,
  usagePercent?: number
): Promise<void> {
  return invoke<void>("end_window", {
    id,
    usagePercent: usagePercent ?? null,
  });
}

// Settings commands
export async function getSettings(): Promise<Settings> {
  return invoke<Settings>("get_settings");
}

export async function saveSettings(settings: Settings): Promise<void> {
  return invoke<void>("save_settings", { settings });
}

// Scheduler commands
export async function getSchedules(
  accountId?: number
): Promise<ScheduledTrigger[]> {
  return invoke<ScheduledTrigger[]>("get_schedules", {
    accountId: accountId ?? null,
  });
}

export async function createSchedule(
  schedule: NewScheduledTrigger
): Promise<ScheduledTrigger> {
  return invoke<ScheduledTrigger>("create_schedule", { schedule });
}

export async function deleteSchedule(id: number): Promise<void> {
  return invoke<void>("delete_schedule", { id });
}

export async function installSchedule(
  id: number,
  cliCommand: string
): Promise<string> {
  return invoke<string>("install_schedule", { id, cliCommand });
}

export async function uninstallSchedule(id: number): Promise<void> {
  return invoke<void>("uninstall_schedule", { id });
}

// Monitor types
export interface DetectedProcess {
  pid: number;
  name: string;
  command: string;
  account_id: number | null;
}

export interface MonitoringStatus {
  is_running: boolean;
  detected_processes: DetectedProcess[];
  last_check: string | null;
}

// Monitor commands
export async function startMonitoring(): Promise<void> {
  return invoke<void>("start_monitoring");
}

export async function stopMonitoring(): Promise<void> {
  return invoke<void>("stop_monitoring");
}

export async function getMonitoringStatus(): Promise<MonitoringStatus> {
  return invoke<MonitoringStatus>("get_monitoring_status");
}

export async function updateMonitorConfig(
  accounts: [number, string][]
): Promise<void> {
  return invoke<void>("update_monitor_config", { accounts });
}

export async function scanCliProcesses(): Promise<DetectedProcess[]> {
  return invoke<DetectedProcess[]>("scan_cli_processes");
}

// Notification commands
export async function notifyWindowEndingSoon(
  accountName: string,
  minutesRemaining: number
): Promise<void> {
  return invoke<void>("notify_window_ending_soon", {
    accountName,
    minutesRemaining,
  });
}

export async function notifyScheduledTrigger(
  accountName: string,
  success: boolean
): Promise<void> {
  return invoke<void>("notify_scheduled_trigger", { accountName, success });
}

export async function notifyWeeklySummary(
  totalWindows: number,
  avgDuration: number
): Promise<void> {
  return invoke<void>("notify_weekly_summary", { totalWindows, avgDuration });
}

export async function sendNotification(
  title: string,
  body: string
): Promise<void> {
  return invoke<void>("send_notification", { title, body });
}

// Helper to format date for API calls
export function formatDateForApi(date: Date): string {
  return date.toISOString();
}

// Helper to get week boundaries
export function getWeekBoundaries(date: Date): { start: string; end: string } {
  const start = new Date(date);
  start.setDate(start.getDate() - start.getDay()); // Start of week (Sunday)
  start.setHours(0, 0, 0, 0);

  const end = new Date(start);
  end.setDate(end.getDate() + 6); // End of week (Saturday)
  end.setHours(23, 59, 59, 999);

  return {
    start: formatDateForApi(start),
    end: formatDateForApi(end),
  };
}
