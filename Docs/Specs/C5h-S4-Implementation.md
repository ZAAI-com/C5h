# C5h Implementation Plan

A detailed, step-by-step implementation guide that any developer can follow.

---

## Prerequisites

Before starting, ensure you have:

- [ ] macOS 12+ (Monterey or later)
- [ ] Bun (`brew install bun`)
- [ ] Rust (`curl --proto '=https' --tlsv1.2 -sSf ``https://sh.rustup.rs`` | sh`)
- [ ] Claude Code CLI installed and authenticated
- [ ] Apple Developer Account ($99/year) - for distribution only
- [ ] GitHub account

---

## Phase 1: Project Setup

**Estimated tasks: 8**

### 1.1 Create Tauri Project

```bash
# Install Tauri CLI
bun add -g @tauri-apps/cli

# Create new project
bun create tauri-app C5h --template react-ts

# Navigate to project
cd C5h
```

**Expected output:** New project folder with this structure:
```
C5h/
├── src-react/            # React frontend
├── src-tauri/            # Rust backend
├── package.json
└── tauri.conf.json
```

### 1.2 Install Frontend Dependencies

```bash
# Core dependencies
bun add date-fns zustand

# UI dependencies
bun add -D tailwindcss postcss autoprefixer
bun add class-variance-authority clsx tailwind-merge
bun add lucide-react

# shadcn/ui setup
bunx shadcn@latest init
```

**When prompted for shadcn init:**
- Style: Default
- Base color: Slate
- CSS variables: Yes

### 1.3 Install shadcn Components

```bash
bunx shadcn@latest add button card dialog dropdown-menu input label popover progress select separator switch tabs toast
```

### 1.4 Install ilamy Calendar

```bash
bun add ilamy
```

### 1.5 Install Recharts for Statistics

```bash
bun add recharts
```

### 1.6 Configure Tauri Plugins

Edit `src-tauri/Cargo.toml`:

```toml
[dependencies]
tauri = { version = "2", features = ["tray-icon"] }
tauri-plugin-sql = { version = "2", features = ["sqlite"] }
tauri-plugin-shell = "2"
tauri-plugin-fs = "2"
tauri-plugin-notification = "2"
tauri-plugin-autostart = "2"
tauri-plugin-positioner = "2"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
chrono = { version = "0.4", features = ["serde"] }
```

### 1.7 Configure Tauri Capabilities

Edit `src-tauri/capabilities/default.json`:

```json
{
  "$schema": "../gen/schemas/desktop-schema.json",
  "identifier": "default",
  "description": "Default capabilities for C5h",
  "windows": ["main", "popover"],
  "permissions": [
    "core:default",
    "sql:default",
    "shell:default",
    "fs:default",
    "notification:default",
    "autostart:default",
    "positioner:default"
  ]
}
```

### 1.8 Update Tauri Config

Edit `src-tauri/tauri.conf.json`:

```json
{
  "$schema": "https://schema.tauri.app/config/2",
  "productName": "C5h",
  "identifier": "com.zaai.c5h",
  "version": "0.1.0",
  "build": {
    "beforeBuildCommand": "bun run build",
    "beforeDevCommand": "bun run dev",
    "frontendDist": "../dist"
  },
  "app": {
    "windows": [
      {
        "label": "main",
        "title": "C5h",
        "width": 900,
        "height": 700,
        "minWidth": 600,
        "minHeight": 400,
        "visible": false
      }
    ],
    "trayIcon": {
      "iconPath": "icons/tray.png",
      "iconAsTemplate": true
    }
  },
  "bundle": {
    "active": true,
    "targets": ["dmg", "app"],
    "icon": [
      "icons/32x32.png",
      "icons/128x128.png",
      "icons/128x128@2x.png",
      "icons/icon.icns"
    ],
    "macOS": {
      "minimumSystemVersion": "12.0"
    }
  }
}
```

**Checkpoint:** Run `bun tauri dev` - app should open (empty window is fine)

---

## Phase 2: Database Layer

**Estimated tasks: 6**

### 2.1 Create Database Schema

Create `src-tauri/src/db.rs`:

```rust
use tauri_plugin_sql::{Migration, MigrationKind};

pub fn get_migrations() -> Vec<Migration> {
    vec![
        Migration {
            version: 1,
            description: "create_initial_tables",
            sql: r#"
                -- Accounts table for multi-tool/multi-account support
                CREATE TABLE IF NOT EXISTS accounts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    tool_type TEXT NOT NULL DEFAULT 'claude_code',
                    cli_command TEXT NOT NULL DEFAULT 'claude',
                    cli_args TEXT DEFAULT '-p "1+1"',
                    window_duration_hours INTEGER NOT NULL DEFAULT 5,
                    color TEXT NOT NULL DEFAULT '#6366f1',
                    enabled INTEGER NOT NULL DEFAULT 1,
                    created_at TEXT NOT NULL DEFAULT (datetime('now'))
                );

                CREATE TABLE IF NOT EXISTS windows (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    account_id INTEGER NOT NULL DEFAULT 1,
                    started_at TEXT NOT NULL,
                    ended_at TEXT,
                    triggered_by TEXT NOT NULL DEFAULT 'detected',
                    notes TEXT,
                    created_at TEXT NOT NULL DEFAULT (datetime('now')),
                    FOREIGN KEY (account_id) REFERENCES accounts(id)
                );

                CREATE TABLE IF NOT EXISTS settings (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS scheduled_jobs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    account_id INTEGER NOT NULL DEFAULT 1,
                    enabled INTEGER NOT NULL DEFAULT 1,
                    hour INTEGER NOT NULL,
                    minute INTEGER NOT NULL,
                    days TEXT NOT NULL DEFAULT '[1,2,3,4,5]',
                    last_run TEXT,
                    created_at TEXT NOT NULL DEFAULT (datetime('now')),
                    FOREIGN KEY (account_id) REFERENCES accounts(id)
                );

                -- Insert default accounts
                INSERT OR IGNORE INTO accounts (id, name, tool_type, cli_command, window_duration_hours, color) VALUES
                    (1, 'Claude Code', 'claude_code', 'claude', 5, '#6366f1'),
                    (2, 'Codex', 'codex', 'codex', 5, '#10a37f'),
                    (3, 'Gemini', 'gemini', 'gemini', 24, '#4285f4');

                -- Insert default settings
                INSERT OR IGNORE INTO settings (key, value) VALUES
                    ('launch_at_login', 'true'),
                    ('show_in_menu_bar', 'true'),
                    ('theme', 'system'),
                    ('notifications_enabled', 'true'),
                    ('notify_ending_soon', 'true'),
                    ('notify_trigger_status', 'true'),
                    ('notify_weekly_summary', 'true'),
                    ('poll_interval_minutes', '15');
            "#,
            kind: MigrationKind::Up,
        },
    ]
}
```

### 2.2 Create Data Models

Create `src-tauri/src/models.rs`:

```rust
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Account {
    pub id: Option<i64>,
    pub name: String,
    pub tool_type: String,  // "claude_code", "codex", etc.
    pub cli_command: String,
    pub cli_args: Option<String>,
    pub window_duration_hours: i32,
    pub color: String,
    pub enabled: bool,
    pub created_at: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Window {
    pub id: Option<i64>,
    pub account_id: i64,
    pub started_at: String,
    pub ended_at: Option<String>,
    pub triggered_by: String,
    pub notes: Option<String>,
    pub created_at: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Settings {
    pub launch_at_login: bool,
    pub show_in_menu_bar: bool,
    pub theme: String,
    pub notifications_enabled: bool,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ScheduledJob {
    pub id: Option<i64>,
    pub account_id: i64,
    pub enabled: bool,
    pub hour: i32,
    pub minute: i32,
    pub days: Vec<i32>,
    pub last_run: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct WindowStats {
    pub total_windows: i64,
    pub avg_duration_minutes: f64,
    pub windows_this_week: i64,
}
```

### 2.3 Create Tauri Commands for Windows

Create `src-tauri/src/commands/windows.rs`:

```rust
use crate::models::Window;
use tauri::State;
use tauri_plugin_sql::{DbInstances, DbPool};

#[tauri::command]
pub async fn get_windows(
    db: State<'_, DbInstances>,
    from: String,
    to: String,
) -> Result<Vec<Window>, String> {
    let pool = db.0.get("sqlite:c5h.db").ok_or("Database not found")?;

    let windows: Vec<Window> = sqlx::query_as!(
        Window,
        r#"
        SELECT id, started_at, ended_at, triggered_by, notes, created_at
        FROM windows
        WHERE started_at >= ? AND started_at <= ?
        ORDER BY started_at DESC
        "#,
        from,
        to
    )
    .fetch_all(pool)
    .await
    .map_err(|e| e.to_string())?;

    Ok(windows)
}

#[tauri::command]
pub async fn get_current_window(
    db: State<'_, DbInstances>,
) -> Result<Option<Window>, String> {
    let pool = db.0.get("sqlite:c5h.db").ok_or("Database not found")?;

    let window: Option<Window> = sqlx::query_as!(
        Window,
        r#"
        SELECT id, started_at, ended_at, triggered_by, notes, created_at
        FROM windows
        WHERE ended_at IS NULL
        ORDER BY started_at DESC
        LIMIT 1
        "#
    )
    .fetch_optional(pool)
    .await
    .map_err(|e| e.to_string())?;

    Ok(window)
}

#[tauri::command]
pub async fn create_window(
    db: State<'_, DbInstances>,
    triggered_by: String,
) -> Result<Window, String> {
    let pool = db.0.get("sqlite:c5h.db").ok_or("Database not found")?;
    let now = chrono::Utc::now().to_rfc3339();

    sqlx::query!(
        r#"INSERT INTO windows (started_at, triggered_by) VALUES (?, ?)"#,
        now,
        triggered_by
    )
    .execute(pool)
    .await
    .map_err(|e| e.to_string())?;

    let window = sqlx::query_as!(
        Window,
        "SELECT * FROM windows ORDER BY id DESC LIMIT 1"
    )
    .fetch_one(pool)
    .await
    .map_err(|e| e.to_string())?;

    Ok(window)
}

#[tauri::command]
pub async fn end_current_window(
    db: State<'_, DbInstances>,
) -> Result<(), String> {
    let pool = db.0.get("sqlite:c5h.db").ok_or("Database not found")?;
    let now = chrono::Utc::now().to_rfc3339();

    sqlx::query!(
        r#"UPDATE windows SET ended_at = ? WHERE ended_at IS NULL"#,
        now
    )
    .execute(pool)
    .await
    .map_err(|e| e.to_string())?;

    Ok(())
}
```

### 2.4 Create Tauri Commands for Settings

Create `src-tauri/src/commands/settings.rs`:

```rust
use crate::models::Settings;
use tauri::State;
use tauri_plugin_sql::{DbInstances, DbPool};

#[tauri::command]
pub async fn get_settings(
    db: State<'_, DbInstances>,
) -> Result<Settings, String> {
    let pool = db.0.get("sqlite:c5h.db").ok_or("Database not found")?;

    let rows: Vec<(String, String)> = sqlx::query_as(
        "SELECT key, value FROM settings"
    )
    .fetch_all(pool)
    .await
    .map_err(|e| e.to_string())?;

    let mut settings = Settings {
        launch_at_login: true,
        show_in_menu_bar: true,
        theme: "system".to_string(),
        notifications_enabled: true,
    };

    for (key, value) in rows {
        match key.as_str() {
            "launch_at_login" => settings.launch_at_login = value == "true",
            "show_in_menu_bar" => settings.show_in_menu_bar = value == "true",
            "theme" => settings.theme = value,
            "notifications_enabled" => settings.notifications_enabled = value == "true",
            _ => {}
        }
    }

    Ok(settings)
}

#[tauri::command]
pub async fn save_settings(
    db: State<'_, DbInstances>,
    settings: Settings,
) -> Result<(), String> {
    let pool = db.0.get("sqlite:c5h.db").ok_or("Database not found")?;

    let pairs = vec![
        ("launch_at_login", settings.launch_at_login.to_string()),
        ("show_in_menu_bar", settings.show_in_menu_bar.to_string()),
        ("theme", settings.theme),
        ("notifications_enabled", settings.notifications_enabled.to_string()),
    ];

    for (key, value) in pairs {
        sqlx::query!(
            "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
            key,
            value
        )
        .execute(pool)
        .await
        .map_err(|e| e.to_string())?;
    }

    Ok(())
}
```

### 2.5 Wire Up Commands in main.rs

Edit `src-tauri/src/main.rs`:

```rust
mod commands;
mod db;
mod models;

use tauri::Manager;

fn main() {
    tauri::Builder::default()
        .plugin(
            tauri_plugin_sql::Builder::default()
                .add_migrations("sqlite:c5h.db", db::get_migrations())
                .build(),
        )
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            Some(vec!["--hidden"]),
        ))
        .plugin(tauri_plugin_positioner::init())
        .invoke_handler(tauri::generate_handler![
            commands::windows::get_windows,
            commands::windows::get_current_window,
            commands::windows::create_window,
            commands::windows::end_current_window,
            commands::settings::get_settings,
            commands::settings::save_settings,
        ])
        .setup(|app| {
            // Setup code will go here
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

### 2.6 Create Frontend API Layer

Create `src-react/lib/api.ts`:

```typescript
import { invoke } from '@tauri-apps/api/core';

export type ToolType = 'claude_code' | 'codex' | 'gemini' | 'other';

export interface Account {
  id: number;
  name: string;
  tool_type: ToolType;
  cli_command: string;
  cli_args: string | null;
  window_duration_hours: number;
  color: string;
  enabled: boolean;
  created_at: string;
}

export interface Window {
  id: number;
  account_id: number;
  started_at: string;
  ended_at: string | null;
  triggered_by: 'manual' | 'scheduled' | 'detected';
  notes: string | null;
  created_at: string;
}

export interface Settings {
  launch_at_login: boolean;
  show_in_menu_bar: boolean;
  theme: 'light' | 'dark' | 'system';
  notifications_enabled: boolean;
}

export interface ScheduledJob {
  id: number;
  account_id: number;
  enabled: boolean;
  hour: number;
  minute: number;
  days: number[];
  last_run: string | null;
}

export const api = {
  // Accounts
  getAccounts: () =>
    invoke<Account[]>('get_accounts'),

  createAccount: (account: Omit<Account, 'id' | 'created_at'>) =>
    invoke<Account>('create_account', { account }),

  updateAccount: (account: Account) =>
    invoke<void>('update_account', { account }),

  deleteAccount: (id: number) =>
    invoke<void>('delete_account', { id }),

  // Windows
  getWindows: (from: string, to: string, accountId?: number) =>
    invoke<Window[]>('get_windows', { from, to, accountId }),

  getCurrentWindow: (accountId?: number) =>
    invoke<Window | null>('get_current_window', { accountId }),

  createWindow: (accountId: number, triggeredBy: string) =>
    invoke<Window>('create_window', { accountId, triggeredBy }),

  endCurrentWindow: (accountId?: number) =>
    invoke<void>('end_current_window', { accountId }),

  // Settings
  getSettings: () =>
    invoke<Settings>('get_settings'),

  saveSettings: (settings: Settings) =>
    invoke<void>('save_settings', { settings }),
};
```

**Checkpoint:** Database should be created at `~/Library/Application Support/com.zaai.c5h/c5h.db`

---

## Phase 3: State Management

**Estimated tasks: 3**

### 3.1 Create Zustand Store

Create `src-react/store/index.ts`:

```typescript
import { create } from 'zustand';
import { api, Window, Settings, ScheduledJob } from '@/lib/api';
import { startOfWeek, endOfWeek, formatISO } from 'date-fns';

interface AppState {
  // Data
  currentWindow: Window | null;
  windows: Window[];
  settings: Settings | null;
  scheduledJob: ScheduledJob | null;

  // UI State
  selectedDate: Date;
  isLoading: boolean;
  error: string | null;

  // Actions
  fetchCurrentWindow: () => Promise<void>;
  fetchWindows: (date: Date) => Promise<void>;
  fetchSettings: () => Promise<void>;
  saveSettings: (settings: Settings) => Promise<void>;
  setSelectedDate: (date: Date) => void;
  triggerWindow: () => Promise<void>;
}

export const useStore = create<AppState>((set, get) => ({
  // Initial state
  currentWindow: null,
  windows: [],
  settings: null,
  scheduledJob: null,
  selectedDate: new Date(),
  isLoading: false,
  error: null,

  // Actions
  fetchCurrentWindow: async () => {
    try {
      const currentWindow = await api.getCurrentWindow();
      set({ currentWindow });
    } catch (error) {
      set({ error: String(error) });
    }
  },

  fetchWindows: async (date: Date) => {
    set({ isLoading: true });
    try {
      const from = formatISO(startOfWeek(date, { weekStartsOn: 1 }));
      const to = formatISO(endOfWeek(date, { weekStartsOn: 1 }));
      const windows = await api.getWindows(from, to);
      set({ windows, isLoading: false });
    } catch (error) {
      set({ error: String(error), isLoading: false });
    }
  },

  fetchSettings: async () => {
    try {
      const settings = await api.getSettings();
      set({ settings });
    } catch (error) {
      set({ error: String(error) });
    }
  },

  saveSettings: async (settings: Settings) => {
    try {
      await api.saveSettings(settings);
      set({ settings });
    } catch (error) {
      set({ error: String(error) });
    }
  },

  setSelectedDate: (date: Date) => {
    set({ selectedDate: date });
    get().fetchWindows(date);
  },

  triggerWindow: async () => {
    try {
      const window = await api.createWindow('manual');
      set({ currentWindow: window });
      get().fetchWindows(get().selectedDate);
    } catch (error) {
      set({ error: String(error) });
    }
  },
}));
```

### 3.2 Create Custom Hooks

Create `src-react/hooks/useCurrentWindow.ts`:

```typescript
import { useEffect } from 'react';
import { useStore } from '@/store';
import { differenceInMinutes, parseISO, addHours } from 'date-fns';

