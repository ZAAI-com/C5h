# C5h - AI Tool Usage Tracker

## Comprehensive Documentation

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture](#architecture)
3. [Features](#features)
4. [Getting Started](#getting-started)
5. [Database Schema](#database-schema)
6. [API Commands Reference](#api-commands-reference)
7. [Frontend Components](#frontend-components)
8. [Backend Services](#backend-services)
9. [Testing](#testing)
10. [Build & Deployment](#build--deployment)
11. [Troubleshooting](#troubleshooting)

---

## Project Overview

### Purpose

C5h is a **macOS menu bar application** designed to visualize and optimize AI coding tool usage windows. It tracks rolling usage limits for tools like Claude Code, Codex, and Gemini CLI, helping developers maximize their productive hours.

### Key Problems Solved

| Problem | Solution |
|---------|----------|
| **No visibility** into usage window status | Real-time menu bar percentage display |
| **Wasted usage** during off-hours | Smart scheduling via launchd |
| **Multiple tools** hard to track | Multi-account support with color coding |
| **Unknown patterns** | Statistics dashboard with heatmaps |

### Supported AI Tools

| Tool | Company | Default Window | CLI Command |
|------|---------|----------------|-------------|
| Claude Code | Anthropic | 5 hours | `claude` |
| Codex | OpenAI | 5 hours | `codex` |
| Gemini CLI | Google | 24 hours | `gemini` |

### Tech Stack

| Layer | Technology |
|-------|------------|
| **Frontend** | React 19 + TypeScript + Vite 7 |
| **UI Components** | shadcn/ui + Tailwind CSS 4 |
| **State Management** | Zustand 5 |
| **Charts** | Recharts 3 |
| **Backend** | Rust + Tauri 2.0 |
| **Database** | SQLite (via sqlx) |
| **Package Manager** | Bun |

---

## Architecture

### Project Structure

```text
c5h/
├── src-react/                 # React frontend
│   ├── components/            # UI components
│   │   ├── shadcn-ui/         # Base UI (button, card, dialog, etc.)
│   │   ├── CalendarView.tsx   # Week calendar with usage windows
│   │   ├── StatsView.tsx      # Statistics dashboard
│   │   ├── SettingsView.tsx   # App settings & account management
│   │   ├── PopoverWindow.tsx  # Menu bar popover
│   │   ├── StatusCard.tsx     # Account status with progress
│   │   ├── MonitoringCard.tsx # Process monitoring UI
│   │   └── Layout.tsx         # Main navigation layout
│   ├── hooks/                 # Custom React hooks
│   │   ├── useAppInit.ts      # App initialization
│   │   ├── useCurrentWindow.ts# Window state & percentage
│   │   └── useMonitoring.ts   # Real-time monitoring
│   ├── store/                 # Zustand state management
│   │   └── index.ts           # Global store with async actions
│   ├── lib/                   # API layer & utilities
│   │   ├── api.ts             # Tauri IPC wrapper functions
│   │   ├── types.ts           # TypeScript type definitions
│   │   └── utils.ts           # Utility functions
│   ├── App.tsx                # Main application component
│   ├── main.tsx               # Main window entry point
│   └── popover.tsx            # Popover window entry point
├── src-tauri/                 # Rust backend
│   └── src/
│       ├── commands/          # Tauri command handlers
│       │   ├── accounts.rs    # Account CRUD
│       │   ├── windows.rs     # Usage window management
│       │   ├── settings.rs    # Settings management
│       │   ├── scheduler.rs   # Schedule + launchd integration
│       │   └── notifications.rs # System notifications
│       ├── services/          # Business logic
│       │   └── output_parser.rs # CLI output parsing
│       ├── db.rs              # Database connection + migrations
│       ├── models.rs          # Data models and types
│       ├── monitor.rs         # Process monitoring service
│       ├── validation.rs      # Input validation functions
│       └── lib.rs             # Application entry point
├── .conductor/                # Conductor scripts
│   ├── main                   # Setup script
│   └── run                    # Development server
└── Docs/                      # Specifications and planning
```

### Data Flow

```text
┌─────────────────┐     IPC      ┌─────────────────┐
│  React Frontend │ ◄──────────► │   Rust Backend  │
│                 │   (invoke)   │                 │
│  - Components   │              │  - Commands     │
│  - Hooks        │              │  - Services     │
│  - Zustand      │              │  - Monitor      │
└─────────────────┘              └────────┬────────┘
                                          │
                                          ▼
                                 ┌─────────────────┐
                                 │     SQLite      │
                                 │    Database     │
                                 └─────────────────┘
```

---

## Features

### Feature 1: Menu Bar Widget (P0)

**Purpose**: Persistent status indicator in macOS menu bar.

**Functionality**:
- Shows current usage percentage as icon text
- Left-click opens quick-status popover
- Right-click shows context menu (Open, Quit)

**Icon States**:
| State | Display | Meaning |
|-------|---------|---------|
| No window | Gray "—" | No active usage window |
| Active | Colored % | Window active with percentage |
| Ending soon | Pulsing orange | < 30 minutes remaining |
| Error | Red "!" | CLI unavailable or error |

### Feature 2: Calendar Week View (P0)

**Purpose**: Visual timeline of usage windows.

**Functionality**:
- Week view with hourly time slots (00:00 - 23:00)
- Colored blocks for each usage window
- Navigate between weeks (prev/next)
- Click time slot to create scheduled trigger
- Current time indicator line

### Feature 3: Multi-Account Support (P0)

**Purpose**: Track multiple AI tools independently.

**Account Configuration**:
- **Name**: Display name (e.g., "Claude Code")
- **Tool Type**: claude, codex, gemini, other
- **CLI Command**: Full path to CLI executable
- **CLI Args**: Arguments for triggering (e.g., `-p "1+1"`)
  Quotes in shell examples are for readability. When saving args in the app, store the literal values the CLI should receive, e.g. `-p 1+1`.
- **Window Duration**: Hours per window (default: 5)
- **Color**: Hex color for visual distinction
- **Enabled**: Toggle account on/off

### Feature 4: Real-Time Process Monitoring (P0)

**Purpose**: Automatically detect CLI tool usage.

**Implementation**:
- Background task scans processes every 5 seconds
- Uses `sysinfo` crate for cross-platform detection
- Matches process names against configured CLIs
- Emits events: `process-started`, `process-stopped`
- Auto-creates windows when CLI detected

### Feature 5: Smart Scheduler (P1)

**Purpose**: Schedule automatic window triggers.

**Implementation**:
- Creates plist files in `~/Library/LaunchAgents/`
- One-time schedules (not recurring)
- Triggers CLI: `{cli_command} -p 1+1`
- Can wake Mac from sleep
- Status tracking: pending → completed/failed/cancelled

### Feature 6: Notifications (P1)

**Types**:
| Notification | When |
|--------------|------|
| Window ending soon | 30 min, 15 min before end |
| Trigger success | Scheduled trigger executed |
| Trigger failure | Scheduled trigger failed |
| Weekly summary | Configurable weekly report |

### Feature 7: Statistics Dashboard (P2)

**Charts**:
- **Day of Week Heatmap**: Usage distribution across weekdays
- **Time Distribution**: When you use AI tools
- **Account Breakdowns**: Per-tool statistics

**Metrics**:
- Total windows this week
- Total hours used
- Average window duration
- Windows per account

### Feature 8: Settings (P1)

**Configurable Options**:
| Setting | Description | Default |
|---------|-------------|---------|
| Launch at login | Start app on macOS login | true |
| Show in menu bar | Display tray icon | true |
| Theme | system / light / dark | system |
| Poll interval | Minutes between checks | 15 |
| Notifications | Enable system notifications | true |

---

## Getting Started

### Prerequisites

| Requirement | Version | Install |
|-------------|---------|---------|
| Rust | 1.70+ | https://rustup.rs |
| Bun | Latest | https://bun.sh |
| Xcode CLT | Latest | `xcode-select --install` |

### Quick Start with Conductor

```bash
# 1. Setup (checks prerequisites, installs dependencies)
.conductor/main

# 2. Start development server
.conductor/run
```

### Manual Setup

```bash
# Install frontend dependencies
bun install

# Run in development mode
bun tauri dev

# Build for production
bun tauri build
```

### First Launch

1. App appears in menu bar with gray "—" icon
2. Click icon to open popover
3. Click "Open" to launch main window
4. Go to **Settings** tab to configure accounts

### Adding an Account

1. Open **Settings** → **Accounts**
2. Click **"Add Account"**
3. Fill in configuration:
   - Name: `Claude Code`
   - Tool Type: `claude`
   - CLI Command: `/usr/local/bin/claude` (find with `which claude`)
   - CLI Args: `-p "1+1"`
     Save the literal argument values the CLI should receive. In this case, store `-p 1+1` unless the quotes are part of the argument itself.
   - Duration: `5` hours
   - Color: Pick a color
4. Click **Save**

---

## Database Schema

**Location**: `~/Library/Application Support/com.zaai.c5h/c5h.db`

### Table: accounts

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER | Primary key |
| name | TEXT | Display name |
| tool_type | TEXT | claude, codex, gemini, other |
| cli_command | TEXT | Full path to CLI |
| cli_args | TEXT | CLI arguments |
| window_duration_hours | INTEGER | Window duration |
| color | TEXT | Hex color (#RRGGBB) |
| enabled | INTEGER | 1=enabled, 0=disabled |
| created_at | TEXT | ISO 8601 timestamp |

### Table: windows

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER | Primary key |
| account_id | INTEGER | FK → accounts |
| started_at | TEXT | Window start (ISO 8601) |
| ended_at | TEXT | Window end (NULL if active) |
| triggered_by | TEXT | detected, manual, scheduled |
| usage_percent | INTEGER | Usage 0-100 |
| notes | TEXT | Optional notes |
| created_at | TEXT | ISO 8601 timestamp |

### Table: settings

| Column | Type | Description |
|--------|------|-------------|
| key | TEXT | Primary key |
| value | TEXT | Setting value |

**Default Settings**:
- `launch_at_login`: true
- `show_in_menu_bar`: true
- `theme`: system
- `notifications_enabled`: true
- `poll_interval_minutes`: 15

### Table: scheduled_triggers

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER | Primary key |
| account_id | INTEGER | FK → accounts |
| scheduled_at | TEXT | Scheduled time (ISO 8601) |
| status | TEXT | pending, completed, failed, cancelled |
| plist_path | TEXT | Path to launchd plist |
| created_at | TEXT | ISO 8601 timestamp |

---

## API Commands Reference

### Account Commands

```typescript
// Get all accounts
const accounts = await invoke<Account[]>('get_accounts');

// Create account
const account = await invoke<Account>('create_account', {
  account: {
    name: "Claude Code",
    tool_type: "claude",
    cli_command: "/usr/local/bin/claude",
    cli_args: "-p 1+1",
    window_duration_hours: 5,
    color: "#6366f1",
    enabled: true
  }
});

// Update account
await invoke('update_account', { account: { id: 1, ...updates } });

// Delete account
await invoke('delete_account', { id: 1 });
```

### Window Commands

```typescript
// Get windows in date range
const windows = await invoke<Window[]>('get_windows', {
  from: "2024-01-01T00:00:00Z",
  to: "2024-01-07T23:59:59Z",
  accountId: 1 // optional
});

// Get current active window
const window = await invoke<Window | null>('get_current_window', {
  accountId: 1 // optional
});

// Create new window
const window = await invoke<Window>('create_window', {
  accountId: 1,
  triggeredBy: "manual" // or "detected", "scheduled"
});

// End window
await invoke('end_window', { id: 1, usagePercent: 85 });
```

### Settings Commands

```typescript
// Get all settings
const settings = await invoke<Settings>('get_settings');

// Save settings
await invoke('save_settings', {
  settings: {
    launch_at_login: true,
    show_in_menu_bar: true,
    theme: "dark",
    notifications_enabled: true,
    poll_interval_minutes: 15
  }
});
```

### Scheduler Commands

```typescript
// Get pending schedules
const schedules = await invoke<Schedule[]>('get_schedules', {
  accountId: 1 // optional
});

// Create schedule
const schedule = await invoke<Schedule>('create_schedule', {
  accountId: 1,
  scheduledAt: "2024-01-15T03:00:00Z"
});

// Install to launchd
await invoke('install_schedule', {
  id: 1,
  cliCommand: "/usr/local/bin/claude"
});

// Uninstall from launchd
await invoke('uninstall_schedule', { id: 1 });

// Delete schedule
await invoke('delete_schedule', { id: 1 });
```

### Monitor Commands

```typescript
// Start monitoring
await invoke('start_monitoring');

// Stop monitoring
await invoke('stop_monitoring');

// Get status
const status = await invoke<MonitorStatus>('get_monitoring_status');

// Manual scan
const processes = await invoke<DetectedProcess[]>('scan_cli_processes');
```

### Notification Commands

```typescript
// Window ending soon
await invoke('notify_window_ending_soon', {
  accountName: "Claude Code",
  minutesRemaining: 30
});

// Trigger status
await invoke('notify_scheduled_trigger', {
  accountName: "Claude Code",
  success: true
});

// Weekly summary
await invoke('notify_weekly_summary', {
  windowCount: 8,
  totalHours: 4.2
});

// Generic notification
await invoke('send_notification', {
  title: "Title",
  body: "Message body"
});
```

---

## Frontend Components

### Main Components

| Component | File | Purpose |
|-----------|------|---------|
| App | `App.tsx` | Main app with error handling |
| Layout | `Layout.tsx` | Tab navigation (Calendar/Stats/Settings) |
| CalendarView | `CalendarView.tsx` | Week calendar with windows |
| StatsView | `StatsView.tsx` | Statistics & charts |
| SettingsView | `SettingsView.tsx` | Settings & account management |
| PopoverWindow | `PopoverWindow.tsx` | Menu bar quick-status |
| StatusCard | `StatusCard.tsx` | Account status with progress |
| MonitoringCard | `MonitoringCard.tsx` | Process monitoring status |
| SchedulerSettings | `SchedulerSettings.tsx` | Schedule management |

### shadcn/ui Components

Located in `src-react/components/shadcn-ui/`:

- Button, Card, Dialog, Input, Label
- Popover, Progress, Select, Separator
- Switch, Tabs, DropdownMenu

### Custom Hooks

| Hook | Purpose |
|------|---------|
| `useAppInit` | App initialization & startup |
| `useCurrentWindow` | Window state with percentage |
| `useMonitoring` | Real-time monitoring updates |
| `useWindowEndingAlert` | Window ending notifications |

---

## Backend Services

### Process Monitor (`monitor.rs`)

Real-time CLI detection using `sysinfo` crate.

**Features**:
- Scans processes every 5 seconds
- Matches against configured CLI patterns
- Emits Tauri events on state changes
- Configurable patterns from account data

### Output Parser (`services/output_parser.rs`)

Parses CLI output to extract usage data.

**Supported Formats**:
- Claude Code `/usage` output
- Codex `/status` output
- Gemini usage tables

### Validation (`validation.rs`)

Input validation for security.

**Validations**:
- CLI command: absolute path, no shell metacharacters
- Window duration: 1-168 hours
- Color: hex format #RRGGBB
- Account name: non-empty, max 100 chars
- Scheduled time: valid RFC3339, in future
- Poll interval: 1-60 minutes

---

## Testing

### Frontend Tests

```bash
# Run all tests
bun test

# Watch mode
bun test --watch

# Coverage report
bun test:coverage
```

### Backend Tests

```bash
# Run all Rust tests
cargo test --manifest-path src-tauri/Cargo.toml

# Run specific test
cargo test test_parse_claude_output
```

---

## Build & Deployment

### Development

```bash
bun tauri dev
```

Opens app with hot-reload for frontend changes.

### Production Build

```bash
bun tauri build
```

**Output**:
- `src-tauri/target/release/bundle/macos/C5h.app`
- `src-tauri/target/release/bundle/dmg/C5h_*.dmg`

### System Requirements

- macOS 12.0+ (Monterey or later)
- Apple Silicon and Intel supported

### File Locations

| Item | Location |
|------|----------|
| Database | `~/Library/Application Support/com.zaai.c5h/c5h.db` |
| Scheduled triggers | `~/Library/LaunchAgents/com.zaai.c5h.trigger.*.plist` |
| App bundle | `/Applications/C5h.app` |

---

## Troubleshooting

### Common Issues

**"Database connection not initialized"**
- Restart the application
- Check permissions on `~/Library/Application Support/com.zaai.c5h/`

**"CLI command must be an absolute path"**
- Use full path: `/usr/local/bin/claude`
- Find path with: `which claude`

**Scheduler not triggering**
```bash
# Check plist files
ls ~/Library/LaunchAgents/com.zaai.c5h.*

# Verify loaded
launchctl list | grep c5h

# Check logs
cat /tmp/c5h-trigger-*.log
```

**Process monitoring not detecting CLI**
- Ensure CLI command matches running process name
- Check monitoring status in UI
- Verify CLI running: `ps aux | grep claude`

---

## Feature Verification Checklist

| Feature | How to Verify | Status |
|---------|---------------|--------|
| Menu Bar Icon | Look for tray icon | [ ] |
| Main Window | Click tray → Open | [ ] |
| Calendar View | Main tab shows week grid | [ ] |
| Stats View | Click Stats tab | [ ] |
| Settings View | Click Settings tab | [ ] |
| Add Account | Settings → Add Account | [ ] |
| Process Monitoring | Run CLI → see detection | [ ] |
| Create Window | Manual: Click Start Window | [ ] |
| Popover | Click tray icon | [ ] |
| Scheduling | Click calendar slot | [ ] |
| Notifications | Enable → trigger alert | [ ] |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 0.2.0 | Current | Multi-account, scheduling, stats |
| 0.1.0 | Initial | Basic window tracking |

---

*Generated by C5h Documentation System*
