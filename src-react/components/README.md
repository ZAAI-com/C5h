# Components Documentation

This directory contains all React components for the C5h application.

## Component Hierarchy

```
App
├── Layout
│   ├── CalendarView
│   │   ├── StatusCard
│   │   └── MonitoringCard
│   ├── StatsView
│   └── SettingsView
│       └── SchedulerSettings
└── Toaster (sonner)

PopoverWindow (separate tree)
```

## Core Components

### Layout.tsx

Main application shell with tab navigation.

**Props:**
```typescript
interface LayoutProps {
  calendarContent: React.ReactNode;
  statsContent: React.ReactNode;
  settingsContent: React.ReactNode;
}
```

**Features:**
- Tab-based navigation (Calendar, Stats, Settings)
- Responsive layout
- Consistent header/footer

**Usage:**
```tsx
<Layout
  calendarContent={<CalendarView />}
  statsContent={<StatsView />}
  settingsContent={<SettingsView />}
/>
```

---

### CalendarView.tsx

Week calendar with visual timeline of usage windows.

**Features:**
- 7-day week view with 24-hour time grid
- Window blocks colored by account
- Click to create scheduled triggers
- Previous/Next week navigation
- "Today" quick navigation
- Tooltip on hover showing window details

**Data Flow:**
```typescript
const windows = useStore((state) => state.windows);
const selectedDate = useStore((state) => state.selectedDate);
const setSelectedDate = useStore((state) => state.setSelectedDate);
```

**Window Display:**
- Active windows: Solid color block
- Scheduled triggers: Orange dashed border
- Ended windows: Semi-transparent

---

### StatusCard.tsx

Current window status display.

**Features:**
- Progress bar showing usage percentage
- Time remaining (Xh Xm format)
- Reset time display
- "End Window" button
- Loading states

**Hook Usage:**
```typescript
const { currentWindow, account, timeRemaining, usagePercent } = useCurrentWindow();
```

**States:**
- No active window: "No active window" message
- Active window: Progress bar + time remaining
- Window ending soon (<30 min): Orange warning color

---

### StatsView.tsx

Statistics dashboard with multiple visualizations.

**Charts:**

1. **Summary Cards** (4 stat cards):
   - Total Windows
   - Total Hours
   - Avg Window Duration
   - Active Accounts

2. **Windows Per Day** (Stacked bar chart):
   - 7-day view of window counts
   - Stacked by account
   - Color-coded by account

3. **Usage by Day of Week** (Heatmap):
   - Shows patterns across all days of week
   - Intensity-based coloring
   - Helps identify peak usage days

4. **Usage by Time of Day** (Histogram):
   - 24-hour distribution
   - Identifies peak usage hours
   - Helps optimize scheduling

5. **By Account** (List):
   - Window count per account
   - Total hours per account
   - Color indicator

**Data Calculations:**
```typescript
const stats = useMemo(() => {
  // Calculate total windows, hours, averages
  // Group by account
  return { totalWindows, totalHours, avgHoursPerWindow, accountStats };
}, [windows, accounts]);
```

---

### SettingsView.tsx

Application settings panel with multiple sections.

**Sections:**

1. **General Settings**:
   - Theme selection (system, light, dark)
   - Notifications toggle

2. **Accounts**:
   - List of configured accounts
   - Add/Edit/Delete buttons
   - Account configuration dialog:
     - Name input
     - Tool type select (claude, codex, gemini)
     - CLI command and args
     - Window duration (hours)
     - Color picker
     - Enabled toggle

3. **Scheduler** (via SchedulerSettings):
   - Enable/disable scheduler
   - View pending schedules
   - Uninstall schedules

**Account Dialog:**
```typescript
const [isDialogOpen, setIsDialogOpen] = useState(false);
const [editingAccount, setEditingAccount] = useState<Account | null>(null);

const handleSave = async () => {
  if (editingAccount?.id) {
    await updateAccount(editingAccount);
  } else {
    await createAccount(newAccount);
  }
};
```

---

### SchedulerSettings.tsx

Scheduler configuration component.

**Features:**
- Enable/disable scheduler toggle
- Pending schedules list
- Install/uninstall status indicators
- Delete schedule button

**Schedule Display:**
```typescript
schedules.map((schedule) => (
  <div key={schedule.id}>
    <span>{format(new Date(schedule.scheduled_at), "PPpp")}</span>
    <span>{schedule.status}</span>
    <Button onClick={() => deleteSchedule(schedule.id)}>Delete</Button>
  </div>
))
```

**States:**
- `pending`: Created but not installed
- `installed`: Plist installed in LaunchAgents
- `completed`: Trigger has fired
- `failed`: Installation or trigger failed

---

### PopoverWindow.tsx

Menu bar popover component (separate window).

**Layout:**
```
┌──────────────────────────────────┐
│  Claude Code                     │
│  ━━━━━━━━━━░░░░ 75% used         │
│  Resets: 3:24 PM                 │
├──────────────────────────────────┤
│  [▶ Start New Window]            │
├──────────────────────────────────┤
│  This Week: 45% used             │
│  Next scheduled: 3:00 AM         │
├──────────────────────────────────┤
│  ⚙️ Settings    📊 Open App      │
└──────────────────────────────────┘
```

