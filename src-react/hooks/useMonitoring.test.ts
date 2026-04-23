import { describe, expect, it, vi, beforeEach } from "vitest";
import { renderHook, act, waitFor } from "@testing-library/react";
import { useMonitoring } from "./useMonitoring";
import * as api from "@/lib/api";
import type { DetectedProcess, MonitoringStatus } from "@/lib/api";
import { listen } from "@tauri-apps/api/event";
import { useStore } from "@/store";

vi.mock("@/lib/api", async () => {
  const actual = await vi.importActual<typeof import("@/lib/api")>("@/lib/api");
  return {
    ...actual,
    getMonitoringStatus: vi.fn(),
    startMonitoring: vi.fn(),
    stopMonitoring: vi.fn(),
    scanCliProcesses: vi.fn(),
    updateMonitorConfig: vi.fn(),
  };
});

type EventCallback<T> = (event: { payload: T }) => void;

describe("useMonitoring", () => {
  let listeners: Record<string, EventCallback<unknown>>;
  let createWindow: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    vi.clearAllMocks();
    listeners = {};

    vi.mocked(listen).mockImplementation(
      ((event: string, cb: EventCallback<unknown>) => {
        listeners[event] = cb;
        return Promise.resolve(() => {});
      }) as typeof listen
    );

    vi.mocked(api.getMonitoringStatus).mockResolvedValue({
      is_running: false,
      detected_processes: [],
      last_check: null,
    });
    vi.mocked(api.startMonitoring).mockResolvedValue(undefined);
    vi.mocked(api.stopMonitoring).mockResolvedValue(undefined);
    vi.mocked(api.scanCliProcesses).mockResolvedValue([]);
    vi.mocked(api.updateMonitorConfig).mockResolvedValue(undefined);

    createWindow = vi.fn().mockResolvedValue(undefined);
    useStore.setState({
      accounts: [],
      createWindow: createWindow as unknown as (
        accountId: number,
        triggeredBy: string
      ) => Promise<void>,
    });
  });

  it("loads initial monitoring status on mount", async () => {
    const initial: MonitoringStatus = {
      is_running: true,
      detected_processes: [{ pid: 1, name: "claude", command: "claude", account_id: 1 }],
      last_check: "2024-01-15T12:00:00Z",
    };
    vi.mocked(api.getMonitoringStatus).mockResolvedValueOnce(initial);

    const { result } = renderHook(() => useMonitoring());

    await waitFor(() => expect(result.current.status).toEqual(initial));
    expect(api.getMonitoringStatus).toHaveBeenCalledTimes(1);
  });

  it("subscribes to monitoring-status, process-started, and process-stopped events", () => {
    renderHook(() => useMonitoring());

    expect(listen).toHaveBeenCalledWith("monitoring-status", expect.any(Function));
    expect(listen).toHaveBeenCalledWith("process-started", expect.any(Function));
    expect(listen).toHaveBeenCalledWith("process-stopped", expect.any(Function));
  });

  it("updates status when monitoring-status event fires", async () => {
    const { result } = renderHook(() => useMonitoring());

    await waitFor(() => expect(listeners["monitoring-status"]).toBeDefined());

    const newStatus: MonitoringStatus = {
      is_running: true,
      detected_processes: [],
      last_check: "2024-01-15T13:00:00Z",
    };

    act(() => {
      listeners["monitoring-status"]({ payload: newStatus });
    });

    expect(result.current.status).toEqual(newStatus);
  });

  it("auto-creates window when process-started event has account_id", async () => {
    renderHook(() => useMonitoring());

    await waitFor(() => expect(listeners["process-started"]).toBeDefined());

    const proc: DetectedProcess = {
      pid: 1234,
      name: "claude",
      command: "claude",
      account_id: 5,
    };

    await act(async () => {
      await listeners["process-started"]({ payload: proc });
    });

    expect(createWindow).toHaveBeenCalledWith(5, "auto-detected");
  });

  it("does not auto-create window when process-started has no account_id", async () => {
    renderHook(() => useMonitoring());

    await waitFor(() => expect(listeners["process-started"]).toBeDefined());

    const proc: DetectedProcess = {
      pid: 1234,
      name: "unknown",
      command: "unknown",
      account_id: null,
    };

    await act(async () => {
      await listeners["process-started"]({ payload: proc });
    });

    expect(createWindow).not.toHaveBeenCalled();
  });

  it("updates monitor config when accounts change", async () => {
    renderHook(() => useMonitoring());

    act(() => {
      useStore.setState({
        accounts: [
          {
            id: 1,
            name: "Claude",
            tool_type: "claude",
            cli_command: "claude",
            cli_args: null,
            window_duration_hours: 5,
            color: "#000",
            enabled: true,
          },
          {
            id: 2,
            name: "Codex",
            tool_type: "codex",
            cli_command: "codex",
            cli_args: null,
            window_duration_hours: 5,
            color: "#fff",
            enabled: false,
          },
        ],
      });
    });

    await waitFor(() => expect(api.updateMonitorConfig).toHaveBeenCalled());
    // Disabled accounts should be filtered out
    expect(api.updateMonitorConfig).toHaveBeenLastCalledWith([[1, "claude"]]);
  });

  it("startMonitoring calls api and sets is_running to true", async () => {
    const { result } = renderHook(() => useMonitoring());

    await act(async () => {
      await result.current.startMonitoring();
    });

    expect(api.startMonitoring).toHaveBeenCalled();
    expect(result.current.status.is_running).toBe(true);
  });

  it("stopMonitoring calls api and sets is_running to false", async () => {
    vi.mocked(api.getMonitoringStatus).mockResolvedValueOnce({
      is_running: true,
      detected_processes: [],
      last_check: null,
    });
    const { result } = renderHook(() => useMonitoring());

    await waitFor(() => expect(result.current.status.is_running).toBe(true));

    await act(async () => {
      await result.current.stopMonitoring();
    });

    expect(api.stopMonitoring).toHaveBeenCalled();
    expect(result.current.status.is_running).toBe(false);
  });

  it("scanNow updates detected_processes and last_check", async () => {
    const processes: DetectedProcess[] = [
      { pid: 1, name: "claude", command: "claude", account_id: 1 },
    ];
    vi.mocked(api.scanCliProcesses).mockResolvedValueOnce(processes);

    const { result } = renderHook(() => useMonitoring());

    await act(async () => {
      const returned = await result.current.scanNow();
      expect(returned).toEqual(processes);
    });

    expect(result.current.status.detected_processes).toEqual(processes);
    expect(result.current.status.last_check).not.toBeNull();
  });
});
