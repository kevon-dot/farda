import { describe, expect, it } from 'vitest';
import { inspectRuntime } from '../scripts/runtime-readiness';
import { revenueCatActivationReady } from '../src/common/activation';
import { stripeActivationReady } from '../src/billing/catalog';
import { completeProviderTestEnv } from './helpers/provider-env';

describe('database test provider environment', () => {
  it('stays compatible with every fail-closed local activation gate', () => {
    expect(stripeActivationReady(completeProviderTestEnv)).toBe(true);
    expect(revenueCatActivationReady(completeProviderTestEnv)).toBe(true);
    expect(inspectRuntime(completeProviderTestEnv).filter(check => check.status !== 'pass')).toEqual([]);
  });
});
