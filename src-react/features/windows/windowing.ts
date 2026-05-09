import type { Account, Window } from "@/shared/types/types";

const DEFAULT_WINDOW_DURATION_HOURS = 5;

export function getWindowDurationHours(account?: Pick<Account, "window_duration_hours"> | null): number {
  return account?.window_duration_hours ?? DEFAULT_WINDOW_DURATION_HOURS;
}

export function getEffectiveWindowEnd(
  window: Pick<Window, "started_at" | "ended_at">,
  account?: Pick<Account, "window_duration_hours"> | null
): Date {
  if (window.ended_at) {
    return new Date(window.ended_at);
  }

  const startedAt = new Date(window.started_at);
  return new Date(
    startedAt.getTime() + getWindowDurationHours(account) * 60 * 60 * 1000
  );
}

export function getWindowDurationHoursByAccountId(
  accounts: Account[],
  accountId: number
): number {
  return getWindowDurationHours(accounts.find((account) => account.id === accountId));
}

export function getWindowDurationInHours(
  window: Pick<Window, "started_at" | "ended_at">,
  account?: Pick<Account, "window_duration_hours"> | null
): number {
  const startedAt = new Date(window.started_at);
  const endedAt = getEffectiveWindowEnd(window, account);
  return (endedAt.getTime() - startedAt.getTime()) / (1000 * 60 * 60);
}
