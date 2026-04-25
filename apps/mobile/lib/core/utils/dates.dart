import 'dart:math' as math;

/// Add [months] to [date], clamping the day-of-month so we never silently
/// roll over into the next month (e.g. Jan 31 + 1 month -> Feb 28/29, not
/// Mar 3).
DateTime addMonthsSafe(DateTime date, int months) {
  // Compute target year/month with proper handling of negatives.
  final totalMonths = date.month - 1 + months;
  final targetYear = date.year + (totalMonths ~/ 12);
  final targetMonth = (totalMonths % 12) + 1;
  // The 0th day of the next month is the last day of `targetMonth`.
  final lastDay = DateTime(targetYear, targetMonth + 1, 0).day;
  return DateTime(targetYear, targetMonth, math.min(date.day, lastDay));
}