export function useCurrentWindow() {
  const { currentWindow, fetchCurrentWindow } = useStore();

  useEffect(() => {
    fetchCurrentWindow();

    // Refresh every minute
    const interval = setInterval(fetchCurrentWindow, 60000);
    return () => clearInterval(interval);
  }, [fetchCurrentWindow]);

  const getTimeRemaining = () => {
    if (!currentWindow) return null;

    const startTime = parseISO(currentWindow.started_at);
    const endTime = addHours(startTime, 5);
    const now = new Date();

    const minutesRemaining = differenceInMinutes(endTime, now);

    if (minutesRemaining <= 0) return { hours: 0, minutes: 0, percent: 100 };

    const hours = Math.floor(minutesRemaining / 60);
    const minutes = minutesRemaining % 60;
    const percent = Math.round(((300 - minutesRemaining) / 300) * 100);

    return { hours, minutes, percent };
  };

  return {
    currentWindow,
    timeRemaining: getTimeRemaining(),
    isActive: !!currentWindow && !currentWindow.ended_at,
  };
}
```

### 3.3 Create App Initialization Hook

Create `src-react/hooks/useAppInit.ts`:

```typescript
import { useEffect } from 'react';
import { useStore } from '@/store';

export function useAppInit() {
  const { fetchCurrentWindow, fetchWindows, fetchSettings, selectedDate } = useStore();

  useEffect(() => {
    const init = async () => {
      await Promise.all([
        fetchCurrentWindow(),
        fetchWindows(selectedDate),
        fetchSettings(),
      ]);
    };

    init();
  }, []);
}
```

**Checkpoint:** Store should compile without errors

---

## Phase 4: UI Components

**Estimated tasks: 12**

### 4.1 Create Layout Component

Create `src-react/components/Layout.tsx`:

```tsx
import { ReactNode } from 'react';
import { Tabs, TabsList, TabsTrigger } from '@/components/shadcn-ui/tabs';
import { Calendar, BarChart3, Settings } from 'lucide-react';

interface LayoutProps {
  children: ReactNode;
  activeTab: string;
  onTabChange: (tab: string) => void;
}

export function Layout({ children, activeTab, onTabChange }: LayoutProps) {
  return (
    <div className="flex flex-col h-screen bg-background">
      <header className="border-b px-4 py-3">
        <h1 className="text-lg font-semibold">C5h</h1>
      </header>

      <main className="flex-1 overflow-auto p-4">
        {children}
      </main>

      <footer className="border-t">
        <Tabs value={activeTab} onValueChange={onTabChange}>
          <TabsList className="w-full justify-around h-14">
            <TabsTrigger value="calendar" className="flex-1">
              <Calendar className="h-5 w-5" />
            </TabsTrigger>
            <TabsTrigger value="stats" className="flex-1">
              <BarChart3 className="h-5 w-5" />
            </TabsTrigger>
            <TabsTrigger value="settings" className="flex-1">
              <Settings className="h-5 w-5" />
            </TabsTrigger>
          </TabsList>
        </Tabs>
      </footer>
    </div>
  );
}
```

### 4.2 Create Status Card Component

Create `src-react/components/StatusCard.tsx`:

```tsx
import { Card, CardContent, CardHeader, CardTitle } from '@/components/shadcn-ui/card';
import { Progress } from '@/components/shadcn-ui/progress';
import { useCurrentWindow } from '@/hooks/useCurrentWindow';
import { format, parseISO } from 'date-fns';

export function StatusCard() {
  const { currentWindow, timeRemaining, isActive } = useCurrentWindow();

  if (!isActive || !timeRemaining) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="text-sm font-medium">Current Window</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-muted-foreground">No active window</p>
          <p className="text-sm text-muted-foreground mt-1">
            Start using Claude Code to begin a new 5h window
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-sm font-medium">Current Window</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex items-center justify-between">
          <span className="text-2xl font-bold">
            {timeRemaining.hours}h {timeRemaining.minutes}m
          </span>
          <span className="text-sm text-muted-foreground">remaining</span>
        </div>

        <Progress value={timeRemaining.percent} className="h-2" />

        <div className="flex justify-between text-sm text-muted-foreground">
          <span>Started: {format(parseISO(currentWindow!.started_at), 'h:mm a')}</span>
          <span>{timeRemaining.percent}% used</span>
        </div>
      </CardContent>
    </Card>
  );
}
```

### 4.3 Create Week Navigation Component

Create `src-react/components/WeekNavigation.tsx`:

```tsx
import { Button } from '@/components/shadcn-ui/button';
import { ChevronLeft, ChevronRight } from 'lucide-react';
import { useStore } from '@/store';
import { addWeeks, subWeeks, format, startOfWeek, endOfWeek } from 'date-fns';

export function WeekNavigation() {
  const { selectedDate, setSelectedDate } = useStore();

  const weekStart = startOfWeek(selectedDate, { weekStartsOn: 1 });
  const weekEnd = endOfWeek(selectedDate, { weekStartsOn: 1 });

  const goToPreviousWeek = () => setSelectedDate(subWeeks(selectedDate, 1));
  const goToNextWeek = () => setSelectedDate(addWeeks(selectedDate, 1));
  const goToToday = () => setSelectedDate(new Date());

  return (
    <div className="flex items-center justify-between mb-4">
      <div className="flex items-center gap-2">
        <Button variant="outline" size="icon" onClick={goToPreviousWeek}>
          <ChevronLeft className="h-4 w-4" />
        </Button>
        <Button variant="outline" size="icon" onClick={goToNextWeek}>
          <ChevronRight className="h-4 w-4" />
        </Button>
        <Button variant="outline" size="sm" onClick={goToToday}>
          Today
        </Button>
      </div>

      <span className="font-medium">
        {format(weekStart, 'MMM d')} - {format(weekEnd, 'MMM d, yyyy')}
      </span>
    </div>
  );
}
```

### 4.4 Create Calendar View Component

**Scheduling UI Features:**
The calendar supports multiple ways to create schedules:
- **Click** on a time slot to create a schedule at that time
- **Drag** to select a time range for the window
- **Right-click menu** for quick schedule options

Multiple schedules per account are allowed, as long as windows don't overlap.

Create `src-react/components/CalendarView.tsx`:

```tsx
import { useStore } from '@/store';
import { WeekNavigation } from './WeekNavigation';
import { StatusCard } from './StatusCard';
import {
  format,
  parseISO,
  startOfWeek,
  addDays,
  isSameDay,
  differenceInMinutes,
  addHours
} from 'date-fns';

const HOURS = Array.from({ length: 24 }, (_, i) => i);
const HOUR_HEIGHT = 48; // pixels per hour

