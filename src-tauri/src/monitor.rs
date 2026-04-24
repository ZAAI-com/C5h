use crate::db::{get_pool, DbPool};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use sysinfo::{ProcessRefreshKind, ProcessesToUpdate, System};
use tauri::{AppHandle, Emitter, State};
use tokio::sync::Mutex;
use tokio::time::{interval, Duration};

/// Process detection result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DetectedProcess {
    pub pid: u32,
    pub name: String,
    pub command: String,
    pub account_id: Option<i64>,
}

/// Monitoring state
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MonitoringStatus {
    pub is_running: bool,
    pub detected_processes: Vec<DetectedProcess>,
    pub last_check: Option<String>,
}

/// CLI tools to monitor (command -> account_id mapping)
#[derive(Debug, Clone)]
pub struct MonitorConfig {
    pub cli_patterns: HashMap<String, i64>,
    pub poll_interval_secs: u64,
}

impl Default for MonitorConfig {
    fn default() -> Self {
        let mut patterns = HashMap::new();
        patterns.insert("claude".to_string(), 1);
        patterns.insert("codex".to_string(), 2);
        patterns.insert("gemini".to_string(), 3);

        Self {
            cli_patterns: patterns,
            // Default to 30 seconds; will be overridden by settings poll_interval_minutes
            poll_interval_secs: 30,
        }
    }
}

/// Monitor state that persists across the app
pub struct ProcessMonitor {
    pub is_running: Arc<Mutex<bool>>,
    pub detected_processes: Arc<Mutex<Vec<DetectedProcess>>>,
    pub config: Arc<Mutex<MonitorConfig>>,
    pub generation: Arc<Mutex<u64>>,
}

impl Default for ProcessMonitor {
    fn default() -> Self {
        Self {
            is_running: Arc::new(Mutex::new(false)),
            detected_processes: Arc::new(Mutex::new(Vec::new())),
            config: Arc::new(Mutex::new(MonitorConfig::default())),
            generation: Arc::new(Mutex::new(0)),
        }
    }
}

impl ProcessMonitor {
    /// Scan for matching processes
    pub async fn scan_processes(&self) -> Vec<DetectedProcess> {
        let config = self.config.lock().await;
        let mut system = System::new();
        system.refresh_processes_specifics(
            ProcessesToUpdate::All,
            true,
            ProcessRefreshKind::new().with_cmd(sysinfo::UpdateKind::Always),
        );

        let mut detected = Vec::new();

        for (pid, process) in system.processes() {
            let process_name = process.name().to_string_lossy().to_lowercase();
            let cmd_str = process
                .cmd()
                .iter()
                .map(|s| s.to_string_lossy().to_string())
                .collect::<Vec<_>>()
                .join(" ");

            for (pattern, account_id) in &config.cli_patterns {
                if process_name.contains(pattern) || cmd_str.to_lowercase().contains(pattern) {
                    detected.push(DetectedProcess {
                        pid: pid.as_u32(),
                        name: process_name.clone(),
                        command: cmd_str.clone(),
                        account_id: Some(*account_id),
                    });
                    break;
                }
            }
        }

        detected
    }

    /// Update config from database accounts
    pub async fn update_config(&self, accounts: Vec<(i64, String)>) {
        let mut config = self.config.lock().await;
        config.cli_patterns.clear();
        for (id, cli_command) in accounts {
            // Extract the base command name
            let cmd = cli_command.split_whitespace().next().unwrap_or("").trim();
            if cmd.is_empty() {
                continue;
            }
            config.cli_patterns.insert(cmd.to_lowercase(), id);
        }
    }

    pub async fn set_poll_interval_secs(&self, poll_interval_secs: u64) {
        let mut config = self.config.lock().await;
        config.poll_interval_secs = poll_interval_secs;
    }
}

async fn load_poll_interval_secs(db: &State<'_, DbPool>) -> Result<u64, String> {
    let pool = get_pool(db).await?;
    let row: Option<(String,)> =
        sqlx::query_as("SELECT value FROM settings WHERE key = 'poll_interval_minutes'")
            .fetch_optional(&pool)
            .await
            .map_err(|e| format!("Failed to fetch poll interval: {}", e))?;

    let poll_interval_minutes = row
        .and_then(|(value,)| value.parse::<u64>().ok())
        .filter(|minutes| (1..=60).contains(minutes))
        .unwrap_or(15);

    Ok(poll_interval_minutes * 60)
}

