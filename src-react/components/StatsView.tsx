import { useMemo } from "react";
import { useStore } from "@/store";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/shadcn-ui/card";
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Legend,
} from "recharts";
import { Activity, Clock, Calendar, TrendingUp } from "lucide-react";
import { format, startOfWeek, eachDayOfInterval, isSameDay } from "date-fns";

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
