import { useEffect, useState, useCallback, useRef } from "react";
import { listen } from "@tauri-apps/api/event";
import { toast } from "sonner";
import * as api from "@/lib/api";
import type { DetectedProcess, MonitoringStatus } from "@/lib/api";
import { useStore } from "@/store";
import { mapError } from "@/lib/errors";

export function useMonitoring() {
  const [status, setStatus] = useState<MonitoringStatus>({
    is_running: false,
    detected_processes: [],
    last_check: null,
  });
  const [isLoading, setIsLoading] = useState(false);

  const createWindow = useStore((state) => state.createWindow);
  const accounts = useStore((state) => state.accounts);
  const pendingStartsRef = useRef(new Set<number>());

  const showMonitoringError = useCallback((prefix: string, err: unknown) => {
    const message = mapError(err instanceof Error ? err.message : String(err));
    toast.error(`${prefix}: ${message}`);
  }, []);

  // Load initial status
  useEffect(() => {
    api.getMonitoringStatus().then(setStatus).catch((err) => {
      showMonitoringError("Failed to load monitoring status", err);
    });
  }, [showMonitoringError]);

  // Listen for events
  useEffect(() => {
    const unlistenStatus = listen<MonitoringStatus>(
      "monitoring-status",
      (event) => {
        setStatus(event.payload);
      }
    );

    const unlistenStarted = listen<DetectedProcess>(
      "process-started",
      async (event) => {
        const proc = event.payload;
        console.log("Process started:", proc);

        // Auto-create window when process is detected
        if (proc.account_id && !pendingStartsRef.current.has(proc.account_id)) {
          pendingStartsRef.current.add(proc.account_id);
          try {
            await createWindow(proc.account_id, "auto-detected");
          } catch (err) {
            showMonitoringError("Failed to auto-create window", err);
          } finally {
            pendingStartsRef.current.delete(proc.account_id);
          }
        }
      }
    );

    const unlistenStopped = listen<DetectedProcess>(
      "process-stopped",
      (event) => {
        console.log("Process stopped:", event.payload);
        // Note: We don't auto-end windows when processes stop
        // as the user might restart the tool
      }
    );

    return () => {
      unlistenStatus.then((fn) => fn());
      unlistenStarted.then((fn) => fn());
      unlistenStopped.then((fn) => fn());
    };
  }, [createWindow, showMonitoringError]);

  // Update monitor config when accounts change
  useEffect(() => {
    const config: [number, string][] = accounts
      .filter((a) => a.enabled && a.id)
      .map((a) => [a.id!, a.cli_command]);
    api.updateMonitorConfig(config).catch((err) => {
      showMonitoringError("Failed to update monitoring config", err);
    });
  }, [accounts, showMonitoringError]);

  const startMonitoring = useCallback(async () => {
    setIsLoading(true);
    try {
      await api.startMonitoring();
      setStatus((prev) => ({ ...prev, is_running: true }));
    } catch (err) {
      showMonitoringError("Failed to start monitoring", err);
      throw err;
    } finally {
      setIsLoading(false);
    }
  }, [showMonitoringError]);

  const stopMonitoring = useCallback(async () => {
    setIsLoading(true);
    try {
      await api.stopMonitoring();
      setStatus((prev) => ({ ...prev, is_running: false }));
    } catch (err) {
      showMonitoringError("Failed to stop monitoring", err);
      throw err;
    } finally {
      setIsLoading(false);
    }
  }, [showMonitoringError]);

  const scanNow = useCallback(async () => {
    setIsLoading(true);
    try {
      const processes = await api.scanCliProcesses();
      setStatus((prev) => ({
        ...prev,
        detected_processes: processes,
        last_check: new Date().toISOString(),
      }));
      return processes;
    } catch (err) {
      showMonitoringError("Failed to scan for CLI processes", err);
      throw err;
    } finally {
      setIsLoading(false);
    }
  }, [showMonitoringError]);

  return {
    status,
    isLoading,
    startMonitoring,
    stopMonitoring,
    scanNow,
  };
}
