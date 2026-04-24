import { describe, it, expect, beforeEach, vi } from "vitest";
import { useStore } from "./index";

// Mock the API module
vi.mock("@/lib/api", () => ({
  getAccounts: vi.fn(),
  createAccount: vi.fn(),
  updateAccount: vi.fn(),
  deleteAccount: vi.fn(),
  getWindows: vi.fn(),
  getCurrentWindow: vi.fn(),
  createWindow: vi.fn(),
  endWindow: vi.fn(),
  getSettings: vi.fn(),
  saveSettings: vi.fn(),
  getSchedules: vi.fn(),
  createSchedule: vi.fn(),
  deleteSchedule: vi.fn(),
  installSchedule: vi.fn(),
  uninstallSchedule: vi.fn(),
  updateMonitorConfig: vi.fn(),
  updateTrayTitle: vi.fn(),
  getWeekBoundaries: vi.fn(() => ({
    start: "2024-01-14T00:00:00Z",
    end: "2024-01-21T00:00:00Z",
  })),
}));

import * as api from "@/lib/api";

describe("Store", () => {
  beforeEach(() => {
    // Reset store state before each test
    useStore.setState({
      accounts: [],
      windows: [],
      currentWindow: null,
      schedules: [],
      settings: null,
      selectedDate: new Date("2024-01-15"),
      selectedAccountId: null,
      isLoading: false,
      error: null,
    });
    vi.clearAllMocks();
    vi.mocked(api.updateMonitorConfig).mockResolvedValue(undefined);
    vi.mocked(api.updateTrayTitle).mockResolvedValue(undefined);
  });

  describe("accounts", () => {
    it("should fetch accounts", async () => {
      const mockAccounts = [
        {
          id: 1,
          name: "Claude Code",
          tool_type: "claude",
          cli_command: "claude",
          cli_args: null,
          window_duration_hours: 5,
          color: "#6366f1",
          enabled: true,
        },
      ];

      vi.mocked(api.getAccounts).mockResolvedValueOnce(mockAccounts);

      await useStore.getState().fetchAccounts();

      expect(api.getAccounts).toHaveBeenCalled();
      expect(useStore.getState().accounts).toEqual(mockAccounts);
    });

    it("should create account and refresh list", async () => {
      const mockAccounts = [
        {
          id: 2,
          name: "Codex",
          tool_type: "codex",
          cli_command: "codex",
          cli_args: null,
          window_duration_hours: 5,
          color: "#10a37f",
          enabled: true,
        },
      ];

      vi.mocked(api.createAccount).mockResolvedValueOnce(undefined);
      vi.mocked(api.getAccounts).mockResolvedValueOnce(mockAccounts);

      await useStore.getState().createAccount({
        name: "Codex",
        tool_type: "codex",
        cli_command: "codex",
        cli_args: null,
        window_duration_hours: 5,
        color: "#10a37f",
        enabled: true,
      });

      expect(api.createAccount).toHaveBeenCalled();
      expect(api.getAccounts).toHaveBeenCalled();
      expect(useStore.getState().accounts).toEqual(mockAccounts);
    });

    it("should delete account and refresh list", async () => {
      useStore.setState({
        accounts: [
          {
            id: 1,
            name: "Claude Code",
            tool_type: "claude",
            cli_command: "claude",
            cli_args: null,
            window_duration_hours: 5,
            color: "#6366f1",
            enabled: true,
          },
        ],
      });

      vi.mocked(api.deleteAccount).mockResolvedValueOnce(undefined);
      vi.mocked(api.getAccounts).mockResolvedValueOnce([]);

      await useStore.getState().deleteAccount(1);

      expect(api.deleteAccount).toHaveBeenCalledWith(1);
      expect(useStore.getState().accounts).toHaveLength(0);
    });
  });

  describe("windows", () => {
    it("should fetch windows for date range", async () => {
      const mockWindows = [
        {
          id: 1,
          account_id: 1,
          started_at: "2024-01-15T10:00:00Z",
          ended_at: "2024-01-15T15:00:00Z",
          triggered_by: "manual",
          notes: null,
        },
      ];

      vi.mocked(api.getWindows).mockResolvedValueOnce(mockWindows);

      await useStore
        .getState()
        .fetchWindows("2024-01-14T00:00:00Z", "2024-01-21T00:00:00Z");

      expect(api.getWindows).toHaveBeenCalledWith(
        "2024-01-14T00:00:00Z",
        "2024-01-21T00:00:00Z",
        undefined,
      );
      expect(useStore.getState().windows).toEqual(mockWindows);
    });

    it("should create window and refresh data", async () => {
      const currentWindow = {
        id: 1,
        account_id: 1,
        started_at: "2024-01-15T10:00:00Z",
        ended_at: null,
        triggered_by: "manual",
        notes: null,
      };

      vi.mocked(api.createWindow).mockResolvedValueOnce(undefined);
      vi.mocked(api.getCurrentWindow).mockResolvedValueOnce(currentWindow);
      vi.mocked(api.getWindows).mockResolvedValueOnce([currentWindow]);

      await useStore.getState().createWindow(1, "manual");

      expect(api.createWindow).toHaveBeenCalledWith({
        account_id: 1,
        triggered_by: "manual",
      });
      expect(useStore.getState().currentWindow).toEqual(currentWindow);
    });

    it("should end window and refresh data", async () => {
      useStore.setState({
        currentWindow: {
          id: 1,
          account_id: 1,
          started_at: "2024-01-15T10:00:00Z",
          ended_at: null,
          triggered_by: "manual",
          notes: null,
        },
      });

      vi.mocked(api.endWindow).mockResolvedValueOnce(undefined);
      vi.mocked(api.getCurrentWindow).mockResolvedValueOnce(null);
      vi.mocked(api.getWindows).mockResolvedValueOnce([]);

      await useStore.getState().endWindow(1);

      expect(api.endWindow).toHaveBeenCalledWith(1, undefined);
      expect(useStore.getState().currentWindow).toBeNull();
    });
  });

  describe("selectedDate", () => {
    it("should set selected date", () => {
      const newDate = new Date("2024-02-01");
      useStore.getState().setSelectedDate(newDate);
      expect(useStore.getState().selectedDate).toEqual(newDate);
    });
  });

  describe("settings", () => {
    it("should fetch settings", async () => {
      const mockSettings = {
        theme: "dark",
        launch_at_login: true,
        show_in_menu_bar: true,
        notifications_enabled: true,
        notify_ending_soon: true,
        notify_trigger_status: true,
        notify_weekly_summary: true,
        poll_interval_minutes: 15,
      };

      vi.mocked(api.getSettings).mockResolvedValueOnce(mockSettings);

      await useStore.getState().fetchSettings();

      expect(api.getSettings).toHaveBeenCalled();
      expect(useStore.getState().settings).toEqual(mockSettings);
    });

    it("should save settings", async () => {
      const newSettings = {
        theme: "light",
        launch_at_login: true,
        show_in_menu_bar: true,
        notifications_enabled: true,
        notify_ending_soon: true,
        notify_trigger_status: true,
        notify_weekly_summary: true,
        poll_interval_minutes: 15,
      };

      vi.mocked(api.saveSettings).mockResolvedValueOnce(undefined);

      await useStore.getState().saveSettings(newSettings);

      expect(api.saveSettings).toHaveBeenCalledWith(newSettings);
      expect(api.updateMonitorConfig).toHaveBeenCalledWith([]);
      expect(useStore.getState().settings).toEqual(newSettings);
    });
  });

  describe("error handling", () => {
    it("should set error and rethrow on fetch failure", async () => {
      vi.mocked(api.getAccounts).mockRejectedValueOnce(
        new Error("Network error")
      );

      await expect(useStore.getState().fetchAccounts()).rejects.toThrow(
        "Network error"
      );

      expect(useStore.getState().error).toBe("Network error");
    });
  });
});
