import { useMemo } from "react";
import { useStore } from "@/store";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/shadcn-ui/card";
import { Button } from "@/components/shadcn-ui/button";
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

  const getWindowsForDay = (day: Date) => {
    return windows.filter((w) => {
      const windowDate = new Date(w.started_at);
      return isSameDay(windowDate, day);
    });
  };

  const getSchedulesForDay = (day: Date) => {
    return schedules.filter((s) => {
      const scheduleDate = new Date(s.scheduled_at);
      return isSameDay(scheduleDate, day);
    });
  };

  const getAccountColor = (accountId: number) => {
    return accounts.find((a) => a.id === accountId)?.color ?? "#6366f1";
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
                <Button variant="outline" size="sm" onClick={handlePrevWeek}>
                  <ChevronLeft className="h-4 w-4" />
                </Button>
                <Button variant="outline" size="sm" onClick={handleToday}>
                  Today
                </Button>
                <Button variant="outline" size="sm" onClick={handleNextWeek}>
                  <ChevronRight className="h-4 w-4" />
                </Button>
              </div>
            </div>
          </CardHeader>
          <CardContent className="p-0">
            <div className="overflow-x-auto">
              <div className="min-w-[700px]">
                {/* Header with days */}
                <div className="grid grid-cols-8 border-b">
                  <div className="p-2 text-center text-xs text-muted-foreground border-r">
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
                <div className="relative">
                  {HOURS.map((hour) => (
                    <div key={hour} className="grid grid-cols-8 border-b h-8">
                      <div className="p-1 text-xs text-muted-foreground text-right pr-2 border-r">
                        {hour.toString().padStart(2, "0")}:00
                      </div>
                      {weekDays.map((day) => {
                        const dayWindows = getWindowsForDay(day);
                        const daySchedules = getSchedulesForDay(day);

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
                            className={`border-r relative ${
                              isToday(day) ? "bg-primary/5" : ""
                            }`}
                          >
                            {windowsAtHour.map((w, i) => (
                              <div
                                key={w.id}
                                className="absolute inset-0 opacity-60"
                                style={{
                                  backgroundColor: getAccountColor(
                                    w.account_id
                                  ),
                                  marginLeft: `${i * 4}px`,
                                }}
                                title={`Window #${w.id}`}
                              />
                            ))}
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
    </div>
  );
}
