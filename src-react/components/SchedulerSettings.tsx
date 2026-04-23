import { useState } from "react";
import { useStore } from "@/store";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/shadcn-ui/card";
import { Button } from "@/components/shadcn-ui/button";
import { Input } from "@/components/shadcn-ui/input";
import { Label } from "@/components/shadcn-ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/shadcn-ui/select";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/shadcn-ui/dialog";
import { Calendar, Clock, Plus, Trash2, Play, Square } from "lucide-react";
import { format } from "date-fns";

export function SchedulerSettings() {
  const accounts = useStore((state) => state.accounts);
  const schedules = useStore((state) => state.schedules);
  const createSchedule = useStore((state) => state.createSchedule);
  const deleteSchedule = useStore((state) => state.deleteSchedule);
  const installSchedule = useStore((state) => state.installSchedule);
  const uninstallSchedule = useStore((state) => state.uninstallSchedule);

  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const [selectedAccountId, setSelectedAccountId] = useState<string>("");
  const [scheduledDate, setScheduledDate] = useState("");
  const [scheduledTime, setScheduledTime] = useState("");

  const enabledAccounts = accounts.filter((a) => a.enabled);

  const handleCreateSchedule = async () => {
    if (!selectedAccountId || !scheduledDate || !scheduledTime) return;

    const scheduledAt = new Date(`${scheduledDate}T${scheduledTime}`).toISOString();
    await createSchedule(parseInt(selectedAccountId), scheduledAt);
    setIsDialogOpen(false);
    setSelectedAccountId("");
    setScheduledDate("");
    setScheduledTime("");
  };

  const handleDeleteSchedule = async (id: number) => {
    if (confirm("Are you sure you want to delete this scheduled trigger?")) {
      await deleteSchedule(id);
    }
  };

  const handleToggleInstall = async (scheduleId: number, isInstalled: boolean, accountId: number) => {
    if (isInstalled) {
      await uninstallSchedule(scheduleId);
    } else {
      const account = accounts.find((a) => a.id === accountId);
      if (account) {
        await installSchedule(scheduleId, account.cli_command);
      }
    }
  };

  const getAccountById = (id: number) => accounts.find((a) => a.id === id);

  const pendingSchedules = schedules.filter((s) => s.status === "pending");

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle className="flex items-center gap-2">
              <Calendar className="h-5 w-5" />
              Scheduled Triggers
            </CardTitle>
            <CardDescription>
              Schedule automatic window triggers using macOS launchd
            </CardDescription>
          </div>
          <Dialog open={isDialogOpen} onOpenChange={setIsDialogOpen}>
            <DialogTrigger asChild>
              <Button disabled={enabledAccounts.length === 0}>
                <Plus className="h-4 w-4 mr-2" />
                Add Schedule
              </Button>
            </DialogTrigger>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Create Scheduled Trigger</DialogTitle>
                <DialogDescription>
                  Schedule a time to automatically start a new usage window.
                </DialogDescription>
              </DialogHeader>

              <div className="space-y-4 py-4">
                <div className="space-y-2">
                  <Label htmlFor="account">Account</Label>
                  <Select
                    value={selectedAccountId}
                    onValueChange={setSelectedAccountId}
                  >
                    <SelectTrigger>
                      <SelectValue placeholder="Select account" />
                    </SelectTrigger>
                    <SelectContent>
                      {enabledAccounts.map((account) => (
                        <SelectItem key={account.id} value={String(account.id)}>
                          <div className="flex items-center gap-2">
                            <div
                              className="w-3 h-3 rounded-full"
                              style={{ backgroundColor: account.color }}
                            />
                            {account.name}
                          </div>
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>

                <div className="space-y-2">
                  <Label htmlFor="date">Date</Label>
                  <Input
                    id="date"
                    type="date"
                    value={scheduledDate}
                    onChange={(e) => setScheduledDate(e.target.value)}
                    min={format(new Date(), "yyyy-MM-dd")}
                  />
                </div>

                <div className="space-y-2">
                  <Label htmlFor="time">Time</Label>
                  <Input
                    id="time"
                    type="time"
                    value={scheduledTime}
                    onChange={(e) => setScheduledTime(e.target.value)}
                  />
                </div>
              </div>

              <DialogFooter>
                <Button variant="outline" onClick={() => setIsDialogOpen(false)}>
                  Cancel
                </Button>
                <Button
                  onClick={handleCreateSchedule}
                  disabled={!selectedAccountId || !scheduledDate || !scheduledTime}
                >
                  Create Schedule
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </div>
      </CardHeader>
      <CardContent>
        {pendingSchedules.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            No scheduled triggers. Add one to automatically start usage windows.
          </p>
        ) : (
          <div className="space-y-2">
            {pendingSchedules.map((schedule) => {
              const account = getAccountById(schedule.account_id);
              const isInstalled = !!schedule.plist_path;
              const scheduledAt = new Date(schedule.scheduled_at);

              return (
                <div
                  key={schedule.id}
                  className="flex items-center justify-between p-3 rounded-lg bg-muted"
                >
                  <div className="flex items-center gap-3">
                    {account && (
                      <div
                        className="w-3 h-3 rounded-full"
                        style={{ backgroundColor: account.color }}
                      />
                    )}
                    <div>
                      <p className="font-medium">{account?.name ?? "Unknown"}</p>
                      <p className="text-sm text-muted-foreground flex items-center gap-1">
                        <Clock className="h-3 w-3" />
                        {format(scheduledAt, "MMM d, yyyy 'at' h:mm a")}
                      </p>
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    {isInstalled ? (
                      <span className="text-xs text-green-600 px-2 py-1 bg-green-100 rounded">
                        Active
                      </span>
                    ) : (
                      <span className="text-xs text-yellow-600 px-2 py-1 bg-yellow-100 rounded">
                        Not installed
                      </span>
                    )}
                    <Button
                      variant="ghost"
                      size="icon"
                      title={isInstalled ? "Uninstall from launchd" : "Install to launchd"}
                      aria-label={isInstalled ? "Uninstall schedule" : "Install schedule"}
                      onClick={() =>
                        schedule.id &&
                        handleToggleInstall(schedule.id, isInstalled, schedule.account_id)
                      }
                    >
                      {isInstalled ? (
                        <Square className="h-4 w-4" />
                      ) : (
                        <Play className="h-4 w-4" />
                      )}
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      aria-label="Delete schedule"
                      onClick={() => schedule.id && handleDeleteSchedule(schedule.id)}
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                </div>
              );
            })}
          </div>
        )}

        <div className="mt-4 p-3 rounded-lg bg-orange-500/10 border border-orange-500/20">
          <p className="text-sm text-orange-700 dark:text-orange-300">
            <strong>Note:</strong> Scheduled triggers use macOS launchd and will run even when the
            app is closed. They trigger the CLI command to start a new usage window.
          </p>
        </div>
      </CardContent>
    </Card>
  );
}
