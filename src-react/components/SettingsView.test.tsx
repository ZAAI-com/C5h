import { describe, expect, it, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { SettingsView } from "./SettingsView";
import { useStore } from "@/store";

const baseSettings = {
  launch_at_login: true,
  show_in_menu_bar: true,
  theme: "system",
  notifications_enabled: true,
  notify_ending_soon: true,
  notify_trigger_status: true,
  notify_weekly_summary: true,
  poll_interval_minutes: 15,
};

describe("SettingsView", () => {
  beforeEach(() => {
    useStore.setState({
      settings: baseSettings,
      accounts: [],
      schedules: [],
      saveSettings: vi.fn().mockResolvedValue(undefined),
      createAccount: vi.fn().mockResolvedValue(undefined),
      updateAccount: vi.fn().mockResolvedValue(undefined),
      deleteAccount: vi.fn().mockResolvedValue(undefined),
    });
  });

  it("shows loading message when settings are null", () => {
    useStore.setState({ settings: null });
    render(<SettingsView />);
    expect(screen.getByText(/loading settings/i)).toBeInTheDocument();
  });

  it("renders General, Appearance, Notifications, and Accounts sections", () => {
    render(<SettingsView />);
    expect(screen.getByText("General")).toBeInTheDocument();
    expect(screen.getByText("Appearance")).toBeInTheDocument();
    expect(screen.getByText("Notifications")).toBeInTheDocument();
    expect(screen.getByText("Accounts")).toBeInTheDocument();
  });

  it("calls saveSettings when toggling launch_at_login", () => {
    const saveSettings = vi.fn().mockResolvedValue(undefined);
    useStore.setState({ saveSettings });

    render(<SettingsView />);
    const toggle = screen.getByLabelText(/launch at login/i);
    fireEvent.click(toggle);

    expect(saveSettings).toHaveBeenCalledWith(
      expect.objectContaining({ launch_at_login: false })
    );
  });

  it("disables sub-notification switches when notifications_enabled is false", () => {
    useStore.setState({
      settings: { ...baseSettings, notifications_enabled: false },
    });

    render(<SettingsView />);
    expect(screen.getByLabelText(/window ending soon/i)).toBeDisabled();
    expect(screen.getByLabelText(/trigger status/i)).toBeDisabled();
    expect(screen.getByLabelText(/weekly summary/i)).toBeDisabled();
  });

  it("shows 'No accounts configured' when accounts array is empty", () => {
    render(<SettingsView />);
    expect(screen.getByText(/no accounts configured/i)).toBeInTheDocument();
  });

  it("renders configured accounts with details", () => {
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

    render(<SettingsView />);
    expect(screen.getByText("Claude Code")).toBeInTheDocument();
    expect(screen.getByText(/claude · 5h window/i)).toBeInTheDocument();
  });

  it("shows Disabled badge for disabled accounts", () => {
    useStore.setState({
      accounts: [
        {
          id: 1,
          name: "Codex",
          tool_type: "codex",
          cli_command: "codex",
          cli_args: null,
          window_duration_hours: 5,
          color: "#10a37f",
          enabled: false,
        },
      ],
    });

    render(<SettingsView />);
    expect(screen.getByText("Disabled")).toBeInTheDocument();
  });
});
