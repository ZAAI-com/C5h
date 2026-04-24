use crate::db::get_pool;
use crate::errors::db_err;
use crate::models::{Account, NewAccount};
use crate::validation::{
    validate_account_name, validate_cli_args, validate_cli_command, validate_color,
    validate_window_duration_hours,
};
use serde_json::Value;
use sqlx::SqlitePool;
use tauri::State;
use crate::db::DbPool;

/// Validate account fields before create/update operations.
fn validate_account_fields(
    name: &str,
    cli_command: &str,
    cli_args: Option<&str>,
    window_duration_hours: i32,
    color: &str,
) -> Result<(), String> {
    validate_account_name(name)?;
    validate_cli_command(cli_command)?;
    validate_cli_args(cli_args)?;
    validate_window_duration_hours(window_duration_hours)?;
    validate_color(color)?;
    Ok(())
}

pub async fn get_accounts_impl(pool: &SqlitePool) -> Result<Vec<Account>, String> {
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
    .fetch_all(pool)
    .await
    .map_err(db_err("fetch accounts"))?;

    rows
        .into_iter()
        .map(|(v,)| {
            serde_json::from_value(v).map_err(|e| format!("Malformed account record: {}", e))
        })
        .collect()
}

#[tauri::command]
pub async fn get_accounts(db: State<'_, DbPool>) -> Result<Vec<Account>, String> {
    let pool = get_pool(&db).await?;
    get_accounts_impl(&pool).await
}

