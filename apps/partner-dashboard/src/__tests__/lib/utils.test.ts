import { describe, it, expect } from 'vitest';
import { formatCurrency } from '@/lib/utils';

describe('formatCurrency', () => {
  it('formats a typical dollar amount', () => {
    expect(formatCurrency(1234.56)).toBe('$1,234.56');
  });

  it('formats zero as $0.00', () => {
    expect(formatCurrency(0)).toBe('$0.00');
  });

  it('formats negative numbers with a minus sign', () => {
    const result = formatCurrency(-49.99);
    // Intl.NumberFormat may use a minus sign or a Unicode minus (U+2212)
    expect(result).toMatch(/^-\$49\.99$/);
  });

  it('rounds to two decimal places', () => {
    expect(formatCurrency(9.999)).toBe('$10.00');
  });

  it('formats large numbers with comma grouping', () => {
    expect(formatCurrency(1000000)).toBe('$1,000,000.00');
  });

  it('formats small fractional amounts', () => {
    expect(formatCurrency(0.5)).toBe('$0.50');
  });

  // Audit Ch10-W036: formatCurrency now falls back to "$0.00" rather than
  // surfacing "NaN" — DECIMAL columns can serialize as empty strings on a
  // 5xx upstream and the prior NaN string leaked into KPI cards.
  it('handles NaN gracefully (returns $0.00)', () => {
    expect(formatCurrency(NaN)).toBe('$0.00');
  });

  it('accepts string inputs (DECIMAL wire shape)', () => {
    expect(formatCurrency('1234.56')).toBe('$1,234.56');
    expect(formatCurrency('')).toBe('$0.00');
    expect(formatCurrency('not-a-number')).toBe('$0.00');
  });
});
