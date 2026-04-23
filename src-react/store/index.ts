import { create } from "zustand";
import { toast } from "sonner";
import type { Account, Window, ScheduledTrigger, Settings, UsageInfo } from "@/lib/types";
import * as api from "@/lib/api";
import { mapError } from "@/lib/errors";

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
  fetchAccounts: () => Promise<void>;
  fetchWindows: (from: string, to: string) => Promise<void>;
  fetchCurrentWindow: () => Promise<void>;
  fetchSchedules: () => Promise<void>;
  fetchSettings: () => Promise<void>;

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
  fetchAccounts: async () => {
    try {
      const accounts = await api.getAccounts();
      set({ accounts });
    } catch (err) {
      set({ error: err instanceof Error ? err.message : String(err) });
    }
  },

  fetchWindows: async (from, to) => {
    try {
      const { selectedAccountId } = get();
      const windows = await api.getWindows(from, to, selectedAccountId ?? undefined);
      set({ windows });
    } catch (err) {
      set({ error: err instanceof Error ? err.message : String(err) });
    }
  },

  fetchCurrentWindow: async () => {
    try {
      const { selectedAccountId } = get();
      const currentWindow = await api.getCurrentWindow(selectedAccountId ?? undefined);
      set({ currentWindow });
    } catch (err) {
      set({ error: err instanceof Error ? err.message : String(err) });
    }
  },

  fetchSchedules: async () => {
    try {
      const { selectedAccountId } = get();
      const schedules = await api.getSchedules(selectedAccountId ?? undefined);
      set({ schedules });
    } catch (err) {
      set({ error: err instanceof Error ? err.message : String(err) });
    }
  },

  fetchSettings: async () => {
    try {
      const settings = await api.getSettings();
      set({ settings });
    } catch (err) {
      set({ error: err instanceof Error ? err.message : String(err) });
    }
  },

  // Account Actions
  createAccount: async (account) => {
    try {
      await api.createAccount(account);
      await get().fetchAccounts();
      toast.success("Account created successfully");
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      set({ error: message });
      toast.error(mapError(message));
      throw err;
    }
  },

  updateAccount: async (account) => {
    try {
      await api.updateAccount(account);
      await get().fetchAccounts();
      toast.success("Account updated successfully");
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      set({ error: message });
      toast.error(mapError(message));
      throw err;
    }
  },

  deleteAccount: async (id) => {
    try {
      await api.deleteAccount(id);
      await get().fetchAccounts();
      toast.success("Account deleted successfully");
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      set({ error: message });
      toast.error(mapError(message));
      throw err;
    }
  },

  // Window Actions
  createWindow: async (accountId, triggeredBy) => {
    try {
      await api.createWindow({ account_id: accountId, triggered_by: triggeredBy });
      await get().fetchCurrentWindow();
      const { selectedDate } = get();
      const { start, end } = api.getWeekBoundaries(selectedDate);
      await get().fetchWindows(start, end);
      toast.success("Window started successfully");
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      set({ error: message });
      toast.error(mapError(message));
      throw err;
    }
  },

  endWindow: async (id, usagePercent) => {
    try {
      await api.endWindow(id, usagePercent);
      await get().fetchCurrentWindow();
      const { selectedDate } = get();
      const { start, end } = api.getWeekBoundaries(selectedDate);
      await get().fetchWindows(start, end);
      toast.success("Window ended successfully");
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      set({ error: message });
      toast.error(mapError(message));
      throw err;
    }
  },

  // Settings Actions
  saveSettings: async (settings) => {
    try {
      await api.saveSettings(settings);
      set({ settings });
      toast.success("Settings saved successfully");
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      set({ error: message });
      toast.error(mapError(message));
      throw err;
    }
  },

  // Schedule Actions
  createSchedule: async (accountId, scheduledAt) => {
    try {
      await api.createSchedule({ account_id: accountId, scheduled_at: scheduledAt });
      await get().fetchSchedules();
      toast.success("Schedule created successfully");
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      set({ error: message });
      toast.error(mapError(message));
      throw err;
    }
  },

  deleteSchedule: async (id) => {
    try {
      await api.deleteSchedule(id);
      await get().fetchSchedules();
      toast.success("Schedule deleted successfully");
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      set({ error: message });
      toast.error(mapError(message));
      throw err;
    }
  },

  installSchedule: async (id, cliCommand) => {
    try {
      await api.installSchedule(id, cliCommand);
      await get().fetchSchedules();
      toast.success("Schedule installed successfully");
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      set({ error: message });
      toast.error(mapError(message));
      throw err;
    }
  },

  uninstallSchedule: async (id) => {
    try {
      await api.uninstallSchedule(id);
      await get().fetchSchedules();
      toast.success("Schedule uninstalled successfully");
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      set({ error: message });
      toast.error(mapError(message));
      throw err;
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

      // Update tray title with active account's usage %
      const { currentWindow } = get();
      if (currentWindow) {
        const usage = usageByAccount[currentWindow.account_id];
        if (usage?.session_percent != null) {
          api.updateTrayTitle(`${Math.round(usage.session_percent)}%`).catch(() => {});
        }
      } else {
        api.updateTrayTitle(null).catch(() => {});
      }
    } catch (err) {
      // Polling failures are non-critical — don't set error state
      const message = err instanceof Error ? err.message : String(err);
      toast.warning(`Usage polling failed: ${mapError(message)}`);
    }
  },

  // Initialize app
  initialize: async () => {
    set({ isLoading: true, error: null });
    try {
      // Fetch accounts and settings first — other queries depend on them
      await get().fetchAccounts();
      await get().fetchSettings();

      const selectedDate = new Date();
      const { start, end } = api.getWeekBoundaries(selectedDate);

      // Fetch remaining data in parallel; use allSettled so partial failures
      // don't block the entire init
      const results = await Promise.allSettled([
        get().fetchCurrentWindow(),
        get().fetchWindows(start, end),
        get().fetchSchedules(),
        api.purgeOldWindows(),
      ]);

      const failures = results
        .filter((r): r is PromiseRejectedResult => r.status === "rejected")
        .map((r) => (r.reason instanceof Error ? r.reason.message : String(r.reason)));

      if (failures.length > 0) {
        toast.warning(`Some data failed to load: ${failures.join(", ")}`);
      }
    } catch (err) {
      set({ error: err instanceof Error ? err.message : String(err) });
    } finally {
      set({ isLoading: false });
    }
  },
}));
