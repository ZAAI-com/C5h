# Commands API Documentation

Complete reference for all Tauri commands exposed to the frontend.

## Overview

Commands are the IPC bridge between the React frontend and Rust backend. Each command is a Rust function decorated with `#[tauri::command]` that can be invoked from JavaScript using `invoke()`.

**Frontend Usage:**
```typescript
import { invoke } from "@tauri-apps/api/core";

const accounts = await invoke<Account[]>("get_accounts");
```

---

## Account Commands

Located in `commands/accounts.rs`

### get_accounts

Retrieve all accounts.

**Rust Signature:**
```rust
#[tauri::command]
async fn get_accounts(db: State<'_, Database>) -> Result<Vec<Account>, String>
```

**Frontend Usage:**
```typescript
const accounts = await invoke<Account[]>("get_accounts");
```

**Returns:**
```typescript
interface Account {
  id: number;
  name: string;
  tool_type: string;
  cli_command: string;
  cli_args?: string;
  window_duration_hours: number;
  color: string;
  enabled: boolean;
  created_at: string;
}
```

**Errors:**
- Database query failure

---

### create_account

Create a new account.

**Rust Signature:**
```rust
#[tauri::command]
async fn create_account(
    account: NewAccount,
    db: State<'_, Database>
) -> Result<Account, String>
```

**Frontend Usage:**
```typescript
const newAccount = {
  name: "Claude Code",
  tool_type: "claude",
  cli_command: "claude",
  cli_args: "-p '1+1'",
  window_duration_hours: 5.0,
  color: "#6366f1",
  enabled: true,
};

const account = await invoke<Account>("create_account", { account: newAccount });
```

**Parameters:**
```typescript
interface NewAccount {
  name: string;
  tool_type: string;
  cli_command: string;
  cli_args?: string;
  window_duration_hours: number;
  color: string;
  enabled: boolean;
}
```

**Validation:**
- `name` must not be empty
- `tool_type` must be one of: "claude", "codex", "gemini"
- `window_duration_hours` must be > 0

**Errors:**
- Validation failure
- Database insert failure
- Duplicate account name

---

### update_account

Update an existing account.

**Rust Signature:**
```rust
#[tauri::command]
async fn update_account(
    account: Account,
    db: State<'_, Database>
) -> Result<(), String>
```

**Frontend Usage:**
```typescript
const updatedAccount = {
  ...existingAccount,
  name: "New Name",
  color: "#10a37f",
};

await invoke("update_account", { account: updatedAccount });
```

**Parameters:**
- `account`: Full `Account` object with `id`

**Errors:**
- Account not found
- Database update failure

---

### delete_account

Delete an account and all associated windows.

**Rust Signature:**
```rust
#[tauri::command]
async fn delete_account(
    id: i64,
    db: State<'_, Database>
) -> Result<(), String>
```

**Frontend Usage:**
```typescript
await invoke("delete_account", { id: 42 });
```

**Side Effects:**
- Cascades delete to all windows with `account_id = id`
- Uninstalls all schedules for this account

**Errors:**
- Account not found
- Database delete failure

---

## Window Commands

Located in `commands/windows.rs`

### get_windows

Retrieve windows within a date range.

**Rust Signature:**
```rust
#[tauri::command]
async fn get_windows(
    from: String,    // ISO 8601 format
    to: String,      // ISO 8601 format
    account_id: Option<i64>,
    db: State<'_, Database>
) -> Result<Vec<Window>, String>
```

**Frontend Usage:**
```typescript
const windows = await invoke<Window[]>("get_windows", {
  from: "2024-01-15T00:00:00Z",
  to: "2024-01-22T23:59:59Z",
  accountId: 42, // Optional: filter by account
});
```

**Returns:**
```typescript
interface Window {
  id: number;
  account_id: number;
  started_at: string;  // ISO 8601
  ended_at?: string;   // ISO 8601
  triggered_by: string;
  notes?: string;
}
```

