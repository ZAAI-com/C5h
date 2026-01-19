import { useAppInit, useWindowEndingAlert } from "@/hooks";
import { useStore } from "@/store";
import { Layout, CalendarView, StatsView, SettingsView } from "@/components";
import { Button } from "@/components/shadcn-ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/shadcn-ui/card";
import { Toaster } from "@/components/shadcn-ui/sonner";
import { Loader2, AlertCircle } from "lucide-react";

function App() {
  const { isLoading, error } = useAppInit();
  const setError = useStore((state) => state.setError);
  const initialize = useStore((state) => state.initialize);

  // Enable window ending notifications
  useWindowEndingAlert();

  if (isLoading) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-background">
        <div className="text-center">
          <Loader2 className="h-8 w-8 animate-spin mx-auto mb-4 text-primary" />
          <h1 className="text-2xl font-bold mb-2">C5h</h1>
          <p className="text-muted-foreground">Loading...</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
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
  }

  return (
    <>
      <Layout
        calendarContent={<CalendarView />}
        statsContent={<StatsView />}
        settingsContent={<SettingsView />}
      />
      <Toaster />
    </>
  );
}

export default App;