fn spawn_monitoring_task(
    app_handle: AppHandle,
    is_running: Arc<Mutex<bool>>,
    detected_processes: Arc<Mutex<Vec<DetectedProcess>>>,
    config: Arc<Mutex<MonitorConfig>>,
    generation: Arc<Mutex<u64>>,
    run_generation: u64,
) {
    tokio::spawn(async move {
        let poll_interval = {
            let cfg = config.lock().await;
            cfg.poll_interval_secs
        };

        let mut ticker = interval(Duration::from_secs(poll_interval));

        loop {
            ticker.tick().await;

            {
                let running = is_running.lock().await;
                let current_generation = *generation.lock().await;
                if !*running || current_generation != run_generation {
                    break;
                }
            }

            let monitor = ProcessMonitor {
                is_running: is_running.clone(),
                detected_processes: detected_processes.clone(),
                config: config.clone(),
                generation: generation.clone(),
            };

            let new_detected = monitor.scan_processes().await;

            {
                let mut detected = detected_processes.lock().await;
                let old_pids: Vec<u32> = detected.iter().map(|p| p.pid).collect();
                let new_pids: Vec<u32> = new_detected.iter().map(|p| p.pid).collect();

                for proc in &new_detected {
                    if !old_pids.contains(&proc.pid) {
                        let _ = app_handle.emit("process-started", proc.clone());
                    }
                }

                for proc in detected.iter() {
                    if !new_pids.contains(&proc.pid) {
                        let _ = app_handle.emit("process-stopped", proc.clone());
                    }
                }

                *detected = new_detected;
            }

            let status = MonitoringStatus {
                is_running: true,
                detected_processes: detected_processes.lock().await.clone(),
                last_check: Some(chrono::Utc::now().to_rfc3339()),
            };
            let _ = app_handle.emit("monitoring-status", status);
        }
    });
}

async fn restart_monitoring_if_running(
    app: &AppHandle,
    monitor: &State<'_, ProcessMonitor>,
) -> Result<(), String> {
    let is_running = *monitor.is_running.lock().await;
    if !is_running {
        return Ok(());
    }

    let next_generation = {
        let mut generation = monitor.generation.lock().await;
        *generation += 1;
        *generation
    };

    spawn_monitoring_task(
        app.clone(),
        monitor.is_running.clone(),
        monitor.detected_processes.clone(),
        monitor.config.clone(),
        monitor.generation.clone(),
        next_generation,
    );

    let status = MonitoringStatus {
        is_running: true,
        detected_processes: monitor.detected_processes.lock().await.clone(),
        last_check: Some(chrono::Utc::now().to_rfc3339()),
    };
    let _ = app.emit("monitoring-status", status);

    Ok(())
}

/// Start monitoring background task
#[tauri::command]
pub async fn start_monitoring(
    app: AppHandle,
    monitor: State<'_, ProcessMonitor>,
    db: State<'_, DbPool>,
) -> Result<(), String> {
    let poll_interval_secs = load_poll_interval_secs(&db).await?;
    monitor.set_poll_interval_secs(poll_interval_secs).await;

    let is_running = monitor.is_running.clone();
    let detected_processes = monitor.detected_processes.clone();
    let config = monitor.config.clone();
    let generation = monitor.generation.clone();

    // Check if already running
    {
        let mut running = is_running.lock().await;
        if *running {
            return Ok(());
        }
        *running = true;
    }

    let run_generation = {
        let mut generation = generation.lock().await;
        *generation += 1;
        *generation
    };

    spawn_monitoring_task(
        app.clone(),
        is_running,
        detected_processes,
        config,
        generation,
        run_generation,
    );

    // Emit initial status
    let status = MonitoringStatus {
        is_running: true,
        detected_processes: Vec::new(),
        last_check: Some(chrono::Utc::now().to_rfc3339()),
    };
    let _ = app.emit("monitoring-status", status);

    Ok(())
}

/// Stop monitoring
#[tauri::command]
pub async fn stop_monitoring(monitor: State<'_, ProcessMonitor>) -> Result<(), String> {
    let mut running = monitor.is_running.lock().await;
    *running = false;
    let mut generation = monitor.generation.lock().await;
    *generation += 1;

    Ok(())
}

