import { create } from "zustand";
import { toast } from "sonner";
import type { Account, Window, ScheduledTrigger, Settings, UsageInfo } from "@/lib/types";
import * as api from "@/lib/api";
import { mapError } from "@/lib/errors";

interface FetchOptions {
  surfaceError?: boolean;
}

function getMappedError(err: unknown): string {
  return mapError(err instanceof Error ? err.message : String(err));
}

interface AppState {
  // Data
  accounts: Account[];
  windows: Window[];
  currentWindow: Window | null;
  schedules: ScheduledTrigger[];
  settings: Settings | null;
  usageByAccount: Record<number, UsageInfo>;

  // UI State
  selectedDate: Date;
  selectedAccountId: number | null;
  isLoading: boolean;
  error: string | null;

  // Actions
  setSelectedDate: (date: Date) => void;
  setSelectedAccountId: (id: number | null) => void;
  setError: (error: string | null) => void;

  // Data Actions
  fetchAccounts: (options?: FetchOptions) => Promise<void>;
  fetchWindows: (from: string, to: string, options?: FetchOptions) => Promise<void>;
  fetchCurrentWindow: (options?: FetchOptions) => Promise<void>;
  fetchSchedules: (options?: FetchOptions) => Promise<void>;
  fetchSettings: (options?: FetchOptions) => Promise<void>;

  // Account Actions
  createAccount: (account: Omit<Account, "id" | "created_at">) => Promise<void>;
  updateAccount: (account: Account) => Promise<void>;
  deleteAccount: (id: number) => Promise<void>;

  // Window Actions
  createWindow: (accountId: number, triggeredBy: string) => Promise<void>;
  endWindow: (id: number, usagePercent?: number) => Promise<void>;

  // Settings Actions
  saveSettings: (settings: Settings) => Promise<void>;

  // Schedule Actions
  createSchedule: (accountId: number, scheduledAt: string) => Promise<void>;
  deleteSchedule: (id: number) => Promise<void>;
  installSchedule: (id: number, cliCommand: string) => Promise<void>;
  uninstallSchedule: (id: number) => Promise<void>;

  // Polling Actions
  fetchUsage: () => Promise<void>;

  // Init
  initialize: () => Promise<void>;
}

const USAGE_REFRESH_INTERVAL_MS = 60_000;
const USAGE_WARNING_COOLDOWN_MS = 5 * 60_000;

let usageRefreshTimer: ReturnType<typeof setInterval> | null = null;
let lastUsageWarning: { message: string | null; timestamp: number } = {
  message: null,
  timestamp: 0,
};

function stopUsageRefreshLoop() {
  if (usageRefreshTimer) {
    clearInterval(usageRefreshTimer);
    usageRefreshTimer = null;
  }
  // Tray title is owned by useTraySync — it derives Idle when currentWindow clears.
}

function syncUsageRefreshLoop(state: Pick<AppState, "currentWindow" | "fetchUsage">) {
  if (!state.currentWindow) {
    stopUsageRefreshLoop();
    return;
  }

  if (usageRefreshTimer) {
    return;
  }

  usageRefreshTimer = setInterval(() => {
    void state.fetchUsage();
  }, USAGE_REFRESH_INTERVAL_MS);
}

