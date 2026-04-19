/**
 * Add `months` to `date` without overflowing into the next month when the
 * source day is greater than the target month's last day. e.g.
 *   addMonthsSafe(Jan 31, 1) === Feb 28/29 (last day of Feb), not Mar 3.
 */
export function addMonthsSafe(date: Date, months: number): Date {
  const d = new Date(date.getTime());
  const startMonth = d.getMonth();
  d.setMonth(startMonth + months);
  const expectedMonth = (((startMonth + months) % 12) + 12) % 12;
  if (d.getMonth() !== expectedMonth) {
    // We rolled into a subsequent month — clamp to the last day of the
    // intended month by going back to day 0 (last day of previous month).
    d.setDate(0);
  }
  return d;
}
