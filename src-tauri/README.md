# Backend Architecture

The C5h backend is built with Rust and Tauri 2.0, providing a secure, performant foundation for the application.

## Directory Structure

```
src-tauri/
├── src/
│   ├── commands/        # Tauri command handlers
│   │   ├── mod.rs
│   │   ├── accounts.rs
│   │   ├── windows.rs
│   │   ├── settings.rs
│   │   ├── scheduler.rs
│   │   └── notifications.rs
│   ├── services/        # Business logic
│   │   ├── mod.rs
│   │   └── output_parser.rs
│   ├── db.rs           # Database migrations
│   ├── models.rs       # Data models
│   ├── monitor.rs      # Process monitoring
│   ├── lib.rs          # Library root
│   └── main.rs         # Binary entry point
├── capabilities/        # Tauri security capabilities
│   └── default.json
├── icons/              # App icons
├── build.rs            # Build script
├── Cargo.toml          # Dependencies
└── tauri.conf.json     # Tauri configuration
```

## Core Components

### 1. Tauri Commands

Commands are the IPC bridge between frontend and backend. Each command is a Rust function decorated with `#[tauri::command]`.

**Example:**
```rust
#[tauri::command]
async fn get_accounts(
    db: State<'_, Database>
) -> Result<Vec<Account>, String> {
    let accounts = sqlx::query_as::<_, Account>(
        "SELECT * FROM accounts ORDER BY created_at DESC"
    )
    .fetch_all(&db.pool)
    .await
    .map_err(|e| e.to_string())?;

    Ok(accounts)
}
```

**Command Modules:**
- `accounts.rs`: Account CRUD operations
- `windows.rs`: Window tracking and management
- `settings.rs`: App settings persistence
- `scheduler.rs`: Schedule management and launchd integration
- `notifications.rs`: System notification triggers

See [Commands Documentation](src/commands/README.md) for detailed API reference.

### 2. Database Layer

**Database:** SQLite with sqlx for type-safe queries

**Location:** `~/Library/Application Support/com.zaai.c5h/c5h.db`

**Schema:**
```sql
-- Accounts
CREATE TABLE accounts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    tool_type TEXT NOT NULL,
    cli_command TEXT NOT NULL,
    cli_args TEXT,
    window_duration_hours REAL NOT NULL DEFAULT 5.0,
    color TEXT NOT NULL DEFAULT '#6366f1',
    enabled BOOLEAN NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Windows
CREATE TABLE windows (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id INTEGER NOT NULL,
    started_at TEXT NOT NULL,
    ended_at TEXT,
    triggered_by TEXT NOT NULL,
    notes TEXT,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);

-- Settings
CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- Scheduled Jobs
CREATE TABLE scheduled_jobs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id INTEGER NOT NULL,
    scheduled_at TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    installed_at TEXT,
    executed_at TEXT,
    plist_path TEXT,
    error TEXT,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);
```

**Migrations:**
Managed via `tauri-plugin-sql` with migrations defined in `db.rs`:

```rust
pub fn get_migrations() -> Vec<Migration> {
    vec![
        Migration {
            version: 1,
            description: "create_accounts_table",
            sql: "CREATE TABLE accounts (...)",
            kind: MigrationKind::Up,
        },
        // ... more migrations
    ]
}
```

**Access Pattern:**
```rust
use sqlx::{SqlitePool, query_as};

let accounts = query_as::<_, Account>(
    "SELECT * FROM accounts WHERE enabled = 1"
)
.fetch_all(&pool)
.await?;
```

### 3. Models

