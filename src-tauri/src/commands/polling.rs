use crate::db::get_pool;
use crate::errors::db_err;
use crate::services::cli_poller;
use crate::services::output_parser::UsageInfo;
use tauri::State;
use crate::db::DbPool;

/// Poll a single account for usage information.
///
/// Runs the account's CLI command and parses the output.
#[tauri::command]
pub async fn poll_account(
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

    // Poll the CLI
    let usage_info = cli_poller::poll_account(&resolved_path, &tool_type).await?;

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

    for (account_id, cli_command, tool_type) in rows {
        match cli_poller::resolve_cli_path(&cli_command).await {
            Ok(resolved_path) => {
                match cli_poller::poll_account(&resolved_path, &tool_type).await {
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
