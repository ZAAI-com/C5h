use crate::db::get_pool;
use crate::db::DbPool;
use crate::errors::db_err;
use crate::services::cli_poller;
use crate::services::output_parser::UsageInfo;
use std::path::PathBuf;
use tauri::{AppHandle, Manager, State};

/// Resolve `<app_data_dir>/gemini-poll-workspace`, creating it if missing.
///
/// Gemini refuses to run in untrusted workspaces. We poll from this app-owned
/// directory and pair it with `GEMINI_CLI_TRUST_WORKSPACE=true` (set on the
/// subprocess only) so polling does not depend on the user's current cwd.
fn ensure_gemini_poll_workspace(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|e| format!("Failed to resolve app_data_dir: {}", e))?
        .join("gemini-poll-workspace");
    std::fs::create_dir_all(&dir)
        .map_err(|e| format!("Failed to create gemini-poll-workspace: {}", e))?;
    Ok(dir)
}

fn is_gemini(tool_type: &str) -> bool {
    tool_type == "gemini"
}

/// Poll a single account for usage information.
///
/// Runs the account's CLI command and parses the output.
#[tauri::command]
pub async fn poll_account(
    app: AppHandle,
    db: State<'_, DbPool>,
    account_id: i64,
) -> Result<UsageInfo, String> {
    let pool = get_pool(&db).await?;

    // Get account details
    let row: Option<(String, String)> = sqlx::query_as(
        "SELECT cli_command, tool_type FROM accounts WHERE id = ? AND enabled = 1",
    )
    .bind(account_id)
    .fetch_optional(&pool)
    .await
    .map_err(db_err("fetch account for polling"))?;

    let (cli_command, tool_type) = row.ok_or("Account not found or disabled")?;

    // Resolve the CLI path (handles both absolute paths and command names)
    let resolved_path = cli_poller::resolve_cli_path(&cli_command).await?;

    // Poll the CLI — for Gemini, scope trust + workdir to this subprocess.
    let usage_info = if is_gemini(&tool_type) {
        let overrides = match ensure_gemini_poll_workspace(&app) {
            Ok(dir) => cli_poller::gemini_overrides(dir),
            Err(e) => {
                log::warn!(
                    "Falling back to no Gemini overrides for account {}: {}",
                    account_id,
                    e
                );
                cli_poller::PollOverrides::default()
            }
        };
        cli_poller::poll_account_with_overrides(&resolved_path, &tool_type, overrides).await?
    } else {
        cli_poller::poll_account(&resolved_path, &tool_type).await?
    };

    // Update the current window's usage_percent if one is active
    if let Some(percent) = usage_info.session_percent {
        sqlx::query(
            "UPDATE windows SET usage_percent = ? WHERE account_id = ? AND ended_at IS NULL",
        )
        .bind(percent as i32)
        .bind(account_id)
        .execute(&pool)
        .await
        .map_err(db_err("update polled usage"))?;
    }

    Ok(usage_info)
}

/// Poll all enabled accounts for usage information.
///
/// Returns a list of (account_id, UsageInfo) pairs.
#[tauri::command]
pub async fn poll_all_accounts(
    app: AppHandle,
    db: State<'_, DbPool>,
) -> Result<Vec<(i64, UsageInfo)>, String> {
    let pool = get_pool(&db).await?;

    let rows: Vec<(i64, String, String)> = sqlx::query_as(
        "SELECT id, cli_command, tool_type FROM accounts WHERE enabled = 1",
    )
    .fetch_all(&pool)
    .await
    .map_err(db_err("fetch accounts for polling"))?;

    let mut results = Vec::new();

    // Resolve the Gemini poll workspace lazily and cache for the duration of this call.
    let mut gemini_workdir: Option<Option<PathBuf>> = None;

    for (account_id, cli_command, tool_type) in rows {
        match cli_poller::resolve_cli_path(&cli_command).await {
            Ok(resolved_path) => {
                let poll_result = if is_gemini(&tool_type) {
                    let dir = gemini_workdir.get_or_insert_with(|| {
                        match ensure_gemini_poll_workspace(&app) {
                            Ok(d) => Some(d),
                            Err(e) => {
                                log::warn!("Gemini poll workspace unavailable: {}", e);
                                None
                            }
                        }
                    });
                    let overrides = match dir {
                        Some(d) => cli_poller::gemini_overrides(d.clone()),
                        None => cli_poller::PollOverrides::default(),
                    };
                    cli_poller::poll_account_with_overrides(&resolved_path, &tool_type, overrides)
                        .await
                } else {
                    cli_poller::poll_account(&resolved_path, &tool_type).await
                };

                match poll_result {
                    Ok(info) => {
                        // Update usage_percent on active window
                        if let Some(percent) = info.session_percent {
                            if let Err(err) = sqlx::query(
                                "UPDATE windows SET usage_percent = ? WHERE account_id = ? AND ended_at IS NULL",
                            )
                            .bind(percent as i32)
                            .bind(account_id)
                            .execute(&pool)
                            .await
                            {
                                log::warn!(
                                    "Failed to persist usage_percent for account {}: {}",
                                    account_id,
                                    db_err("update polled usage")(err)
                                );
                            }
                        }
                        results.push((account_id, info));
                    }
                    Err(e) => {
                        log::warn!("Failed to poll account {}: {}", account_id, e);
                        // Return default UsageInfo for failed polls
                        results.push((account_id, UsageInfo::default()));
                    }
                }
            }
            Err(e) => {
                log::warn!("CLI not found for account {}: {}", account_id, e);
                results.push((account_id, UsageInfo::default()));
            }
        }
    }

    Ok(results)
}

/// Check which CLI tools are available on the system.
///
/// Returns a list of (command_name, is_available, resolved_path) tuples.
#[tauri::command]
pub async fn check_cli_availability(
    commands: Vec<String>,
) -> Result<Vec<(String, bool, Option<String>)>, String> {
    let mut results = Vec::new();

    for cmd in commands {
        match cli_poller::resolve_cli_path(&cmd).await {
            Ok(path) => results.push((cmd, true, Some(path))),
            Err(_) => results.push((cmd, false, None)),
        }
    }

    Ok(results)
}