pub async fn create_account_impl(
    pool: &SqlitePool,
    account: NewAccount,
) -> Result<Account, String> {
    validate_account_fields(
        &account.name,
        &account.cli_command,
        account.cli_args.as_deref(),
        account.window_duration_hours,
        &account.color,
    )?;

    let result = sqlx::query(
        "INSERT INTO accounts (name, tool_type, cli_command, cli_args, window_duration_hours, color, enabled)
         VALUES (?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(&account.name)
    .bind(account.tool_type.to_string())
    .bind(&account.cli_command)
    .bind(&account.cli_args)
    .bind(account.window_duration_hours)
    .bind(&account.color)
    .bind(account.enabled)
    .execute(pool)
    .await
    .map_err(db_err("create account"))?;

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
pub async fn create_account(
    db: State<'_, DbPool>,
    account: NewAccount,
) -> Result<Account, String> {
    let pool = get_pool(&db).await?;
    create_account_impl(&pool, account).await
}

pub async fn update_account_impl(pool: &SqlitePool, account: Account) -> Result<(), String> {
    validate_account_fields(
        &account.name,
        &account.cli_command,
        account.cli_args.as_deref(),
        account.window_duration_hours,
        &account.color,
    )?;

    let id = account.id.ok_or("Account ID is required")?;

    let result = sqlx::query(
        "UPDATE accounts SET
         name = ?, tool_type = ?, cli_command = ?, cli_args = ?,
         window_duration_hours = ?, color = ?, enabled = ?
         WHERE id = ?",
    )
    .bind(&account.name)
    .bind(account.tool_type.to_string())
    .bind(&account.cli_command)
    .bind(&account.cli_args)
    .bind(account.window_duration_hours)
    .bind(&account.color)
    .bind(account.enabled)
    .bind(id)
    .execute(pool)
    .await
    .map_err(db_err("update account"))?;

    if result.rows_affected() == 0 {
        return Err("Account not found".to_string());
    }

    Ok(())
}

#[tauri::command]
pub async fn update_account(db: State<'_, DbPool>, account: Account) -> Result<(), String> {
    let pool = get_pool(&db).await?;
    update_account_impl(&pool, account).await
}

pub async fn delete_account_impl(pool: &SqlitePool, id: i64) -> Result<(), String> {
    let result = sqlx::query("DELETE FROM accounts WHERE id = ?")
        .bind(id)
        .execute(pool)
        .await
        .map_err(db_err("delete account"))?;

    if result.rows_affected() == 0 {
        return Err("Account not found".to_string());
    }

    Ok(())
}

#[tauri::command]
pub async fn delete_account(db: State<'_, DbPool>, id: i64) -> Result<(), String> {
    let pool = get_pool(&db).await?;
    delete_account_impl(&pool, id).await
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::init_test_pool;

    fn sample_new_account() -> NewAccount {
        NewAccount {
            name: "Test Account".to_string(),
            tool_type: crate::models::ToolType::Claude,
            cli_command: "claude".to_string(),
            cli_args: Some("-p \"hi\"".to_string()),
            window_duration_hours: 5,
            color: "#abcdef".to_string(),
            enabled: true,
        }
    }

    #[tokio::test]
    async fn get_accounts_returns_seeded_defaults() {
        let pool = init_test_pool().await;
        let accounts = get_accounts_impl(&pool).await.unwrap();
        assert_eq!(accounts.len(), 3);
        assert_eq!(accounts[0].name, "Claude Code");
        assert_eq!(accounts[1].name, "Codex");
        assert_eq!(accounts[2].name, "Gemini");
    }

    #[tokio::test]
    async fn create_account_persists_and_returns_id() {
        let pool = init_test_pool().await;
        let created = create_account_impl(&pool, sample_new_account()).await.unwrap();
        assert!(created.id.is_some());
        assert_eq!(created.name, "Test Account");

        let all = get_accounts_impl(&pool).await.unwrap();
        assert_eq!(all.len(), 4);
    }

    #[tokio::test]
    async fn create_account_rejects_invalid_name() {
        let pool = init_test_pool().await;
        let mut acct = sample_new_account();
        acct.name = "   ".to_string();
        let err = create_account_impl(&pool, acct).await.unwrap_err();
        assert!(err.contains("name"), "got: {err}");
    }

    #[tokio::test]
    async fn create_account_rejects_invalid_color() {
        let pool = init_test_pool().await;
        let mut acct = sample_new_account();
        acct.color = "red".to_string();
        let err = create_account_impl(&pool, acct).await.unwrap_err();
        assert!(err.to_lowercase().contains("color"));
    }

    #[tokio::test]
    async fn create_account_rejects_dangerous_cli_command() {
        let pool = init_test_pool().await;
        let mut acct = sample_new_account();
        acct.cli_command = "claude; rm -rf /".to_string();
        assert!(create_account_impl(&pool, acct).await.is_err());
    }

    #[tokio::test]
    async fn create_account_rejects_invalid_duration() {
        let pool = init_test_pool().await;
        let mut acct = sample_new_account();
        acct.window_duration_hours = 0;
        assert!(create_account_impl(&pool, acct).await.is_err());

        let mut acct = sample_new_account();
        acct.window_duration_hours = 200;
        assert!(create_account_impl(&pool, acct).await.is_err());
    }

    #[tokio::test]
    async fn update_account_modifies_fields() {
        let pool = init_test_pool().await;
        let created = create_account_impl(&pool, sample_new_account()).await.unwrap();

        let mut updated = created.clone();
        updated.name = "Renamed".to_string();
        updated.color = "#fedcba".to_string();
        update_account_impl(&pool, updated).await.unwrap();

        let all = get_accounts_impl(&pool).await.unwrap();
        let found = all.iter().find(|a| a.id == created.id).unwrap();
        assert_eq!(found.name, "Renamed");
        assert_eq!(found.color, "#fedcba");
    }

    #[tokio::test]
    async fn update_account_requires_id() {
        let pool = init_test_pool().await;
        let mut acct = Account {
            id: None,
            name: "x".to_string(),
            tool_type: crate::models::ToolType::Claude,
            cli_command: "claude".to_string(),
            cli_args: None,
            window_duration_hours: 5,
            color: "#abcdef".to_string(),
            enabled: true,
            created_at: None,
        };
        acct.id = None;
        let err = update_account_impl(&pool, acct).await.unwrap_err();
        assert!(err.contains("ID"), "got: {err}");
    }

    #[tokio::test]
    async fn delete_account_removes_row() {
        let pool = init_test_pool().await;
        let created = create_account_impl(&pool, sample_new_account()).await.unwrap();
        let id = created.id.unwrap();

        delete_account_impl(&pool, id).await.unwrap();

        let all = get_accounts_impl(&pool).await.unwrap();
        assert!(all.iter().all(|a| a.id != Some(id)));
    }

    #[tokio::test]
    async fn update_account_errors_when_missing() {
        let pool = init_test_pool().await;
        let err = update_account_impl(
            &pool,
            Account {
                id: Some(999_999),
                name: "Missing".to_string(),
                tool_type: crate::models::ToolType::Claude,
                cli_command: "claude".to_string(),
                cli_args: None,
                window_duration_hours: 5,
                color: "#abcdef".to_string(),
                enabled: true,
                created_at: None,
            },
        )
        .await
        .unwrap_err();

        assert!(err.contains("Account not found"), "got: {err}");
    }

    #[tokio::test]
    async fn delete_account_errors_when_missing() {
        let pool = init_test_pool().await;
        let err = delete_account_impl(&pool, 999_999).await.unwrap_err();
        assert!(err.contains("Account not found"), "got: {err}");
    }
}