**Features:**
- Current window status (compact)
- Quick start button
- Week summary stats
- Next scheduled trigger info
- Links to main app and settings

**Tauri Commands:**
```typescript
// Open main window
await invoke("show_main_window");

// Start new window
await createWindow(accountId, "manual");
```

---

### MonitoringCard.tsx

Real-time CLI monitoring status display.

**Features:**
- Monitor on/off toggle
- Currently monitored accounts list
- Last detected CLI activity
- Start/stop monitoring controls

**Monitor State:**
```typescript
const [isMonitoring, setIsMonitoring] = useState(false);
const [monitoredAccounts, setMonitoredAccounts] = useState<string[]>([]);

const toggleMonitoring = async () => {
  if (isMonitoring) {
    await invoke("stop_monitoring");
  } else {
    await invoke("start_monitoring");
  }
  setIsMonitoring(!isMonitoring);
};
```

---

### ErrorBoundary.tsx

React error boundary for graceful error handling.

**Features:**
- Catches rendering errors
- Displays friendly error message
- "Reload" button to recover
- Logs error to console

**Implementation:**
```typescript
class ErrorBoundary extends Component<Props, State> {
  static getDerivedStateFromError(error: Error) {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error("Error boundary caught:", error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return <ErrorFallback error={this.state.error} />;
    }
    return this.props.children;
  }
}
```

---

## shadcn/ui Components

Base components from shadcn/ui (in `shadcn-ui/` directory):

- **button.tsx**: Button with variants (default, destructive, outline, ghost)
- **card.tsx**: Card container with header, content, footer
- **dialog.tsx**: Modal dialog
- **dropdown-menu.tsx**: Context menus
- **input.tsx**: Text input
- **label.tsx**: Form label
- **popover.tsx**: Floating popover
- **progress.tsx**: Progress bar
- **select.tsx**: Dropdown select
- **separator.tsx**: Visual divider
- **sonner.tsx**: Toast notifications (customized)
- **switch.tsx**: Toggle switch
- **tabs.tsx**: Tab navigation

### Sonner Configuration

Custom toast configuration with icons:

```typescript
<Sonner
  theme="system"
  icons={{
    success: <CircleCheckIcon className="size-4" />,
    error: <OctagonXIcon className="size-4" />,
    warning: <TriangleAlertIcon className="size-4" />,
    info: <InfoIcon className="size-4" />,
    loading: <Loader2Icon className="size-4 animate-spin" />,
  }}
/>
```

---

## Component Patterns

### 1. Data Fetching

```typescript
// Use Zustand store selectors
const data = useStore((state) => state.data);
const fetchData = useStore((state) => state.fetchData);

useEffect(() => {
  fetchData();
}, [fetchData]);
```

### 2. Form Handling

```typescript
const [formData, setFormData] = useState<FormData>(initialData);

const handleChange = (field: keyof FormData, value: string) => {
  setFormData((prev) => ({ ...prev, [field]: value }));
};

const handleSubmit = async (e: React.FormEvent) => {
  e.preventDefault();
  await saveData(formData);
};
```

### 3. Loading States

```typescript
const [isLoading, setIsLoading] = useState(false);

const handleAction = async () => {
  setIsLoading(true);
  try {
    await performAction();
  } finally {
    setIsLoading(false);
  }
};

return isLoading ? <Loader2 className="animate-spin" /> : <Content />;
```

### 4. Error Handling

```typescript
try {
  await riskyOperation();
  toast.success("Operation successful");
} catch (err) {
  const message = err instanceof Error ? err.message : String(err);
  toast.error(`Operation failed: ${message}`);
}
```

---

## Testing Components

### Example Test

```typescript
import { render, screen, fireEvent } from "@testing-library/react";
import { StatusCard } from "./StatusCard";

describe("StatusCard", () => {
  it("displays current window status", () => {
    render(<StatusCard />);
    expect(screen.getByText(/active window/i)).toBeInTheDocument();
  });

  it("shows end window button", () => {
    render(<StatusCard />);
    const button = screen.getByRole("button", { name: /end window/i });
    fireEvent.click(button);
    // Assert expected behavior
  });
});
```

---

## Best Practices

1. **Props**: Use TypeScript interfaces for all props
2. **State**: Prefer Zustand store over local state for shared data
3. **Memo**: Use `useMemo` for expensive calculations
4. **Keys**: Always provide unique `key` prop in lists
5. **Accessibility**: Use semantic HTML and ARIA attributes
6. **Error Handling**: Wrap async operations in try/catch
7. **Loading States**: Show feedback during async operations
8. **Toast Notifications**: Provide user feedback for all actions

---

## Adding New Components

1. Create component file in `src-react/components/`
2. Define TypeScript interface for props
3. Implement component with proper error handling
4. Add to `index.ts` for easy imports
5. Write tests in `.test.tsx` file
6. Document in this README
