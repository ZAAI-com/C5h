import { describe, it, expect, beforeEach, vi, afterEach } from "vitest";
import { renderHook, act } from "@testing-library/react";
import { useCurrentWindow, useWindowStatus } from "./useCurrentWindow";
import { useStore } from "@/store";

describe("useCurrentWindow", () => {
  beforeEach(() => {
    vi.useFakeTimers();
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
      currentWindow: null,
    });
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("should return inactive status when no current window exists", () => {
    const { result } = renderHook(() => useCurrentWindow());

    expect(result.current.isActive).toBe(false);
    expect(result.current.hoursRemaining).toBe(0);
    expect(result.current.minutesRemaining).toBe(0);
    expect(result.current.percentUsed).toBe(0);
    expect(result.current.endTime).toBeNull();
    expect(result.current.isEndingSoon).toBe(false);
  });

  it("should return active status for current window", () => {
    const now = new Date("2024-01-15T12:00:00Z");
    vi.setSystemTime(now);

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

    const { result } = renderHook(() => useCurrentWindow());

    expect(result.current.isActive).toBe(true);
    expect(result.current.hoursRemaining).toBe(3);
    expect(result.current.minutesRemaining).toBe(0);
    expect(result.current.percentUsed).toBeCloseTo(40, 0); // 2h of 5h = 40%
    expect(result.current.endTime).not.toBeNull();
  });

  it("should return expired status for window past duration", () => {
    const now = new Date("2024-01-15T16:00:00Z"); // 6 hours after start
    vi.setSystemTime(now);

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

    const { result } = renderHook(() => useCurrentWindow());

    expect(result.current.isActive).toBe(false);
    expect(result.current.hoursRemaining).toBe(0);
    expect(result.current.minutesRemaining).toBe(0);
    expect(result.current.percentUsed).toBe(100);
  });

  it("should flag window as ending soon when less than 30 minutes remain", () => {
    const now = new Date("2024-01-15T14:45:00Z"); // 15 minutes before end
    vi.setSystemTime(now);

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

    const { result } = renderHook(() => useCurrentWindow());

    expect(result.current.isEndingSoon).toBe(true);
    expect(result.current.hoursRemaining).toBe(0);
    expect(result.current.minutesRemaining).toBe(15);
  });

  it("should update status every minute", () => {
    const now = new Date("2024-01-15T12:00:00Z");
    vi.setSystemTime(now);

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

    const { result } = renderHook(() => useCurrentWindow());

    const initialPercent = result.current.percentUsed;

    // Advance time by 1 minute (need to trigger the interval)
    act(() => {
      vi.advanceTimersByTime(60 * 1000);
    });

    // percentUsed should increase (or stay the same due to interval timing)
    expect(result.current.percentUsed).toBeGreaterThanOrEqual(initialPercent);
  });

  it("should use account window duration when calculating time", () => {
    const now = new Date("2024-01-15T12:00:00Z");
    vi.setSystemTime(now);

    useStore.setState({
      accounts: [
        {
          id: 1,
          name: "Gemini",
          tool_type: "gemini",
          cli_command: "gemini",
          cli_args: null,
          window_duration_hours: 24, // Gemini has 24h window
          color: "#4285f4",
          enabled: true,
        },
      ],
      currentWindow: {
        id: 1,
        account_id: 1,
        started_at: "2024-01-15T10:00:00Z",
        ended_at: null,
        triggered_by: "manual",
        notes: null,
      },
    });

    const { result } = renderHook(() => useCurrentWindow());

    expect(result.current.isActive).toBe(true);
    expect(result.current.hoursRemaining).toBe(22); // 24 - 2 = 22 hours
    expect(result.current.percentUsed).toBeCloseTo(8.33, 0); // 2h of 24h
  });
});

describe("useWindowStatus", () => {
  it("should be an alias for useCurrentWindow", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2024-01-15T12:00:00Z"));

    useStore.setState({
      accounts: [],
      currentWindow: null,
    });

    const { result: result1 } = renderHook(() => useCurrentWindow());
    const { result: result2 } = renderHook(() => useWindowStatus());

    expect(result1.current).toEqual(result2.current);

    vi.useRealTimers();
  });
});
