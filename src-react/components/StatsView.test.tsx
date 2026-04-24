import { describe, expect, it, beforeEach, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { StatsView } from "./StatsView";
import { useStore } from "@/store";
import * as api from "@/lib/api";

vi.mock("@/lib/api", () => ({
  getWindows: vi.fn().mockResolvedValue([]),
}));

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

describe("StatsView", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(api.getWindows).mockResolvedValue([]);
    useStore.setState({
      accounts: [],
      windows: [],
      selectedDate: new Date("2024-01-15T12:00:00Z"),
      selectedAccountId: null,
    });
  });

  it("shows empty state when no accounts and no windows", () => {
    render(<StatsView />);
    expect(screen.getByText(/no statistics yet/i)).toBeInTheDocument();
    expect(
      screen.getByText(/create an account and start using/i)
    ).toBeInTheDocument();
  });

  it("renders summary cards when data exists", () => {
    useStore.setState({
      accounts: [account],
      windows: [
        {
          id: 1,
          account_id: 1,
          started_at: "2024-01-15T10:00:00Z",
          ended_at: "2024-01-15T13:00:00Z",
          triggered_by: "manual",
          notes: null,
          usage_percent: null,
        },
      ],
    });
    render(<StatsView />);
    expect(screen.getByText("Total Windows")).toBeInTheDocument();
    expect(screen.getByText("Total Hours")).toBeInTheDocument();
    expect(screen.getByText("Avg Window Duration")).toBeInTheDocument();
    expect(screen.getByText("Active Accounts")).toBeInTheDocument();
  });

  it("renders trend chart card title", () => {
    useStore.setState({
      accounts: [account],
      windows: [
        {
          id: 1,
          account_id: 1,
          started_at: "2024-01-15T10:00:00Z",
          ended_at: "2024-01-15T13:00:00Z",
          triggered_by: "manual",
          notes: null,
          usage_percent: null,
        },
      ],
    });
    render(<StatsView />);
    expect(
      screen.getByText(/average duration trend \(8 weeks\)/i)
    ).toBeInTheDocument();
  });

  it("renders day-of-week and time-of-day chart titles", () => {
    useStore.setState({
      accounts: [account],
      windows: [
        {
          id: 1,
          account_id: 1,
          started_at: "2024-01-15T10:00:00Z",
          ended_at: "2024-01-15T13:00:00Z",
          triggered_by: "manual",
          notes: null,
          usage_percent: null,
        },
      ],
    });
    render(<StatsView />);
    expect(screen.getByText(/usage by day of week/i)).toBeInTheDocument();
    expect(screen.getByText(/usage by time of day/i)).toBeInTheDocument();
    expect(screen.getByText(/windows per day/i)).toBeInTheDocument();
  });

  it("shows account-by-account breakdown", () => {
    useStore.setState({
      accounts: [account],
      windows: [
        {
          id: 1,
          account_id: 1,
          started_at: "2024-01-15T10:00:00Z",
          ended_at: "2024-01-15T15:00:00Z",
          triggered_by: "manual",
          notes: null,
          usage_percent: null,
        },
        {
          id: 2,
          account_id: 1,
          started_at: "2024-01-16T10:00:00Z",
          ended_at: "2024-01-16T15:00:00Z",
          triggered_by: "manual",
          notes: null,
          usage_percent: null,
        },
      ],
    });
    render(<StatsView />);
    expect(screen.getByText(/by account/i)).toBeInTheDocument();
    expect(screen.getByText(/2 windows · 10h/i)).toBeInTheDocument();
  });

  it("shows total window count in summary", () => {
    useStore.setState({
      accounts: [account],
      windows: [
        {
          id: 1,
          account_id: 1,
          started_at: "2024-01-15T10:00:00Z",
          ended_at: "2024-01-15T13:00:00Z",
          triggered_by: "manual",
          notes: null,
          usage_percent: null,
        },
        {
          id: 2,
          account_id: 1,
          started_at: "2024-01-16T10:00:00Z",
          ended_at: null,
          triggered_by: "manual",
          notes: null,
          usage_percent: null,
        },
      ],
    });
    render(<StatsView />);
    // Two windows
    expect(screen.getByText("2")).toBeInTheDocument();
  });

  it("fetches a dedicated 8-week range for trend data", async () => {
    useStore.setState({
      accounts: [account],
      windows: [],
      selectedDate: new Date("2024-01-15T12:00:00Z"),
    });

    render(<StatsView />);

    await waitFor(() => {
      expect(api.getWindows).toHaveBeenCalledTimes(1);
    });
  });
});
