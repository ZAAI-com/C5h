use crate::models::{Account, NewAccount};
use serde_json::Value;
use sqlx::SqlitePool;
use tauri::State;
use tauri_plugin_sql::DbInstances;

#[tauri::command]
pub async fn get_accounts(db: State<'_, DbInstances>) -> Result<Vec<Account>, String> {
    let pool = get_pool(&db).await?;

    let rows: Vec<(Value,)> = sqlx::query_as(
        "SELECT json_object(
            'id', id,
            'name', name,
            'tool_type', tool_type,
            'cli_command', cli_command,
            'cli_args', cli_args,
            'window_duration_hours', window_duration_hours,
            'color', color,
            'enabled', enabled,
            'created_at', created_at
        ) FROM accounts ORDER BY id"
    )
    .fetch_all(&pool)
    .await
    .map_err(|e| e.to_string())?;

    let accounts: Vec<Account> = rows
        .into_iter()
        .filter_map(|(v,)| serde_json::from_value(v).ok())
        .collect();

    Ok(accounts)
}

#[tauri::command]
pub async fn create_account(
    db: State<'_, DbInstances>,
    account: NewAccount,
) -> Result<Account, String> {
    let pool = get_pool(&db).await?;

    let result = sqlx::query(
        "INSERT INTO accounts (name, tool_type, cli_command, cli_args, window_duration_hours, color, enabled)
         VALUES (?, ?, ?, ?, ?, ?, ?)"
    )
    .bind(&account.name)
    .bind(&account.tool_type)
    .bind(&account.cli_command)
    .bind(&account.cli_args)
    .bind(account.window_duration_hours)
    .bind(&account.color)
    .bind(account.enabled)
    .execute(&pool)
    .await
    .map_err(|e| e.to_string())?;

    let id = result.last_insert_rowid();

    Ok(Account {
        id: Some(id),
        name: account.name,
        tool_type: account.tool_type,
        cli_command: account.cli_command,
        cli_args: account.cli_args,
        window_duration_hours: account.window_duration_hours,
        color: account.color,
        enabled: account.enabled,
        created_at: None,
    })
}

#[tauri::command]
pub async fn update_account(
    db: State<'_, DbInstances>,
    account: Account,
) -> Result<(), String> {
    let pool = get_pool(&db).await?;
    let id = account.id.ok_or("Account ID is required")?;

    sqlx::query(
        "UPDATE accounts SET
         name = ?, tool_type = ?, cli_command = ?, cli_args = ?,
         window_duration_hours = ?, color = ?, enabled = ?
         WHERE id = ?"
    )
    .bind(&account.name)
    .bind(&account.tool_type)
    .bind(&account.cli_command)
    .bind(&account.cli_args)
    .bind(account.window_duration_hours)
    .bind(&account.color)
    .bind(account.enabled)
    .bind(id)
    .execute(&pool)
    .await
    .map_err(|e| e.to_string())?;

    Ok(())
}

#[tauri::command]
pub async fn delete_account(db: State<'_, DbInstances>, id: i64) -> Result<(), String> {
    let pool = get_pool(&db).await?;

    sqlx::query("DELETE FROM accounts WHERE id = ?")
        .bind(id)
        .execute(&pool)
        .await
        .map_err(|e| e.to_string())?;

    Ok(())
}

async fn get_pool(db: &State<'_, DbInstances>) -> Result<SqlitePool, String> {
    let instances = db.0.read().await;
    let db_pool = instances
        .get("sqlite:c5h.db")
        .ok_or_else(|| "Database not found".to_string())?;

    match db_pool {
        tauri_plugin_sql::DbPool::Sqlite(pool) => Ok(pool.clone()),
        #[allow(unreachable_patterns)]
        _ => Err("Expected SQLite database".to_string()),
    }
}
