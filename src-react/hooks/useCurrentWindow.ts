import { useMemo, useEffect, useState } from "react";
import { useStore } from "@/store";
import { getEffectiveWindowEnd, getWindowDurationHours } from "@/lib/windowing";

interface WindowStatus {
  isActive: boolean;
  hoursRemaining: number;
  minutesRemaining: number;
  percentUsed: number;
  endTime: Date | null;
  isEndingSoon: boolean;
}

export function useCurrentWindow(): WindowStatus {
  const currentWindow = useStore((state) => state.currentWindow);
  const accounts = useStore((state) => state.accounts);
  const [now, setNow] = useState(new Date());

  // Update time every minute
  useEffect(() => {
    const interval = setInterval(() => {
      setNow(new Date());
    }, 60000); // Every minute

    return () => clearInterval(interval);
  }, []);

  return useMemo(() => {
    if (!currentWindow) {
      return {
        isActive: false,
        hoursRemaining: 0,
        minutesRemaining: 0,
        percentUsed: 0,
        endTime: null,
        isEndingSoon: false,
      };
    }

    const account = accounts.find((a) => a.id === currentWindow.account_id);
    const startedAt = new Date(currentWindow.started_at);
    const windowDurationHours = getWindowDurationHours(account);
    const endTime = getEffectiveWindowEnd(currentWindow, account);

    const totalMs = windowDurationHours * 60 * 60 * 1000;
    const elapsedMs = now.getTime() - startedAt.getTime();
    const remainingMs = Math.max(0, totalMs - elapsedMs);

    const hoursRemaining = Math.floor(remainingMs / (60 * 60 * 1000));
    const minutesRemaining = Math.floor((remainingMs % (60 * 60 * 1000)) / (60 * 1000));
    const percentUsed = Math.min(100, (elapsedMs / totalMs) * 100);

    // Ending soon: less than 30 minutes remaining
    const isEndingSoon = remainingMs > 0 && remainingMs < 30 * 60 * 1000;

    return {
      isActive: remainingMs > 0,
      hoursRemaining,
      minutesRemaining,
      percentUsed,
      endTime,
      isEndingSoon,
    };
  }, [currentWindow, accounts, now]);
}

// Alias for backward compatibility
export function useWindowStatus() {
  return useCurrentWindow();
}