**Filters:**
- `from`: Inclusive start date
- `to`: Inclusive end date
- `account_id`: Optional account filter

---

### get_current_window

Get the currently active window.

**Rust Signature:**
```rust
#[tauri::command]
async fn get_current_window(
    account_id: Option<i64>,
    db: State<'_, Database>
) -> Result<Option<Window>, String>
```

**Frontend Usage:**
```typescript
const currentWindow = await invoke<Window | null>("get_current_window", {
  accountId: 42, // Optional: filter by account
});
```

**Logic:**
- Returns window where `ended_at IS NULL`
- If multiple active windows, returns most recent
- If `account_id` provided, filters to that account

---

### create_window

Create a new usage window.

**Rust Signature:**
```rust
#[tauri::command]
async fn create_window(
    account_id: i64,
    triggered_by: String,
    db: State<'_, Database>
) -> Result<Window, String>
```

**Frontend Usage:**
```typescript
const window = await invoke<Window>("create_window", {
  accountId: 42,
  triggeredBy: "manual", // or "scheduled", "cli_detected"
});
```

**Triggered By:**
- `"manual"`: User clicked "Start New Window"
- `"scheduled"`: Launchd schedule fired
- `"cli_detected"`: Process monitor detected CLI

**Side Effects:**
- Sets `started_at` to current timestamp
- `ended_at` is NULL (active window)

---

### end_window

End an active window.

**Rust Signature:**
```rust
#[tauri::command]
async fn end_window(
    id: i64,
    usage_percent: Option<f32>,
    db: State<'_, Database>
) -> Result<(), String>
```

**Frontend Usage:**
```typescript
await invoke("end_window", {
  id: 42,
  usagePercent: 75.5, // Optional: actual usage %
});
```

**Parameters:**
- `id`: Window ID to end
- `usage_percent`: Optional actual usage percentage (from CLI output)

**Side Effects:**
- Sets `ended_at` to current timestamp
- Stores `usage_percent` in `notes` field (if provided)

---

## Settings Commands

Located in `commands/settings.rs`

### get_settings

Get all settings as key-value pairs.

**Rust Signature:**
```rust
#[tauri::command]
async fn get_settings(
    db: State<'_, Database>
) -> Result<HashMap<String, String>, String>
```

**Frontend Usage:**
```typescript
const settings = await invoke<Record<string, string>>("get_settings");
// { "theme": "dark", "notifications_enabled": "true" }
```

---

### save_settings

Save multiple settings at once.

**Rust Signature:**
```rust
#[tauri::command]
async fn save_settings(
    settings: HashMap<String, String>,
    db: State<'_, Database>
) -> Result<(), String>
```

**Frontend Usage:**
```typescript
await invoke("save_settings", {
  settings: {
    theme: "dark",
    notifications_enabled: "true",
  },
});
```

**Behavior:**
- Upserts each key-value pair
- Existing keys are updated
- New keys are inserted

**Common Settings:**
- `theme`: "system" | "light" | "dark"
- `notifications_enabled`: "true" | "false"
- `scheduler_enabled`: "true" | "false"
- `default_trigger_time`: "03:00"

---

## Scheduler Commands

Located in `commands/scheduler.rs`

### get_schedules

Get all scheduled triggers.

**Rust Signature:**
```rust
#[tauri::command]
async fn get_schedules(
    account_id: Option<i64>,
    db: State<'_, Database>
) -> Result<Vec<ScheduledTrigger>, String>
```

**Frontend Usage:**
```typescript
const schedules = await invoke<ScheduledTrigger[]>("get_schedules", {
  accountId: 42, // Optional filter
});
```

**Returns:**
```typescript
interface ScheduledTrigger {
  id: number;
  account_id: number;
  scheduled_at: string;  // ISO 8601
  status: "pending" | "installed" | "completed" | "failed";
  installed_at?: string;
  executed_at?: string;
  plist_path?: string;
  error?: string;
}
```

---

### create_schedule

