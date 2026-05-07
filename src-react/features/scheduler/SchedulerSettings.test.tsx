import { describe, expect, it, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { SchedulerSettings } from "./SchedulerSettings";
import { useStore } from "@/app/store";

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

describe("SchedulerSettings", () => {
  beforeEach(() => {
    useStore.setState({
      accounts: [account],
      schedules: [],
      createSchedule: vi.fn().mockResolvedValue(undefined),
      deleteSchedule: vi.fn().mockResolvedValue(undefined),
      installSchedule: vi.fn().mockResolvedValue(undefined),
      uninstallSchedule: vi.fn().mockResolvedValue(undefined),
    });
  });

  it("shows empty-state message when no pending schedules", () => {
    render(<SchedulerSettings />);
    expect(screen.getByText(/no scheduled triggers/i)).toBeInTheDocument();
  });

  it("disables Add Schedule button when no enabled accounts", () => {
    useStore.setState({
      accounts: [{ ...account, enabled: false }],
    });
    render(<SchedulerSettings />);
    expect(screen.getByRole("button", { name: /add schedule/i })).toBeDisabled();
  });

  it("renders pending schedule with account name", () => {
    useStore.setState({
      schedules: [
        {
          id: 100,
          account_id: 1,
          scheduled_at: "2030-06-01T14:30:00Z",
          status: "pending",
          plist_path: null,
          executed_at: null,
        },
      ],
    });
    render(<SchedulerSettings />);
    expect(screen.getByText("Claude Code")).toBeInTheDocument();
    expect(screen.getByText("Not installed")).toBeInTheDocument();
  });

  it("shows Active badge when schedule has plist_path", () => {
    useStore.setState({
      schedules: [
        {
          id: 100,
          account_id: 1,
          scheduled_at: "2030-06-01T14:30:00Z",
          status: "pending",
          plist_path: "/Users/x/Library/LaunchAgents/com.zaai.c5h.trigger.100.plist",
          executed_at: null,
        },
      ],
    });
    render(<SchedulerSettings />);
    expect(screen.getByText("Active")).toBeInTheDocument();
  });

  it("calls installSchedule when install button clicked", async () => {
    const installSchedule = vi.fn().mockResolvedValue(undefined);
    useStore.setState({
      installSchedule,
      schedules: [
        {
          id: 100,
          account_id: 1,
          scheduled_at: "2030-06-01T14:30:00Z",
          status: "pending",
          plist_path: null,
          executed_at: null,
        },
      ],
    });

    render(<SchedulerSettings />);
    fireEvent.click(screen.getByRole("button", { name: /install schedule/i }));

    expect(installSchedule).toHaveBeenCalledWith(100, "claude");
  });

  it("calls uninstallSchedule when uninstall button clicked", async () => {
    const uninstallSchedule = vi.fn().mockResolvedValue(undefined);
    useStore.setState({
      uninstallSchedule,
      schedules: [
        {
          id: 100,
          account_id: 1,
          scheduled_at: "2030-06-01T14:30:00Z",
          status: "pending",
          plist_path: "/some/path.plist",
          executed_at: null,
        },
      ],
    });

    render(<SchedulerSettings />);
    fireEvent.click(screen.getByRole("button", { name: /uninstall schedule/i }));

    expect(uninstallSchedule).toHaveBeenCalledWith(100);
  });

  it("hides completed schedules from list", () => {
    useStore.setState({
      schedules: [
        {
          id: 100,
          account_id: 1,
          scheduled_at: "2030-06-01T14:30:00Z",
          status: "completed",
          plist_path: null,
          executed_at: "2030-06-01T14:30:00Z",
        },
      ],
    });
    render(<SchedulerSettings />);
    expect(screen.getByText(/no scheduled triggers/i)).toBeInTheDocument();
  });
});
