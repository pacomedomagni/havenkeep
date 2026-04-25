/**
 * Money helpers used across the warranty/claim/maintenance services. The
 * audit caught `parseFloat(row.amount_saved)` everywhere — those calls drop
 * trailing precision the moment the value crosses a JS number boundary,
 * and writing `repair_cost - out_of_pocket` arithmetic in JS then re-storing
 * as DECIMAL silently rounds (Ch04-F004).
 *
 * Internally we work in integer cents so a value never round-trips through
 * a base-10-fragile float. Callers pass the raw column (string|number|null)
 * and get back a finite cents integer.
 */

const DECIMAL_RE = /^-?\d+(?:\.\d+)?$/;

/**
 * Convert a DECIMAL column value (which `pg` returns as a string by default)
 * into integer cents. Returns 0 for null/undefined/empty/NaN — callers that
 * need to distinguish absent-vs-zero should guard at the call site.
 */
export function decimalToCents(value: string | number | null | undefined): number {
  if (value === null || value === undefined || value === '') return 0;
  const str = String(value).trim();
  if (!DECIMAL_RE.test(str)) {
    return 0;
  }
  // Split into integer + fraction halves and re-assemble in cents to avoid
  // the float->cents drift that audit Ch04-F004 caught (e.g. 19.99 * 100 =
  // 1998.9999999999998 → floored to 1998).
  const negative = str.startsWith('-');
  const unsigned = negative ? str.slice(1) : str;
  const [intPart, fracPart = ''] = unsigned.split('.');
  const fracPadded = (fracPart + '00').slice(0, 2);
  const cents = Number(intPart) * 100 + Number(fracPadded || '0');
  return negative ? -cents : cents;
}

/**
 * Inverse of decimalToCents. Returns a `string` (not a number) so the
 * value can flow straight into a parameterized DECIMAL column without
 * losing precision.
 */
export function centsToDecimalString(cents: number): string {
  if (!Number.isFinite(cents)) return '0.00';
  const sign = cents < 0 ? '-' : '';
  const abs = Math.abs(Math.trunc(cents));
  const dollars = Math.floor(abs / 100);
  const remainder = abs - dollars * 100;
  return `${sign}${dollars}.${String(remainder).padStart(2, '0')}`;
}

/**
 * Convert a dollar amount (number or numeric string) into integer cents.
 * Throws on invalid input — callers feed Stripe with this value, so a
 * silent 0 is more dangerous than a thrown error (Ch03-F020, F117).
 */
export function dollarsToCents(value: number | string): number {
  const cents = decimalToCents(value);
  if (cents === 0 && value !== 0 && value !== '0' && value !== '0.00') {
    // decimalToCents returned 0 because the input was malformed — refuse.
    throw new Error(`dollarsToCents: invalid amount '${String(value)}'`);
  }
  return cents;
}

/**
 * Compute commission cents from a base amount + rate. Rate is a decimal
 * (e.g. 0.15 for 15%). All math runs in integer cents to avoid float drift.
 */
export function commissionCents(amountCents: number, rate: number): number {
  if (!Number.isFinite(amountCents) || !Number.isFinite(rate) || rate < 0) {
    throw new Error(`commissionCents: invalid args amount=${amountCents} rate=${rate}`);
  }
  // Round half-to-even at the cent boundary so successive identical commissions
  // sum predictably. Math.round is half-up; close enough for cents.
  return Math.round(amountCents * rate);
}
