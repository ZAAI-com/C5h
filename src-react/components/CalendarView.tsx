import { useEffect, useMemo, useState } from "react";
import { useStore } from "@/store";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/shadcn-ui/card";
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
} from "@/components/shadcn-ui/dialog";
import { ChevronLeft, ChevronRight, CalendarIcon } from "lucide-react";
import { StatusCard } from "./StatusCard";
import { MonitoringCard } from "./MonitoringCard";
import {
  format,
  startOfWeek,
  endOfWeek,
  eachDayOfInterval,
  isSameDay,
  isToday,
  addWeeks,
  subWeeks,
} from "date-fns";
import { getWeekBoundaries } from "@/lib/api";

const HOURS = Array.from({ length: 24 }, (_, i) => i);

export function CalendarView() {
  const selectedDate = useStore((state) => state.selectedDate);
  const setSelectedDate = useStore((state) => state.setSelectedDate);
  const windows = useStore((state) => state.windows);
  const accounts = useStore((state) => state.accounts);
  const schedules = useStore((state) => state.schedules);
  const fetchWindows = useStore((state) => state.fetchWindows);

  // Current time for the "now" indicator line
  const [now, setNow] = useState(new Date());
  useEffect(() => {
    const timer = setInterval(() => setNow(new Date()), 60_000);
    return () => clearInterval(timer);
  }, []);

  const createSchedule = useStore((state) => state.createSchedule);

  // Click-to-schedule state
  const [scheduleDialogOpen, setScheduleDialogOpen] = useState(false);
  const [scheduleDate, setScheduleDate] = useState("");
  const [scheduleTime, setScheduleTime] = useState("");
  const [scheduleAccountId, setScheduleAccountId] = useState<string>("");

  const enabledAccounts = accounts.filter((a) => a.enabled);

  const handleCellClick = (day: Date, hour: number) => {
    setScheduleDate(format(day, "yyyy-MM-dd"));
    setScheduleTime(`${hour.toString().padStart(2, "0")}:00`);
    setScheduleAccountId(enabledAccounts[0]?.id?.toString() ?? "");
    setScheduleDialogOpen(true);
  };

  const handleCreateSchedule = async () => {
    if (!scheduleAccountId || !scheduleDate || !scheduleTime) return;
    const scheduledAt = new Date(`${scheduleDate}T${scheduleTime}`).toISOString();
    await createSchedule(parseInt(scheduleAccountId), scheduledAt);
    setScheduleDialogOpen(false);
  };

  const weekDays = useMemo(() => {
    const start = startOfWeek(selectedDate);
    const end = endOfWeek(selectedDate);
    return eachDayOfInterval({ start, end });
  }, [selectedDate]);

  const handlePrevWeek = async () => {
    const newDate = subWeeks(selectedDate, 1);
    setSelectedDate(newDate);
    const { start, end } = getWeekBoundaries(newDate);
    await fetchWindows(start, end);
  };

  const handleNextWeek = async () => {
    const newDate = addWeeks(selectedDate, 1);
    setSelectedDate(newDate);
    const { start, end } = getWeekBoundaries(newDate);
    await fetchWindows(start, end);
  };

  const handleToday = async () => {
    const newDate = new Date();
    setSelectedDate(newDate);
    const { start, end } = getWeekBoundaries(newDate);
    await fetchWindows(start, end);
  };

  // Pre-compute per-day lookups once when data changes
  const windowsByDay = useMemo(() => {
    const map = new Map<string, typeof windows>();
    for (const day of weekDays) {
      const key = day.toISOString();
      map.set(
        key,
        windows.filter((w) => isSameDay(new Date(w.started_at), day)),
      );
    }
    return map;
  }, [windows, weekDays]);

  const schedulesByDay = useMemo(() => {
    const map = new Map<string, typeof schedules>();
    for (const day of weekDays) {
      const key = day.toISOString();
      map.set(
        key,
        schedules.filter((s) => isSameDay(new Date(s.scheduled_at), day)),
      );
    }
    return map;
  }, [schedules, weekDays]);

  // Pre-compute account lookup maps
  const accountColorMap = useMemo(() => {
    const map = new Map<number, string>();
    for (const a of accounts) {
      if (a.id != null) map.set(a.id, a.color);
    }
    return map;
  }, [accounts]);

  const accountNameMap = useMemo(() => {
    const map = new Map<number, string>();
    for (const a of accounts) {
      if (a.id != null) map.set(a.id, a.name);
    }
    return map;
  }, [accounts]);

  const getAccountColor = (accountId: number) =>
    accountColorMap.get(accountId) ?? "#6366f1";

  const getAccountName = (accountId: number) =>
    accountNameMap.get(accountId) ?? "Unknown";

  const formatHour = (date: Date) => {
    return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  };

  return (
    <div className="space-y-6">
      <div className="grid gap-6 lg:grid-cols-4">
        <div className="lg:col-span-1 space-y-4">
          <StatusCard />
          <MonitoringCard />
        </div>

        <Card className="lg:col-span-3">
          <CardHeader className="pb-4">
            <div className="flex items-center justify-between">
              <CardTitle className="flex items-center gap-2">
                <CalendarIcon className="h-5 w-5" />
                {format(selectedDate, "MMMM yyyy")}
              </CardTitle>
              <div className="flex items-center gap-2">
                <Button variant="outline" size="sm" onClick={handlePrevWeek} aria-label="Previous week">
                  <ChevronLeft className="h-4 w-4" />
                </Button>
                <Button variant="outline" size="sm" onClick={handleToday}>
                  Today
                </Button>
                <Button variant="outline" size="sm" onClick={handleNextWeek} aria-label="Next week">
                  <ChevronRight className="h-4 w-4" />
                </Button>
              </div>
            </div>
          </CardHeader>
          <CardContent className="p-0 relative">
            {windows.length === 0 && schedules.length === 0 && (
              <div className="absolute inset-0 flex items-center justify-center z-10 pointer-events-none">
                <div className="text-center p-6 bg-background/80 rounded-lg">
                  <CalendarIcon className="h-12 w-12 text-muted-foreground/30 mx-auto mb-3" />
                  <p className="text-muted-foreground text-sm">
                    No usage windows this week. Click any cell to schedule one,
                    or start using a CLI tool to track automatically.
                  </p>
                </div>
              </div>
            )}
            <div className="overflow-x-auto">
              <div className="min-w-[700px]">
                {/* Header with days */}
                <div className="grid grid-cols-8 border-b">
                  <div className="p-2 text-center text-xs text-muted-foreground border-r" title={Intl.DateTimeFormat().resolvedOptions().timeZone}>
                    Time
                  </div>
                  {weekDays.map((day) => (
                    <div
                      key={day.toISOString()}
                      className={`p-2 text-center ${
                        isToday(day) ? "bg-primary/5" : ""
                      }`}
                    >
                      <div className="text-xs text-muted-foreground">
                        {format(day, "EEE")}
                      </div>
                      <div
                        className={`text-sm font-medium ${
                          isToday(day) ? "text-primary" : ""
                        }`}
                      >
                        {format(day, "d")}
                      </div>
                    </div>
                  ))}
                </div>

                {/* Time grid */}
                <div className="relative" role="grid" aria-label="Weekly usage calendar">
                  {/* Current time indicator line */}
                  {weekDays.some((day) => isToday(day)) && (
                    <div
                      className="absolute left-0 right-0 border-t-2 border-red-500 z-20 pointer-events-none"
                      style={{
                        top: `${((now.getHours() * 60 + now.getMinutes()) / (24 * 60)) * 100}%`,
                      }}
                    >
                      <div className="absolute -left-1 -top-1 w-2 h-2 rounded-full bg-red-500" />
                    </div>
                  )}
                  {HOURS.map((hour) => (
                    <div key={hour} className="grid grid-cols-8 border-b h-8" role="row">
                      <div className="p-1 text-xs text-muted-foreground text-right pr-2 border-r">
                        {hour.toString().padStart(2, "0")}:00
                      </div>
                      {weekDays.map((day) => {
                        const dayWindows = windowsByDay.get(day.toISOString()) ?? [];
                        const daySchedules = schedulesByDay.get(day.toISOString()) ?? [];

                        const windowsAtHour = dayWindows.filter((w) => {
                          const windowStart = new Date(w.started_at);
                          const windowEnd = w.ended_at
                            ? new Date(w.ended_at)
                            : new Date(
                                windowStart.getTime() + 5 * 60 * 60 * 1000
                              );
                          const hourStart = new Date(day);
                          hourStart.setHours(hour, 0, 0, 0);
                          const hourEnd = new Date(day);
                          hourEnd.setHours(hour + 1, 0, 0, 0);
                          return windowStart < hourEnd && windowEnd > hourStart;
                        });

                        const schedulesAtHour = daySchedules.filter((s) => {
                          const scheduleDate = new Date(s.scheduled_at);
                          return scheduleDate.getHours() === hour;
                        });

                        return (
                          <div
                            key={`${day.toISOString()}-${hour}`}
                            role="gridcell"
                            tabIndex={0}
                            aria-label={`${format(day, "EEEE, MMM d")} at ${hour.toString().padStart(2, "0")}:00`}
                            className={`border-r relative cursor-pointer hover:bg-muted/50 focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-inset outline-none ${
                              isToday(day) ? "bg-primary/5" : ""
                            }`}
                            onClick={() => handleCellClick(day, hour)}
                            onKeyDown={(e) => {
                              if (e.key === "Enter" || e.key === " ") {
                                e.preventDefault();
                                handleCellClick(day, hour);
                              }
                            }}
                          >
                            {windowsAtHour.map((w, i) => {
                              const startTime = new Date(w.started_at);
                              const endTime = w.ended_at
                                ? new Date(w.ended_at)
                                : null;
                              const name = getAccountName(w.account_id);
                              const usageLabel = w.usage_percent != null
                                ? ` (${w.usage_percent}%)`
                                : "";
                              const timeRange = endTime
                                ? `${formatHour(startTime)}–${formatHour(endTime)}`
                                : `${formatHour(startTime)}–now`;
                              return (
                                <div
                                  key={w.id}
                                  className="absolute inset-0 opacity-60"
                                  style={{
                                    backgroundColor: getAccountColor(
                                      w.account_id
                                    ),
                                    marginLeft: `${i * 4}px`,
                                  }}
                                  title={`${name} ${timeRange}${usageLabel}`}
                                />
                              );
                            })}
                            {schedulesAtHour.map((s, i) => (
                              <div
                                key={s.id}
                                className="absolute inset-1 rounded border-2 border-dashed border-orange-500 bg-orange-500/10"
                                style={{ marginLeft: `${i * 4}px` }}
                                title={`Scheduled trigger at ${format(
                                  new Date(s.scheduled_at),
                                  "HH:mm"
                                )}`}
                              />
                            ))}
                          </div>
                        );
                      })}
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Click-to-schedule dialog */}
      <Dialog open={scheduleDialogOpen} onOpenChange={setScheduleDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Schedule Window</DialogTitle>
            <DialogDescription>
              Create a scheduled trigger for the selected time slot.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label htmlFor="schedule-account">Account</Label>
              <Select
                value={scheduleAccountId}
                onValueChange={setScheduleAccountId}
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
              <Label htmlFor="schedule-date">Date</Label>
              <Input
                id="schedule-date"
                type="date"
                value={scheduleDate}
                onChange={(e) => setScheduleDate(e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="schedule-time">Time</Label>
              <Input
                id="schedule-time"
                type="time"
                value={scheduleTime}
                onChange={(e) => setScheduleTime(e.target.value)}
              />
            </div>
          </div>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setScheduleDialogOpen(false)}
            >
              Cancel
            </Button>
            <Button
              onClick={handleCreateSchedule}
              disabled={!scheduleAccountId || !scheduleDate || !scheduleTime}
            >
              Create Schedule
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