export function CalendarView() {
  const { windows, selectedDate } = useStore();
  const weekStart = startOfWeek(selectedDate, { weekStartsOn: 1 });
  const days = Array.from({ length: 7 }, (_, i) => addDays(weekStart, i));

  const getWindowStyle = (window: typeof windows[0]) => {
    const start = parseISO(window.started_at);
    const end = window.ended_at ? parseISO(window.ended_at) : addHours(start, 5);

    const startHour = start.getHours() + start.getMinutes() / 60;
    const duration = differenceInMinutes(end, start) / 60;

    return {
      top: `${startHour * HOUR_HEIGHT}px`,
      height: `${Math.min(duration, 5) * HOUR_HEIGHT}px`,
    };
  };

  const getWindowsForDay = (day: Date) => {
    return windows.filter(w => isSameDay(parseISO(w.started_at), day));
  };

  return (
    <div className="space-y-4">
      <StatusCard />
      <WeekNavigation />

      <div className="border rounded-lg overflow-hidden">
        {/* Header */}
        <div className="grid grid-cols-8 border-b bg-muted/50">
          <div className="p-2 text-xs text-muted-foreground" />
          {days.map(day => (
            <div key={day.toISOString()} className="p-2 text-center border-l">
              <div className="text-xs text-muted-foreground">
                {format(day, 'EEE')}
              </div>
              <div className={`text-sm font-medium ${
                isSameDay(day, new Date()) ? 'text-primary' : ''
              }`}>
                {format(day, 'd')}
              </div>
            </div>
          ))}
        </div>

        {/* Time grid */}
        <div className="grid grid-cols-8 relative" style={{ height: `${24 * HOUR_HEIGHT}px` }}>
          {/* Time labels */}
          <div className="relative">
            {HOURS.map(hour => (
              <div
                key={hour}
                className="absolute w-full text-xs text-muted-foreground text-right pr-2"
                style={{ top: `${hour * HOUR_HEIGHT}px` }}
              >
                {format(new Date().setHours(hour, 0), 'h a')}
              </div>
            ))}
          </div>

          {/* Day columns */}
          {days.map(day => (
            <div key={day.toISOString()} className="relative border-l">
              {/* Hour lines */}
              {HOURS.map(hour => (
                <div
                  key={hour}
                  className="absolute w-full border-t border-dashed border-muted"
                  style={{ top: `${hour * HOUR_HEIGHT}px` }}
                />
              ))}

              {/* Windows */}
              {getWindowsForDay(day).map(window => (
                <div
                  key={window.id}
                  className="absolute left-1 right-1 bg-primary/20 border-l-2 border-primary rounded-sm p-1 overflow-hidden"
                  style={getWindowStyle(window)}
                >
                  <div className="text-xs font-medium truncate">
                    5h Window
                  </div>
                  <div className="text-xs text-muted-foreground">
                    {format(parseISO(window.started_at), 'h:mm a')}
                  </div>
                </div>
              ))}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
```

### 4.5 Create Settings View Component

Create `src-react/components/SettingsView.tsx`:

```tsx
import { useStore } from '@/store';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/shadcn-ui/card';
import { Label } from '@/components/shadcn-ui/label';
import { Switch } from '@/components/shadcn-ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/shadcn-ui/select';
import { AccountsSettings } from './AccountsSettings';
import { SchedulerSettings } from './SchedulerSettings';

export function SettingsView() {
  const { settings, saveSettings } = useStore();

  if (!settings) return null;

  const updateSetting = <K extends keyof typeof settings>(
    key: K,
    value: typeof settings[K]
  ) => {
    saveSettings({ ...settings, [key]: value });
  };

  return (
    <div className="space-y-4">
      {/* Accounts Section */}
      <AccountsSettings />

      {/* Scheduler Section */}
      <SchedulerSettings />

      {/* General Settings */}
      <Card>
        <CardHeader>
          <CardTitle>General</CardTitle>
          <CardDescription>Configure app behavior</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center justify-between">
            <Label htmlFor="launch-at-login">Launch at login</Label>
            <Switch
              id="launch-at-login"
              checked={settings.launch_at_login}
              onCheckedChange={(v) => updateSetting('launch_at_login', v)}
            />
          </div>

          <div className="flex items-center justify-between">
            <Label htmlFor="show-menu-bar">Show in menu bar</Label>
            <Switch
              id="show-menu-bar"
              checked={settings.show_in_menu_bar}
              onCheckedChange={(v) => updateSetting('show_in_menu_bar', v)}
            />
          </div>

          <div className="flex items-center justify-between">
            <Label htmlFor="notifications">Notifications</Label>
            <Switch
              id="notifications"
              checked={settings.notifications_enabled}
              onCheckedChange={(v) => updateSetting('notifications_enabled', v)}
            />
          </div>
        </CardContent>
      </Card>

      {/* Appearance Settings */}
      <Card>
        <CardHeader>
          <CardTitle>Appearance</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-between">
            <Label>Theme</Label>
            <Select
              value={settings.theme}
              onValueChange={(v) => updateSetting('theme', v as any)}
            >
              <SelectTrigger className="w-32">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="system">System</SelectItem>
                <SelectItem value="light">Light</SelectItem>
                <SelectItem value="dark">Dark</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
```

### 4.6 Create Accounts Settings Component

Create `src-react/components/AccountsSettings.tsx`:

```tsx
import { useState, useEffect } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/shadcn-ui/card';
import { Button } from '@/components/shadcn-ui/button';
import { Input } from '@/components/shadcn-ui/input';
import { Label } from '@/components/shadcn-ui/label';
import { Switch } from '@/components/shadcn-ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/shadcn-ui/select';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from '@/components/shadcn-ui/dialog';
import { Plus, Pencil, Trash2 } from 'lucide-react';
import { api, Account, ToolType } from '@/lib/api';

const TOOL_TYPES: { value: ToolType; label: string; defaultCommand: string }[] = [
  { value: 'claude_code', label: 'Claude Code', defaultCommand: 'claude' },
  { value: 'codex', label: 'Codex (OpenAI)', defaultCommand: 'codex' },
  { value: 'gemini', label: 'Gemini', defaultCommand: 'gemini' },
  { value: 'other', label: 'Other', defaultCommand: '' },
];

const DEFAULT_COLORS = [
  '#6366f1', // Indigo (Claude)
  '#10a37f', // Green (OpenAI)
  '#4285f4', // Blue (Google)
  '#f59e0b', // Amber
  '#ec4899', // Pink
  '#8b5cf6', // Purple
];

export function AccountsSettings() {
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [editingAccount, setEditingAccount] = useState<Partial<Account> | null>(null);
  const [isDialogOpen, setIsDialogOpen] = useState(false);

  useEffect(() => {
    loadAccounts();
  }, []);

  const loadAccounts = async () => {
    const data = await api.getAccounts();
    setAccounts(data);
  };

  const handleSave = async () => {
    if (!editingAccount?.name || !editingAccount?.cli_command) return;

    if (editingAccount.id) {
      await api.updateAccount(editingAccount as Account);
    } else {
      await api.createAccount({
        name: editingAccount.name,
        tool_type: editingAccount.tool_type || 'other',
        cli_command: editingAccount.cli_command,
        cli_args: editingAccount.cli_args || null,
        window_duration_hours: editingAccount.window_duration_hours || 5,
        color: editingAccount.color || DEFAULT_COLORS[accounts.length % DEFAULT_COLORS.length],
        enabled: true,
      });
    }

    setIsDialogOpen(false);
    setEditingAccount(null);
    loadAccounts();
  };

  const handleDelete = async (id: number) => {
    if (confirm('Delete this account?')) {
      await api.deleteAccount(id);
      loadAccounts();
    }
  };

  const openNewDialog = () => {
    setEditingAccount({
      tool_type: 'claude_code',
      cli_command: 'claude',
      window_duration_hours: 5,
      color: DEFAULT_COLORS[accounts.length % DEFAULT_COLORS.length],
    });
    setIsDialogOpen(true);
  };

  const openEditDialog = (account: Account) => {
    setEditingAccount(account);
    setIsDialogOpen(true);
  };

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle>Accounts</CardTitle>
            <CardDescription>Manage AI tool accounts</CardDescription>
          </div>
          <Button size="sm" onClick={openNewDialog}>
            <Plus className="h-4 w-4 mr-1" />
            Add
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        {accounts.map(account => (
          <div
            key={account.id}
            className="flex items-center justify-between p-3 border rounded-lg"
          >
            <div className="flex items-center gap-3">
              <div
                className="w-3 h-3 rounded-full"
                style={{ backgroundColor: account.color }}
              />
              <div>
                <div className="font-medium">{account.name}</div>
                <div className="text-sm text-muted-foreground">
                  {account.cli_command} • {account.window_duration_hours}h window
                </div>
              </div>
            </div>
            <div className="flex items-center gap-2">
              <Switch
                checked={account.enabled}
                onCheckedChange={async (enabled) => {
                  await api.updateAccount({ ...account, enabled });
                  loadAccounts();
                }}
              />
              <Button variant="ghost" size="icon" onClick={() => openEditDialog(account)}>
                <Pencil className="h-4 w-4" />
              </Button>
              <Button variant="ghost" size="icon" onClick={() => handleDelete(account.id)}>
                <Trash2 className="h-4 w-4" />
              </Button>
            </div>
          </div>
        ))}

        <Dialog open={isDialogOpen} onOpenChange={setIsDialogOpen}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>
                {editingAccount?.id ? 'Edit Account' : 'Add Account'}
              </DialogTitle>
            </DialogHeader>
            <div className="space-y-4">
              <div className="space-y-2">
                <Label>Tool Type</Label>
                <Select
                  value={editingAccount?.tool_type || 'claude_code'}
                  onValueChange={(value: ToolType) => {
                    const tool = TOOL_TYPES.find(t => t.value === value);
                    setEditingAccount(prev => ({
                      ...prev,
                      tool_type: value,
                      cli_command: tool?.defaultCommand || prev?.cli_command,
                      window_duration_hours: value === 'gemini' ? 24 : 5,
                    }));
                  }}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {TOOL_TYPES.map(type => (
                      <SelectItem key={type.value} value={type.value}>
                        {type.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              <div className="space-y-2">
                <Label>Account Name</Label>
                <Input
                  value={editingAccount?.name || ''}
                  onChange={e => setEditingAccount(prev => ({ ...prev, name: e.target.value }))}
                  placeholder="e.g., Claude Code (Work)"
                />
              </div>

              <div className="space-y-2">
                <Label>CLI Command</Label>
                <Input
                  value={editingAccount?.cli_command || ''}
                  onChange={e => setEditingAccount(prev => ({ ...prev, cli_command: e.target.value }))}
                  placeholder="e.g., claude"
                />
              </div>

              <div className="space-y-2">
                <Label>CLI Arguments (optional)</Label>
                <Input
                  value={editingAccount?.cli_args || ''}
                  onChange={e => setEditingAccount(prev => ({ ...prev, cli_args: e.target.value }))}
                  placeholder='e.g., -p "1+1"'
                />
              </div>

              <div className="space-y-2">
                <Label>Window Duration (hours)</Label>
                <Input
                  type="number"
                  min={1}
                  max={24}
                  value={editingAccount?.window_duration_hours || 5}
                  onChange={e => setEditingAccount(prev => ({
                    ...prev,
                    window_duration_hours: Number(e.target.value)
                  }))}
                />
              </div>

              <div className="space-y-2">
                <Label>Color</Label>
                <div className="flex gap-2">
                  {DEFAULT_COLORS.map(color => (
                    <button
                      key={color}
                      className={`w-8 h-8 rounded-full border-2 ${
                        editingAccount?.color === color ? 'border-primary' : 'border-transparent'
                      }`}
                      style={{ backgroundColor: color }}
                      onClick={() => setEditingAccount(prev => ({ ...prev, color }))}
                    />
                  ))}
                </div>
              </div>

              <div className="flex justify-end gap-2">
                <Button variant="outline" onClick={() => setIsDialogOpen(false)}>
                  Cancel
                </Button>
                <Button onClick={handleSave}>
                  Save
                </Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>
      </CardContent>
    </Card>
  );
}
```

### 4.7 Create Stats View Component

Create `src-react/components/StatsView.tsx`:

```tsx
import { Card, CardContent, CardHeader, CardTitle } from '@/components/shadcn-ui/card';
import { useStore } from '@/store';
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer
} from 'recharts';
import {
  startOfWeek,
  endOfWeek,
  eachDayOfInterval,
  format,
  parseISO,
  isSameDay,
  differenceInMinutes,
  addHours
} from 'date-fns';

export function StatsView() {
  const { windows, selectedDate } = useStore();

  const weekStart = startOfWeek(selectedDate, { weekStartsOn: 1 });
  const weekEnd = endOfWeek(selectedDate, { weekStartsOn: 1 });
  const daysInWeek = eachDayOfInterval({ start: weekStart, end: weekEnd });

  // Calculate stats
  const totalWindows = windows.length;
  const avgDuration = windows.length > 0
    ? windows.reduce((acc, w) => {
        const start = parseISO(w.started_at);
        const end = w.ended_at ? parseISO(w.ended_at) : addHours(start, 5);
        return acc + differenceInMinutes(end, start);
      }, 0) / windows.length / 60
    : 0;

  // Chart data
  const chartData = daysInWeek.map(day => ({
    name: format(day, 'EEE'),
    windows: windows.filter(w => isSameDay(parseISO(w.started_at), day)).length,
  }));

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-4">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">
              Windows This Week
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{totalWindows}</div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">
              Avg Duration
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{avgDuration.toFixed(1)}h</div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-sm font-medium">Windows by Day</CardTitle>
        </CardHeader>
        <CardContent>
          <ResponsiveContainer width="100%" height={200}>
            <BarChart data={chartData}>
              <XAxis dataKey="name" />
              <YAxis allowDecimals={false} />
              <Tooltip />
              <Bar dataKey="windows" fill="hsl(var(--primary))" radius={4} />
            </BarChart>
          </ResponsiveContainer>
        </CardContent>
      </Card>
    </div>
  );
}
```

### 4.7 Update App.tsx

Replace `src-react/App.tsx`:

```tsx
import { useState } from 'react';
import { Layout } from '@/components/Layout';
import { CalendarView } from '@/components/CalendarView';
import { StatsView } from '@/components/StatsView';
import { SettingsView } from '@/components/SettingsView';
import { useAppInit } from '@/hooks/useAppInit';
import './App.css';

function App() {
  const [activeTab, setActiveTab] = useState('calendar');

  useAppInit();

  return (
    <Layout activeTab={activeTab} onTabChange={setActiveTab}>
      {activeTab === 'calendar' && <CalendarView />}
      {activeTab === 'stats' && <StatsView />}
      {activeTab === 'settings' && <SettingsView />}
    </Layout>
  );
}

export default App;
```

**Checkpoint:** Run `bun tauri dev` - main app window should display

---

## Phase 5: Menu Bar (System Tray)

**Estimated tasks: 5**

### 5.1 Create Tray Icon

Create a 22x22 PNG icon for the menu bar:
- Save as `src-tauri/icons/tray.png`
- Use a simple cloud or timer icon
- Should be monochrome for macOS template icon

### 5.2 Set Up Tray in Rust

Update `src-tauri/src/main.rs`:

```rust
use tauri::{
    AppHandle, Manager, SystemTray, SystemTrayEvent,
    CustomMenuItem, SystemTrayMenu, SystemTrayMenuItem
};

fn create_tray_menu() -> SystemTrayMenu {
    let open = CustomMenuItem::new("open".to_string(), "Open C5h");
    let quit = CustomMenuItem::new("quit".to_string(), "Quit");

    SystemTrayMenu::new()
        .add_item(open)
        .add_native_item(SystemTrayMenuItem::Separator)
        .add_item(quit)
}

fn main() {
    let tray = SystemTray::new()
        .with_menu(create_tray_menu())
        .with_tooltip("C5h - No active window");

    tauri::Builder::default()
        .system_tray(tray)
        .on_system_tray_event(|app, event| match event {
            SystemTrayEvent::LeftClick { .. } => {
                // Toggle popover window
                if let Some(window) = app.get_window("popover") {
                    if window.is_visible().unwrap_or(false) {
                        let _ = window.hide();
                    } else {
                        let _ = window.show();
                        let _ = window.set_focus();
                    }
                }
            }
            SystemTrayEvent::MenuItemClick { id, .. } => match id.as_str() {
                "open" => {
                    if let Some(window) = app.get_window("main") {
                        let _ = window.show();
                        let _ = window.set_focus();
                    }
                }
                "quit" => {
                    std::process::exit(0);
                }
                _ => {}
            },
            _ => {}
        })
        // ... rest of builder
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

### 5.3 Create Popover Window

Add to `src-tauri/tauri.conf.json` in the `windows` array:

```json
{
  "label": "popover",
  "title": "C5h Status",
  "width": 300,
  "height": 280,
  "visible": false,
  "decorations": false,
  "alwaysOnTop": true,
  "skipTaskbar": true,
  "resizable": false
}
```

### 5.4 Create Popover UI Component

Create `src-react/components/PopoverWindow.tsx`:

```tsx
import { Button } from '@/components/shadcn-ui/button';
import { Progress } from '@/components/shadcn-ui/progress';
import { Separator } from '@/components/shadcn-ui/separator';
import { Settings, ExternalLink, Play } from 'lucide-react';
import { useCurrentWindow } from '@/hooks/useCurrentWindow';
import { useStore } from '@/store';
import { format, parseISO } from 'date-fns';
import { invoke } from '@tauri-apps/api/core';

export function PopoverWindow() {
  const { currentWindow, timeRemaining, isActive } = useCurrentWindow();
  const { triggerWindow } = useStore();

  const openMainWindow = async () => {
    await invoke('open_main_window');
  };

  const handleQuickStart = async () => {
    await triggerWindow();
  };

  return (
    <div className="p-3 space-y-3">
      {/* Header with percentage display (shown in menu bar) */}
      <div className="flex justify-between items-center">
        <div className="font-medium">Current Window</div>
        {isActive && timeRemaining && (
          <div className="text-lg font-bold">{timeRemaining.percent}%</div>
        )}
      </div>

      {isActive && timeRemaining ? (
        <>
          <div className="space-y-2">
            <div className="flex justify-between items-baseline">
              <span className="text-2xl font-bold">
                {timeRemaining.hours}h {timeRemaining.minutes}m
              </span>
              <span className="text-sm text-muted-foreground">remaining</span>
            </div>
            <Progress value={timeRemaining.percent} className="h-2" />
            <div className="flex justify-between text-xs text-muted-foreground">
              <span>Started: {format(parseISO(currentWindow!.started_at), 'h:mm a')}</span>
              <span>{timeRemaining.percent}% used</span>
            </div>
          </div>
        </>
      ) : (
        <div className="space-y-3">
          <div className="text-muted-foreground text-sm">
            No active window
          </div>
          {/* Quick Start Window Button */}
          <Button
            variant="default"
            size="sm"
            className="w-full"
            onClick={handleQuickStart}
          >
            <Play className="h-4 w-4 mr-2" />
            Start New Window
          </Button>
        </div>
      )}

      <Separator />

      <div className="flex justify-between text-sm">
        <span className="text-muted-foreground">This week</span>
        <span>4 windows</span>
      </div>

      <div className="flex justify-between text-sm">
        <span className="text-muted-foreground">Next scheduled</span>
        <span>3:00 AM</span>
      </div>

      <Separator />

      <div className="flex gap-2">
        <Button variant="outline" size="sm" className="flex-1" onClick={openMainWindow}>
          <ExternalLink className="h-4 w-4 mr-1" />
          Open App
        </Button>
        <Button variant="outline" size="icon" onClick={openMainWindow}>
          <Settings className="h-4 w-4" />
        </Button>
      </div>
    </div>
  );
}
```

### 5.5 Create Popover Entry Point

Create `src-react/popover.tsx`:

```tsx
import React from 'react';
import ReactDOM from 'react-dom/client';
import { PopoverWindow } from '@/components/PopoverWindow';
import './index.css';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <PopoverWindow />
  </React.StrictMode>
);
```

Update `index.html` to conditionally load popover or main app based on URL.

**Checkpoint:** Menu bar icon should appear, clicking shows popover

---

## Phase 6: Scheduler Integration

**Estimated tasks: 4**

### Window Detection

**Detection Method:** Poll CLI every 15 minutes

The app runs a background task that polls the CLI tools to detect active windows.

**Poll Interval:** 15 minutes (configurable)

**Claude Code:**
Run `/usage` inside Claude Code to see:
```
  Current session
  █████████████████████████████████████▌             75% used
  Resets 1:59am (Europe/Berlin)

  Current week (all models)
  ██████████████████████▌                            45% used
  Resets Jan 22 at 10:59am (Europe/Berlin)

  Current week (Sonnet only)
                                                     0% used
```
Parse this to get:
- Current session percentage used and reset time
- Weekly limit for all models
- Weekly limit for Sonnet-only model
  - End time of the current 5h window
  - Percentage already used

**Gemini CLI:**
Usage is shown on startup. The display shows:
```
│  Model Usage                 Reqs                  Usage left              │
│  ────────────────────────────────────────────────────────────              │
│  gemini-2.5-flash               -       99.9% (Resets in 24h)              │
│  gemini-2.5-flash-lite          -       99.9% (Resets in 24h)              │
│  gemini-2.5-pro                 -      100.0% (Resets in 24h)              │
│  gemini-3-flash-preview         -      100.0% (Resets in 24h)              │
│  gemini-3-pro-preview           -      100.0% (Resets in 24h)              │
```

**Codex (OpenAI):**
Run `/status` inside Codex to see both limits:
```
│  5h limit:       [████████████████████] 100% left (resets 06:44)          │
│  Weekly limit:   [████████████████████] 99% left (resets 19:51 on 24 Jan) │
```

**Key differences:**
- Claude Code: 5h rolling windows, ~11 windows/week at 100% usage, starts on full hour
- Codex: 5h windows + weekly limit, starts on any minute (more flexible)
- Gemini: 24h daily quota per model, resets after first use

**Important timing rules:**
- Claude Code windows always start on the **full hour** (e.g., 3:00 AM)
- Codex windows start on **any minute** (e.g., 3:15 AM) - more flexible
- Gemini has no windows - uses rolling 24h daily limit
- Overlapping is OK across different tools, but not for the same account

### 6.1 Create Scheduler Commands

Create `src-tauri/src/commands/scheduler.rs`:

```rust
use std::fs;
use std::path::PathBuf;
use std::process::Command;

// Note: Claude Code windows always start on the full hour
// The trigger command is: claude -p "1+1"
const PLIST_TEMPLATE: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.zaai.c5h.scheduler.{ACCOUNT_ID}</string>
    <key>ProgramArguments</key>
    <array>
        <string>{CLI_COMMAND}</string>
        <string>-p</string>
        <string>1+1</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>{HOUR}</integer>
        <key>Minute</key>
        <integer>{MINUTE}</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/c5h-scheduler.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/c5h-scheduler.log</string>
</dict>
</plist>"#;

fn get_plist_path() -> PathBuf {
    let home = std::env::var("HOME").expect("HOME not set");
    PathBuf::from(home)
        .join("Library")
        .join("LaunchAgents")
        .join("com.zaai.c5h.scheduler.plist")
}

#[tauri::command]
pub fn install_scheduler(hour: i32, minute: i32) -> Result<(), String> {
    let plist_content = PLIST_TEMPLATE
        .replace("{HOUR}", &hour.to_string())
        .replace("{MINUTE}", &minute.to_string());

    let plist_path = get_plist_path();

    // Unload existing if present
    let _ = Command::new("launchctl")
        .args(["unload", plist_path.to_str().unwrap()])
        .output();

    // Write plist file
    fs::write(&plist_path, plist_content)
        .map_err(|e| format!("Failed to write plist: {}", e))?;

    // Load the new plist
    Command::new("launchctl")
        .args(["load", plist_path.to_str().unwrap()])
        .output()
        .map_err(|e| format!("Failed to load plist: {}", e))?;

    Ok(())
}

#[tauri::command]
pub fn uninstall_scheduler() -> Result<(), String> {
    let plist_path = get_plist_path();

    if plist_path.exists() {
        // Unload
        Command::new("launchctl")
            .args(["unload", plist_path.to_str().unwrap()])
            .output()
            .map_err(|e| format!("Failed to unload plist: {}", e))?;

        // Delete file
        fs::remove_file(&plist_path)
            .map_err(|e| format!("Failed to delete plist: {}", e))?;
    }

    Ok(())
}

#[tauri::command]
pub fn is_scheduler_installed() -> bool {
    get_plist_path().exists()
}
```

### 6.2 Add Scheduler UI

Create `src-react/components/SchedulerSettings.tsx`:

```tsx
import { useState, useEffect } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/shadcn-ui/card';
import { Label } from '@/components/shadcn-ui/label';
import { Switch } from '@/components/shadcn-ui/switch';
import { Input } from '@/components/shadcn-ui/input';
import { Button } from '@/components/shadcn-ui/button';
import { invoke } from '@tauri-apps/api/core';

export function SchedulerSettings() {
  const [enabled, setEnabled] = useState(false);
  const [hour, setHour] = useState(3);
  const [minute, setMinute] = useState(0);

  useEffect(() => {
    invoke<boolean>('is_scheduler_installed').then(setEnabled);
  }, []);

  const handleToggle = async (value: boolean) => {
    if (value) {
      await invoke('install_scheduler', { hour, minute });
    } else {
      await invoke('uninstall_scheduler');
    }
    setEnabled(value);
  };

  const handleTimeChange = async () => {
    if (enabled) {
      await invoke('install_scheduler', { hour, minute });
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Scheduler</CardTitle>
        <CardDescription>
          Automatically start a 5h window at a scheduled time
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex items-center justify-between">
          <Label htmlFor="scheduler-enabled">Enable scheduler</Label>
          <Switch
            id="scheduler-enabled"
            checked={enabled}
            onCheckedChange={handleToggle}
          />
        </div>

        {enabled && (
          <div className="space-y-2">
            <Label>Trigger time</Label>
            <div className="flex gap-2 items-center">
              <Input
                type="number"
                min={0}
                max={23}
                value={hour}
                onChange={(e) => setHour(Number(e.target.value))}
                className="w-20"
              />
              <span>:</span>
              <Input
                type="number"
                min={0}
                max={59}
                value={minute}
                onChange={(e) => setMinute(Number(e.target.value))}
                className="w-20"
              />
              <Button variant="outline" onClick={handleTimeChange}>
                Update
              </Button>
            </div>
            <p className="text-xs text-muted-foreground">
              Mac will wake from sleep to run at this time
            </p>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
```

### 6.3 Register Scheduler Commands

Add to `main.rs` invoke_handler:

```rust
commands::scheduler::install_scheduler,
commands::scheduler::uninstall_scheduler,
commands::scheduler::is_scheduler_installed,
```

### 6.4 Add Scheduler to Settings View

Update `SettingsView.tsx` to include `<SchedulerSettings />`.

**Checkpoint:** Scheduler toggle should install/uninstall launchd plist

---

## Phase 7: Notifications & Background Polling

**Estimated tasks: 5**

### 7.1 Create Background Polling Service

Create `src-tauri/src/commands/polling.rs`:

```rust
use std::process::Command;
use tauri::AppHandle;
use tauri_plugin_notification::NotificationExt;

/// Poll interval: 15 minutes (in milliseconds)
const POLL_INTERVAL_MS: u64 = 15 * 60 * 1000;

#[tauri::command]
pub async fn poll_cli_usage(app: AppHandle, account_id: i64, cli_command: String) -> Result<String, String> {
    // Run the CLI command to check usage
    // This is a simplified version - actual implementation needs to parse CLI output
    let output = Command::new(&cli_command)
        .args(["--version"]) // Placeholder - actual command varies by tool
        .output()
        .map_err(|e| format!("Failed to run CLI: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    Ok(stdout)
}

/// Start the background polling timer
pub fn start_polling_timer(app: AppHandle) {
    std::thread::spawn(move || {
        loop {
            std::thread::sleep(std::time::Duration::from_millis(POLL_INTERVAL_MS));
            // Emit event to frontend to trigger polling
            let _ = app.emit("poll-usage", ());
        }
    });
}
```

### 7.2 Create Notification Service

Create `src-tauri/src/commands/notifications.rs`:

```rust
use tauri::AppHandle;
use tauri_plugin_notification::NotificationExt;

#[tauri::command]
pub async fn send_notification(
    app: AppHandle,
    title: String,
    body: String,
) -> Result<(), String> {
    app.notification()
        .builder()
        .title(&title)
        .body(&body)
        .show()
        .map_err(|e| e.to_string())?;

    Ok(())
}

#[tauri::command]
pub async fn notify_window_ending_soon(
    app: AppHandle,
    account_name: String,
    minutes_remaining: i32,
) -> Result<(), String> {
    let title = format!("Window Ending Soon");
    let body = format!(
        "Your {} window expires in {} minutes",
        account_name, minutes_remaining
    );

    send_notification(app, title, body).await
}

#[tauri::command]
pub async fn notify_scheduled_trigger(
    app: AppHandle,
    account_name: String,
    success: bool,
) -> Result<(), String> {
    let (title, body) = if success {
        (
            "Window Started".to_string(),
            format!("New {} window started successfully", account_name),
        )
    } else {
        (
            "Trigger Failed".to_string(),
            format!("Failed to start {} window - check CLI", account_name),
        )
    };

    send_notification(app, title, body).await
}

#[tauri::command]
pub async fn notify_weekly_summary(
    app: AppHandle,
    total_windows: i32,
    avg_duration: f32,
) -> Result<(), String> {
    let title = "Weekly Summary".to_string();
    let body = format!(
        "This week: {} windows used, avg {:.1}h each",
        total_windows, avg_duration
    );

    send_notification(app, title, body).await
}
```

### 7.3 Add Notification Settings

Update `src-react/components/SettingsView.tsx` to add notification toggles:

```tsx
{/* Notification Settings */}
<Card>
  <CardHeader>
    <CardTitle>Notifications</CardTitle>
    <CardDescription>Configure when to receive notifications</CardDescription>
  </CardHeader>
  <CardContent className="space-y-4">
    <div className="flex items-center justify-between">
      <div>
        <Label>Window ending soon</Label>
        <p className="text-xs text-muted-foreground">
          Alert 30 and 15 minutes before expiry
        </p>
      </div>
      <Switch
        checked={settings.notify_ending_soon}
        onCheckedChange={(v) => updateSetting('notify_ending_soon', v)}
      />
    </div>

    <div className="flex items-center justify-between">
      <div>
        <Label>Scheduled trigger status</Label>
        <p className="text-xs text-muted-foreground">
          Confirm when scheduled windows start
        </p>
      </div>
      <Switch
        checked={settings.notify_trigger_status}
        onCheckedChange={(v) => updateSetting('notify_trigger_status', v)}
      />
    </div>

    <div className="flex items-center justify-between">
      <div>
        <Label>Weekly summary</Label>
        <p className="text-xs text-muted-foreground">
          Summary on Sunday evening
        </p>
      </div>
      <Switch
        checked={settings.notify_weekly_summary}
        onCheckedChange={(v) => updateSetting('notify_weekly_summary', v)}
      />
    </div>
  </CardContent>
</Card>
```

### 7.4 Update Settings Model

Update `src-tauri/src/models.rs`:

```rust
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Settings {
    pub launch_at_login: bool,
    pub show_in_menu_bar: bool,
    pub theme: String,
    pub notifications_enabled: bool,
    // New notification settings
    pub notify_ending_soon: bool,
    pub notify_trigger_status: bool,
    pub notify_weekly_summary: bool,
    pub poll_interval_minutes: i32,
}
```

### 7.5 Add Window Ending Timer

Create `src-react/hooks/useWindowEndingAlert.ts`:

```typescript
import { useEffect, useRef } from 'react';
import { useCurrentWindow } from './useCurrentWindow';
import { invoke } from '@tauri-apps/api/core';
import { useStore } from '@/store';

export function useWindowEndingAlert() {
  const { currentWindow, timeRemaining } = useCurrentWindow();
  const { settings } = useStore();
  const alertedRef = useRef<Set<number>>(new Set());

  useEffect(() => {
    if (!settings?.notify_ending_soon || !timeRemaining) return;

    const minutesLeft = timeRemaining.hours * 60 + timeRemaining.minutes;

    // Alert at 30 minutes
    if (minutesLeft <= 30 && minutesLeft > 15 && !alertedRef.current.has(30)) {
      invoke('notify_window_ending_soon', {
        accountName: 'Claude Code', // Get from account
        minutesRemaining: 30,
      });
      alertedRef.current.add(30);
    }

    // Alert at 15 minutes
    if (minutesLeft <= 15 && !alertedRef.current.has(15)) {
      invoke('notify_window_ending_soon', {
        accountName: 'Claude Code',
        minutesRemaining: 15,
      });
      alertedRef.current.add(15);
    }

    // Reset alerts when window changes
    if (!currentWindow) {
      alertedRef.current.clear();
    }
  }, [timeRemaining, settings, currentWindow]);
}
```

**Checkpoint:** Notifications should appear for window ending, trigger status, and weekly summary

---

## Phase 8: Distribution Setup

**Estimated tasks: 6**

### 8.1 Create GitHub Actions Workflow

Create `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Bun
        uses: oven-sh/setup-bun@v2
        with:
          bun-version: latest

      - name: Install Rust
        uses: dtolnay/rust-toolchain@stable
        with:
          targets: aarch64-apple-darwin,x86_64-apple-darwin

      - name: Install dependencies
        run: bun install

      - name: Build Tauri
        uses: tauri-apps/tauri-action@v0
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          APPLE_CERTIFICATE: ${{ secrets.APPLE_CERTIFICATE }}
          APPLE_CERTIFICATE_PASSWORD: ${{ secrets.APPLE_CERTIFICATE_PASSWORD }}
          APPLE_SIGNING_IDENTITY: ${{ secrets.APPLE_SIGNING_IDENTITY }}
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_PASSWORD: ${{ secrets.APPLE_PASSWORD }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        with:
          tagName: ${{ github.ref_name }}
          releaseName: 'C5h ${{ github.ref_name }}'
          releaseBody: 'See the assets to download this version.'
          releaseDraft: true
          prerelease: false
          args: --target universal-apple-darwin
```

### 8.2 Create App Icons

Generate icons in these sizes:
- `32x32.png`
- `128x128.png`
- `128x128@2x.png` (256x256)
- `icon.icns` (macOS app icon)
- `tray.png` (22x22, template icon)

Place in `src-tauri/icons/`.

### 8.3 Configure Bundle Settings

Update `src-tauri/tauri.conf.json`:

```json
{
  "bundle": {
    "active": true,
    "targets": ["dmg", "app"],
    "icon": [
      "icons/32x32.png",
      "icons/128x128.png",
      "icons/128x128@2x.png",
      "icons/icon.icns"
    ],
    "macOS": {
      "minimumSystemVersion": "12.0",
      "entitlements": null,
      "signingIdentity": null,
      "providerShortName": null
    }
  }
}
```

### 8.4 Set Up GitHub Secrets

Add these secrets to your GitHub repo (or org):

| Secret | How to get it |
| --- | --- |
| `APPLE_CERTIFICATE` | Base64 of .p12: `base64 -i cert.p12 \ | pbcopy` |
| `APPLE_CERTIFICATE_PASSWORD` | Password you set when exporting .p12 |
| `APPLE_SIGNING_IDENTITY` | `Developer ID Application: Name (TEAMID)` |
| `APPLE_ID` | Your Apple ID email |
| `APPLE_PASSWORD` | App-specific password from appleid.apple.com |
| `APPLE_TEAM_ID` | 10-char Team ID from developer.apple.com |

### 8.5 Create Homebrew Cask Formula

Create `homebrew-cask/c5h.rb`:

```ruby
cask "c5h" do
  version "0.1.0"
  sha256 "REPLACE_WITH_ACTUAL_SHA256"

  url "https://github.com/YOUR_USERNAME/c5h/releases/download/v#{version}/C5h_#{version}_universal.dmg"
  name "C5h"
  desc "Claude Code 5h window optimizer"
  homepage "https://github.com/YOUR_USERNAME/c5h"

  depends_on macos: ">= :monterey"

  app "C5h.app"

  zap trash: [
    "~/Library/Application Support/com.zaai.c5h",
    "~/Library/LaunchAgents/com.zaai.c5h.scheduler.plist",
    "~/Library/Preferences/com.zaai.c5h.plist",
  ]
end
```

### 8.6 Create Release Checklist

Create `RELEASE.md`:

```markdown
# Release Checklist

## Before Release
- [ ] Update version in `package.json`
- [ ] Update version in `src-tauri/Cargo.toml`
- [ ] Update version in `src-tauri/tauri.conf.json`
- [ ] Update CHANGELOG.md
- [ ] Test on macOS Intel
- [ ] Test on macOS Apple Silicon

## Release
1. Create and push tag: `git tag v0.1.0 && git push origin v0.1.0`
2. Wait for GitHub Actions to build
3. Download DMG from draft release
4. Test DMG installation
5. Publish release

## After Release
- [ ] Update Homebrew cask with new SHA256
- [ ] Submit PR to homebrew-cask (or your tap)
```

**Checkpoint:** Push a tag, verify GitHub Actions builds successfully

---

## Phase 9: Testing & Polish

**Estimated tasks: 5**

### 9.1 Manual Test Checklist

```markdown
## Menu Bar
- [ ] Icon appears in menu bar showing percentage (e.g., "75%")
- [ ] Left-click opens popover
- [ ] Popover shows current window status
- [ ] Quick Start button triggers new window
- [ ] Right-click shows menu
- [ ] "Open C5h" opens main window
- [ ] "Quit" exits app

## Main Window
- [ ] Calendar shows current week
- [ ] Navigation buttons work
- [ ] Windows display correctly with account colors
- [ ] Click on calendar creates one-time schedule
- [ ] Stats tab shows charts
- [ ] Settings save correctly

## Accounts
- [ ] Default accounts (Claude, Codex, Gemini) appear
- [ ] Can add new account
- [ ] Can edit account (name, color, CLI)
- [ ] Can enable/disable account
- [ ] Can delete account

## Scheduler
- [ ] Toggle installs plist
- [ ] Toggle uninstalls plist
- [ ] Time change updates plist
- [ ] Plist runs at scheduled time
- [ ] Mac wakes from sleep for scheduled trigger

## Notifications
- [ ] Window ending soon (30 min) notification works
- [ ] Window ending soon (15 min) notification works
- [ ] Scheduled trigger success notification works
- [ ] Scheduled trigger failed notification works
- [ ] Weekly summary notification works (Sunday)
- [ ] Notification toggles in settings work

## Background Polling
- [ ] CLI polled every 15 minutes
- [ ] Window status updates automatically
- [ ] Menu bar percentage updates

## Data
- [ ] Windows tracked in database
- [ ] Data persists after restart
- [ ] Multiple accounts tracked separately
```

### 9.2 Add Error Handling

Create `src-react/components/ErrorBoundary.tsx`:

```tsx
import { Component, ReactNode } from 'react';
import { Button } from '@/components/shadcn-ui/button';

interface Props {
  children: ReactNode;
}

interface State {
  hasError: boolean;
  error?: Error;
}

export class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false };

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="p-4 text-center">
          <h2 className="text-lg font-semibold mb-2">Something went wrong</h2>
          <p className="text-sm text-muted-foreground mb-4">
            {this.state.error?.message}
          </p>
          <Button onClick={() => window.location.reload()}>
            Reload
          </Button>
        </div>
      );
    }

    return this.props.children;
  }
}
```

### 9.3 Add Loading States

Update components to show loading spinners when `isLoading` is true.

### 9.4 Add Toast Notifications

Use shadcn toast for success/error feedback:

```tsx
import { useToast } from '@/components/shadcn-ui/use-toast';

const { toast } = useToast();

// On success
toast({ title: 'Settings saved' });

// On error
toast({ title: 'Error', description: error.message, variant: 'destructive' });
```

### 9.5 Performance Optimization

- Add React.memo to expensive components
- Use useMemo for computed values
- Lazy load Stats and Settings views

---

## Summary: File Structure

```
C5h/
├── .claude/
│   └── CLAUDE.md                        # Claude Code project context
├── .github/
│   └── workflows/
│       └── release.yml
├── .gitignore                           # Git ignore patterns
├── distribution/
│   ├── README.md                        # Release process documentation
│   ├── .env.example                     # Environment variables template
│   └── homebrew/
│       └── c5h.rb                       # Homebrew Cask formula
├── docs/
│   ├── README.md                        # Project overview
│   ├── CHANGELOG.md                     # Version history
│   ├── LICENSE                          # Open source license
│   └── design/
│       ├── README.md                    # Design assets documentation
│       ├── icon.svg                     # Source icon (exports to src-tauri/icons/)
│       └── mockups/                     # UI mockups and wireframes
├── src-react/
│   ├── README.md                        # Frontend architecture overview
│   ├── components/
│   │   ├── README.md                    # Components documentation
│   │   ├── shadcn-ui/                   # shadcn components
│   │   ├── AccountsSettings.tsx
│   │   ├── AccountsSettings.test.tsx    # Colocated test
│   │   ├── CalendarView.tsx
│   │   ├── CalendarView.test.tsx
│   │   ├── ErrorBoundary.tsx
│   │   ├── ErrorBoundary.test.tsx
│   │   ├── Layout.tsx
│   │   ├── Layout.test.tsx
│   │   ├── PopoverWindow.tsx
│   │   ├── PopoverWindow.test.tsx
│   │   ├── SchedulerSettings.tsx
│   │   ├── SchedulerSettings.test.tsx
│   │   ├── SettingsView.tsx
│   │   ├── SettingsView.test.tsx
│   │   ├── StatsView.tsx
│   │   ├── StatsView.test.tsx
│   │   ├── StatusCard.tsx
│   │   ├── StatusCard.test.tsx
│   │   ├── WeekNavigation.tsx
│   │   └── WeekNavigation.test.tsx
│   ├── hooks/
│   │   ├── README.md                    # Hooks documentation
│   │   ├── useAppInit.ts
│   │   ├── useAppInit.test.ts
│   │   ├── useCurrentWindow.ts
│   │   ├── useCurrentWindow.test.ts
│   │   ├── useWindowEndingAlert.ts
│   │   └── useWindowEndingAlert.test.ts
│   ├── lib/
│   │   ├── README.md                    # Utilities documentation
│   │   ├── api.ts
│   │   ├── api.test.ts
│   │   ├── utils.ts
│   │   └── utils.test.ts
│   ├── store/
│   │   ├── README.md                    # State management docs
│   │   ├── index.ts
│   │   └── index.test.ts
│   ├── App.tsx
│   ├── App.test.tsx
│   ├── main.tsx
│   ├── popover.tsx
│   └── index.css
├── src-tauri/
│   ├── README.md                        # Rust backend overview
│   ├── icons/
│   │   ├── 32x32.png
│   │   ├── 128x128.png
│   │   ├── 128x128@2x.png
│   │   ├── icon.icns
│   │   └── tray.png
│   ├── src/
│   │   ├── commands/
│   │   │   ├── README.md                # Commands documentation
│   │   │   ├── mod.rs
│   │   │   ├── notifications.rs
│   │   │   ├── notifications_test.rs    # Colocated Rust test
│   │   │   ├── polling.rs
│   │   │   ├── polling_test.rs
│   │   │   ├── scheduler.rs
│   │   │   ├── scheduler_test.rs
│   │   │   ├── settings.rs
│   │   │   ├── settings_test.rs
│   │   │   ├── windows.rs
│   │   │   └── windows_test.rs
│   │   ├── db.rs
│   │   ├── db_test.rs
│   │   ├── main.rs
│   │   ├── models.rs
│   │   └── models_test.rs
│   ├── Cargo.toml
│   ├── capabilities/
│   │   └── default.json
│   └── tauri.conf.json
├── config/
│   ├── tailwind.config.js               # Tailwind CSS configuration
│   ├── tsconfig.json                    # TypeScript configuration
│   └── bunfig.toml                      # Bun configuration (test runner)
└── package.json                         # Must stay in root for Bun/npm
```

### README.md Contents

Each colocated README.md should contain:
- **Purpose**: What this directory/module does
- **Key files**: Brief description of each file
- **Dependencies**: Internal and external dependencies
- **Usage examples**: How to use the components/functions

### Test File Convention

| Language | Source File | Test File |
| --- | --- | --- |
| TypeScript/React | `Component.tsx` | `Component.test.tsx` |
| TypeScript | `module.ts` | `module.test.ts` |
| Rust | `module.rs` | `module_test.rs` |

Tests are colocated with source files for easier navigation and maintenance.

---

## Quick Start Commands

```bash
# Install dependencies
bun install

# Development
bun tauri dev

# Run tests (frontend)
bun test

# Run tests with watch mode
bun test --watch

# Build for production
bun tauri build

# Create release tag
git tag v0.1.0
git push origin v0.1.0
```