export const useStore = create<AppState>((set, get) => ({
  // Initial state
  accounts: [],
  windows: [],
  currentWindow: null,
  schedules: [],
  settings: null,
  usageByAccount: {},
  selectedDate: new Date(),
  selectedAccountId: null,
  isLoading: false,
  error: null,

  // UI Actions
  setSelectedDate: (date) => set({ selectedDate: date }),
  setSelectedAccountId: (id) => set({ selectedAccountId: id }),
  setError: (error) => set({ error }),

  // Data fetch actions
  fetchAccounts: async (options) => {
    try {
      const accounts = await api.getAccounts();
      set({ accounts });
    } catch (err) {
      const mappedError = getMappedError(err);
      if (options?.surfaceError !== false) {
        set({ error: mappedError });
      }
      throw new Error(mappedError);
    }
  },

  fetchWindows: async (from, to, options) => {
    try {
      const { selectedAccountId } = get();
      const windows = await api.getWindows(from, to, selectedAccountId ?? undefined);
      set({ windows });
    } catch (err) {
      const mappedError = getMappedError(err);
      if (options?.surfaceError !== false) {
        set({ error: mappedError });
      }
      throw new Error(mappedError);
    }
  },

  fetchCurrentWindow: async (options) => {
    try {
      const { selectedAccountId } = get();
      const currentWindow = await api.getCurrentWindow(selectedAccountId ?? undefined);
      set({ currentWindow });
      syncUsageRefreshLoop(get());
    } catch (err) {
      const mappedError = getMappedError(err);
      if (options?.surfaceError !== false) {
        set({ error: mappedError });
      }
      throw new Error(mappedError);
    }
  },

  fetchSchedules: async (options) => {
    try {
      const { selectedAccountId } = get();
      const schedules = await api.getSchedules(selectedAccountId ?? undefined);
      set({ schedules });
    } catch (err) {
      const mappedError = getMappedError(err);
      if (options?.surfaceError !== false) {
        set({ error: mappedError });
      }
      throw new Error(mappedError);
    }
  },

  fetchSettings: async (options) => {
    try {
      const settings = await api.getSettings();
      set({ settings });
    } catch (err) {
      const mappedError = getMappedError(err);
      if (options?.surfaceError !== false) {
        set({ error: mappedError });
      }
      throw new Error(mappedError);
    }
  },

  // Account Actions
  createAccount: async (account) => {
    try {
      await api.createAccount(account);
      await get().fetchAccounts({ surfaceError: false });
      toast.success("Account created successfully");
    } catch (err) {
      const mappedError = getMappedError(err);
      set({ error: mappedError });
      toast.error(mappedError);
      throw new Error(mappedError);
    }
  },

  updateAccount: async (account) => {
    try {
      await api.updateAccount(account);
      await get().fetchAccounts({ surfaceError: false });
      toast.success("Account updated successfully");
    } catch (err) {
      const mappedError = getMappedError(err);
      set({ error: mappedError });
      toast.error(mappedError);
      throw new Error(mappedError);
    }
  },

  deleteAccount: async (id) => {
    try {
      await api.deleteAccount(id);
      await get().fetchAccounts({ surfaceError: false });
      toast.success("Account deleted successfully");
    } catch (err) {
      const mappedError = getMappedError(err);
      set({ error: mappedError });
      toast.error(mappedError);
      throw new Error(mappedError);
    }
  },

  // Window Actions
  createWindow: async (accountId, triggeredBy) => {
    try {
      await api.createWindow({ account_id: accountId, triggered_by: triggeredBy });
      await get().fetchCurrentWindow({ surfaceError: false });
      const { selectedDate } = get();
      const { start, end } = api.getWeekBoundaries(selectedDate);
      await get().fetchWindows(start, end, { surfaceError: false });
      toast.success("Window started successfully");
    } catch (err) {
      const mappedError = getMappedError(err);
      set({ error: mappedError });
      toast.error(mappedError);
      throw new Error(mappedError);
    }
  },

  endWindow: async (id, usagePercent) => {
    try {
      await api.endWindow(id, usagePercent);
      await get().fetchCurrentWindow({ surfaceError: false });
      const { selectedDate } = get();
      const { start, end } = api.getWeekBoundaries(selectedDate);
      await get().fetchWindows(start, end, { surfaceError: false });
      toast.success("Window ended successfully");
    } catch (err) {
      const mappedError = getMappedError(err);
      set({ error: mappedError });
      toast.error(mappedError);
      throw new Error(mappedError);
    }
  },

  // Settings Actions
  saveSettings: async (settings) => {
    try {
      await api.saveSettings(settings);
      set({ settings });
      const enabledAccountConfig: [number, string][] = get()
        .accounts
        .filter((account) => account.enabled && account.id != null)
        .map((account) => [account.id!, account.cli_command]);
      await api.updateMonitorConfig(enabledAccountConfig);
      toast.success("Settings saved successfully");
    } catch (err) {
      const mappedError = getMappedError(err);
      set({ error: mappedError });
      toast.error(mappedError);
      throw new Error(mappedError);
    }
  },

  // Schedule Actions
  createSchedule: async (accountId, scheduledAt) => {
    try {
      await api.createSchedule({ account_id: accountId, scheduled_at: scheduledAt });
      await get().fetchSchedules({ surfaceError: false });
      toast.success("Schedule created successfully");
    } catch (err) {
      const mappedError = getMappedError(err);
      set({ error: mappedError });
      toast.error(mappedError);
      throw new Error(mappedError);
    }
  },

  deleteSchedule: async (id) => {
    try {
      await api.deleteSchedule(id);
      await get().fetchSchedules({ surfaceError: false });
      toast.success("Schedule deleted successfully");
    } catch (err) {
      const mappedError = getMappedError(err);
      set({ error: mappedError });
      toast.error(mappedError);
      throw new Error(mappedError);
    }
  },

  installSchedule: async (id, cliCommand) => {
    try {
      await api.installSchedule(id, cliCommand);
      await get().fetchSchedules({ surfaceError: false });
      toast.success("Schedule installed successfully");
    } catch (err) {
      const mappedError = getMappedError(err);
      set({ error: mappedError });
      toast.error(mappedError);
      throw new Error(mappedError);
    }
  },

  uninstallSchedule: async (id) => {
    try {
      await api.uninstallSchedule(id);
      await get().fetchSchedules({ surfaceError: false });
      toast.success("Schedule uninstalled successfully");
    } catch (err) {
      const mappedError = getMappedError(err);
      set({ error: mappedError });
      toast.error(mappedError);
      throw new Error(mappedError);
    }
  },

  // Polling Actions
  fetchUsage: async () => {
    try {
      const results = await api.pollAllAccounts();
      const usageByAccount: Record<number, UsageInfo> = {};
      for (const [accountId, info] of results) {
        usageByAccount[accountId] = info;
      }
      set({ usageByAccount });
      lastUsageWarning = { message: null, timestamp: 0 };
      // Tray title is owned by useTraySync, which reacts to usageByAccount.
    } catch (err) {
      // Polling failures are non-critical — don't set error state
      const message = mapError(err instanceof Error ? err.message : String(err));
      const now = Date.now();
      const shouldWarn =
        lastUsageWarning.message !== message ||
        now - lastUsageWarning.timestamp > USAGE_WARNING_COOLDOWN_MS;

      if (shouldWarn) {
        lastUsageWarning = { message, timestamp: now };
        toast.warning(`Usage polling failed: ${message}`);
      }
    }
  },

  // Initialize app
  initialize: async () => {
    set({ isLoading: true, error: null });
    try {
      // Fetch accounts and settings first — other queries depend on them
      await get().fetchAccounts();
      await get().fetchSettings();
      await get().fetchCurrentWindow({ surfaceError: false });

      const selectedDate = get().selectedDate;
      const { start, end } = api.getWeekBoundaries(selectedDate);

      // Fetch remaining data in parallel; use allSettled so partial failures
      // don't block the entire init
      const results = await Promise.allSettled([
        get().fetchWindows(start, end, { surfaceError: false }),
        get().fetchSchedules({ surfaceError: false }),
        get().fetchUsage(),
        api.purgeOldWindows(),
      ]);

      const failures = results
        .filter((r): r is PromiseRejectedResult => r.status === "rejected")
        .map((r) => (r.reason instanceof Error ? r.reason.message : String(r.reason)));

      if (failures.length > 0) {
        toast.warning(`Some data failed to load: ${failures.join(", ")}`);
      }
    } catch (err) {
      set({ error: getMappedError(err) });
    } finally {
      set({ isLoading: false });
    }
  },
}));
