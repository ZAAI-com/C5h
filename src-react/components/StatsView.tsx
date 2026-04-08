import { useMemo } from "react";
import { useStore } from "@/store";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/shadcn-ui/card";
import {
  BarChart,
  Bar,
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Legend,
  Cell,
} from "recharts";
import { Activity, Clock, Calendar, TrendingUp, BarChart3 } from "lucide-react";
import { format, startOfWeek, endOfWeek, eachDayOfInterval, eachWeekOfInterval, isSameDay, getDay, getHours, subWeeks, isWithinInterval } from "date-fns";

export function StatsView() {
  const windows = useStore((state) => state.windows);
  const accounts = useStore((state) => state.accounts);
  const selectedDate = useStore((state) => state.selectedDate);

  const weekData = useMemo(() => {
    const weekStart = startOfWeek(selectedDate);
    const days = eachDayOfInterval({
      start: weekStart,
      end: new Date(weekStart.getTime() + 6 * 24 * 60 * 60 * 1000),
    });

    return days.map((day) => {
      const dayWindows = windows.filter((w) =>
        isSameDay(new Date(w.started_at), day)
      );

      const byAccount: Record<string, number> = {};
      accounts.forEach((a) => {
        const accountWindows = dayWindows.filter(
          (w) => w.account_id === a.id
        );
        byAccount[a.name] = accountWindows.length;
      });

      return {
        day: format(day, "EEE"),
        date: format(day, "MMM d"),
        windows: dayWindows.length,
        ...byAccount,
      };
    });
  }, [windows, accounts, selectedDate]);

  const stats = useMemo(() => {
    const totalWindows = windows.length;
    const accountStats = accounts.map((a) => {
      const accountWindows = windows.filter((w) => w.account_id === a.id);
      const totalHours = accountWindows.reduce((acc, w) => {
        const start = new Date(w.started_at);
        const end = w.ended_at
          ? new Date(w.ended_at)
          : new Date(start.getTime() + a.window_duration_hours * 60 * 60 * 1000);
        return acc + (end.getTime() - start.getTime()) / (1000 * 60 * 60);
      }, 0);
      return {
        account: a,
        windowCount: accountWindows.length,
        totalHours: Math.round(totalHours * 10) / 10,
      };
    });

    const totalHours = accountStats.reduce((acc, s) => acc + s.totalHours, 0);
    const avgHoursPerWindow =
      totalWindows > 0 ? Math.round((totalHours / totalWindows) * 10) / 10 : 0;

    return {
      totalWindows,
      totalHours: Math.round(totalHours * 10) / 10,
      avgHoursPerWindow,
      accountStats,
    };
  }, [windows, accounts]);

  // Heatmap data: Usage by day of week (0 = Sunday, 6 = Saturday)
  const dayOfWeekData = useMemo(() => {
    const dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
    const dayCounts = new Array(7).fill(0);

    windows.forEach((w) => {
      const dayIndex = getDay(new Date(w.started_at));
      dayCounts[dayIndex]++;
    });

    const maxCount = Math.max(...dayCounts, 1);

    return dayNames.map((name, index) => ({
      day: name,
      count: dayCounts[index],
      intensity: dayCounts[index] / maxCount,
    }));
  }, [windows]);

  // Histogram: Time of day distribution (24-hour format)
  const timeOfDayData = useMemo(() => {
    const hourBuckets = new Array(24).fill(0);

    windows.forEach((w) => {
      const hour = getHours(new Date(w.started_at));
      hourBuckets[hour]++;
    });

    return hourBuckets.map((count, hour) => ({
      hour: hour === 0 ? "12am" : hour < 12 ? `${hour}am` : hour === 12 ? "12pm" : `${hour - 12}pm`,
      count,
    }));
  }, [windows]);

  // Avg duration trend: last 8 weeks
  const trendData = useMemo(() => {
    const now = new Date();
    const eightWeeksAgo = subWeeks(now, 8);
    const weekStarts = eachWeekOfInterval({ start: eightWeeksAgo, end: now });

    return weekStarts.map((weekStart) => {
      const weekEnd = endOfWeek(weekStart);
      const weekWindows = windows.filter((w) => {
        const d = new Date(w.started_at);
        return isWithinInterval(d, { start: weekStart, end: weekEnd });
      });

      let avgHours = 0;
      if (weekWindows.length > 0) {
        const totalHours = weekWindows.reduce((acc, w) => {
          const start = new Date(w.started_at);
          const account = accounts.find((a) => a.id === w.account_id);
          const end = w.ended_at
            ? new Date(w.ended_at)
            : new Date(start.getTime() + (account?.window_duration_hours ?? 5) * 3600000);
          return acc + (end.getTime() - start.getTime()) / 3600000;
        }, 0);
        avgHours = Math.round((totalHours / weekWindows.length) * 10) / 10;
      }

      return {
        week: format(weekStart, "MMM d"),
        avgHours,
        windows: weekWindows.length,
      };
    });
  }, [windows, accounts]);

  // Empty state
  if (windows.length === 0 && accounts.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-20 text-center">
        <BarChart3 className="h-16 w-16 text-muted-foreground/30 mb-4" />
        <h2 className="text-xl font-semibold mb-2">No Statistics Yet</h2>
        <p className="text-muted-foreground max-w-md">
          Create an account and start using your AI coding tools to see usage
          statistics here.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Summary Cards */}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium">Total Windows</CardTitle>
            <Activity className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{stats.totalWindows}</div>
            <p className="text-xs text-muted-foreground">This week</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium">Total Hours</CardTitle>
            <Clock className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{stats.totalHours}h</div>
            <p className="text-xs text-muted-foreground">Usage tracked</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium">
              Avg Window Duration
            </CardTitle>
            <TrendingUp className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{stats.avgHoursPerWindow}h</div>
            <p className="text-xs text-muted-foreground">Per window</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium">Active Accounts</CardTitle>
            <Calendar className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {accounts.filter((a) => a.enabled).length}
            </div>
            <p className="text-xs text-muted-foreground">
              of {accounts.length} configured
            </p>
          </CardContent>
        </Card>
      </div>

      {/* Bar Chart */}
      <Card>
        <CardHeader>
          <CardTitle>Windows Per Day</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="h-[300px]">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={weekData}>
                <CartesianGrid strokeDasharray="3 3" className="stroke-muted" />
                <XAxis
                  dataKey="day"
                  tick={{ fill: "hsl(var(--muted-foreground))", fontSize: 12 }}
                />
                <YAxis
                  tick={{ fill: "hsl(var(--muted-foreground))", fontSize: 12 }}
                  allowDecimals={false}
                />
                <Tooltip
                  contentStyle={{
                    backgroundColor: "hsl(var(--card))",
                    border: "1px solid hsl(var(--border))",
                    borderRadius: "var(--radius)",
                  }}
                  labelStyle={{ color: "hsl(var(--foreground))" }}
                />
                <Legend />
                {accounts.map((a) => (
                  <Bar
                    key={a.id}
                    dataKey={a.name}
                    fill={a.color}
                    stackId="windows"
                  />
                ))}
              </BarChart>
            </ResponsiveContainer>
          </div>
        </CardContent>
      </Card>

      {/* Day of Week Heatmap */}
      <Card>
        <CardHeader>
          <CardTitle>Usage by Day of Week</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="h-[300px]">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={dayOfWeekData}>
                <CartesianGrid strokeDasharray="3 3" className="stroke-muted" />
                <XAxis
                  dataKey="day"
                  tick={{ fill: "hsl(var(--muted-foreground))", fontSize: 12 }}
                />
                <YAxis
                  tick={{ fill: "hsl(var(--muted-foreground))", fontSize: 12 }}
                  allowDecimals={false}
                />
                <Tooltip
                  contentStyle={{
                    backgroundColor: "hsl(var(--card))",
                    border: "1px solid hsl(var(--border))",
                    borderRadius: "var(--radius)",
                  }}
                  labelStyle={{ color: "hsl(var(--foreground))" }}
                />
                <Bar dataKey="count" radius={[4, 4, 0, 0]}>
                  {dayOfWeekData.map((entry, index) => (
                    <Cell
                      key={`cell-${index}`}
                      fill={`hsl(var(--primary) / ${Math.max(0.2, entry.intensity)})`}
                    />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
        </CardContent>
      </Card>

      {/* Time of Day Histogram */}
      <Card>
        <CardHeader>
          <CardTitle>Usage by Time of Day</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="h-[300px]">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={timeOfDayData}>
                <CartesianGrid strokeDasharray="3 3" className="stroke-muted" />
                <XAxis
                  dataKey="hour"
                  tick={{ fill: "hsl(var(--muted-foreground))", fontSize: 10 }}
                  interval={2}
                />
                <YAxis
                  tick={{ fill: "hsl(var(--muted-foreground))", fontSize: 12 }}
                  allowDecimals={false}
                />
                <Tooltip
                  contentStyle={{
                    backgroundColor: "hsl(var(--card))",
                    border: "1px solid hsl(var(--border))",
                    borderRadius: "var(--radius)",
                  }}
                  labelStyle={{ color: "hsl(var(--foreground))" }}
                />
                <Bar
                  dataKey="count"
                  fill="hsl(var(--chart-2))"
                  radius={[4, 4, 0, 0]}
                />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </CardContent>
      </Card>

      {/* Avg Duration Trend */}
      <Card>
        <CardHeader>
          <CardTitle>Average Duration Trend (8 Weeks)</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="h-[300px]">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={trendData}>
                <CartesianGrid strokeDasharray="3 3" className="stroke-muted" />
                <XAxis
                  dataKey="week"
                  tick={{ fill: "hsl(var(--muted-foreground))", fontSize: 12 }}
                />
                <YAxis
                  tick={{ fill: "hsl(var(--muted-foreground))", fontSize: 12 }}
                  unit="h"
                />
                <Tooltip
                  contentStyle={{
                    backgroundColor: "hsl(var(--card))",
                    border: "1px solid hsl(var(--border))",
                    borderRadius: "var(--radius)",
                  }}
                  labelStyle={{ color: "hsl(var(--foreground))" }}
                  formatter={(value: number) => [`${value}h`, "Avg Duration"]}
                />
                <Line
                  type="monotone"
                  dataKey="avgHours"
                  stroke="hsl(var(--primary))"
                  strokeWidth={2}
                  dot={{ fill: "hsl(var(--primary))", r: 4 }}
                  activeDot={{ r: 6 }}
                />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </CardContent>
      </Card>

      {/* Account Breakdown */}
      <Card>
        <CardHeader>
          <CardTitle>By Account</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            {stats.accountStats.map((stat) => (
              <div
                key={stat.account.id}
                className="flex items-center justify-between"
              >
                <div className="flex items-center gap-3">
                  <div
                    className="w-3 h-3 rounded-full"
                    style={{ backgroundColor: stat.account.color }}
                  />
                  <span className="font-medium">{stat.account.name}</span>
                </div>
                <div className="text-sm text-muted-foreground">
                  {stat.windowCount} windows · {stat.totalHours}h
                </div>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
