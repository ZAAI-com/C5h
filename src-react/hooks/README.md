# Hooks Documentation

Custom React hooks for the C5h application.

## Overview

Hooks encapsulate reusable logic and provide clean interfaces for components. All hooks follow React hooks conventions (start with `use`, follow rules of hooks).

## Available Hooks

### useAppInit

Initializes the application by loading all necessary data.

**Location:** `src-react/hooks/useAppInit.ts`

**Usage:**
```typescript
import { useAppInit } from "@/hooks";

function App() {
  const { isLoading, error } = useAppInit();

  if (isLoading) return <LoadingScreen />;
  if (error) return <ErrorScreen error={error} />;

  return <MainApp />;
}
```

**Returns:**
```typescript
interface UseAppInitReturn {
  isLoading: boolean;
  error: string | null;
}
```

**Implementation:**
```typescript
export function useAppInit() {
  const isLoading = useStore((state) => state.isLoading);
  const error = useStore((state) => state.error);
  const initialize = useStore((state) => state.initialize);

  useEffect(() => {
    initialize();
  }, [initialize]);

  return { isLoading, error };
}
```

**What it does:**
1. Calls `initialize()` action on mount
2. Loads:
   - Accounts
   - Settings
   - Current window
   - Week's windows
   - Schedules
3. Sets loading/error states
4. Returns loading/error for UI handling

**When to use:**
- In the root `App.tsx` component
- Only once per app lifecycle
- Before rendering main UI

---

### useCurrentWindow

Provides computed data for the currently active window.

**Location:** `src-react/hooks/useCurrentWindow.ts`

**Usage:**
```typescript
import { useCurrentWindow } from "@/hooks";

function StatusCard() {
  const { currentWindow, account, timeRemaining, usagePercent } = useCurrentWindow();

  if (!currentWindow) return <NoWindow />;

  return (
    <Card>
      <Progress value={usagePercent} />
      <span>Time remaining: {timeRemaining}</span>
    </Card>
  );
}
```

**Returns:**
```typescript
interface UseCurrentWindowReturn {
  currentWindow: Window | null;
  account: Account | null;
  timeRemaining: string | null;  // "3h 24m" format
  usagePercent: number;           // 0-100
  isEndingSoon: boolean;          // <30 min remaining
}
```

**Implementation:**
```typescript
export function useCurrentWindow() {
  const currentWindow = useStore((state) => state.currentWindow);
  const accounts = useStore((state) => state.accounts);

  const account = useMemo(() => {
    if (!currentWindow) return null;
    return accounts.find((a) => a.id === currentWindow.account_id) || null;
  }, [currentWindow, accounts]);

  const timeRemaining = useMemo(() => {
    if (!currentWindow || !account) return null;

    const start = new Date(currentWindow.started_at);
    const end = new Date(start.getTime() + account.window_duration_hours * 60 * 60 * 1000);
    const remaining = end.getTime() - Date.now();

    if (remaining <= 0) return "Expired";

    const hours = Math.floor(remaining / (1000 * 60 * 60));
    const minutes = Math.floor((remaining % (1000 * 60 * 60)) / (1000 * 60));

    return `${hours}h ${minutes}m`;
  }, [currentWindow, account]);

  const usagePercent = useMemo(() => {
    if (!currentWindow || !account) return 0;

    const start = new Date(currentWindow.started_at);
    const end = new Date(start.getTime() + account.window_duration_hours * 60 * 60 * 1000);
    const total = end.getTime() - start.getTime();
    const elapsed = Date.now() - start.getTime();

    return Math.min(100, Math.round((elapsed / total) * 100));
  }, [currentWindow, account]);

  const isEndingSoon = useMemo(() => {
    if (!currentWindow || !account) return false;

    const start = new Date(currentWindow.started_at);
    const end = new Date(start.getTime() + account.window_duration_hours * 60 * 60 * 1000);
    const remaining = end.getTime() - Date.now();

    return remaining > 0 && remaining < 30 * 60 * 1000; // <30 min
  }, [currentWindow, account]);

  return { currentWindow, account, timeRemaining, usagePercent, isEndingSoon };
}
```

**Calculations:**
- **timeRemaining**: `endTime - now` formatted as "Xh Ym"
- **usagePercent**: `(elapsed / total) * 100` clamped to 0-100
- **isEndingSoon**: remaining time < 30 minutes

**When to use:**
- In StatusCard component
- In PopoverWindow component
- Anywhere current window info is needed

**Performance:**
All calculations are memoized with `useMemo` to prevent unnecessary recalculations.

---

### useWindowEndingAlert

Triggers system notifications when a window is ending soon.

**Location:** `src-react/hooks/useWindowEndingAlert.ts`

**Usage:**
```typescript
import { useWindowEndingAlert } from "@/hooks";

function App() {
  useAppInit();
  useWindowEndingAlert(); // Just call it, no return value

  return <Layout />;
}
```

**Returns:** `void` (side effects only)

