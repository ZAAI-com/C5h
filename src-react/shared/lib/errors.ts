/**
 * Maps raw backend error strings to user-friendly messages with recovery hints.
 */

const ERROR_MAP: Record<string, string> = {
  "Failed to fetch accounts":
    "Could not load your accounts. Please restart the app.",
  "Failed to create account":
    "Could not create the account. Please check your inputs and try again.",
  "Failed to update account":
    "Could not save account changes. Please try again.",
  "Failed to delete account":
    "Could not delete the account. It may have active windows.",
  "Failed to fetch windows":
    "Could not load usage windows. Please try refreshing.",
  "Failed to fetch current window":
    "Could not check your current window status.",
  "Failed to create window":
    "Could not start a new window. Please try again.",
  "Failed to end window": "Could not end the window. Please try again.",
  "Failed to fetch settings":
    "Could not load your settings. Default values will be used.",
  "Failed to save settings":
    "Could not save settings. Please try again.",
  "Failed to fetch schedules":
    "Could not load your schedules. Please try refreshing.",
  "Failed to create schedule":
    "Could not create the schedule. Please check the date and try again.",
  "Failed to delete schedule":
    "Could not remove the schedule. Please try again.",
  "Failed to install schedule":
    "Could not install the schedule to launchd. Check that the CLI path is valid.",
  "Failed to update schedule with plist path":
    "Schedule was installed but could not update the record.",
  "Database connection not initialized. Please restart the application.":
    "The database is not available. Please restart C5h.",
  "HOME environment variable not set. Cannot locate LaunchAgents directory.":
    "Could not find your home directory. Please check your system configuration.",
};

/**
 * Convert a raw error string from the backend into a user-friendly message.
 * Falls through to the original message if no mapping exists.
 */
export function mapError(raw: string): string {
  // Check exact matches first
  if (ERROR_MAP[raw]) return ERROR_MAP[raw];

  // Check partial matches for validation errors (already user-friendly)
  if (
    raw.startsWith("CLI command") ||
    raw.startsWith("Account name") ||
    raw.startsWith("Window duration") ||
    raw.startsWith("Color must") ||
    raw.startsWith("Poll interval") ||
    raw.startsWith("Usage percentage") ||
    raw.startsWith("Scheduled time") ||
    raw.startsWith("Invalid datetime")
  ) {
    return raw;
  }

  // Fallback: return the original
  return raw;
}
