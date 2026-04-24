import { useEffect, useRef } from "react";
import { useStore } from "@/store";
import { useCurrentWindow } from "./useCurrentWindow";
import { notifyWindowEndingSoon } from "@/lib/api";

interface AlertState {
  windowId: number | null;
  alert30MinSent: boolean;
  alert15MinSent: boolean;
}

/**
 * Hook to monitor window ending and trigger notifications
 * Sends alerts at 30 minutes and 15 minutes remaining
 */
export function useWindowEndingAlert() {
  const currentWindow = useStore((state) => state.currentWindow);
  const accounts = useStore((state) => state.accounts);
  const settings = useStore((state) => state.settings);
  const status = useCurrentWindow();

  const alertState = useRef<AlertState>({
    windowId: null,
    alert30MinSent: false,
    alert15MinSent: false,
  });

  useEffect(() => {
    // Skip if notifications are disabled
    if (!settings?.notifications_enabled || !settings?.notify_ending_soon) {
      return;
    }

    // Skip if no active window
    if (!status.isActive || !currentWindow?.id) {
      // Reset state when window ends
      if (alertState.current.windowId !== null) {
        alertState.current = {
          windowId: null,
          alert30MinSent: false,
          alert15MinSent: false,
        };
      }
      return;
    }

    // Reset if this is a new window
    if (alertState.current.windowId !== currentWindow.id) {
      alertState.current = {
        windowId: currentWindow.id,
        alert30MinSent: false,
        alert15MinSent: false,
      };
    }

    const totalMinutes = status.hoursRemaining * 60 + status.minutesRemaining;
    const account = accounts.find((a) => a.id === currentWindow.account_id);
    const accountName = account?.name ?? "Unknown";

    // Check for 30 minute alert
    if (totalMinutes <= 30 && totalMinutes > 15 && !alertState.current.alert30MinSent) {
      alertState.current.alert30MinSent = true;
      notifyWindowEndingSoon(accountName, 30).catch(console.error);
    }

    // Check for 15 minute alert
    if (totalMinutes <= 15 && totalMinutes > 0 && !alertState.current.alert15MinSent) {
      alertState.current.alert15MinSent = true;
      notifyWindowEndingSoon(accountName, 15).catch(console.error);
    }
  }, [
    currentWindow?.id,
    currentWindow?.account_id,
    status.isActive,
    status.hoursRemaining,
    status.minutesRemaining,
    accounts,
    settings?.notifications_enabled,
    settings?.notify_ending_soon,
  ]);
}
