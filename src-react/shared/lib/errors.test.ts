import { describe, expect, it } from "vitest";
import { mapError } from "./errors";

describe("mapError", () => {
  it("maps known backend error to friendly message", () => {
    expect(mapError("Failed to fetch accounts")).toBe(
      "Could not load your accounts. Please restart the app."
    );
  });

  it("maps database init error", () => {
    expect(
      mapError("Database connection not initialized. Please restart the application.")
    ).toBe("The database is not available. Please restart C5h.");
  });

  it("maps HOME env error", () => {
    expect(
      mapError("HOME environment variable not set. Cannot locate LaunchAgents directory.")
    ).toBe("Could not find your home directory. Please check your system configuration.");
  });

  it("passes through CLI command validation errors", () => {
    const msg = "CLI command must not contain shell metacharacters";
    expect(mapError(msg)).toBe(msg);
  });

  it("passes through Account name validation errors", () => {
    const msg = "Account name cannot be empty";
    expect(mapError(msg)).toBe(msg);
  });

  it("passes through Window duration validation errors", () => {
    const msg = "Window duration must be between 1 and 168 hours";
    expect(mapError(msg)).toBe(msg);
  });

  it("passes through Color validation errors", () => {
    const msg = "Color must be a valid hex code";
    expect(mapError(msg)).toBe(msg);
  });

  it("passes through Poll interval validation errors", () => {
    const msg = "Poll interval must be between 1 and 60 minutes";
    expect(mapError(msg)).toBe(msg);
  });

  it("passes through Usage percentage validation errors", () => {
    const msg = "Usage percentage must be between 0 and 100";
    expect(mapError(msg)).toBe(msg);
  });

  it("passes through Scheduled time validation errors", () => {
    const msg = "Scheduled time must be in the future";
    expect(mapError(msg)).toBe(msg);
  });

  it("passes through Invalid datetime errors", () => {
    const msg = "Invalid datetime format: not-a-date";
    expect(mapError(msg)).toBe(msg);
  });

  it("falls through unknown messages unchanged", () => {
    const msg = "Some completely unknown error from a third party";
    expect(mapError(msg)).toBe(msg);
  });

  it("handles empty string", () => {
    expect(mapError("")).toBe("");
  });
});
