import { describe, expect, it, vi, beforeEach } from "vitest";
import { fireEvent, render, screen } from "@testing-library/react";
import { PopoverWindow } from "./PopoverWindow";
import { useStore } from "@/app/store";

vi.mock("@/features/windows/useCurrentWindow", () => ({
  useCurrentWindow: vi.fn(),
}));
vi.mock("@/shared/api/api", () => ({
  showMainWindow: vi.fn().mockResolvedValue(undefined),
}));

import { useCurrentWindow } from "@/features/windows/useCurrentWindow";
import * as api from "@/shared/api/api";

const account = {
  id: 1,
  name: "Claude Code",
  tool_type: "claude",
  cli_command: "claude",
  cli_args: null,
  window_duration_hours: 5,
  color: "#6366f1",
  enabled: true,
};

describe("PopoverWindow", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    useStore.setState({
      accounts: [account],
      currentWindow: null,
      schedules: [],
      windows: [],
      usageByAccount: {},
      initialize: vi.fn().mockResolvedValue(undefined),
      createWindow: vi.fn().mockResolvedValue(undefined),
    });
  });

  it("shows 'No active window' when no current window", () => {
    vi.mocked(useCurrentWindow).mockReturnValue({
      isActive: false,
      hoursRemaining: 0,
      minutesRemaining: 0,
      percentUsed: 0,
      endTime: null,
      isEndingSoon: false,
    });
    render(<PopoverWindow />);
    expect(screen.getByText(/no active window/i)).toBeInTheDocument();
  });

  it("shows account name and percent used when active", () => {
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
    vi.mocked(useCurrentWindow).mockReturnValue({
      isActive: true,
      hoursRemaining: 3,
      minutesRemaining: 0,
      percentUsed: 40,
      endTime: new Date("2024-01-15T15:00:00Z"),
      isEndingSoon: false,
    });
    render(<PopoverWindow />);
    expect(screen.getByText("Claude Code")).toBeInTheDocument();
    expect(screen.getByText(/40% used/)).toBeInTheDocument();
  });

  it("prefers session_percent from CLI polling over time-based percent", () => {
    useStore.setState({
      currentWindow: {
        id: 1,
        account_id: 1,
        started_at: "2024-01-15T10:00:00Z",
        ended_at: null,
        triggered_by: "manual",
        notes: null,
      },
      usageByAccount: {
        1: {
          session_percent: 75,
          weekly_percent: 30,
          reset_time: "3:00 PM",
        },
      },
    });
    vi.mocked(useCurrentWindow).mockReturnValue({
      isActive: true,
      hoursRemaining: 3,
      minutesRemaining: 0,
      percentUsed: 40,
      endTime: new Date("2024-01-15T15:00:00Z"),
      isEndingSoon: false,
    });
    render(<PopoverWindow />);
    expect(screen.getByText(/75% used/)).toBeInTheDocument();
    expect(screen.getByText(/3:00 PM/)).toBeInTheDocument();
  });

  it("shows weekly_percent when present", () => {
    useStore.setState({
      currentWindow: {
        id: 1,
        account_id: 1,
        started_at: "2024-01-15T10:00:00Z",
        ended_at: null,
        triggered_by: "manual",
        notes: null,
      },
      usageByAccount: {
        1: { session_percent: 50, weekly_percent: 25, reset_time: null },
      },
    });
    vi.mocked(useCurrentWindow).mockReturnValue({
      isActive: true,
      hoursRemaining: 3,
      minutesRemaining: 0,
      percentUsed: 40,
      endTime: new Date("2024-01-15T15:00:00Z"),
      isEndingSoon: false,
    });
    render(<PopoverWindow />);
    expect(screen.getByText("Weekly")).toBeInTheDocument();
    expect(screen.getByText(/25% used/)).toBeInTheDocument();
  });

  it("shows week stats summary", () => {
    useStore.setState({
      windows: [
        {
          id: 1,
          account_id: 1,
          started_at: "2024-01-15T10:00:00Z",
          ended_at: "2024-01-15T13:00:00Z", // 3h
          triggered_by: "manual",
          notes: null,
        },
      ],
    });
    vi.mocked(useCurrentWindow).mockReturnValue({
      isActive: false,
      hoursRemaining: 0,
      minutesRemaining: 0,
      percentUsed: 0,
      endTime: null,
      isEndingSoon: false,
    });
    render(<PopoverWindow />);
    expect(screen.getByText(/1 windows \(3.0h\)/i)).toBeInTheDocument();
  });

  it("falls back to an enabled account when the current window account is missing", () => {
    useStore.setState({
      currentWindow: {
        id: 1,
        account_id: 999,
        started_at: "2024-01-15T10:00:00Z",
        ended_at: null,
        triggered_by: "manual",
        notes: null,
      },
    });
    vi.mocked(useCurrentWindow).mockReturnValue({
      isActive: true,
      hoursRemaining: 3,
      minutesRemaining: 0,
      percentUsed: 40,
      endTime: new Date("2024-01-15T15:00:00Z"),
      isEndingSoon: false,
    });

    render(<PopoverWindow />);
    expect(screen.getByText("Claude Code")).toBeInTheDocument();
  });

  it("opens the settings tab from the settings button", () => {
    vi.mocked(useCurrentWindow).mockReturnValue({
      isActive: false,
      hoursRemaining: 0,
      minutesRemaining: 0,
      percentUsed: 0,
      endTime: null,
      isEndingSoon: false,
    });

    render(<PopoverWindow />);
    fireEvent.click(screen.getByRole("button", { name: /settings/i }));
    expect(api.showMainWindow).toHaveBeenCalledWith("settings");
  });
});
