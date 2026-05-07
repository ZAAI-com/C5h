import { invoke } from "@tauri-apps/api/core";
import type {
  Account,
  NewAccount,
  Window,
  NewWindow,
  ScheduledTrigger,
  NewScheduledTrigger,
  Settings,
  StatsPayload,
  UsageInfo,
} from "./types";

export type AppErrorCode = "ipc" | "timeout" | "aborted";

export interface InvokeOptions {
  signal?: AbortSignal;
  timeoutMs?: number;
}

export class AppError extends Error {
  code: AppErrorCode;
  details?: unknown;

  constructor(code: AppErrorCode, message: string, details?: unknown) {
    super(message);
    this.name = "AppError";
    this.code = code;
    this.details = details;
  }

  static from(error: unknown): AppError {
    if (error instanceof AppError) {
      return error;
    }

    if (typeof error === "string") {
      return new AppError("ipc", error, { raw: error });
    }

    if (error instanceof Error) {
      return new AppError("ipc", error.message, { cause: error });
    }

    return new AppError("ipc", "Unexpected application error", { raw: error });
  }
}

async function invokeWithTimeout<T>(
  cmd: string,
  args?: Record<string, unknown>,
  options: InvokeOptions = {}
): Promise<T> {
  const { signal, timeoutMs = 30_000 } = options;

  if (signal?.aborted) {
    throw new AppError("aborted", "Request was cancelled", { cmd });
  }

  return new Promise<T>((resolve, reject) => {
    let settled = false;

    const abortHandler = () => {
      if (settled) {
        return;
      }

      settled = true;
      cleanup();
      reject(new AppError("aborted", "Request was cancelled", { cmd }));
    };

    const timeoutId = setTimeout(() => {
      if (settled) {
        return;
      }

      settled = true;
      cleanup();
      reject(new AppError("timeout", "Request timed out", { cmd, timeoutMs }));
    }, timeoutMs);

    const cleanup = () => {
      clearTimeout(timeoutId);
      if (signal) {
        signal.removeEventListener("abort", abortHandler);
      }
    };

    if (signal) {
      signal.addEventListener("abort", abortHandler, { once: true });
    }

    const request = args === undefined ? invoke<T>(cmd) : invoke<T>(cmd, args);

    request
      .then((value) => {
        if (settled) {
          return;
        }

        settled = true;
        cleanup();
        resolve(value);
      })
      .catch((error) => {
        if (settled) {
          return;
        }

        settled = true;
        cleanup();
        reject(AppError.from(error));
      });
  });
}

// Account commands
export async function getAccounts(): Promise<Account[]> {
  return invokeWithTimeout<Account[]>("get_accounts");
}

export async function createAccount(account: NewAccount): Promise<Account> {
  return invokeWithTimeout<Account>("create_account", { account });
}

export async function updateAccount(account: Account): Promise<void> {
  return invokeWithTimeout<void>("update_account", { account });
}

export async function deleteAccount(id: number): Promise<void> {
  return invokeWithTimeout<void>("delete_account", { id });
}

// Window commands
export async function getWindows(
  from: string,
  to: string,
  accountId?: number,
  options?: InvokeOptions
): Promise<Window[]> {
  return invokeWithTimeout<Window[]>("get_windows", {
    from,
    to,
    accountId: accountId ?? null,
  }, options);
}

export async function getCurrentWindow(
  accountId?: number
): Promise<Window | null> {
  return invokeWithTimeout<Window | null>("get_current_window", {
    accountId: accountId ?? null,
  });
}

export async function createWindow(window: NewWindow): Promise<Window> {
  return invokeWithTimeout<Window>("create_window", { window });
}

export async function endWindow(
  id: number,
  usagePercent?: number
): Promise<void> {
  return invokeWithTimeout<void>("end_window", {
    id,
    usagePercent: usagePercent ?? null,
  });
}

// Settings commands
export async function getSettings(): Promise<Settings> {
  return invokeWithTimeout<Settings>("get_settings");
}

export async function saveSettings(settings: Settings): Promise<void> {
  return invokeWithTimeout<void>("save_settings", { settings });
}

// Scheduler commands
export async function getSchedules(
  accountId?: number
): Promise<ScheduledTrigger[]> {
  return invokeWithTimeout<ScheduledTrigger[]>("get_schedules", {
    accountId: accountId ?? null,
  });
}

export async function createSchedule(
  schedule: NewScheduledTrigger
): Promise<ScheduledTrigger> {
  return invokeWithTimeout<ScheduledTrigger>("create_schedule", { schedule });
}

export async function getStats(
  selectedDate: string,
  accountId?: number,
  options?: InvokeOptions
): Promise<StatsPayload> {
  return invokeWithTimeout<StatsPayload>(
    "get_stats",
    {
      selectedDate,
      accountId: accountId ?? null,
    },
    options
  );
}

