import { useEffect, useState, useCallback } from "react";
import { listen } from "@tauri-apps/api/event";
import * as api from "@/lib/api";
import type { DetectedProcess, MonitoringStatus } from "@/lib/api";
import { useStore } from "@/store";

export function useMonitoring() {
  const [status, setStatus] = useState<MonitoringStatus>({
    is_running: false,
    detected_processes: [],
    last_check: null,
  });
  const [isLoading, setIsLoading] = useState(false);

  const createWindow = useStore((state) => state.createWindow);
  const accounts = useStore((state) => state.accounts);

  // Load initial status
  useEffect(() => {
    api.getMonitoringStatus().then(setStatus).catch(console.error);
  }, []);

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
        if (proc.account_id) {
          try {
            await createWindow(proc.account_id, "auto-detected");
          } catch (err) {
            console.error("Failed to auto-create window:", err);
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
  }, [createWindow]);

  // Update monitor config when accounts change
  useEffect(() => {
    if (accounts.length > 0) {
      const config: [number, string][] = accounts
        .filter((a) => a.enabled && a.id)
        .map((a) => [a.id!, a.cli_command]);
      api.updateMonitorConfig(config).catch(console.error);
    }
  }, [accounts]);

  const startMonitoring = useCallback(async () => {
    setIsLoading(true);
    try {
      await api.startMonitoring();
      setStatus((prev) => ({ ...prev, is_running: true }));
    } finally {
      setIsLoading(false);
    }
  }, []);

  const stopMonitoring = useCallback(async () => {
    setIsLoading(true);
    try {
      await api.stopMonitoring();
      setStatus((prev) => ({ ...prev, is_running: false }));
    } finally {
      setIsLoading(false);
    }
  }, []);

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
    } finally {
      setIsLoading(false);
    }
  }, []);

  return {
    status,
    isLoading,
    startMonitoring,
    stopMonitoring,
    scanNow,
  };
}
