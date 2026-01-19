import { useMonitoring } from "@/hooks";
import { useStore } from "@/store";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/shadcn-ui/card";
import { Button } from "@/components/shadcn-ui/button";
import { Switch } from "@/components/shadcn-ui/switch";
import { Label } from "@/components/shadcn-ui/label";
import { Activity, Scan, Loader2, CheckCircle, Circle } from "lucide-react";
import { format } from "date-fns";

export function MonitoringCard() {
  const { status, isLoading, startMonitoring, stopMonitoring, scanNow } =
    useMonitoring();
  const accounts = useStore((state) => state.accounts);

  const getAccountName = (accountId: number | null) => {
    if (!accountId) return "Unknown";
    return accounts.find((a) => a.id === accountId)?.name ?? "Unknown";
  };

  const getAccountColor = (accountId: number | null) => {
    if (!accountId) return "#888";
    return accounts.find((a) => a.id === accountId)?.color ?? "#888";
  };

  const handleToggle = async (enabled: boolean) => {
    if (enabled) {
      await startMonitoring();
    } else {
      await stopMonitoring();
    }
  };

  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <CardTitle className="text-lg flex items-center gap-2">
            <Activity className="h-5 w-5" />
            CLI Monitoring
          </CardTitle>
          <div className="flex items-center gap-2">
            <Label
              htmlFor="monitoring-toggle"
              className="text-sm text-muted-foreground"
            >
              {status.is_running ? "Active" : "Inactive"}
            </Label>
            <Switch
              id="monitoring-toggle"
              checked={status.is_running}
              onCheckedChange={handleToggle}
              disabled={isLoading}
            />
          </div>
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        {status.is_running && (
          <>
            <div className="flex items-center gap-2 text-sm">
              {status.detected_processes.length > 0 ? (
                <CheckCircle className="h-4 w-4 text-green-500" />
              ) : (
                <Circle className="h-4 w-4 text-muted-foreground" />
              )}
              <span>
                {status.detected_processes.length > 0
                  ? `${status.detected_processes.length} process(es) detected`
                  : "Monitoring for CLI activity..."}
              </span>
            </div>

            {status.detected_processes.length > 0 && (
              <div className="space-y-2">
                {status.detected_processes.map((proc) => (
                  <div
                    key={proc.pid}
                    className="flex items-center gap-2 p-2 rounded bg-muted text-sm"
                  >
                    <div
                      className="w-2 h-2 rounded-full"
                      style={{ backgroundColor: getAccountColor(proc.account_id) }}
                    />
                    <span className="font-medium">
                      {getAccountName(proc.account_id)}
                    </span>
                    <span className="text-muted-foreground truncate flex-1">
                      PID {proc.pid}
                    </span>
                  </div>
                ))}
              </div>
            )}

            {status.last_check && (
              <p className="text-xs text-muted-foreground">
                Last check: {format(new Date(status.last_check), "HH:mm:ss")}
              </p>
            )}
          </>
        )}

        {!status.is_running && (
          <p className="text-sm text-muted-foreground">
            Enable monitoring to automatically detect when you start using Claude
            Code, Codex, or Gemini CLI tools.
          </p>
        )}

        <Button
          variant="outline"
          size="sm"
          className="w-full"
          onClick={scanNow}
          disabled={isLoading}
        >
          {isLoading ? (
            <Loader2 className="h-4 w-4 mr-2 animate-spin" />
          ) : (
            <Scan className="h-4 w-4 mr-2" />
          )}
          Scan Now
        </Button>
      </CardContent>
    </Card>
  );
}
