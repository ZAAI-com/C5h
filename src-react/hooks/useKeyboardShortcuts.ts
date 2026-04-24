import { useEffect } from "react";

interface KeyboardShortcutOptions {
  onSwitchTab?: (tab: string) => void;
  onStartWindow?: () => void;
  onJumpToToday?: () => void;
  onNavigateWeek?: (direction: "prev" | "next") => void;
}

/**
 * Global keyboard shortcuts for the app.
 *
 * - Cmd+1 / Cmd+2 / Cmd+3: Switch tabs (calendar, stats, settings)
 * - Cmd+N: Start new window
 * - Cmd+T: Jump to today
 * - ArrowLeft / ArrowRight: Navigate weeks (when not in an input)
 */
export function useKeyboardShortcuts({
  onSwitchTab,
  onStartWindow,
  onJumpToToday,
  onNavigateWeek,
}: KeyboardShortcutOptions) {
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.repeat) {
        return;
      }

      const meta = e.metaKey || e.ctrlKey;
      const target = e.target as HTMLElement;
      const isInput =
        target.tagName === "INPUT" ||
        target.tagName === "TEXTAREA" ||
        target.tagName === "SELECT" ||
        target.isContentEditable;

      // Cmd+1/2/3 → switch tabs
      if (meta && e.key === "1") {
        e.preventDefault();
        onSwitchTab?.("calendar");
      } else if (meta && e.key === "2") {
        e.preventDefault();
        onSwitchTab?.("stats");
      } else if (meta && e.key === "3") {
        e.preventDefault();
        onSwitchTab?.("settings");
      }

      // Cmd+N → start new window
      if (meta && e.key === "n") {
        e.preventDefault();
        onStartWindow?.();
      }

      // Cmd+T → jump to today
      if (meta && e.key === "t") {
        e.preventDefault();
        onJumpToToday?.();
      }

      // Arrow keys → navigate weeks (only when not focused on inputs)
      if (!isInput && !meta && e.key === "ArrowLeft") {
        e.preventDefault();
        onNavigateWeek?.("prev");
      }
      if (!isInput && !meta && e.key === "ArrowRight") {
        e.preventDefault();
        onNavigateWeek?.("next");
      }
    };

    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [onSwitchTab, onStartWindow, onJumpToToday, onNavigateWeek]);
}
