import { useEffect, useRef } from "react";
import { useStore } from "@/app/store";
import { useCurrentWindow } from "@/features/windows/useCurrentWindow";
import { updateTrayState, type TrayState } from "@/shared/api/api";
import { useReducedMotion } from "@/shared/lib/motion";

/**
 * Pushes the current tray-icon state to the Rust side whenever the relevant
 * inputs change. Single source of truth for what the menu-bar title displays.
 *
 * Inputs:
 * - currentWindow + accounts (active window status, per-minute remaining)
 * - usageByAccount (real-time CLI-polled %)
 * - prefers-reduced-motion (disables the pulse on the Rust side)
 *
 * The Rust handler dedupes via a generation counter, so spamming on every
 * minute tick costs at most one tray title set.
 */
export function useTraySync() {
  const status = useCurrentWindow();
  const currentWindow = useStore((state) => state.currentWindow);
  const usageByAccount = useStore((state) => state.usageByAccount);
  const reducedMotion = useReducedMotion();

  // Memoize the most recent payload we sent to avoid no-op IPC chatter.
  const lastSentRef = useRef<string | null>(null);

  useEffect(() => {
    let nextState: TrayState;
    if (!status.isActive || !currentWindow) {
      nextState = { kind: "idle" };
    } else {
      const polledPercent = usageByAccount[currentWindow.account_id]?.session_percent;
      const percent =
        polledPercent != null ? Math.round(polledPercent) : Math.round(status.percentUsed);
      const totalMinutes = status.hoursRemaining * 60 + status.minutesRemaining;
      nextState = {
        kind: "active",
        percent,
        minutes_remaining: totalMinutes,
      };
    }

    const fingerprint = JSON.stringify({ nextState, reducedMotion });
    if (fingerprint === lastSentRef.current) return;
    lastSentRef.current = fingerprint;

    updateTrayState(nextState, reducedMotion).catch(() => {
      // Tray push failures are non-critical; the main UI is unaffected.
    });
  }, [
    status.isActive,
    status.percentUsed,
    status.hoursRemaining,
    status.minutesRemaining,
    currentWindow,
    usageByAccount,
    reducedMotion,
  ]);
}
