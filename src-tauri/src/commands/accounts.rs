use crate::db::get_pool;
use crate::models::{Account, NewAccount};
use crate::validation::{
    validate_account_name, validate_cli_command, validate_color, validate_window_duration_hours,
};
use serde_json::Value;
use tauri::State;
use crate::db::DbPool;

/// Validate account fields before create/update operations.
fn validate_account_fields(
    name: &str,
    cli_command: &str,
    window_duration_hours: i32,
    color: &str,
) -> Result<(), String> {
    validate_account_name(name)?;
    validate_cli_command(cli_command)?;
    validate_window_duration_hours(window_duration_hours)?;
    validate_color(color)?;
    Ok(())
}

#[tauri::command]
pub async fn get_accounts(db: State<'_, DbPool>) -> Result<Vec<Account>, String> {
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
        ) FROM accounts ORDER BY id",
    )
    .fetch_all(&pool)
    .await
    .map_err(|e| {
        eprintln!("Database error in get_accounts: {:?}", e);
        "Failed to fetch accounts".to_string()
    })?;

    let accounts: Vec<Account> = rows
        .into_iter()
        .filter_map(|(v,)| match serde_json::from_value(v.clone()) {
            Ok(account) => Some(account),
            Err(e) => {
                eprintln!("Failed to deserialize account: {:?}, data: {:?}", e, v);
                None
            }
        })
        .collect();

    Ok(accounts)
}

#[tauri::command]
pub async fn create_account(
    db: State<'_, DbPool>,
    account: NewAccount,
) -> Result<Account, String> {
    // Validate all fields
    validate_account_fields(
        &account.name,
        &account.cli_command,
        account.window_duration_hours,
        &account.color,
    )?;

    let pool = get_pool(&db).await?;

    let result = sqlx::query(
        "INSERT INTO accounts (name, tool_type, cli_command, cli_args, window_duration_hours, color, enabled)
         VALUES (?, ?, ?, ?, ?, ?, ?)",
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
    .map_err(|e| {
        eprintln!("Database error in create_account: {:?}", e);
        "Failed to create account".to_string()
    })?;

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
pub async fn update_account(db: State<'_, DbPool>, account: Account) -> Result<(), String> {
    // Validate all fields
    validate_account_fields(
        &account.name,
        &account.cli_command,
        account.window_duration_hours,
        &account.color,
    )?;

    let pool = get_pool(&db).await?;
    let id = account.id.ok_or("Account ID is required")?;

    sqlx::query(
        "UPDATE accounts SET
         name = ?, tool_type = ?, cli_command = ?, cli_args = ?,
         window_duration_hours = ?, color = ?, enabled = ?
         WHERE id = ?",
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
    .map_err(|e| {
        eprintln!("Database error in update_account: {:?}", e);
        "Failed to update account".to_string()
    })?;

    Ok(())
}

#[tauri::command]
pub async fn delete_account(db: State<'_, DbPool>, id: i64) -> Result<(), String> {
    let pool = get_pool(&db).await?;

    sqlx::query("DELETE FROM accounts WHERE id = ?")
        .bind(id)
        .execute(&pool)
        .await
        .map_err(|e| {
            eprintln!("Database error in delete_account: {:?}", e);
            "Failed to delete account".to_string()
        })?;

    Ok(())
}
