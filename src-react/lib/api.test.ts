import { describe, expect, it } from "vitest";
import { formatDateForApi, getWeekBoundaries } from "./api";

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
    // 2024-01-17 is a Wednesday. Sunday of that week is 2024-01-14.
    const wednesday = new Date(2024, 0, 17, 14, 30);
    const { start } = getWeekBoundaries(wednesday);
    const startDate = new Date(start);
    expect(startDate.getDay()).toBe(0); // Sunday
    expect(startDate.getHours()).toBe(0);
    expect(startDate.getMinutes()).toBe(0);
    expect(startDate.getSeconds()).toBe(0);
    expect(startDate.getMilliseconds()).toBe(0);
  });

  it("returns Saturday 23:59:59.999 as end", () => {
    const wednesday = new Date(2024, 0, 17, 14, 30);
    const { end } = getWeekBoundaries(wednesday);
    const endDate = new Date(end);
    expect(endDate.getDay()).toBe(6); // Saturday
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
    expect(diffDays).toBe(6); // 6 days, 23:59:59.999
  });

  it("returns same date as start when input is already Sunday at midnight", () => {
    // 2024-01-14 is a Sunday at local midnight
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