**Implementation:**
```typescript
export function useWindowEndingAlert() {
  const { currentWindow, account, timeRemaining } = useCurrentWindow();
  const alertsSent = useRef<Set<string>>(new Set());

  useEffect(() => {
    if (!currentWindow || !account || !timeRemaining) {
      // Reset alerts when window changes
      alertsSent.current.clear();
      return;
    }

    const start = new Date(currentWindow.started_at);
    const end = new Date(start.getTime() + account.window_duration_hours * 60 * 60 * 1000);
    const remaining = end.getTime() - Date.now();

    // Check for 30-minute alert
    const thirtyMin = 30 * 60 * 1000;
    if (remaining <= thirtyMin && remaining > 0) {
      const key = `${currentWindow.id}-30`;
      if (!alertsSent.current.has(key)) {
        invoke("notify_window_ending_soon", {
          accountName: account.name,
          minutesRemaining: 30,
        });
        alertsSent.current.add(key);
      }
    }

    // Check for 15-minute alert
    const fifteenMin = 15 * 60 * 1000;
    if (remaining <= fifteenMin && remaining > 0) {
      const key = `${currentWindow.id}-15`;
      if (!alertsSent.current.has(key)) {
        invoke("notify_window_ending_soon", {
          accountName: account.name,
          minutesRemaining: 15,
        });
        alertsSent.current.add(key);
      }
    }
  }, [currentWindow, account, timeRemaining]);

  // Poll every minute to check alerts
  useEffect(() => {
    const interval = setInterval(() => {
      // Trigger re-check by reading timeRemaining
    }, 60 * 1000);

    return () => clearInterval(interval);
  }, []);
}
```

**Alert Triggers:**
- **30 minutes** before window ends
- **15 minutes** before window ends

**Alert Tracking:**
Uses `useRef<Set<string>>` to track sent alerts per window to prevent duplicate notifications.

**Alert Key Format:**
```typescript
const key = `${windowId}-${minutes}`;
// Example: "42-30" = window 42, 30-minute alert
```

**When to use:**
- In root `App.tsx` component
- After `useAppInit` has loaded data
- Only once per app lifecycle

**Backend Integration:**
Calls Tauri command `notify_window_ending_soon` which triggers macOS notification.

---

## Hook Patterns

### 1. Store Integration

```typescript
export function useMyData() {
  const data = useStore((state) => state.data);
  const fetchData = useStore((state) => state.fetchData);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  return { data };
}
```

### 2. Computed Values

```typescript
export function useComputedValue() {
  const rawData = useStore((state) => state.rawData);

  const computed = useMemo(() => {
    return expensiveComputation(rawData);
  }, [rawData]);

  return computed;
}
```

### 3. Side Effects

```typescript
export function useSideEffect() {
  const condition = useStore((state) => state.condition);

  useEffect(() => {
    if (condition) {
      performSideEffect();
    }
  }, [condition]);
}
```

### 4. Polling

```typescript
export function usePolling(interval: number) {
  const fetchData = useStore((state) => state.fetchData);

  useEffect(() => {
    const id = setInterval(() => {
      fetchData();
    }, interval);

    return () => clearInterval(id);
  }, [fetchData, interval]);
}
```

---

## Testing Hooks

### Using @testing-library/react-hooks

```typescript
import { renderHook, waitFor } from "@testing-library/react";
import { useCurrentWindow } from "./useCurrentWindow";

describe("useCurrentWindow", () => {
  it("returns null when no current window", () => {
    const { result } = renderHook(() => useCurrentWindow());
    expect(result.current.currentWindow).toBeNull();
  });

  it("calculates time remaining correctly", () => {
    // Mock store with active window
    const { result } = renderHook(() => useCurrentWindow());
    expect(result.current.timeRemaining).toBe("3h 24m");
  });
});
```

### Testing Side Effects

```typescript
import { renderHook } from "@testing-library/react";
import { useWindowEndingAlert } from "./useWindowEndingAlert";
import { invoke } from "@tauri-apps/api/core";

jest.mock("@tauri-apps/api/core");

describe("useWindowEndingAlert", () => {
  it("sends alert at 30 minutes", async () => {
    renderHook(() => useWindowEndingAlert());

    await waitFor(() => {
      expect(invoke).toHaveBeenCalledWith("notify_window_ending_soon", {
        accountName: "Claude Code",
        minutesRemaining: 30,
      });
    });
  });
});
```

---

## Creating New Hooks

### Guidelines

1. **Naming**: Start with `use`, follow with descriptive name (e.g., `useWindowData`)
2. **Single Responsibility**: Each hook should do one thing well
3. **Memoization**: Use `useMemo` for expensive calculations
4. **Dependencies**: Carefully manage `useEffect` dependencies
5. **Testing**: Write tests for all hooks
6. **Documentation**: Add to this README with examples

### Template

```typescript
// useMyFeature.ts
import { useMemo, useEffect } from "react";
import { useStore } from "@/store";

export function useMyFeature() {
  // 1. Get data from store
  const data = useStore((state) => state.data);

  // 2. Compute derived values
  const computed = useMemo(() => {
    return transform(data);
  }, [data]);

  // 3. Side effects
  useEffect(() => {
    // Setup
    const cleanup = setup();

    // Cleanup
    return () => cleanup();
  }, []);

  // 4. Return interface
  return { computed };
}
```

---

## Best Practices

1. **Keep hooks small**: One responsibility per hook
2. **Avoid prop drilling**: Use hooks to access store directly
3. **Memoize expensive operations**: Use `useMemo` and `useCallback`
4. **Document return types**: Use TypeScript interfaces
5. **Handle cleanup**: Return cleanup functions from `useEffect`
6. **Test thoroughly**: Write unit tests for all hooks
7. **Avoid overuse**: Sometimes a component method is better

---

## Future Hooks

Potential hooks to add:

- `useWindowHistory`: Access historical window data
- `useAccountStats`: Per-account statistics
- `useTheme`: Theme management
- `useNotifications`: Notification preferences
- `useScheduler`: Scheduler state management
- `useExport`: Export data to various formats
