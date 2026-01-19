# C5h Product Specifications

## Overview

**Product Name:** C5h
**Bundle Identifier:** `com.zaai.c5h`
**Platform:** macOS (Apple Silicon + Intel)
**Purpose:** Visualize and optimize AI coding tool usage windows (Claude Code, Codex, Gemini)

---

## Problem Statement

AI coding tools like Claude Code have rolling usage limits (5-hour windows) that reset after a period of inactivity. Users often:
1. Don't know how much time remains in their current window
2. Consume the limit during work hours, leaving none for later
3. Can't see historical usage patterns across multiple tools/accounts

---

## User Goals

1. **Visualize** — See current window status and history at a glance
2. **Optimize** — Schedule window starts during sleep to maximize productive hours

---

## Supported AI Tools

| Company | Tool | Model(s) | Window Duration | Limit | CLI |
| --- | --- | --- | --- | --- | --- |
| Anthropic | Claude Code | Sonnet, Opus | 5 hours | ~11 windows/week | `claude` |
| OpenAI | Codex | GPT-5.2 Codex | 5 hours | ~99% weekly | `codex` |
| Google | Gemini CLI | 2.5 Flash, 2.5 Pro, 3 Flash, 3 Pro | 24 hours | Daily quota per model | `gemini` |

---

## Features

### Feature 1: Menu Bar Widget

**Priority:** P0 (Must have)

**Description:** Persistent menu bar icon showing usage percentage for current window.

**UI Requirements:**
- Display format: `75%` in menu bar (percentage used)
- Click to open popover with details
- Update on each poll (every 15 minutes)

**Popover Content:**
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

**Icon States:**

| State | Icon | Text |
| --- | --- | --- |
| No active window | Gray circle | "—" |
| Window active | Colored circle (account color) | "75%" |
| Window ending soon (<30 min) | Pulsing/orange | "⚠️ 92%" |
| Error/CLI unavailable | Red circle | "!" |
| Multiple windows (diff accounts) | Split circle | "C:45% X:80%" |

---

### Feature 2: Calendar Week View

**Priority:** P0 (Must have)

**Description:** Main app window showing week calendar with usage windows as events.

**UI Requirements:**
- Week view with hourly time slots (00:00 - 24:00)
- Each window shown as a colored block (color per account)
- Navigate between weeks
- Current time indicator line
- Click on time slot to create one-time schedule

**Window Block Display:**
```
┌─────────────────────────┐
│ Claude Code             │
│ 10:00 AM - 3:00 PM      │
│ Usage: 87%              │
└─────────────────────────┘
```

