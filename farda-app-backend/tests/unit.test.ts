import { describe, it, expect } from 'vitest';

import { getRandomInt } from '@src/common/utils/number-utils';
import { transformIsDate } from '@src/common/utils/validators';

/**
 * Self-contained unit tests for pure helpers. These intentionally avoid the
 * database, the Express app, and any external service so the suite is
 * deterministic and runs in CI without credentials.
 */

describe('number-utils.getRandomInt', () => {
  it('returns an integer within the documented range', () => {
    for (let i = 0; i < 100; i++) {
      const n = getRandomInt();
      expect(Number.isInteger(n)).toBe(true);
      expect(n).toBeGreaterThanOrEqual(0);
      expect(n).toBeLessThan(1_000_000_000_000);
    }
  });
});

describe('validators.transformIsDate', () => {
  it('parses an ISO date string into a Date', () => {
    const parsed = transformIsDate.parse('2026-01-22T12:36:45Z');
    expect(parsed).toBeInstanceOf(Date);
    expect(parsed.getUTCFullYear()).toBe(2026);
  });

  it('accepts an existing Date instance', () => {
    const d = new Date('2026-06-27');
    expect(transformIsDate.parse(d)).toBeInstanceOf(Date);
  });

  it('rejects an invalid date string', () => {
    expect(() => transformIsDate.parse('not-a-date')).toThrow();
  });
});