Create a new scheduled trigger.

**Rust Signature:**
```rust
#[tauri::command]
async fn create_schedule(
    account_id: i64,
    scheduled_at: String,  // ISO 8601
    db: State<'_, Database>
) -> Result<ScheduledTrigger, String>
```

**Frontend Usage:**
```typescript
const schedule = await invoke<ScheduledTrigger>("create_schedule", {
  accountId: 42,
  scheduledAt: "2024-01-20T03:00:00Z",
});
```

**Initial Status:** `"pending"`

**Note:** Creating a schedule does not install it. Call `install_schedule` separately.

---

### delete_schedule

Delete a scheduled trigger.

**Rust Signature:**
```rust
#[tauri::command]
async fn delete_schedule(
    id: i64,
    db: State<'_, Database>
) -> Result<(), String>
```

**Frontend Usage:**
```typescript
await invoke("delete_schedule", { id: 42 });
```

**Side Effects:**
- If status is "installed", automatically calls `uninstall_schedule` first
- Deletes plist file if exists

---

### install_schedule

Install a schedule by creating and loading a launchd plist.

**Rust Signature:**
```rust
#[tauri::command]
async fn install_schedule(
    id: i64,
    cli_command: String,
    db: State<'_, Database>
) -> Result<String, String>  // Returns plist_path
```

**Frontend Usage:**
```typescript
const plistPath = await invoke<string>("install_schedule", {
  id: 42,
  cliCommand: "claude -p '1+1'",
});
```

**Process:**
1. Generate plist XML with `StartCalendarInterval`
2. Write to `~/Library/LaunchAgents/com.zaai.c5h.trigger.{id}.plist`
3. Execute `launchctl load {plist_path}`
4. Update schedule status to "installed"

**Plist Example:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.zaai.c5h.trigger.42</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>-c</string>
        <string>claude -p '1+1'</string>
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

**Errors:**
- Schedule not found
- File write failure
- `launchctl load` failure

---

### uninstall_schedule

Uninstall a schedule by unloading and removing the plist.

**Rust Signature:**
```rust
#[tauri::command]
async fn uninstall_schedule(
    id: i64,
    db: State<'_, Database>
) -> Result<(), String>
```

**Frontend Usage:**
```typescript
await invoke("uninstall_schedule", { id: 42 });
```

**Process:**
1. Execute `launchctl unload {plist_path}`
2. Delete plist file
3. Update schedule status to "pending"

---

## Notification Commands

Located in `commands/notifications.rs`

### notify_window_ending_soon

Trigger a system notification for window ending soon.

**Rust Signature:**
```rust
#[tauri::command]
async fn notify_window_ending_soon(
    app: AppHandle,
    account_name: String,
    minutes_remaining: i32,
) -> Result<(), String>
```

**Frontend Usage:**
```typescript
await invoke("notify_window_ending_soon", {
  accountName: "Claude Code",
  minutesRemaining: 30,
});
```

**Notification:**
- **Title:** "Window Ending Soon"
- **Body:** "Your {account_name} window expires in {minutes_remaining} minutes"

---

### notify_scheduled_trigger

Notify about scheduled trigger execution.

**Rust Signature:**
```rust
#[tauri::command]
async fn notify_scheduled_trigger(
    app: AppHandle,
    account_name: String,
    success: bool,
) -> Result<(), String>
```

**Frontend Usage:**
```typescript
// Success
await invoke("notify_scheduled_trigger", {
  accountName: "Claude Code",
  success: true,
});

// Failure
await invoke("notify_scheduled_trigger", {
  accountName: "Claude Code",
  success: false,
});
```

**Notifications:**
- **Success:**
  - Title: "Scheduled Window Started"
  - Body: "New {account_name} window started successfully"
- **Failure:**
  - Title: "Scheduled Window Failed"
  - Body: "Failed to start {account_name} window - check CLI"

---

### notify_weekly_summary

Send weekly usage summary notification.

