import { describe, expect, it, beforeEach, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { StatsView } from "./StatsView";
import { useStore } from "@/app/store";
import * as api from "@/shared/api/api";

vi.mock("recharts", () => {
  const passthrough = ({ children }: { children?: React.ReactNode }) => (
    <div>{children}</div>
  );

  return {
    ResponsiveContainer: passthrough,
    BarChart: passthrough,
    Bar: passthrough,
    LineChart: passthrough,
    Line: passthrough,
    XAxis: passthrough,
    YAxis: passthrough,
    CartesianGrid: passthrough,
    Tooltip: passthrough,
    Legend: passthrough,
    Cell: passthrough,
  };
});

vi.mock("@/shared/api/api", () => ({
  getStats: vi.fn(),
}));

const makeStatsPayload = () => ({
  summary: {
    total_windows: 2,
    total_hours: 10,
    avg_duration_hours: 5,
  },
  week_data: [
    {
      day: "Mon",
      date: "Jan 15",
      window_count: 2,
      account_counts: {
        account_1: 2,
      },
    },
  ],
  day_of_week: [
    {
      day: "Monday",
      count: 2,
      intensity: 1,
    },
  ],
  time_of_day: [
    {
      hour: "10am",
      count: 2,
    },
  ],
  duration_trend: [
    {
      week: "Jan 15",
      avg_hours: 5,
      windows: 2,
    },
  ],
  account_breakdown: [
    {
      account_id: 1,
      window_count: 2,
      total_hours: 10,
    },
  ],
  selected_week_label: "Jan 14 - Jan 20",
  is_current_week: false,
});

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

async function waitForStatsToLoad() {
  await screen.findByText(/Peak selected-week day: Monday\./i);
}

describe("StatsView", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(api.getStats).mockResolvedValue(makeStatsPayload());
    useStore.setState({
      accounts: [],
      windows: [],
      selectedDate: new Date("2024-01-15T12:00:00Z"),
      selectedAccountId: null,
    });
  });

  it("shows empty state when no accounts and no windows", () => {
    vi.mocked(api.getStats).mockImplementationOnce(() => new Promise(() => {}));
    render(<StatsView />);
    expect(screen.getByText(/no statistics yet/i)).toBeInTheDocument();
    expect(
      screen.getByText(/create an account and start using/i)
    ).toBeInTheDocument();
  });

  it("renders summary cards when data exists", async () => {
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
    await waitForStatsToLoad();
    expect(screen.getByText("Total Windows")).toBeInTheDocument();
    expect(screen.getByText("Total Hours")).toBeInTheDocument();
    expect(screen.getByText("Avg Window Duration")).toBeInTheDocument();
    expect(screen.getByText("Active Accounts")).toBeInTheDocument();
  });

  it("renders trend chart card title", async () => {
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
    await waitForStatsToLoad();
    expect(
      screen.getByText(/average duration trend \(8 weeks\)/i)
    ).toBeInTheDocument();
  });

  it("renders day-of-week and time-of-day chart titles", async () => {
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
    await waitForStatsToLoad();
    expect(screen.getByText(/usage by day of week/i)).toBeInTheDocument();
    expect(screen.getByText(/usage by time of day/i)).toBeInTheDocument();
    expect(screen.getByText(/windows per day/i)).toBeInTheDocument();
  });

  it("shows account-by-account breakdown", async () => {
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
    await waitForStatsToLoad();
    expect(screen.getByText(/by account/i)).toBeInTheDocument();
    expect(await screen.findByText(/2 windows · 10h/i)).toBeInTheDocument();
  });

  it("shows total window count in summary", async () => {
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
    await waitForStatsToLoad();
    await waitFor(() => {
      expect(screen.getByText("2")).toBeInTheDocument();
    });
  });

  it("fetches a dedicated 8-week range for trend data", async () => {
    useStore.setState({
      accounts: [account],
      windows: [],
      selectedDate: new Date("2024-01-15T12:00:00Z"),
    });

    render(<StatsView />);

    await waitFor(() => {
      expect(api.getStats).toHaveBeenCalledWith(
        "2024-01-15T12:00:00.000Z",
        undefined,
        expect.objectContaining({ signal: expect.any(AbortSignal) })
      );
    });
  });
});