/// Get current monitoring status
#[tauri::command]
pub async fn get_monitoring_status(
    monitor: State<'_, ProcessMonitor>,
) -> Result<MonitoringStatus, String> {
    let is_running = *monitor.is_running.lock().await;
    let detected_processes = monitor.detected_processes.lock().await.clone();

    Ok(MonitoringStatus {
        is_running,
        detected_processes,
        last_check: if is_running {
            Some(chrono::Utc::now().to_rfc3339())
        } else {
            None
        },
    })
}

/// Update monitor config from accounts
#[tauri::command]
pub async fn update_monitor_config(
    app: AppHandle,
    monitor: State<'_, ProcessMonitor>,
    db: State<'_, DbPool>,
    accounts: Vec<(i64, String)>,
) -> Result<(), String> {
    monitor.update_config(accounts).await;
    monitor.set_poll_interval_secs(load_poll_interval_secs(&db).await?).await;
    restart_monitoring_if_running(&app, &monitor).await?;
    Ok(())
}

/// Force a single scan (for testing)
#[tauri::command]
pub async fn scan_cli_processes(
    monitor: State<'_, ProcessMonitor>,
) -> Result<Vec<DetectedProcess>, String> {
    Ok(monitor.scan_processes().await)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_monitor_config_default() {
        let config = MonitorConfig::default();

        assert_eq!(config.poll_interval_secs, 30);
        assert!(config.cli_patterns.contains_key("claude"));
        assert!(config.cli_patterns.contains_key("codex"));
        assert!(config.cli_patterns.contains_key("gemini"));
        assert_eq!(config.cli_patterns.get("claude"), Some(&1));
        assert_eq!(config.cli_patterns.get("codex"), Some(&2));
        assert_eq!(config.cli_patterns.get("gemini"), Some(&3));
    }

    #[test]
    fn test_process_monitor_default() {
        let monitor = ProcessMonitor::default();

        // Check that defaults are set correctly
        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(async {
            assert!(!*monitor.is_running.lock().await);
            assert!(monitor.detected_processes.lock().await.is_empty());
            assert_eq!(*monitor.generation.lock().await, 0);
        });
    }

    #[tokio::test]
    async fn test_update_config() {
        let monitor = ProcessMonitor::default();

        let accounts = vec![
            (10, "my-claude".to_string()),
            (20, "my-codex --flag".to_string()),
        ];

        monitor.update_config(accounts).await;

        let config = monitor.config.lock().await;
        assert_eq!(config.cli_patterns.get("my-claude"), Some(&10));
        assert_eq!(config.cli_patterns.get("my-codex"), Some(&20));
        assert!(!config.cli_patterns.contains_key("claude")); // Old defaults should be cleared
    }

    #[test]
    fn test_detected_process_serialization() {
        let process = DetectedProcess {
            pid: 12345,
            name: "claude".to_string(),
            command: "claude -p test".to_string(),
            account_id: Some(1),
        };

        let json = serde_json::to_string(&process).unwrap();
        assert!(json.contains("12345"));
        assert!(json.contains("claude"));

        let deserialized: DetectedProcess = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.pid, 12345);
        assert_eq!(deserialized.name, "claude");
        assert_eq!(deserialized.account_id, Some(1));
    }

    #[test]
    fn test_monitoring_status_serialization() {
        let status = MonitoringStatus {
            is_running: true,
            detected_processes: vec![
                DetectedProcess {
                    pid: 1,
                    name: "test".to_string(),
                    command: "test cmd".to_string(),
                    account_id: Some(1),
                }
            ],
            last_check: Some("2024-01-15T12:00:00Z".to_string()),
        };

        let json = serde_json::to_string(&status).unwrap();
        assert!(json.contains("is_running"));
        assert!(json.contains("detected_processes"));
        assert!(json.contains("last_check"));

        let deserialized: MonitoringStatus = serde_json::from_str(&json).unwrap();
        assert!(deserialized.is_running);
        assert_eq!(deserialized.detected_processes.len(), 1);
    }

    #[tokio::test]
    async fn test_scan_processes_returns_vec() {
        let monitor = ProcessMonitor::default();

        // This test just ensures scan_processes runs without panicking
        // Actual process detection depends on system state
        let _processes = monitor.scan_processes().await;
        // No assertion needed - just checking it doesn't panic
    }
}
