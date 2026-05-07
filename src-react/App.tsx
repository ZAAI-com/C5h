import { type ReactNode, useCallback, useEffect, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import { useAppInit, useWindowEndingAlert, useKeyboardShortcuts, useTraySync } from "@/hooks";
import { useStore } from "@/store";
import {
  Layout,
  CalendarView,
  StatsView,
  SettingsView,
  InsightBanner,
} from "@/components";
import { OnboardingFlow } from "@/components/onboarding/OnboardingFlow";
import { Button } from "@/components/shadcn-ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/shadcn-ui/card";
import { Toaster } from "@/components/shadcn-ui/sonner";
import { Loader2, AlertCircle } from "lucide-react";
import { getWeekBoundaries, isOnboardingCompleted, quitApp } from "@/lib/api";
import { subWeeks, addWeeks } from "date-fns";

function App() {
  const { isLoading, error } = useAppInit();
  const setError = useStore((state) => state.setError);
  const initialize = useStore((state) => state.initialize);
  const [activeTab, setActiveTab] = useState<"calendar" | "stats" | "settings">("calendar");

  // Onboarding gate. `null` means "still checking" — renders nothing rather
  // than flashing the main UI before we know whether to show the flow.
  const [onboardingDone, setOnboardingDone] = useState<boolean | null>(null);
  useEffect(() => {
    isOnboardingCompleted()
      .then(setOnboardingDone)
      .catch(() => setOnboardingDone(true)); // fail open — never block the user
  }, []);

  // Enable window ending notifications
  useWindowEndingAlert();

  // Push tray-title state (single source of truth for the menu-bar text).
  useTraySync();

  // Keyboard shortcuts
  const accounts = useStore((state) => state.accounts);
  const createWindow = useStore((state) => state.createWindow);
  const setSelectedDate = useStore((state) => state.setSelectedDate);
  const fetchWindows = useStore((state) => state.fetchWindows);
  const selectedDate = useStore((state) => state.selectedDate);

  const handleStartWindow = useCallback(() => {
    const account = accounts.find((a) => a.enabled);
    if (account?.id) {
      createWindow(account.id, "manual");
    }
  }, [accounts, createWindow]);

  const handleJumpToToday = useCallback(() => {
    const today = new Date();
    setSelectedDate(today);
    const { start, end } = getWeekBoundaries(today);
    fetchWindows(start, end);
  }, [setSelectedDate, fetchWindows]);

  const handleNavigateWeek = useCallback(
    (direction: "prev" | "next") => {
      const newDate =
        direction === "prev"
          ? subWeeks(selectedDate, 1)
          : addWeeks(selectedDate, 1);
      setSelectedDate(newDate);
      const { start, end } = getWeekBoundaries(newDate);
      fetchWindows(start, end);
    },
    [selectedDate, setSelectedDate, fetchWindows],
  );

  useKeyboardShortcuts({
    onSwitchTab: setActiveTab,
    onStartWindow: handleStartWindow,
    onJumpToToday: handleJumpToToday,
    onNavigateWeek: handleNavigateWeek,
    onQuit: () => {
      quitApp().catch(console.error);
    },
  });

  useEffect(() => {
    const unlisten = listen<"calendar" | "stats" | "settings">(
      "navigate-to-tab",
      (event) => {
        setActiveTab(event.payload);
      },
    );

    return () => {
      unlisten.then((cleanup) => cleanup());
    };
  }, []);

  let content: ReactNode;

  if (onboardingDone === false && accounts.length === 0 && !isLoading && !error) {
    return (
      <>
        <Toaster />
        <OnboardingFlow
          onComplete={() => {
            setOnboardingDone(true);
            initialize();
          }}
        />
      </>
    );
  }

  if (isLoading) {
    content = (
      <div className="flex items-center justify-center min-h-screen bg-background">
        <div className="text-center">
          <Loader2 className="h-8 w-8 animate-spin mx-auto mb-4 text-primary" />
          <h1 className="text-2xl font-bold mb-2">C5h</h1>
          <p className="text-muted-foreground">Loading...</p>
        </div>
      </div>
    );
  } else if (error) {
    content = (
      <div className="flex items-center justify-center min-h-screen bg-background p-4">
        <Card className="max-w-md w-full">
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-destructive">
              <AlertCircle className="h-5 w-5" />
              Error
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <p className="text-muted-foreground">{error}</p>
            <div className="flex gap-2">
              <Button
                variant="outline"
                onClick={() => setError(null)}
              >
                Dismiss
              </Button>
              <Button onClick={() => initialize()}>
                Retry
              </Button>
            </div>
          </CardContent>
        </Card>
      </div>
    );
  } else {
    content = (
      <Layout
        calendarContent={
          <div className="space-y-4">
            <InsightBanner />
            <CalendarView />
          </div>
        }
        statsContent={<StatsView />}
        settingsContent={<SettingsView />}
        activeTab={activeTab}
        onTabChange={setActiveTab}
      />
    );
  }

  return (
    <>
      <Toaster />
      {content}
    </>
  );
}

export default App;
