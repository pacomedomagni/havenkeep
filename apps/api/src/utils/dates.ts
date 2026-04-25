/**
 * Add `months` to `date` without overflowing into the next month when the
 * source day is greater than the target month's last day.  Uses UTC accessors
 * everywhere so a server in a non-UTC zone never ticks the wrong day across
 * a DST boundary (audit Ch11-I080).
 *
 *   addMonthsSafe(Jan 31, 1)         → Feb 28/29 (last day of Feb)
 *   addMonthsSafe(Jan 31, -1)        → Dec 31 (negative supported, Ch11-I082)
 *   addMonthsSafe(Feb 29 (leap), 12) → Feb 28 (leap edge, Ch11-I083)
 */
export function addMonthsSafe(date: Date, months: number): Date {
  if (!Number.isFinite(months)) {
    throw new TypeError(`addMonthsSafe: months must be finite, got ${months}`);
  }
  if (!Number.isInteger(months)) {
    // Audit Ch11-I081: a fractional months value would be silently floored
    // by setUTCMonth(); explicitly reject so callers can't pass `1.5` and
    // expect six weeks of coverage.
    throw new TypeError(`addMonthsSafe: months must be an integer, got ${months}`);
  }

  const year = date.getUTCFullYear();
  const month = date.getUTCMonth();
  const day = date.getUTCDate();

  const targetMonthAbs = month + months;          // can be negative or >11
  const targetYear = year + Math.floor(targetMonthAbs / 12);
  const targetMonth = ((targetMonthAbs % 12) + 12) % 12;

  // Day 0 of the next month = last day of the target month, at 00:00 UTC.
  const lastDayOfTargetMonth = new Date(Date.UTC(targetYear, targetMonth + 1, 0)).getUTCDate();
  const safeDay = Math.min(day, lastDayOfTargetMonth);

  return new Date(Date.UTC(
    targetYear,
    targetMonth,
    safeDay,
    date.getUTCHours(),
    date.getUTCMinutes(),
    date.getUTCSeconds(),
    date.getUTCMilliseconds(),
  ));
}