export async function deleteSchedule(id: number): Promise<void> {
  return invokeWithTimeout<void>("delete_schedule", { id });
}

export async function installSchedule(
  id: number,
  cliCommand: string
): Promise<string> {
  return invokeWithTimeout<string>("install_schedule", { id, cliCommand });
}

export async function uninstallSchedule(id: number): Promise<void> {
  return invokeWithTimeout<void>("uninstall_schedule", { id });
}

// Polling commands
export async function pollAccount(accountId: number): Promise<UsageInfo> {
  return invokeWithTimeout<UsageInfo>("poll_account", { accountId });
}

export async function pollAllAccounts(
  options?: InvokeOptions
): Promise<[number, UsageInfo][]> {
  return invokeWithTimeout<[number, UsageInfo][]>("poll_all_accounts", undefined, options);
}

export async function checkCliAvailability(
  commands: string[]
): Promise<[string, boolean, string | null][]> {
  return invokeWithTimeout<[string, boolean, string | null][]>("check_cli_availability", {
    commands,
  });
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
  return invokeWithTimeout<void>("start_monitoring");
}

export async function stopMonitoring(): Promise<void> {
  return invokeWithTimeout<void>("stop_monitoring");
}

export async function getMonitoringStatus(): Promise<MonitoringStatus> {
  return invokeWithTimeout<MonitoringStatus>("get_monitoring_status");
}

export async function updateMonitorConfig(
  accounts: [number, string][]
): Promise<void> {
  return invokeWithTimeout<void>("update_monitor_config", { accounts });
}

export async function scanCliProcesses(): Promise<DetectedProcess[]> {
  return invokeWithTimeout<DetectedProcess[]>("scan_cli_processes");
}

// Notification commands
export async function notifyWindowEndingSoon(
  accountName: string,
  minutesRemaining: number
): Promise<void> {
  return invokeWithTimeout<void>("notify_window_ending_soon", {
    accountName,
    minutesRemaining,
  });
}

export async function notifyScheduledTrigger(
  accountName: string,
  success: boolean
): Promise<void> {
  return invokeWithTimeout<void>("notify_scheduled_trigger", { accountName, success });
}

export async function notifyWeeklySummary(
  totalWindows: number,
  avgDuration: number
): Promise<void> {
  return invokeWithTimeout<void>("notify_weekly_summary", { totalWindows, avgDuration });
}

export async function sendNotification(
  title: string,
  body: string
): Promise<void> {
  return invokeWithTimeout<void>("send_notification", { title, body });
}

// Data retention
export async function purgeOldWindows(retentionDays?: number): Promise<number> {
  return invokeWithTimeout<number>("purge_old_windows", {
    retentionDays: retentionDays ?? null,
  });
}

// Tray commands
export async function updateTrayTitle(text: string | null): Promise<void> {
  return invokeWithTimeout<void>("update_tray_title", { text });
}

export type TrayState =
  | { kind: "idle" }
  | { kind: "active"; percent: number | null; minutes_remaining: number | null }
  | { kind: "multi_window"; entries: Array<{ percent: number }> }
  | { kind: "error"; message: string };

export async function updateTrayState(state: TrayState, reducedMotion = false): Promise<void> {
  return invokeWithTimeout<void>("update_tray_state", { state, reducedMotion });
}

// Login-item registration on macOS. Reconciles OS state with the persisted
// launch_at_login setting; called from the Settings UI when the toggle changes.
export async function setAutostart(enabled: boolean): Promise<void> {
  return invokeWithTimeout<void>("set_autostart", { enabled });
}

export async function isAutostartEnabled(): Promise<boolean> {
  return invokeWithTimeout<boolean>("is_autostart_enabled");
}

export async function quitApp(): Promise<void> {
  return invokeWithTimeout<void>("quit_app");
}

// Onboarding completion flag
export async function isOnboardingCompleted(): Promise<boolean> {
  return invokeWithTimeout<boolean>("is_onboarding_completed");
}

export async function markOnboardingCompleted(): Promise<void> {
  return invokeWithTimeout<void>("mark_onboarding_completed");
}

// Predictive insights (local-only)
export interface Insight {
  kind: string;
  key: string;
  account_id: number;
  account_name: string;
  weekday: number; // 0=Sunday
  hour: number;
  minute: number;
  occurrences: number;
  confidence: number;
}

export async function getInsights(): Promise<Insight[]> {
  return invokeWithTimeout<Insight[]>("get_insights");
}

export async function dismissInsight(insightKey: string): Promise<void> {
  return invokeWithTimeout<void>("dismiss_insight", { insightKey });
}

export async function showMainWindow(
  tab?: "calendar" | "stats" | "settings"
): Promise<void> {
  return invokeWithTimeout<void>("show_main_window", { tab: tab ?? null });
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
