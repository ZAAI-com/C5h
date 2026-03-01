//! Input validation functions for C5h commands.
//!
//! This module provides validation functions to prevent security issues and ensure
//! data integrity before database operations.

use std::path::Path;

/// Validates a CLI command path.
///
/// The CLI command must:
/// - Not be empty
/// - Start with '/' (absolute path)
/// - Not contain shell metacharacters that could enable injection
/// - Exist as a file (optional, warning only)
///
/// Returns Ok(()) if valid, Err with a user-friendly message if invalid.
pub fn validate_cli_command(cli_command: &str) -> Result<(), String> {
    if cli_command.is_empty() {
        return Err("CLI command cannot be empty".to_string());
    }

    // Must be an absolute path
    if !cli_command.starts_with('/') {
        return Err("CLI command must be an absolute path (start with '/')".to_string());
    }

    // Disallow shell metacharacters that could enable command injection
    let dangerous_chars = ['&', '|', ';', '$', '`', '(', ')', '{', '}', '<', '>', '\n', '\r'];
    for ch in dangerous_chars {
        if cli_command.contains(ch) {
            return Err(format!(
                "CLI command contains invalid character '{}'",
                ch
            ));
        }
    }

    // Check for path traversal
    if cli_command.contains("..") {
        return Err("CLI command cannot contain '..'".to_string());
    }

    // Validate path exists (warning, not error - user might be setting up)
    if !Path::new(cli_command).exists() {
        eprintln!("Warning: CLI command path does not exist: {}", cli_command);
    }

    Ok(())
}

/// Validates the window duration hours.
///
/// Must be between 1 and 168 hours (1 week maximum).
pub fn validate_window_duration_hours(hours: i32) -> Result<(), String> {
    if hours < 1 {
        return Err("Window duration must be at least 1 hour".to_string());
    }
    if hours > 168 {
        return Err("Window duration cannot exceed 168 hours (1 week)".to_string());
    }
    Ok(())
}

/// Validates a hex color string.
///
/// Must be in format #RRGGBB.
pub fn validate_color(color: &str) -> Result<(), String> {
    if !color.starts_with('#') {
        return Err("Color must start with '#'".to_string());
    }
    if color.len() != 7 {
        return Err("Color must be in format #RRGGBB".to_string());
    }
    if !color[1..].chars().all(|c| c.is_ascii_hexdigit()) {
        return Err("Color must contain valid hex digits".to_string());
    }
    Ok(())
}

/// Validates an account name.
///
/// Must be non-empty and reasonable length.
pub fn validate_account_name(name: &str) -> Result<(), String> {
    let trimmed = name.trim();
    if trimmed.is_empty() {
        return Err("Account name cannot be empty".to_string());
    }
    if trimmed.len() > 100 {
        return Err("Account name cannot exceed 100 characters".to_string());
    }
    Ok(())
}

/// Validates a scheduled_at datetime string.
///
/// Must be a valid RFC3339 datetime in the future.
pub fn validate_scheduled_at(scheduled_at: &str) -> Result<(), String> {
    let dt = chrono::DateTime::parse_from_rfc3339(scheduled_at)
        .map_err(|_| "Invalid datetime format. Use RFC3339 format (e.g., 2024-01-15T10:30:00Z)".to_string())?;

    let now = chrono::Utc::now();
    if dt < now {
        return Err("Scheduled time must be in the future".to_string());
    }

    Ok(())
}

/// Validates usage percentage.
///
/// Must be between 0 and 100 inclusive.
pub fn validate_usage_percent(percent: Option<i32>) -> Result<(), String> {
    if let Some(p) = percent {
        if p < 0 || p > 100 {
            return Err("Usage percentage must be between 0 and 100".to_string());
        }
    }
    Ok(())
}

/// Validates poll interval minutes.
///
/// Must be between 1 and 60 minutes.
pub fn validate_poll_interval(minutes: i32) -> Result<(), String> {
    if minutes < 1 {
        return Err("Poll interval must be at least 1 minute".to_string());
    }
    if minutes > 60 {
        return Err("Poll interval cannot exceed 60 minutes".to_string());
    }
    Ok(())
}

/// Escapes a string for safe inclusion in a plist XML file.
///
/// This prevents XML injection attacks when generating launchd plists.
pub fn escape_for_plist(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_validate_cli_command_valid() {
        assert!(validate_cli_command("/usr/local/bin/claude").is_ok());
        assert!(validate_cli_command("/opt/homebrew/bin/codex").is_ok());
    }

    #[test]
    fn test_validate_cli_command_invalid() {
        // Empty
        assert!(validate_cli_command("").is_err());
        // Not absolute
        assert!(validate_cli_command("claude").is_err());
        assert!(validate_cli_command("./claude").is_err());
        // Shell metacharacters
        assert!(validate_cli_command("/bin/sh; rm -rf /").is_err());
        assert!(validate_cli_command("/bin/sh | cat /etc/passwd").is_err());
        assert!(validate_cli_command("/bin/sh && malicious").is_err());
        assert!(validate_cli_command("/bin/sh$(whoami)").is_err());
        assert!(validate_cli_command("/bin/sh`id`").is_err());
        // Path traversal
        assert!(validate_cli_command("/usr/../etc/passwd").is_err());
    }

    #[test]
    fn test_validate_window_duration_hours() {
        assert!(validate_window_duration_hours(1).is_ok());
        assert!(validate_window_duration_hours(5).is_ok());
        assert!(validate_window_duration_hours(168).is_ok());
        assert!(validate_window_duration_hours(0).is_err());
        assert!(validate_window_duration_hours(-1).is_err());
        assert!(validate_window_duration_hours(169).is_err());
    }

    #[test]
    fn test_validate_color() {
        assert!(validate_color("#6366f1").is_ok());
        assert!(validate_color("#AABBCC").is_ok());
        assert!(validate_color("6366f1").is_err()); // Missing #
        assert!(validate_color("#abc").is_err()); // Too short
        assert!(validate_color("#abcdefg").is_err()); // Too long
        assert!(validate_color("#gggggg").is_err()); // Invalid hex
    }

    #[test]
    fn test_escape_for_plist() {
        assert_eq!(escape_for_plist("hello"), "hello");
        assert_eq!(escape_for_plist("a & b"), "a &amp; b");
        assert_eq!(escape_for_plist("<script>"), "&lt;script&gt;");
        assert_eq!(escape_for_plist("\"quoted\""), "&quot;quoted&quot;");
    }
}
