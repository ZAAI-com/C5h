import { describe, expect, it, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { MonitoringCard } from "./MonitoringCard";
import { useStore } from "@/store";

vi.mock("@/hooks", () => ({
  useMonitoring: vi.fn(),
}));

import { useMonitoring } from "@/hooks";

const accounts = [
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

describe("MonitoringCard", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    useStore.setState({ accounts });
  });

  it("shows Inactive label when monitoring not running", () => {
    vi.mocked(useMonitoring).mockReturnValue({
      status: { is_running: false, detected_processes: [], last_check: null },
      isLoading: false,
      startMonitoring: vi.fn(),
      stopMonitoring: vi.fn(),
      scanNow: vi.fn(),
    });
    render(<MonitoringCard />);
    expect(screen.getByText("Inactive")).toBeInTheDocument();
    expect(screen.getByText(/enable monitoring to automatically detect/i)).toBeInTheDocument();
  });

  it("shows Active label and process count when running with detected processes", () => {
    vi.mocked(useMonitoring).mockReturnValue({
      status: {
        is_running: true,
        detected_processes: [
          { pid: 1234, name: "claude", command: "claude", account_id: 1 },
        ],
        last_check: "2024-01-15T12:34:56Z",
      },
      isLoading: false,
      startMonitoring: vi.fn(),
      stopMonitoring: vi.fn(),
      scanNow: vi.fn(),
    });
    render(<MonitoringCard />);
    expect(screen.getByText("Active")).toBeInTheDocument();
    expect(screen.getByText(/1 process\(es\) detected/i)).toBeInTheDocument();
    expect(screen.getByText(/claude code/i)).toBeInTheDocument();
    expect(screen.getByText(/PID 1234/i)).toBeInTheDocument();
  });

  it("shows monitoring placeholder when running but no processes detected", () => {
    vi.mocked(useMonitoring).mockReturnValue({
      status: { is_running: true, detected_processes: [], last_check: null },
      isLoading: false,
      startMonitoring: vi.fn(),
      stopMonitoring: vi.fn(),
      scanNow: vi.fn(),
    });
    render(<MonitoringCard />);
    expect(screen.getByText(/monitoring for cli activity/i)).toBeInTheDocument();
  });

  it("calls startMonitoring when toggling switch from off", async () => {
    const startMonitoring = vi.fn().mockResolvedValue(undefined);
    vi.mocked(useMonitoring).mockReturnValue({
      status: { is_running: false, detected_processes: [], last_check: null },
      isLoading: false,
      startMonitoring,
      stopMonitoring: vi.fn(),
      scanNow: vi.fn(),
    });
    render(<MonitoringCard />);
    const toggle = screen.getByRole("switch");
    fireEvent.click(toggle);
    expect(startMonitoring).toHaveBeenCalled();
  });

  it("calls scanNow when Scan Now button clicked", async () => {
    const scanNow = vi.fn().mockResolvedValue([]);
    vi.mocked(useMonitoring).mockReturnValue({
      status: { is_running: false, detected_processes: [], last_check: null },
      isLoading: false,
      startMonitoring: vi.fn(),
      stopMonitoring: vi.fn(),
      scanNow,
    });
    render(<MonitoringCard />);
    fireEvent.click(screen.getByRole("button", { name: /scan now/i }));
    expect(scanNow).toHaveBeenCalled();
  });

  it("disables Scan Now button when isLoading", () => {
    vi.mocked(useMonitoring).mockReturnValue({
      status: { is_running: false, detected_processes: [], last_check: null },
      isLoading: true,
      startMonitoring: vi.fn(),
      stopMonitoring: vi.fn(),
      scanNow: vi.fn(),
    });
    render(<MonitoringCard />);
    expect(screen.getByRole("button", { name: /scan now/i })).toBeDisabled();
  });
});
