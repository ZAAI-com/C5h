import { useStore } from "@/store";
import { useCurrentWindow } from "@/hooks";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/shadcn-ui/card";
import { Progress } from "@/components/shadcn-ui/progress";
import { Button } from "@/components/shadcn-ui/button";
import { Clock, Play, AlertCircle } from "lucide-react";

export function StatusCard() {
  const currentWindow = useStore((state) => state.currentWindow);
  const accounts = useStore((state) => state.accounts);
  const createWindow = useStore((state) => state.createWindow);
  const status = useCurrentWindow();

  const usageByAccount = useStore((state) => state.usageByAccount);

  const account = currentWindow
    ? accounts.find((a) => a.id === currentWindow.account_id)
    : accounts.find((a) => a.enabled);

  // Use real CLI polling data when available, fall back to time-based calculation
  const accountUsage = currentWindow
    ? usageByAccount[currentWindow.account_id]
    : undefined;
  const displayPercent = accountUsage?.session_percent ?? status.percentUsed;

  const handleStartWindow = async () => {
    if (account?.id) {
      await createWindow(account.id, "manual");
    }
  };

  if (!status.isActive) {
    return (
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-lg flex items-center gap-2">
            <Clock className="h-5 w-5 text-muted-foreground" />
            No Active Window
          </CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground mb-4">
            Start a new usage window to track your AI tool usage.
          </p>
          {account && (
            <Button onClick={handleStartWindow} className="w-full">
              <Play className="mr-2 h-4 w-4" />
              Start {account.name} Window
            </Button>
          )}
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className={status.isEndingSoon ? "border-orange-500" : ""}>
      <CardHeader className="pb-2">
        <CardTitle className="text-lg flex items-center gap-2">
          {account && (
            <div
              className="w-3 h-3 rounded-full"
              role="img"
              aria-label={`${account.name} color`}
              style={{ backgroundColor: account.color }}
            />
          )}
          {account?.name ?? "Unknown Account"}
          {status.isEndingSoon && (
            <AlertCircle className="h-4 w-4 text-orange-500 ml-auto" />
          )}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div>
          <div className="flex justify-between text-sm mb-2">
            <span className="text-muted-foreground">Time Remaining</span>
            <span className="font-medium">
              {status.hoursRemaining}h {status.minutesRemaining}m
            </span>
          </div>
          <Progress
            value={displayPercent}
            className="h-2"
            aria-label="Window usage"
            aria-valuenow={Math.round(displayPercent)}
            aria-valuemin={0}
            aria-valuemax={100}
          />
        </div>

        <div className="flex justify-between text-sm">
          <span className="text-muted-foreground">Used</span>
          <span>{Math.round(displayPercent)}%</span>
        </div>

        {accountUsage?.weekly_percent != null && (
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">Weekly</span>
            <span>{Math.round(accountUsage.weekly_percent)}% used</span>
          </div>
        )}

        {accountUsage?.reset_time && (
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">Resets</span>
            <span>{accountUsage.reset_time}</span>
          </div>
        )}

        {status.endTime && (
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">Expires</span>
            <span>
              {status.endTime.toLocaleTimeString([], {
                hour: "2-digit",
                minute: "2-digit",
              })}
            </span>
          </div>
        )}

        {status.isEndingSoon && (
          <p className="text-sm text-orange-500 flex items-center gap-2">
            <AlertCircle className="h-4 w-4" />
            Window ending soon!
          </p>
        )}
      </CardContent>
    </Card>
  );
}
