import { useEffect } from "react";
import { useStore } from "@/store";
import { useCurrentWindow } from "@/hooks";
import { Progress } from "@/components/shadcn-ui/progress";
import { Button } from "@/components/shadcn-ui/button";
import { Separator } from "@/components/shadcn-ui/separator";
import { Play, Settings, LayoutDashboard, Clock, AlertCircle } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";

export function PopoverWindow() {
  const currentWindow = useStore((state) => state.currentWindow);
  const accounts = useStore((state) => state.accounts);
  const schedules = useStore((state) => state.schedules);
  const windows = useStore((state) => state.windows);
  const createWindow = useStore((state) => state.createWindow);
  const initialize = useStore((state) => state.initialize);
  const status = useCurrentWindow();

  // Initialize data on mount
  useEffect(() => {
    initialize();
  }, [initialize]);

  const account = currentWindow
    ? accounts.find((a) => a.id === currentWindow.account_id)
    : accounts.find((a) => a.enabled);

  const handleStartWindow = async () => {
    if (account?.id) {
      await createWindow(account.id, "manual");
    }
  };

  const handleOpenApp = async () => {
    // Show main window using our custom command
    await invoke("show_main_window").catch(console.error);
  };

  const handleOpenSettings = async () => {
    // Show main window and navigate to settings (via URL hash or state)
    await handleOpenApp();
  };

  // Calculate week statistics
  const thisWeekWindows = windows.length;
  const totalHours = windows.reduce((acc, w) => {
    const windowAccount = accounts.find((a) => a.id === w.account_id);
    const duration = windowAccount?.window_duration_hours ?? 5;
    if (w.ended_at) {
      const start = new Date(w.started_at);
      const end = new Date(w.ended_at);
      return acc + (end.getTime() - start.getTime()) / (60 * 60 * 1000);
    }
    return acc + duration;
  }, 0);

  // Get next scheduled trigger
  const nextSchedule = schedules
    .filter((s) => s.status === "pending")
    .sort((a, b) => new Date(a.scheduled_at).getTime() - new Date(b.scheduled_at).getTime())[0];

  return (
    <div className="w-[300px] bg-background text-foreground p-4 space-y-4">
      {/* Current Window Status */}
      {status.isActive ? (
        <div className="space-y-3">
          <div className="flex items-center gap-2">
            {account && (
              <div
                className="w-3 h-3 rounded-full"
                style={{ backgroundColor: account.color }}
              />
            )}
            <span className="font-semibold">{account?.name ?? "Unknown"}</span>
            {status.isEndingSoon && (
              <AlertCircle className="h-4 w-4 text-orange-500 ml-auto" />
            )}
          </div>

          <div className="space-y-2">
            <Progress value={status.percentUsed} className="h-2" />
            <div className="flex justify-between text-sm">
              <span className="text-muted-foreground">
                {Math.round(status.percentUsed)}% used
              </span>
              <span className="font-medium">
                Resets: {status.endTime?.toLocaleTimeString([], {
                  hour: "numeric",
                  minute: "2-digit",
                })}
              </span>
            </div>
          </div>
        </div>
      ) : (
        <div className="space-y-3">
          <div className="flex items-center gap-2 text-muted-foreground">
            <Clock className="h-4 w-4" />
            <span>No active window</span>
          </div>
        </div>
      )}

      <Separator />

      {/* Quick Start Button */}
      {account && (
        <Button
          onClick={handleStartWindow}
          className="w-full"
          variant={status.isActive ? "outline" : "default"}
        >
          <Play className="mr-2 h-4 w-4" />
          Start New Window
        </Button>
      )}

      <Separator />

      {/* Week Statistics */}
      <div className="space-y-2">
        <div className="flex justify-between text-sm">
          <span className="text-muted-foreground">This Week</span>
          <span>{thisWeekWindows} windows ({totalHours.toFixed(1)}h)</span>
        </div>

        {nextSchedule && (
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">Next scheduled</span>
            <span className="text-orange-500">
              {new Date(nextSchedule.scheduled_at).toLocaleString([], {
                month: "short",
                day: "numeric",
                hour: "numeric",
                minute: "2-digit",
              })}
            </span>
          </div>
        )}
      </div>

      <Separator />

      {/* Action Buttons */}
      <div className="flex gap-2">
        <Button
          variant="outline"
          size="sm"
          className="flex-1"
          onClick={handleOpenSettings}
        >
          <Settings className="mr-2 h-4 w-4" />
          Settings
        </Button>
        <Button
          variant="outline"
          size="sm"
          className="flex-1"
          onClick={handleOpenApp}
        >
          <LayoutDashboard className="mr-2 h-4 w-4" />
          Open App
        </Button>
      </div>
    </div>
  );
}
