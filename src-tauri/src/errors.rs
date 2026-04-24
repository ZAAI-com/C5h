//! Structured error types for C5h commands.
//!
//! Provides a unified error type that logs internal details while returning
//! user-friendly messages to the frontend via Tauri IPC.

use std::fmt;

/// Application-level error with separate internal and user-facing messages.
#[derive(Debug)]
pub enum C5hError {
    /// Database operation failed
    Database {
        operation: &'static str,
        source: sqlx::Error,
    },
    /// Input validation failed (message is already user-friendly)
    Validation(String),
    /// File system or IO error
    Io {
        operation: &'static str,
        source: std::io::Error,
    },
    /// CLI tool error
    Cli {
        tool: String,
        detail: String,
    },
    /// Generic error with user-facing message
    Other(String),
}

impl fmt::Display for C5hError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            C5hError::Database { operation, .. } => {
                write!(f, "Failed to {}", operation)
            }
            C5hError::Validation(msg) => write!(f, "{}", msg),
            C5hError::Io { operation, .. } => {
                write!(f, "Failed to {}", operation)
            }
            C5hError::Cli { tool, detail } => {
                write!(f, "{} CLI error: {}", tool, detail)
            }
            C5hError::Other(msg) => write!(f, "{}", msg),
        }
    }
}

impl std::error::Error for C5hError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            C5hError::Database { source, .. } => Some(source),
            C5hError::Io { source, .. } => Some(source),
            _ => None,
        }
    }
}

impl From<C5hError> for String {
    fn from(err: C5hError) -> String {
        // Log the internal error details for debugging
        match &err {
            C5hError::Database { operation, source } => {
                log::error!("Database error in {}: {:?}", operation, source);
            }
            C5hError::Io { operation, source } => {
                log::error!("IO error in {}: {:?}", operation, source);
            }
            C5hError::Cli { tool, detail } => {
                log::error!("CLI error for {}: {}", tool, detail);
            }
            _ => {}
        }
        // Return user-friendly message
        err.to_string()
    }
}

/// Helper to convert sqlx errors with context
pub fn db_err(operation: &'static str) -> impl FnOnce(sqlx::Error) -> String {
    move |e| {
        let err = C5hError::Database {
            operation,
            source: e,
        };
        String::from(err)
    }
}