**Color Coding (per account):**
- Blue (#4285f4): Gemini (Google)
- Green (#10a37f): Codex (OpenAI)
- Indigo (#6366f1): Claude Code
- Custom colors for additional accounts

---

### Feature 3: Multi-Account Support

**Priority:** P0 (Must have)

**Description:** Track multiple AI tools and accounts independently.

**Capabilities:**
- Add multiple accounts (Claude Code, Codex, Gemini, custom)
- Each account has its own color in calendar
- Independent window tracking per account
- Multiple schedules per account (non-overlapping)
- Custom CLI command per account (e.g., `claude --profile work`)

---

### Feature 4: Window Detection

**Priority:** P0 (Must have)

**Description:** Automatically detect active windows by polling CLI tools.

**Detection Method:** Poll CLI every 15 minutes (configurable)

| Tool | Detection Command | Output Parsed |
| --- | --- | --- |
| Claude Code | `/usage` in CLI | Session %, reset time, weekly % |
| Codex | `/status` in CLI | 5h %, weekly %, reset times |
| Gemini | Run `gemini` | Usage table on startup |

**Data Model:**
```sql
CREATE TABLE windows (
  id INTEGER PRIMARY KEY,
  account_id INTEGER NOT NULL,
  started_at TEXT NOT NULL,      -- ISO 8601, UTC
  ended_at TEXT,                 -- NULL if active
  triggered_by TEXT,             -- 'manual' | 'scheduled' | 'detected'
  usage_percent INTEGER,
  FOREIGN KEY (account_id) REFERENCES accounts(id)
);

CREATE TABLE accounts (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  tool_type TEXT NOT NULL,       -- 'claude_code' | 'codex' | 'gemini' | 'other'
  cli_command TEXT NOT NULL,
  color TEXT NOT NULL,
  created_at TEXT NOT NULL
);
```

---

### Feature 5: Scheduler

**Priority:** P1 (Should have)

**Description:** Schedule a simple request to start a new window at a specific time.

**Schedule Type:** One-time only (not recurring)

**UI Requirements:**
- Click on calendar time slot to create schedule
- Show scheduled triggers as orange blocks
- Cancel/edit pending schedules

**Technical Implementation:**
- Generate macOS launchd plist file
- Install to `~/Library/LaunchAgents/`
- Plist triggers CLI: `claude -p "1+1"`
- Wakes Mac from sleep (StartCalendarInterval)

**Plist Template:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.zaai.c5h.trigger.{id}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/claude</string>
    <string>-p</string>
    <string>1+1</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>3</integer>
    <key>Minute</key>
    <integer>0</integer>
  </dict>
</dict>
</plist>
```

---

### Feature 6: Notifications

**Priority:** P1 (Should have)

**Description:** System notifications for important events.

| Notification | When | Content |
| --- | --- | --- |
| Window ending soon | 30 min and 15 min before | "Your Claude Code window expires in 30 minutes" |
| Scheduled trigger success | After trigger runs | "New Claude Code window started successfully" |
| Scheduled trigger failed | If trigger fails | "Failed to start Claude Code window - check CLI" |
| Weekly summary | Sunday evening | "This week: 8 windows used, avg 4.2h each" |

---

### Feature 7: Statistics Dashboard

**Priority:** P2 (Nice to have)

**Description:** Charts showing usage patterns over time.

**Charts:**
- Windows per week (bar chart)
- Average window duration (line chart)
- Usage by day of week (heatmap)
- Time of day distribution (histogram)

---

### Feature 8: Settings

**Priority:** P1 (Should have)

**Options:**
- Launch at login (default: on)
- Show in menu bar (default: on)
- Theme: System / Light / Dark
- Poll interval: 15 minutes (configurable)
- Notification preferences (ending soon, trigger status, weekly summary)
- Account management (add/edit/remove accounts)

**Not included:**
- Data export (JSON/CSV)
- Recurring schedules

---

## Technical Specifications

### Data Storage

**Database:** SQLite via `tauri-plugin-sql`
**Location:** `~/Library/Application Support/com.zaai.c5h/c5h.db`

**Schema:**

```sql
-- Accounts table
CREATE TABLE accounts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  tool_type TEXT NOT NULL,
  cli_command TEXT NOT NULL,
  color TEXT NOT NULL DEFAULT '#6366f1',
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Windows table
CREATE TABLE windows (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  account_id INTEGER NOT NULL,
  started_at TEXT NOT NULL,
  ended_at TEXT,
  triggered_by TEXT NOT NULL DEFAULT 'detected',
  usage_percent INTEGER,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (account_id) REFERENCES accounts(id)
);

-- Settings table
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- Scheduled triggers table
CREATE TABLE scheduled_triggers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  account_id INTEGER NOT NULL,
  scheduled_at TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',  -- 'pending' | 'completed' | 'failed' | 'cancelled'
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (account_id) REFERENCES accounts(id)
);
```

---

### IPC Commands (Tauri)

```rust
// Window management
#[tauri::command]
fn get_windows(account_id: Option<i64>, from: String, to: String) -> Vec<Window>;

#[tauri::command]
fn get_current_window(account_id: i64) -> Option<Window>;

#[tauri::command]
fn trigger_window(account_id: i64) -> Result<Window, String>;

// Account management
#[tauri::command]
fn get_accounts() -> Vec<Account>;

#[tauri::command]
fn create_account(account: NewAccount) -> Result<Account, String>;

#[tauri::command]
fn update_account(account: Account) -> Result<(), String>;

#[tauri::command]
fn delete_account(id: i64) -> Result<(), String>;

// Settings
#[tauri::command]
fn get_settings() -> Settings;

#[tauri::command]
fn save_settings(settings: Settings) -> Result<(), String>;

// Scheduler
#[tauri::command]
fn create_schedule(account_id: i64, scheduled_at: String) -> Result<Schedule, String>;

#[tauri::command]
fn cancel_schedule(id: i64) -> Result<(), String>;

#[tauri::command]
fn get_pending_schedules() -> Vec<Schedule>;

// Polling
#[tauri::command]
fn poll_account(account_id: i64) -> Result<PollResult, String>;
```

---

### File Locations

```
~/Library/Application Support/com.zaai.c5h/
├── c5h.db                    # SQLite database

~/Library/Logs/com.zaai.c5h/
├── app.log                   # General app events
├── cli.log                   # Raw CLI detection output
└── scheduler.log             # Trigger execution logs

~/Library/LaunchAgents/
└── com.zaai.c5h.trigger.*.plist   # One plist per scheduled trigger
```

---

### Window Detection Logic

```
1. On app launch:
   - Load all accounts from DB
   - For each account, check CLI availability
   - Query last known window state

2. Periodic polling (every 15 minutes):
   - For each account:
     - Run CLI detection command
     - Parse output for usage %, reset time
     - Update window state in DB
     - Update menu bar display

3. On scheduled trigger:
   - Run `claude -p "1+1"` (or account-specific command)
   - Record new window start
   - Send notification (success or failure)
   - Remove completed schedule
```

---

## UI/UX Guidelines

### Design System
- Use shadcn/ui components
- Tailwind CSS for styling
- ilamy Calendar for week view
- Follow macOS Human Interface Guidelines for menu bar behavior

### Account Colors
| Account | Default Color | Hex |
| --- | --- | --- |
| Claude Code | Indigo | `#6366f1` |
| Codex | OpenAI Green | `#10a37f` |
| Gemini | Google Blue | `#4285f4` |
| Custom | User choice | - |

### Typography
- Font: System font (SF Pro on macOS)
- Menu bar: 12px
- Headings: 16px semibold
- Body: 14px regular
- Small: 12px

---

## Performance Requirements

- App memory usage: < 50 MB idle
- Menu bar update latency: < 100ms
- App launch time: < 2 seconds
- Database queries: < 50ms
- CLI polling: ~1s CPU spike per poll

---

## Security & Privacy

- No data sent to external servers
- No analytics or telemetry
- All data stored locally in SQLite
- CLI tools handle their own authentication
- No credentials stored by C5h
- Scheduler runs with user permissions only
- Code signing + notarization required for distribution
- Open source for transparency
