import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import {
  AppError,
  formatDateForApi,
  getAccounts,
  getWindows,
  getWeekBoundaries,
  pollAllAccounts,
} from "./api";

const mockInvoke = vi.mocked(invoke);

describe("API helpers", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useRealTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("wraps string IPC failures in AppError", async () => {
    mockInvoke.mockRejectedValueOnce("Failed to fetch accounts");

    const error = await getAccounts().catch((err) => err);

    expect(error).toBeInstanceOf(AppError);
    expect(error).toMatchObject({
      code: "ipc",
      message: "Failed to fetch accounts",
    });
  });

  it("wraps Error IPC failures in AppError", async () => {
    mockInvoke.mockRejectedValueOnce(new Error("Boom"));

    const error = await getAccounts().catch((err) => err);

    expect(error).toBeInstanceOf(AppError);
    expect(error).toMatchObject({
      code: "ipc",
      message: "Boom",
    });
  });

  it("rejects immediately for pre-aborted signals", async () => {
    const controller = new AbortController();
    controller.abort();

    const error = await getWindows("2024-01-01", "2024-01-07", 1, {
      signal: controller.signal,
    }).catch((err) => err);

    expect(error).toBeInstanceOf(AppError);
    expect(error).toMatchObject({
      code: "aborted",
      message: "Request was cancelled",
    });
    expect(mockInvoke).not.toHaveBeenCalled();
  });

  it("rejects when a request is aborted mid-flight", async () => {
    mockInvoke.mockImplementationOnce(() => new Promise(() => {}));
    const controller = new AbortController();

    const request = getWindows("2024-01-01", "2024-01-07", 1, {
      signal: controller.signal,
    });

    controller.abort();

    const error = await request.catch((err) => err);

    expect(error).toBeInstanceOf(AppError);
    expect(error).toMatchObject({
      code: "aborted",
      message: "Request was cancelled",
    });
    expect(mockInvoke).toHaveBeenCalledWith("get_windows", {
      from: "2024-01-01",
      to: "2024-01-07",
      accountId: 1,
    });
  });

  it("times out hung IPC requests", async () => {
    vi.useFakeTimers();
    mockInvoke.mockImplementationOnce(() => new Promise(() => {}));

    const request = pollAllAccounts({ timeoutMs: 25 }).catch((err) => err);
    await vi.advanceTimersByTimeAsync(25);
    const error = await request;

    expect(error).toBeInstanceOf(AppError);
    expect(error).toMatchObject({
      code: "timeout",
      message: "Request timed out",
      details: { cmd: "poll_all_accounts", timeoutMs: 25 },
    });
  });

  it("passes getWindows args unchanged when options are provided", async () => {
    mockInvoke.mockResolvedValueOnce([]);

    await getWindows("2024-01-01", "2024-01-07", 42, { timeoutMs: 5000 });

    expect(mockInvoke).toHaveBeenCalledWith("get_windows", {
      from: "2024-01-01",
      to: "2024-01-07",
      accountId: 42,
    });
  });

  it("passes pollAllAccounts with no IPC args when options are provided", async () => {
    mockInvoke.mockResolvedValueOnce([]);

    await pollAllAccounts({ timeoutMs: 5000 });

    expect(mockInvoke).toHaveBeenCalledWith("poll_all_accounts");
  });
});

describe("formatDateForApi", () => {
  it("returns ISO 8601 string", () => {
    const date = new Date("2024-01-15T12:34:56.789Z");
    expect(formatDateForApi(date)).toBe("2024-01-15T12:34:56.789Z");
  });

  it("preserves UTC time", () => {
    const date = new Date(Date.UTC(2024, 5, 15, 10, 30, 0, 0));
    expect(formatDateForApi(date)).toBe("2024-06-15T10:30:00.000Z");
  });
});

describe("getWeekBoundaries", () => {
  it("returns Sunday 00:00:00.000 as start when input is mid-week", () => {
    const wednesday = new Date(2024, 0, 17, 14, 30);
    const { start } = getWeekBoundaries(wednesday);
    const startDate = new Date(start);
    expect(startDate.getDay()).toBe(0);
    expect(startDate.getHours()).toBe(0);
    expect(startDate.getMinutes()).toBe(0);
    expect(startDate.getSeconds()).toBe(0);
    expect(startDate.getMilliseconds()).toBe(0);
  });

  it("returns Saturday 23:59:59.999 as end", () => {
    const wednesday = new Date(2024, 0, 17, 14, 30);
    const { end } = getWeekBoundaries(wednesday);
    const endDate = new Date(end);
    expect(endDate.getDay()).toBe(6);
    expect(endDate.getHours()).toBe(23);
    expect(endDate.getMinutes()).toBe(59);
    expect(endDate.getSeconds()).toBe(59);
    expect(endDate.getMilliseconds()).toBe(999);
  });

  it("end is six days after start", () => {
    const date = new Date(2024, 2, 13);
    const { start, end } = getWeekBoundaries(date);
    const startDate = new Date(start);
    const endDate = new Date(end);
    const diffDays = Math.floor(
      (endDate.getTime() - startDate.getTime()) / (1000 * 60 * 60 * 24)
    );
    expect(diffDays).toBe(6);
  });

  it("returns same date as start when input is already Sunday at midnight", () => {
    const sunday = new Date(2024, 0, 14, 0, 0, 0, 0);
    const { start } = getWeekBoundaries(sunday);
    expect(new Date(start).getTime()).toBe(sunday.getTime());
  });

  it("does not mutate input date", () => {
    const original = new Date(2024, 0, 17, 14, 30);
    const snapshot = original.getTime();
    getWeekBoundaries(original);
    expect(original.getTime()).toBe(snapshot);
  });
});
