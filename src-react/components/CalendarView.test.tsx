import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, within } from "@testing-library/react";
import { CalendarView } from "./CalendarView";
import { useStore } from "@/store";

vi.mock("@/hooks", () => ({
  useCurrentWindow: vi.fn(() => ({
    isActive: false,
    hoursRemaining: 0,
    minutesRemaining: 0,
    percentUsed: 0,
    endTime: null,
    isEndingSoon: false,
  })),
  useMonitoring: vi.fn(() => ({
    status: { is_running: false, detected_processes: [], last_check: null },
    isLoading: false,
    startMonitoring: vi.fn(),
    stopMonitoring: vi.fn(),
    scanNow: vi.fn(),
  })),
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

describe("CalendarView", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2024-01-15T12:00:00Z"));

    useStore.setState({
      accounts: [account],
      windows: [],
      schedules: [],
      currentWindow: null,
      selectedDate: new Date("2024-01-15T12:00:00Z"),
      setSelectedDate: vi.fn(),
      fetchWindows: vi.fn().mockResolvedValue(undefined),
      createSchedule: vi.fn().mockResolvedValue(undefined),
    });
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("shows empty-state message when no windows or schedules", () => {
    render(<CalendarView />);
    expect(
      screen.getByText(/no usage windows this week/i)
    ).toBeInTheDocument();
  });

  it("hides empty-state when windows exist", () => {
    useStore.setState({
      windows: [
        {
          id: 1,
          account_id: 1,
          started_at: "2024-01-15T10:00:00Z",
          ended_at: null,
          triggered_by: "manual",
          notes: null,
          usage_percent: null,
        },
      ],
    });
    render(<CalendarView />);
    expect(
      screen.queryByText(/no usage windows this week/i)
    ).not.toBeInTheDocument();
  });

  it("opens schedule dialog when calendar cell is clicked", () => {
    render(<CalendarView />);
    const cells = screen.getAllByRole("gridcell");
    fireEvent.click(cells[0]);
    expect(screen.getByText("Schedule Window")).toBeInTheDocument();
  });

  it("opens schedule dialog when Enter pressed on a cell", () => {
    render(<CalendarView />);
    const cells = screen.getAllByRole("gridcell");
    fireEvent.keyDown(cells[0], { key: "Enter" });
    expect(screen.getByText("Schedule Window")).toBeInTheDocument();
  });

  it("calls fetchWindows when navigating to next week", () => {
    const fetchWindows = vi.fn().mockResolvedValue(undefined);
    const setSelectedDate = vi.fn();
    useStore.setState({ fetchWindows, setSelectedDate });

    render(<CalendarView />);
    fireEvent.click(screen.getByLabelText(/next week/i));

    expect(setSelectedDate).toHaveBeenCalled();
    expect(fetchWindows).toHaveBeenCalled();
  });

  it("calls fetchWindows when navigating to previous week", () => {
    const fetchWindows = vi.fn().mockResolvedValue(undefined);
    useStore.setState({ fetchWindows });

    render(<CalendarView />);
    fireEvent.click(screen.getByLabelText(/previous week/i));

    expect(fetchWindows).toHaveBeenCalled();
  });

  it("calls fetchWindows when Today button is clicked", () => {
    const fetchWindows = vi.fn().mockResolvedValue(undefined);
    useStore.setState({ fetchWindows });

    render(<CalendarView />);
    fireEvent.click(screen.getByRole("button", { name: /^today$/i }));

    expect(fetchWindows).toHaveBeenCalled();
  });

  it("renders 24 hour rows in calendar grid", () => {
    render(<CalendarView />);
    const grid = screen.getByRole("grid");
    expect(within(grid).getAllByRole("row")).toHaveLength(24);
  });
});
