import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Card, CardContent } from "@/components/shadcn-ui/card";
import { Button } from "@/components/shadcn-ui/button";
import { Sparkles, X } from "lucide-react";
import {
  dismissInsight,
  getInsights,
  type Insight,
} from "@/lib/api";
import { useStore } from "@/store";
import { localDateTimeToOffsetRfc3339 } from "@/lib/datetime";

const WEEKDAY_NAMES = [
  "Sunday",
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
];

/**
 * Surfaces the top-confidence usage habit as an actionable banner.
 *
 * Invisible when:
 * - The Rust side returned no insights (fresh user, random usage, or
 *   everything dismissed).
 * - The user clicks Dismiss for the current top insight.
 *
 * "Schedule it" creates a one-time scheduled trigger at the next occurrence
 * of (weekday, hour:minute) in local time, reusing the existing schedule
 * pipeline (which then installs the launchd plist).
 */
export function InsightBanner() {
  const [insight, setInsight] = useState<Insight | null>(null);
  const [busy, setBusy] = useState(false);
  const createSchedule = useStore((s) => s.createSchedule);

  useEffect(() => {
    let cancelled = false;
    getInsights()
      .then((insights) => {
        if (!cancelled) setInsight(insights[0] ?? null);
      })
      .catch(() => {
        // Silent failure — insights are a nice-to-have, not blocking.
      });
    return () => {
      cancelled = true;
    };
  }, []);

  if (!insight) return null;

  const weekdayName = WEEKDAY_NAMES[insight.weekday] ?? "weekdays";
  const timeLabel = `${String(insight.hour).padStart(2, "0")}:${String(
    insight.minute,
  ).padStart(2, "0")}`;

  const handleSchedule = async () => {
    setBusy(true);
    try {
      const next = nextOccurrence(insight.weekday, insight.hour, insight.minute);
      const date = `${next.getFullYear()}-${pad(next.getMonth() + 1)}-${pad(
        next.getDate(),
      )}`;
      const time = `${pad(next.getHours())}:${pad(next.getMinutes())}`;
      const scheduledAt = localDateTimeToOffsetRfc3339(date, time);
      await createSchedule(insight.account_id, scheduledAt);
      // Persist dismissal so we don't re-suggest the same habit next mount.
      await dismissInsight(insight.key).catch(() => {});
      setInsight(null);
      toast.success(`Scheduled ${insight.account_name} window for ${weekdayName} ${timeLabel}.`);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      toast.error(`Could not schedule: ${msg}`);
    } finally {
      setBusy(false);
    }
  };

  const handleDismiss = async () => {
    setBusy(true);
    try {
      await dismissInsight(insight.key);
      setInsight(null);
    } catch (err) {
      // Even if persistence fails, hide the banner for this session.
      setInsight(null);
      console.error("Failed to persist insight dismissal", err);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Card className="border-primary/30 bg-primary/5">
      <CardContent className="flex items-start gap-3 p-4">
        <Sparkles className="h-5 w-5 text-primary mt-0.5 flex-shrink-0" />
        <div className="flex-1 min-w-0">
          <p className="text-sm">
            You usually start a <strong>{insight.account_name}</strong> window
            around <strong>{timeLabel}</strong> on <strong>{weekdayName}s</strong>.
            Schedule a wake-trigger so the next one starts ready to go?
          </p>
          <p className="text-xs text-muted-foreground mt-1">
            Based on {insight.occurrences} recent windows ·{" "}
            {Math.round(insight.confidence * 100)}% confidence
          </p>
          <div className="flex gap-2 mt-3">
            <Button size="sm" onClick={handleSchedule} disabled={busy}>
              Schedule it
            </Button>
            <Button size="sm" variant="ghost" onClick={handleDismiss} disabled={busy}>
              Dismiss
            </Button>
          </div>
        </div>
        <button
          type="button"
          onClick={handleDismiss}
          aria-label="Dismiss insight"
          className="text-muted-foreground hover:text-foreground"
          disabled={busy}
        >
          <X className="h-4 w-4" />
        </button>
      </CardContent>
    </Card>
  );
}

function pad(n: number): string {
  return String(n).padStart(2, "0");
}

/**
 * Returns the next future Date that lands on `weekday` (0=Sun..6=Sat) at
 * `hour:minute` local time. If today matches and the time is still future,
 * returns today; otherwise jumps to next week's slot.
 */
function nextOccurrence(weekday: number, hour: number, minute: number): Date {
  const now = new Date();
  const candidate = new Date(now);
  candidate.setHours(hour, minute, 0, 0);

  const todayDow = candidate.getDay();
  let daysAhead = (weekday - todayDow + 7) % 7;
  if (daysAhead === 0 && candidate <= now) {
    daysAhead = 7;
  }
  candidate.setDate(candidate.getDate() + daysAhead);
  return candidate;
}