**Rust Signature:**
```rust
#[tauri::command]
async fn notify_weekly_summary(
    app: AppHandle,
    total_windows: i32,
    avg_duration: f32,
) -> Result<(), String>
```

**Frontend Usage:**
```typescript
await invoke("notify_weekly_summary", {
  totalWindows: 8,
  avgDuration: 4.2,
});
```

**Notification:**
- **Title:** "Weekly Summary"
- **Body:** "This week: {total_windows} windows used, avg {avg_duration}h each"

---

### send_notification

Generic notification sender.

**Rust Signature:**
```rust
#[tauri::command]
async fn send_notification(
    app: AppHandle,
    title: String,
    body: String,
) -> Result<(), String>
```

**Frontend Usage:**
```typescript
await invoke("send_notification", {
  title: "Custom Title",
  body: "Custom message",
});
```

---

## Monitor Commands

Located in `monitor.rs`

### start_monitoring

Start real-time CLI process monitoring.

**Rust Signature:**
```rust
#[tauri::command]
async fn start_monitoring(
    monitor: State<'_, ProcessMonitor>,
    db: State<'_, Database>,
) -> Result<(), String>
```

**Frontend Usage:**
```typescript
await invoke("start_monitoring");
```

**Behavior:**
- Loads all enabled accounts
- Starts watching for CLI processes
- Runs in background until `stop_monitoring` called

---

### stop_monitoring

Stop CLI process monitoring.

**Rust Signature:**
```rust
#[tauri::command]
async fn stop_monitoring(
    monitor: State<'_, ProcessMonitor>,
) -> Result<(), String>
```

**Frontend Usage:**
```typescript
await invoke("stop_monitoring");
```

---

### get_monitoring_status

Get current monitoring status.

**Rust Signature:**
```rust
#[tauri::command]
async fn get_monitoring_status(
    monitor: State<'_, ProcessMonitor>,
) -> Result<MonitoringStatus, String>
```

**Frontend Usage:**
```typescript
const status = await invoke<MonitoringStatus>("get_monitoring_status");
```

**Returns:**
```typescript
interface MonitoringStatus {
  is_running: boolean;
  monitored_accounts: string[];
  last_check: string;  // ISO 8601
}
```

---

### scan_cli_processes

Manually scan for CLI processes (one-time).

**Rust Signature:**
```rust
#[tauri::command]
async fn scan_cli_processes(
    monitor: State<'_, ProcessMonitor>,
) -> Result<Vec<ProcessInfo>, String>
```

**Frontend Usage:**
```typescript
const processes = await invoke<ProcessInfo[]>("scan_cli_processes");
```

**Returns:**
```typescript
interface ProcessInfo {
  pid: number;
  name: string;
  command: string;
}
```

---

## Error Handling

All commands return `Result<T, String>` where:
- `Ok(T)`: Success with data
- `Err(String)`: Error with message

**Frontend Pattern:**
```typescript
try {
  const result = await invoke<Data>("command_name", { params });
  toast.success("Success!");
  return result;
} catch (err) {
  const message = err instanceof Error ? err.message : String(err);
  toast.error(`Failed: ${message}`);
  throw err;
}
```

---

## Type Definitions

All TypeScript types should match Rust structs:

```typescript
// lib/types.ts
export interface Account {
  id: number;
  name: string;
  tool_type: string;
  cli_command: string;
  cli_args?: string;
  window_duration_hours: number;
  color: string;
  enabled: boolean;
  created_at: string;
}

export type NewAccount = Omit<Account, "id" | "created_at">;
```

---

## Best Practices

1. **Type Safety**: Always specify return types on `invoke<T>()`
2. **Error Handling**: Wrap all invocations in try/catch
3. **User Feedback**: Show toast notifications for all actions
4. **Loading States**: Display loading indicators during async calls
5. **Validation**: Validate inputs before sending to backend
6. **Retry Logic**: Implement retry for transient failures
7. **Timeout**: Set reasonable timeouts for long-running commands
