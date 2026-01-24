# Frontend Architecture

The C5h frontend is built with React, TypeScript, and Vite, following a modular component architecture with centralized state management.

## Directory Structure

```
src-react/
├── components/          # UI components
│   ├── shadcn-ui/      # shadcn/ui base components
│   ├── Layout.tsx      # App shell with tabs
│   ├── CalendarView.tsx# Week calendar with windows
│   ├── StatsView.tsx   # Statistics dashboard
│   ├── SettingsView.tsx# Settings panel
│   ├── StatusCard.tsx  # Current window status
│   ├── PopoverWindow.tsx# Menu bar popover
│   ├── SchedulerSettings.tsx# Scheduler config
│   ├── ErrorBoundary.tsx# Error handling
│   └── index.ts        # Component exports
├── hooks/              # Custom React hooks
│   ├── useAppInit.ts   # App initialization
│   ├── useCurrentWindow.ts# Current window data
│   └── useWindowEndingAlert.ts# Notification trigger
├── store/              # Zustand state management
│   └── index.ts        # Global state store
├── lib/                # Utilities and API
│   ├── api.ts          # Tauri IPC bridge
│   ├── types.ts        # TypeScript types
│   └── utils.ts        # Helper functions
├── App.tsx             # Main app component
├── main.tsx            # React entry point
├── popover.tsx         # Popover entry point
└── index.css           # Global styles
```

## State Management

### Zustand Store

The app uses a single Zustand store (`src-react/store/index.ts`) with the following structure:

```typescript
interface AppState {
  // Data
  accounts: Account[];
  windows: Window[];
  currentWindow: Window | null;
  schedules: ScheduledTrigger[];
  settings: Settings | null;

  // UI State
  selectedDate: Date;
  selectedAccountId: number | null;
  isLoading: boolean;
  error: string | null;

  // Actions
  fetchAccounts: () => Promise<void>;
  createAccount: (account: Omit<Account, "id" | "created_at">) => Promise<void>;
  // ... more actions
}
```

### Store Pattern

All store actions follow this pattern:
1. Set loading/error state
2. Call API layer
3. Update local state
4. Show toast notification (success/error)
5. Throw error if failed (for component handling)

Example:
```typescript
createAccount: async (account) => {
  try {
    await api.createAccount(account);
    await get().fetchAccounts();
    toast.success("Account created successfully");
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    set({ error: message });
    toast.error(`Failed to create account: ${message}`);
    throw err;
  }
}
```

## API Layer

The API layer (`src-react/lib/api.ts`) provides type-safe wrappers around Tauri IPC commands:

```typescript
export async function getAccounts(): Promise<Account[]> {
  return await invoke<Account[]>("get_accounts");
}

export async function createAccount(account: NewAccount): Promise<void> {
  await invoke("create_account", { account });
}
```

## Component Patterns

### Data Fetching

Components use Zustand store for data access:

```typescript
export function CalendarView() {
  const windows = useStore((state) => state.windows);
  const fetchWindows = useStore((state) => state.fetchWindows);

  // Use data directly, no local state needed
}
```

### Custom Hooks

Complex logic is extracted into custom hooks:

```typescript
// useCurrentWindow.ts
export function useCurrentWindow() {
  const currentWindow = useStore((state) => state.currentWindow);
  const accounts = useStore((state) => state.accounts);

  const account = accounts.find((a) => a.id === currentWindow?.account_id);
  const timeRemaining = /* calculate */;

  return { currentWindow, account, timeRemaining };
}
```

### Error Handling

1. **ErrorBoundary**: Catches React rendering errors
2. **Store errors**: Stored in `error` state, displayed in UI
3. **Toast notifications**: User feedback for async actions

## Styling

### Tailwind CSS

All styling uses Tailwind CSS with a custom theme:

```css
/* index.css */
:root {
  --background: 0 0% 100%;
  --foreground: 222.2 84% 4.9%;
  --primary: 221.2 83.2% 53.3%;
  /* ... more variables */
}
```

### Component Styling

Use Tailwind classes directly in JSX:

```tsx
<div className="flex items-center gap-2 rounded-lg border p-4">
  <span className="text-sm text-muted-foreground">Status</span>
</div>
```

### shadcn/ui Components

Base components from shadcn/ui provide consistent styling:
- Button, Card, Dialog, Input, Select, etc.
- Customized with Tailwind classes
- CSS variables for theming

## Type Safety

### TypeScript Types

All types defined in `src-react/lib/types.ts`:

```typescript
export interface Account {
  id: number;
  name: string;
  tool_type: string;
  cli_command: string;
  window_duration_hours: number;
  color: string;
  enabled: boolean;
  created_at: string;
}

export type NewAccount = Omit<Account, "id" | "created_at">;
```

### Tauri IPC Types

Types match Rust backend structures for type-safe IPC.

## Performance

### Optimization Strategies

1. **useMemo**: Expensive calculations memoized
2. **Selective re-renders**: Zustand selectors prevent unnecessary re-renders
3. **Code splitting**: Popover window separate entry point
4. **Lazy loading**: Components loaded on demand (future)

### Example Optimization

```typescript
const weekData = useMemo(() => {
  // Expensive calculation based on windows and accounts
  return days.map((day) => {
    // ... process data
  });
}, [windows, accounts, selectedDate]);
```

## Testing

### Test Structure

```
src-react/
├── components/
│   ├── CalendarView.tsx
│   └── CalendarView.test.tsx
├── hooks/
│   ├── useAppInit.ts
│   └── useAppInit.test.ts
└── store/
    ├── index.ts
    └── index.test.ts
```

### Testing Pattern

```typescript
import { render, screen } from "@testing-library/react";
import { CalendarView } from "./CalendarView";

describe("CalendarView", () => {
  it("renders week header", () => {
    render(<CalendarView />);
    expect(screen.getByText(/January/)).toBeInTheDocument();
  });
});
```

## Build Configuration

### Vite Config

- TypeScript support
- Path aliases (`@/` → `src-react/`)
- Asset optimization
- HMR (Hot Module Replacement)

### Tauri Integration

- Two entry points: `main.tsx` (main window), `popover.tsx` (popover)
- HTML files: `index.html`, `popover.html`
- IPC bridge via `@tauri-apps/api`

## Best Practices

1. **Component Organization**: One component per file, related files co-located
2. **Prop Drilling**: Avoid by using Zustand store
3. **Type Safety**: No `any` types, explicit interfaces
4. **Error Handling**: Always handle async errors
5. **User Feedback**: Toast notifications for all user actions
6. **Accessibility**: Semantic HTML, ARIA labels
7. **Immutability**: Never mutate store state directly

## Future Enhancements

- [ ] Component lazy loading
- [ ] Virtual scrolling for large window lists
- [ ] Offline support with service worker
- [ ] Dark mode with next-themes
- [ ] i18n for internationalization
