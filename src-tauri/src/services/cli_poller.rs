//! CLI polling service that runs AI tool CLI commands to get usage data.
//!
//! This service executes CLI commands (e.g., `claude -p "/usage"`) and
//! pipes the output to the output_parser to extract usage percentages.

use crate::services::output_parser::{
    parse_claude_output, parse_codex_output, parse_gemini_output, UsageInfo,
};
use std::path::PathBuf;
use std::process::Stdio;
use tokio::process::Command;
use tokio::time::{timeout, Duration};

/// Maximum time to wait for a CLI command to complete
const CLI_TIMEOUT_SECS: u64 = 30;

/// Per-subprocess overrides applied only for this poll invocation.
///
/// Used to scope Gemini's `GEMINI_CLI_TRUST_WORKSPACE=true` and an app-owned
/// working directory to the polling subprocess without persisting trust to disk
/// or affecting other providers.
#[derive(Debug, Default, Clone)]
pub struct PollOverrides {
    /// Working directory for the subprocess. None = inherit parent cwd.
    pub workdir: Option<PathBuf>,
    /// Extra env vars to set on the subprocess only.
    pub extra_env: Vec<(String, String)>,
}

/// Build overrides for Gemini polling: session-only trust + app-owned workdir.
pub fn gemini_overrides(workdir: PathBuf) -> PollOverrides {
    PollOverrides {
        workdir: Some(workdir),
        extra_env: vec![(
            "GEMINI_CLI_TRUST_WORKSPACE".to_string(),
            "true".to_string(),
        )],
    }
}

/// Poll a single account's CLI tool for usage information.
///
/// Runs the appropriate CLI command based on tool_type and parses the output.
pub async fn poll_account(
    cli_command: &str,
    tool_type: &str,
) -> Result<UsageInfo, String> {
    poll_account_with_overrides(cli_command, tool_type, PollOverrides::default()).await
}

/// Like `poll_account`, but allows the caller to inject per-subprocess
/// environment variables and a working directory (e.g. for Gemini trust).
pub async fn poll_account_with_overrides(
    cli_command: &str,
    tool_type: &str,
    overrides: PollOverrides,
) -> Result<UsageInfo, String> {
    let args = get_poll_args(tool_type)?;

    let cmd_result = timeout(
        Duration::from_secs(CLI_TIMEOUT_SECS),
        run_cli_command(cli_command, &args, &overrides),
    )
    .await
    .map_err(|_| format!("CLI command timed out after {}s", CLI_TIMEOUT_SECS))?;

    let output = cmd_result?;

    let info = match tool_type {
        "claude_code" | "claude" => parse_claude_output(&output),
        "codex" => parse_codex_output(&output),
        "gemini" => parse_gemini_output(&output),
        other => {
            return Err(format!("Unknown tool type: {}", other));
        }
    };

    Ok(info)
}

/// Get the CLI arguments needed to query usage for a given tool type.
fn get_poll_args(tool_type: &str) -> Result<Vec<String>, String> {
    match tool_type {
        "claude_code" | "claude" => Ok(vec!["-p".to_string(), "/usage".to_string()]),
        "codex" => Ok(vec!["-p".to_string(), "/status".to_string()]),
        "gemini" => Ok(vec![]), // Gemini shows usage on startup
        other => Err(format!("Unknown tool type: {}", other)),
    }
}

/// Run a CLI command and capture its stdout + stderr.
async fn run_cli_command(
    command: &str,
    args: &[String],
    overrides: &PollOverrides,
) -> Result<String, String> {
    let mut cmd = Command::new(command);
    cmd.args(args).stdout(Stdio::piped()).stderr(Stdio::piped());

    if let Some(dir) = overrides.workdir.as_ref() {
        cmd.current_dir(dir);
    }
    for (k, v) in &overrides.extra_env {
        cmd.env(k, v);
    }

    let output: std::process::Output = cmd
        .output()
        .await
        .map_err(|e| format!("Failed to run '{}': {}", command, e))?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    if !output.status.success() {
        let detail = if !stderr.trim().is_empty() {
            stderr.trim().to_string()
        } else if !stdout.trim().is_empty() {
            stdout.trim().to_string()
        } else {
            "no error output".to_string()
        };

        return Err(format!(
            "CLI '{}' exited with status {}: {}",
            command, output.status, detail
        ));
    }

    // Combine stdout and stderr since some tools write to stderr
    let combined = if stderr.is_empty() {
        stdout
    } else {
        format!("{}\n{}", stdout, stderr)
    };

    if combined.trim().is_empty() {
        return Err(format!("CLI '{}' produced no output", command));
    }

    Ok(combined)
}

