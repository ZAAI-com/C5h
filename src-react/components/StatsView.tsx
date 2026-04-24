import { useEffect, useMemo, useState } from "react";
import { toast } from "sonner";
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
import * as api from "@/lib/api";
import { mapError } from "@/lib/errors";
import type { StatsPayload } from "@/lib/types";

export function StatsView() {
  const accounts = useStore((state) => state.accounts);
  const selectedDate = useStore((state) => state.selectedDate);
  const selectedAccountId = useStore((state) => state.selectedAccountId);
  const [stats, setStats] = useState<StatsPayload | null>(null);

  useEffect(() => {
    const controller = new AbortController();

    api.getStats(
      selectedDate.toISOString(),
      selectedAccountId ?? undefined,
      { signal: controller.signal }
    )
      .then(setStats)
      .catch((err) => {
        const message = err instanceof Error ? err.message : String(err);
        if (message === "Request was cancelled") {
          return;
        }
        toast.warning(`Stats failed to load: ${mapError(message)}`);
      });

    return () => controller.abort();
  }, [selectedDate, selectedAccountId]);

  const chartWeekData = useMemo(
    () =>
      (stats?.week_data ?? []).map((day) => ({
        day: day.day,
        date: day.date,
        windows: day.window_count,
        ...day.account_counts,
      })),
    [stats]
  );

  const accountBreakdown = useMemo(
    () =>
      (stats?.account_breakdown ?? []).map((entry) => {
        const account = accounts.find((candidate) => candidate.id === entry.account_id);
        return {
          ...entry,
          account,
        };
      }),
    [accounts, stats]
  );
  const peakDayLabel =
    stats && stats.day_of_week.length > 0
      ? stats.day_of_week.reduce(
          (top, current) => (current.count > top.count ? current : top),
          stats.day_of_week[0]
        ).day
      : "None";

  if (accounts.length === 0 && !stats) {
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

  const summary = stats?.summary ?? {
    total_windows: 0,
    total_hours: 0,
    avg_duration_hours: 0,
  };
  const rangeLabel = stats?.is_current_week
    ? "This week"
    : `Selected week (${stats?.selected_week_label ?? "loading"})`;

  return (
    <div className="space-y-6">
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium">Total Windows</CardTitle>
            <Activity className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{summary.total_windows}</div>
            <p className="text-xs text-muted-foreground">{rangeLabel}</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium">Total Hours</CardTitle>
            <Clock className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{summary.total_hours}h</div>
            <p className="text-xs text-muted-foreground">{rangeLabel}</p>
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
            <div className="text-2xl font-bold">{summary.avg_duration_hours}h</div>
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
              {accounts.filter((account) => account.enabled).length}
            </div>
            <p className="text-xs text-muted-foreground">
              of {accounts.length} configured
            </p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Windows Per Day</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground mb-4">
            {rangeLabel} spans {summary.total_windows} windows across{" "}
            {stats?.selected_week_label ?? "the selected range"}.
          </p>
          <div className="h-[300px]">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={chartWeekData}>
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
                {accounts.map((account) => (
                  <Bar
                    key={account.id}
                    dataKey={`account_${account.id}`}
                    name={account.name}
                    fill={account.color}
                    stackId="windows"
                  />
                ))}
              </BarChart>
            </ResponsiveContainer>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Usage by Day of Week</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground mb-4">
            Peak selected-week day: {peakDayLabel}.
          </p>
          <div className="h-[300px]">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={stats?.day_of_week ?? []}>
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
                  {(stats?.day_of_week ?? []).map((entry, index) => (
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

      <Card>
        <CardHeader>
          <CardTitle>Usage by Time of Day</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground mb-4">
            Selected-week starts are distributed by local hour, not by the currently loaded calendar rows.
          </p>
          <div className="h-[300px]">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={stats?.time_of_day ?? []}>
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

      <Card>
        <CardHeader>
          <CardTitle>Average Duration Trend (8 Weeks)</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground mb-4">
            Rolling 8-week trend anchored to the currently selected week.
          </p>
          <div className="h-[300px]">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={stats?.duration_trend ?? []}>
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
                  dataKey="avg_hours"
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

      <Card>
        <CardHeader>
          <CardTitle>By Account</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground mb-4">
            Account totals reflect the selected week only.
          </p>
          <div className="space-y-4">
            {accountBreakdown.map((entry) => (
              <div
                key={entry.account_id}
                className="flex items-center justify-between"
              >
                <div className="flex items-center gap-3">
                  <div
                    className="w-3 h-3 rounded-full"
                    style={{ backgroundColor: entry.account?.color ?? "#9ca3af" }}
                  />
                  <span className="font-medium">
                    {entry.account?.name ?? `Account ${entry.account_id}`}
                  </span>
                </div>
                <div className="text-sm text-muted-foreground">
                  {entry.window_count} windows · {entry.total_hours}h
                </div>
              </div>
            ))}
            {accountBreakdown.length === 0 && (
              <p className="text-sm text-muted-foreground">
                No usage windows for {rangeLabel.toLowerCase()}.
              </p>
            )}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