Data models defined in `models.rs` with Serde serialization:

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Account {
    pub id: i64,
    pub name: String,
    pub tool_type: String,
    pub cli_command: String,
    pub cli_args: Option<String>,
    pub window_duration_hours: f64,
    pub color: String,
    pub enabled: bool,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Window {
    pub id: i64,
    pub account_id: i64,
    pub started_at: String,
    pub ended_at: Option<String>,
    pub triggered_by: String,
    pub notes: Option<String>,
}
```

**Type Mapping:**
- Rust → TypeScript automatic via Tauri
- SQLite → Rust via sqlx `FromRow` derive
- All types serializable to JSON

### 4. Process Monitoring

Real-time CLI detection system in `monitor.rs`:

```rust
use sysinfo::{System, ProcessExt};
use tokio::sync::RwLock;

pub struct ProcessMonitor {
    system: Arc<RwLock<System>>,
    monitored_processes: Arc<RwLock<HashMap<String, Process>>>,
}

impl ProcessMonitor {
    pub async fn start_monitoring(&self, accounts: Vec<Account>) {
        let mut system = self.system.write().await;
        system.refresh_processes();

        for process in system.processes().values() {
            if let Some(account) = self.match_process_to_account(process, &accounts) {
                self.handle_new_window(account, process).await;
            }
        }
    }
}
```

**Features:**
- Real-time process detection
- Tool-specific polling for live usage percentages
- Configurable monitoring cadence from persisted settings
- Async processing with Tokio

### 5. CLI Output Parser

Parses usage data from different CLI tools in `services/output_parser.rs`:

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UsageInfo {
    pub session_percent: Option<f32>,
    pub weekly_percent: Option<f32>,
    pub reset_time: Option<String>,
    pub weekly_reset_time: Option<String>,
}

pub fn parse_claude_output(output: &str) -> UsageInfo {
    let session_regex = Regex::new(r"(?s)Current session.*?(\d+)%\s+used").unwrap();
    // ... parse with regex
}

pub fn parse_codex_output(output: &str) -> UsageInfo {
    let session_regex = Regex::new(r"5h limit:.*?(\d+)%\s+left").unwrap();
    // Convert "left" to "used": 100 - left
}

pub fn parse_gemini_output(output: &str) -> UsageInfo {
    let usage_regex = Regex::new(r"gemini-[\w.-]+\s+[\d-]+\s+([\d.]+)%").unwrap();
    // Parse percentage remaining
}
```

**Supported CLIs:**
- **Claude Code**: `/usage` command output
- **Codex**: `/status` command output
- **Gemini**: Usage table format

### 6. Scheduler Integration

macOS launchd integration in `commands/scheduler.rs`:

```rust
pub async fn install_schedule(
    id: i64,
    cli_command: String
) -> Result<String, String> {
    let plist_path = get_plist_path(id);
    let plist_content = generate_plist(id, &schedule, &cli_command)?;

    // Write plist file
    std::fs::write(&plist_path, plist_content)
        .map_err(|e| format!("Failed to write plist: {}", e))?;

    // Load with launchctl
    let output = Command::new("launchctl")
        .args(&["load", &plist_path])
        .output()
        .map_err(|e| format!("Failed to load plist: {}", e))?;

    Ok(plist_path)
}

fn generate_plist(id: i64, schedule: &ScheduledJob, cli_command: &str) -> Result<String, String> {
    let time = chrono::DateTime::parse_from_rfc3339(&schedule.scheduled_at)?;

    Ok(format!(r#"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.zaai.c5h.trigger.{}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>-c</string>
        <string>{}</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>{}</integer>
        <key>Minute</key>
        <integer>{}</integer>
    </dict>
</dict>
</plist>
"#, id, cli_command, time.hour(), time.minute()))
}
```

**Plist Location:** `~/Library/LaunchAgents/com.zaai.c5h.trigger.{id}.plist`

**Commands:**
- `install_schedule`: Generate and load plist
- `uninstall_schedule`: Unload and delete plist
- Uses `launchctl` for lifecycle management

### 7. Notifications

System notifications via `tauri-plugin-notification`:

```rust
use tauri_plugin_notification::NotificationExt;

#[tauri::command]
pub async fn notify_window_ending_soon(
    app: AppHandle,
    account_name: String,
    minutes_remaining: i32,
) -> Result<(), String> {
    app.notification()
        .builder()
        .title("Window Ending Soon")
        .body(format!(
            "Your {} window expires in {} minutes",
            account_name, minutes_remaining
        ))
        .show()
        .map_err(|e| e.to_string())?;

    Ok(())
}
```

**Notification Types:**
- Window ending soon (30 min, 15 min)
- Scheduled trigger success/failure
- Weekly summary

## Security

### Capabilities

Tauri 2.0 uses a capability-based security model defined in `capabilities/default.json`:

```json
{
  "permissions": [
    "core:default",
    "shell:allow-execute",
    "sql:default",
    "notification:default",
    "fs:allow-read",
    "fs:allow-write"
  ]
}
```

**Principles:**
- Least privilege: Only grant necessary permissions
- Explicit allow-listing: No wildcards
- Frontend cannot access arbitrary system APIs

### Command Validation

All inputs validated before execution:

```rust
#[tauri::command]
async fn create_account(account: NewAccount) -> Result<Account, String> {
    // Validate inputs
    if account.name.is_empty() {
        return Err("Account name cannot be empty".to_string());
    }

    if account.window_duration_hours <= 0.0 {
        return Err("Window duration must be positive".to_string());
    }

    // ... proceed with creation
}
```

## Performance

### Async Runtime

Uses Tokio for async operations:

```rust
#[tokio::main]
async fn main() {
    tauri::Builder::default()
        // ... configuration
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

### Connection Pooling

SQLite connection pool managed by sqlx:

```rust
let pool = SqlitePool::connect(&db_url).await?;
// Pool automatically manages connections
```

### Process Monitoring

Efficient process watching with debouncing:

```rust
// Check processes every 5 seconds
let mut interval = tokio::time::interval(Duration::from_secs(5));

loop {
    interval.tick().await;
    self.check_processes().await;
}
```

## Error Handling

### Error Types

```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum AppError {
    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Validation error: {0}")]
    Validation(String),
}
```

### Command Error Handling

```rust
#[tauri::command]
async fn fallible_command() -> Result<Data, String> {
    let data = risky_operation()
        .map_err(|e| format!("Operation failed: {}", e))?;

    Ok(data)
}
```

## Testing

### Unit Tests

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_claude_output() {
        let output = r#"
Current session
█████████████████████████████████████▌             75% used
Resets 1:59am (Europe/Berlin)
"#;

        let info = parse_claude_output(output);
        assert_eq!(info.session_percent, Some(75.0));
        assert_eq!(info.reset_time, Some("1:59am".to_string()));
    }
}
```

### Integration Tests

```rust
#[tokio::test]
async fn test_create_account() {
    let db = setup_test_db().await;

    let account = NewAccount {
        name: "Test".to_string(),
        tool_type: "claude".to_string(),
        // ...
    };

    let result = create_account(db, account).await;
    assert!(result.is_ok());
}
```

## Build Configuration

### Cargo.toml

```toml
[package]
name = "c5h"
version = "0.2.0"
edition = "2021"

[dependencies]
tauri = { version = "2", features = ["tray-icon"] }
tauri-plugin-sql = { version = "2", features = ["sqlite"] }
tauri-plugin-shell = "2"
tauri-plugin-notification = "2"
serde = { version = "1", features = ["derive"] }
sqlx = { version = "0.8", features = ["runtime-tokio", "sqlite"] }
tokio = { version = "1", features = ["full"] }
sysinfo = "0.32"
regex = "1"
chrono = "0.4"
```

### Build Script

`build.rs` runs before compilation:

```rust
fn main() {
    tauri_build::build()
}
```

## Deployment

### Release Build

```bash
cargo build --release
```

### Code Signing

Configured in `tauri.conf.json`:

```json
{
  "bundle": {
    "identifier": "com.zaai.c5h",
    "macOS": {
      "signing": {
        "identity": "Developer ID Application: ZAAI",
        "entitlements": null
      }
    }
  }
}
```

### Notarization

Handled by CI/CD pipeline with Apple credentials.

## Best Practices

1. **Error Handling**: Always use `Result<T, String>` for commands
2. **Async**: Use `async/await` for I/O operations
3. **State Management**: Use Tauri `State` for shared resources
4. **Validation**: Validate all inputs before processing
5. **Logging**: Use `tracing` crate for structured logging
6. **Testing**: Write tests for all business logic
7. **Security**: Minimize permissions, validate all IPC inputs

## Future Enhancements

- [ ] Structured logging with `tracing`
- [ ] Metrics collection for monitoring
- [ ] Plugin system for extensibility
- [ ] gRPC for cross-platform support
- [ ] Encrypted database for sensitive data