/// Resolve a command name to its full path using `which`.
/// Returns the original command if it's already an absolute path.
pub async fn resolve_cli_path(command: &str) -> Result<String, String> {
    if command.starts_with('/') {
        return Ok(command.to_string());
    }

    let output: std::process::Output = Command::new("which")
        .arg(command)
        .stdout(Stdio::piped())
        .output()
        .await
        .map_err(|e| format!("Failed to resolve CLI path for '{}': {}", command, e))?;

    if !output.status.success() {
        return Err(format!(
            "CLI '{}' not found. Make sure it is installed and in your PATH.",
            command
        ));
    }

    let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if path.is_empty() {
        return Err(format!("CLI '{}' not found in PATH", command));
    }

    Ok(path)
}
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_poll_args_claude() {
        let args = get_poll_args("claude_code").unwrap();
        assert_eq!(args, vec!["-p", "/usage"]);

        let args = get_poll_args("claude").unwrap();
        assert_eq!(args, vec!["-p", "/usage"]);
    }

    #[test]
    fn test_get_poll_args_codex() {
        let args = get_poll_args("codex").unwrap();
        assert_eq!(args, vec!["-p", "/status"]);
    }

    #[test]
    fn test_get_poll_args_gemini() {
        let args = get_poll_args("gemini").unwrap();
        assert!(args.is_empty());
    }

    #[test]
    fn test_get_poll_args_unknown() {
        let err = get_poll_args("unknown_tool").unwrap_err();
        assert!(err.contains("Unknown tool type"), "got: {err}");
    }

    #[tokio::test]
    async fn resolve_cli_path_passes_through_absolute_paths() {
        // Doesn't matter if the file exists — the function returns absolute paths verbatim
        let path = resolve_cli_path("/usr/local/bin/some-binary-that-does-not-exist").await.unwrap();
        assert_eq!(path, "/usr/local/bin/some-binary-that-does-not-exist");
    }

    #[tokio::test]
    async fn resolve_cli_path_finds_common_command() {
        // `sh` is on every macOS/Linux system
        let path = resolve_cli_path("sh").await.unwrap();
        assert!(path.starts_with('/'), "expected absolute path, got: {}", path);
        assert!(path.contains("sh"));
    }

    #[tokio::test]
    async fn resolve_cli_path_errors_for_missing_binary() {
        let err = resolve_cli_path("definitely-not-a-real-command-xyzzy-9000").await.unwrap_err();
        assert!(err.contains("not found"), "got: {err}");
    }

    #[tokio::test]
    async fn poll_account_rejects_unknown_tool_type() {
        // /bin/date always produces output, so we get past the empty-output guard
        // and reach the tool_type match
        let err = poll_account("/bin/date", "not_a_real_tool").await.unwrap_err();
        assert!(err.contains("Unknown tool type"), "got: {err}");
    }

    #[tokio::test]
    async fn poll_account_errors_when_command_missing() {
        let err = poll_account("/path/to/nothing-real-1234", "claude_code").await.unwrap_err();
        assert!(err.to_lowercase().contains("failed to run") || err.to_lowercase().contains("no such"));
    }

    #[test]
    fn gemini_overrides_sets_trust_env_and_workdir() {
        let dir = PathBuf::from("/tmp/gemini-poll-x");
        let o = gemini_overrides(dir.clone());
        assert_eq!(o.workdir.as_deref(), Some(dir.as_path()));
        assert!(o
            .extra_env
            .iter()
            .any(|(k, v)| k == "GEMINI_CLI_TRUST_WORKSPACE" && v == "true"));
    }

    #[test]
    fn poll_overrides_default_is_empty() {
        let o = PollOverrides::default();
        assert!(o.workdir.is_none());
        assert!(o.extra_env.is_empty());
    }

    #[tokio::test]
    async fn run_cli_command_applies_workdir() {
        let tmp = std::env::temp_dir();
        let overrides = PollOverrides {
            workdir: Some(tmp.clone()),
            extra_env: vec![],
        };
        let out = run_cli_command("/bin/pwd", &[], &overrides).await.unwrap();
        // Resolve symlinks (e.g. /tmp -> /private/tmp on macOS) so we compare canonical paths.
        let expected = std::fs::canonicalize(&tmp).unwrap();
        let actual_line = out.lines().next().unwrap_or("").trim();
        let actual = std::fs::canonicalize(actual_line).unwrap();
        assert_eq!(actual, expected, "pwd output: {out}");
    }

    #[tokio::test]
    async fn run_cli_command_applies_env() {
        let overrides = PollOverrides {
            workdir: None,
            extra_env: vec![(
                "GEMINI_CLI_TRUST_WORKSPACE".to_string(),
                "true".to_string(),
            )],
        };
        let out = run_cli_command(
            "/bin/sh",
            &["-c".to_string(), "echo $GEMINI_CLI_TRUST_WORKSPACE".to_string()],
            &overrides,
        )
        .await
        .unwrap();
        assert!(out.contains("true"), "env output: {out}");
    }
}
