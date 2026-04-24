import { describe, expect, it, vi, beforeEach } from "vitest";
import { act, renderHook } from "@testing-library/react";
import { useWindowEndingAlert } from "./useWindowEndingAlert";
import { useStore } from "@/store";
import * as api from "@/lib/api";

vi.mock("@/lib/api", async () => {
  const actual = await vi.importActual<typeof import("@/lib/api")>("@/lib/api");
  return {
    ...actual,
    notifyWindowEndingSoon: vi.fn(),
  };
});

vi.mock("./useCurrentWindow", () => ({
  useCurrentWindow: vi.fn(),
}));

import { useCurrentWindow } from "./useCurrentWindow";

const account = {
  id: 1,
  name: "Claude Code",
  tool_type: "claude",
  cli_command: "claude",
  cli_args: null,
  window_duration_hours: 5,
  color: "#000",
  enabled: true,
};

const activeWindow = {
  id: 100,
  account_id: 1,
  started_at: "2024-01-15T10:00:00Z",
  ended_at: null,
  triggered_by: "manual",
  notes: null,
};

const enabledSettings = {
  launch_at_login: false,
  show_in_menu_bar: true,
  theme: "system",
  notifications_enabled: true,
  notify_ending_soon: true,
  notify_trigger_status: true,
  notify_weekly_summary: true,
  poll_interval_minutes: 15,
};

function setStatus(opts: { isActive: boolean; hours: number; minutes: number }) {
  vi.mocked(useCurrentWindow).mockReturnValue({
    isActive: opts.isActive,
    hoursRemaining: opts.hours,
    minutesRemaining: opts.minutes,
    percentUsed: 0,
    endTime: null,
    isEndingSoon: false,
  });
}

describe("useWindowEndingAlert", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(api.notifyWindowEndingSoon).mockResolvedValue(undefined);
    useStore.setState({
      accounts: [account],
      currentWindow: activeWindow,
      settings: enabledSettings,
    });
  });

  it("fires 30-minute notification when 16-30 minutes remain", () => {
    setStatus({ isActive: true, hours: 0, minutes: 25 });

    renderHook(() => useWindowEndingAlert());

    expect(api.notifyWindowEndingSoon).toHaveBeenCalledWith("Claude Code", 30);
  });

  it("fires 15-minute notification when 1-15 minutes remain", () => {
    setStatus({ isActive: true, hours: 0, minutes: 10 });

    renderHook(() => useWindowEndingAlert());

    expect(api.notifyWindowEndingSoon).toHaveBeenCalledWith("Claude Code", 15);
  });

  it("does not fire when more than 30 minutes remain", () => {
    setStatus({ isActive: true, hours: 1, minutes: 0 });

    renderHook(() => useWindowEndingAlert());

    expect(api.notifyWindowEndingSoon).not.toHaveBeenCalled();
  });

  it("does not fire when window is not active", () => {
    setStatus({ isActive: false, hours: 0, minutes: 10 });

    renderHook(() => useWindowEndingAlert());

    expect(api.notifyWindowEndingSoon).not.toHaveBeenCalled();
  });

  it("does not fire when notifications are disabled globally", () => {
    useStore.setState({
      settings: { ...enabledSettings, notifications_enabled: false },
    });
    setStatus({ isActive: true, hours: 0, minutes: 10 });

    renderHook(() => useWindowEndingAlert());

    expect(api.notifyWindowEndingSoon).not.toHaveBeenCalled();
  });

  it("does not fire when notify_ending_soon is disabled", () => {
    useStore.setState({
      settings: { ...enabledSettings, notify_ending_soon: false },
    });
    setStatus({ isActive: true, hours: 0, minutes: 10 });

    renderHook(() => useWindowEndingAlert());

    expect(api.notifyWindowEndingSoon).not.toHaveBeenCalled();
  });

  it("does not re-fire 30-min alert on re-render for same window", () => {
    setStatus({ isActive: true, hours: 0, minutes: 25 });
    const { rerender } = renderHook(() => useWindowEndingAlert());

    expect(api.notifyWindowEndingSoon).toHaveBeenCalledTimes(1);

    setStatus({ isActive: true, hours: 0, minutes: 20 });
    rerender();

    expect(api.notifyWindowEndingSoon).toHaveBeenCalledTimes(1);
  });

  it("fires both 30 and 15 min alerts as time passes within same window", () => {
    setStatus({ isActive: true, hours: 0, minutes: 25 });
    const { rerender } = renderHook(() => useWindowEndingAlert());

    expect(api.notifyWindowEndingSoon).toHaveBeenCalledWith("Claude Code", 30);
    expect(api.notifyWindowEndingSoon).toHaveBeenCalledTimes(1);

    setStatus({ isActive: true, hours: 0, minutes: 10 });
    rerender();

    expect(api.notifyWindowEndingSoon).toHaveBeenCalledWith("Claude Code", 15);
    expect(api.notifyWindowEndingSoon).toHaveBeenCalledTimes(2);
  });

  it("uses 'Unknown' when account is not found", () => {
    useStore.setState({ accounts: [] });
    setStatus({ isActive: true, hours: 0, minutes: 25 });

    renderHook(() => useWindowEndingAlert());

    expect(api.notifyWindowEndingSoon).toHaveBeenCalledWith("Unknown", 30);
  });

  it("resets state when current window changes", () => {
    setStatus({ isActive: true, hours: 0, minutes: 25 });
    const { rerender } = renderHook(() => useWindowEndingAlert());

    expect(api.notifyWindowEndingSoon).toHaveBeenCalledTimes(1);

    // New window with same time-remaining should re-fire 30-min alert
    act(() => {
      useStore.setState({
        currentWindow: { ...activeWindow, id: 200 },
      });
    });
    setStatus({ isActive: true, hours: 0, minutes: 25 });
    rerender();

    expect(api.notifyWindowEndingSoon).toHaveBeenCalledTimes(2);
  });
});
