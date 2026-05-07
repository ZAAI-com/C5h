export function localDateTimeToOffsetRfc3339(
  dateValue: string,
  timeValue: string
): string {
  const [year, month, day] = dateValue.split("-").map(Number);
  const [hour, minute] = timeValue.split(":").map(Number);
  const localDate = new Date(year, month - 1, day, hour, minute, 0, 0);

  const offsetMinutes = -localDate.getTimezoneOffset();
  const sign = offsetMinutes >= 0 ? "+" : "-";
  const absoluteOffsetMinutes = Math.abs(offsetMinutes);
  const offsetHours = String(Math.floor(absoluteOffsetMinutes / 60)).padStart(2, "0");
  const offsetRemainderMinutes = String(absoluteOffsetMinutes % 60).padStart(2, "0");

  return [
    `${year.toString().padStart(4, "0")}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`,
    `T${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}:00`,
    `${sign}${offsetHours}:${offsetRemainderMinutes}`,
  ].join("");
}
