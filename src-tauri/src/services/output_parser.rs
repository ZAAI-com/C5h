use regex::Regex;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UsageInfo {
    pub session_percent: Option<f32>,
    pub weekly_percent: Option<f32>,
    pub reset_time: Option<String>,
    pub weekly_reset_time: Option<String>,
}

impl Default for UsageInfo {
    fn default() -> Self {
        Self {
            session_percent: None,
            weekly_percent: None,
            reset_time: None,
            weekly_reset_time: None,
        }
    }
}

/// Parse Claude Code /usage output
/// Example:
/// ```
/// Current session
/// █████████████████████████████████████▌             75% used
/// Resets 1:59am (Europe/Berlin)
///
/// Current week (all models)
/// ██████████████████████▌                            45% used
/// Resets Jan 22 at 10:59am (Europe/Berlin)
/// ```
pub fn parse_claude_output(output: &str) -> UsageInfo {
    let mut info = UsageInfo::default();

    // Parse session percentage: "75% used"
    // Use (?s) for dotall mode to match across newlines
    let session_regex = Regex::new(r"(?s)Current session.*?(\d+)%\s+used").unwrap();
    if let Some(cap) = session_regex.captures(output) {
        if let Some(percent_str) = cap.get(1) {
            info.session_percent = percent_str.as_str().parse::<f32>().ok();
        }
    }

    // Parse session reset time: "Resets 1:59am (Europe/Berlin)"
    let reset_regex = Regex::new(r"(?s)Current session.*?Resets\s+(\d+:\d+[ap]m)").unwrap();
    if let Some(cap) = reset_regex.captures(output) {
        if let Some(time_str) = cap.get(1) {
            info.reset_time = Some(time_str.as_str().to_string());
        }
    }

    // Parse weekly percentage: "45% used"
    let weekly_regex = Regex::new(r"(?s)Current week.*?(\d+)%\s+used").unwrap();
    if let Some(cap) = weekly_regex.captures(output) {
        if let Some(percent_str) = cap.get(1) {
            info.weekly_percent = percent_str.as_str().parse::<f32>().ok();
        }
    }

    // Parse weekly reset time: "Resets Jan 22 at 10:59am"
    let weekly_reset_regex =
        Regex::new(r"(?s)Current week.*?Resets\s+([A-Za-z]+\s+\d+\s+at\s+\d+:\d+[ap]m)").unwrap();
    if let Some(cap) = weekly_reset_regex.captures(output) {
        if let Some(time_str) = cap.get(1) {
            info.weekly_reset_time = Some(time_str.as_str().to_string());
        }
    }

    info
}

/// Parse Codex /status output
/// Example:
/// ```
/// │  5h limit:       [████████████████████] 100% left (resets 06:44)          │
/// │  Weekly limit:   [████████████████████] 99% left (resets 19:51 on 24 Jan) │
/// ```
pub fn parse_codex_output(output: &str) -> UsageInfo {
    let mut info = UsageInfo::default();

    // Parse 5h limit: "100% left" -> convert to "0% used"
    let session_regex = Regex::new(r"5h limit:.*?(\d+)%\s+left").unwrap();
    if let Some(cap) = session_regex.captures(output) {
        if let Some(percent_str) = cap.get(1) {
            if let Ok(left_percent) = percent_str.as_str().parse::<f32>() {
                info.session_percent = Some(100.0 - left_percent);
            }
        }
    }

    // Parse 5h reset time: "(resets 06:44)"
    let reset_regex = Regex::new(r"5h limit:.*?resets\s+(\d+:\d+)").unwrap();
    if let Some(cap) = reset_regex.captures(output) {
        if let Some(time_str) = cap.get(1) {
            info.reset_time = Some(time_str.as_str().to_string());
        }
    }

    // Parse weekly limit: "99% left" -> convert to "1% used"
    let weekly_regex = Regex::new(r"Weekly limit:.*?(\d+)%\s+left").unwrap();
    if let Some(cap) = weekly_regex.captures(output) {
        if let Some(percent_str) = cap.get(1) {
            if let Ok(left_percent) = percent_str.as_str().parse::<f32>() {
                info.weekly_percent = Some(100.0 - left_percent);
            }
        }
    }

    // Parse weekly reset time: "(resets 19:51 on 24 Jan)"
    let weekly_reset_regex =
        Regex::new(r"Weekly limit:.*?resets\s+(\d+:\d+\s+on\s+\d+\s+[A-Za-z]+)").unwrap();
    if let Some(cap) = weekly_reset_regex.captures(output) {
        if let Some(time_str) = cap.get(1) {
            info.weekly_reset_time = Some(time_str.as_str().to_string());
        }
    }

    info
}

/// Parse Gemini usage table output
/// Example:
/// ```
/// │  Model Usage                 Reqs                  Usage left              │
/// │  gemini-2.5-flash               -       99.9% (Resets in 24h)              │
/// ```
pub fn parse_gemini_output(output: &str) -> UsageInfo {
    let mut info = UsageInfo::default();

    // Parse usage percentage: "99.9% (Resets in 24h)" -> convert to used
    let usage_regex = Regex::new(r"gemini-[\w.-]+\s+[\d-]+\s+([\d.]+)%").unwrap();
    if let Some(cap) = usage_regex.captures(output) {
        if let Some(percent_str) = cap.get(1) {
            if let Ok(left_percent) = percent_str.as_str().parse::<f32>() {
                // Gemini shows "left" percentage, convert to "used"
                info.session_percent = Some(100.0 - left_percent);
            }
        }
    }

    // Parse reset time: "(Resets in 24h)"
    let reset_regex = Regex::new(r"Resets in (\d+h)").unwrap();
    if let Some(cap) = reset_regex.captures(output) {
        if let Some(time_str) = cap.get(1) {
            info.reset_time = Some(time_str.as_str().to_string());
        }
    }

    info
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_claude_output() {
        let output = r#"
Current session
█████████████████████████████████████▌             75% used
Resets 1:59am (Europe/Berlin)

Current week (all models)
██████████████████████▌                            45% used
Resets Jan 22 at 10:59am (Europe/Berlin)
"#;

        let info = parse_claude_output(output);
        assert_eq!(info.session_percent, Some(75.0));
        assert_eq!(info.reset_time, Some("1:59am".to_string()));
        assert_eq!(info.weekly_percent, Some(45.0));
        assert_eq!(
            info.weekly_reset_time,
            Some("Jan 22 at 10:59am".to_string())
        );
    }

    #[test]
    fn test_parse_codex_output() {
        let output = r#"
│  5h limit:       [████████████████████] 100% left (resets 06:44)          │
│  Weekly limit:   [████████████████████] 99% left (resets 19:51 on 24 Jan) │
"#;

        let info = parse_codex_output(output);
        assert_eq!(info.session_percent, Some(0.0));
        assert_eq!(info.reset_time, Some("06:44".to_string()));
        assert_eq!(info.weekly_percent, Some(1.0));
        assert_eq!(
            info.weekly_reset_time,
            Some("19:51 on 24 Jan".to_string())
        );
    }

    #[test]
    fn test_parse_gemini_output() {
        let output = r#"
│  Model Usage                 Reqs                  Usage left              │
│  gemini-2.5-flash               -       99.9% (Resets in 24h)              │
"#;

        let info = parse_gemini_output(output);
        // Use approximate comparison for floating point
        if let Some(percent) = info.session_percent {
            assert!((percent - 0.1).abs() < 0.01, "Expected ~0.1, got {}", percent);
        } else {
            panic!("Expected Some(0.1), got None");
        }
        assert_eq!(info.reset_time, Some("24h".to_string()));
    }
}
