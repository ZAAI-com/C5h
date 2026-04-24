import { ReactNode } from "react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/shadcn-ui/tabs";
import { Calendar, BarChart3, Settings } from "lucide-react";

interface LayoutProps {
  children?: ReactNode;
  calendarContent: ReactNode;
  statsContent: ReactNode;
  settingsContent: ReactNode;
  activeTab?: string;
  onTabChange?: (tab: string) => void;
}

export function Layout({
  calendarContent,
  statsContent,
  settingsContent,
  activeTab,
  onTabChange,
}: LayoutProps) {
  return (
    <div className="min-h-screen bg-background">
      <Tabs
        value={activeTab}
        defaultValue="calendar"
        onValueChange={onTabChange}
        className="w-full h-full"
      >
        <div className="border-b bg-card">
          <div className="container mx-auto px-4">
            <div className="flex items-center justify-between h-14">
              <h1 className="text-lg font-semibold">C5h</h1>
              <TabsList className="grid grid-cols-3 w-auto">
                <TabsTrigger value="calendar" className="gap-2" aria-label="Calendar">
                  <Calendar className="h-4 w-4" />
                  <span className="hidden sm:inline">Calendar</span>
                </TabsTrigger>
                <TabsTrigger value="stats" className="gap-2" aria-label="Stats">
                  <BarChart3 className="h-4 w-4" />
                  <span className="hidden sm:inline">Stats</span>
                </TabsTrigger>
                <TabsTrigger value="settings" className="gap-2" aria-label="Settings">
                  <Settings className="h-4 w-4" />
                  <span className="hidden sm:inline">Settings</span>
                </TabsTrigger>
              </TabsList>
            </div>
          </div>
        </div>

        <main className="container mx-auto px-4 py-6">
          <TabsContent value="calendar" className="mt-0">
            {calendarContent}
          </TabsContent>
          <TabsContent value="stats" className="mt-0">
            {statsContent}
          </TabsContent>
          <TabsContent value="settings" className="mt-0">
            {settingsContent}
          </TabsContent>
        </main>
      </Tabs>
    </div>
  );
}
