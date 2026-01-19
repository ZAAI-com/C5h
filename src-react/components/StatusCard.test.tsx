import { describe, it, expect, beforeEach, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import { StatusCard } from "./StatusCard";
import { useStore } from "@/store";

// Mock the useCurrentWindow hook
vi.mock("@/hooks", () => ({
  useCurrentWindow: vi.fn(),
}));

import { useCurrentWindow } from "@/hooks";

describe("StatusCard", () => {
  beforeEach(() => {
    vi.clearAllMocks();
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

  it("should render no active window message when not active", () => {
    vi.mocked(useCurrentWindow).mockReturnValue({
      isActive: false,
      hoursRemaining: 0,
      minutesRemaining: 0,
      percentUsed: 0,
      endTime: null,
      isEndingSoon: false,
    });

    render(<StatusCard />);

    expect(screen.getByText(/no active window/i)).toBeInTheDocument();
    expect(
      screen.getByText(/start a new usage window/i)
    ).toBeInTheDocument();
  });

  it("should render active window status with account name", () => {
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

    render(<StatusCard />);

    expect(screen.getByText(/claude code/i)).toBeInTheDocument();
    expect(screen.getByText(/3h/)).toBeInTheDocument();
    expect(screen.getByText(/40%/)).toBeInTheDocument();
  });

  it("should show ending soon alert when isEndingSoon is true", () => {
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
      hoursRemaining: 0,
      minutesRemaining: 15,
      percentUsed: 95,
      endTime: new Date("2024-01-15T15:00:00Z"),
      isEndingSoon: true,
    });

    render(<StatusCard />);

    expect(screen.getByText(/window ending soon/i)).toBeInTheDocument();
  });

  it("should show start button with account name when no active window", () => {
    vi.mocked(useCurrentWindow).mockReturnValue({
      isActive: false,
      hoursRemaining: 0,
      minutesRemaining: 0,
      percentUsed: 0,
      endTime: null,
      isEndingSoon: false,
    });

    render(<StatusCard />);

    expect(
      screen.getByRole("button", { name: /start claude code window/i })
    ).toBeInTheDocument();
  });
});
