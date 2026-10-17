import { afterEach, describe, expect, it, vi } from 'vitest';
import { PhotonRefillsProvider } from '../src/refills/providers/photon';

const saved = { ...process.env };

async function runtimeConfig(environment?: string) {
  Object.assign(process.env, {
    FARDA_REFILL_PROVIDER_ENABLED: 'true',
    PHOTON_CLIENT_ID: 'runtime-client',
    PHOTON_CLIENT_SECRET: 'runtime-secret',
  });
  if (environment === undefined) delete process.env.FARDA_REFILL_PROVIDER_ENVIRONMENT;
  else process.env.FARDA_REFILL_PROVIDER_ENVIRONMENT = environment;
  vi.resetModules();
  return (await import('../src/common/constants/env')).default;
}

afterEach(() => {
  process.env = { ...saved };
  vi.resetModules();
});

describe('Photon runtime configuration', () => {
  it.each([undefined, 'staging'])('keeps an enabled provider unconfigured for environment %s', async environment => {
    const runtime = await runtimeConfig(environment);
    const fetcher = vi.fn<typeof fetch>();
    const provider = new PhotonRefillsProvider({
      enabled: runtime.FARDA_REFILL_PROVIDER_ENABLED,
      environment: runtime.FARDA_REFILL_PROVIDER_ENVIRONMENT,
      clientId: runtime.PHOTON_CLIENT_ID,
      clientSecret: runtime.PHOTON_CLIENT_SECRET,
    }, fetcher);

    expect(runtime.FARDA_REFILL_PROVIDER_ENABLED).toBe(false);
    expect(runtime.FARDA_REFILL_PROVIDER_ENVIRONMENT).toBeUndefined();
    expect(provider.configured).toBe(false);
    await expect(provider.getOrder('synthetic-order')).rejects.toMatchObject({ code: 'provider_unavailable' });
    expect(fetcher).not.toHaveBeenCalled();
  });

  it('configures only with an explicit recognized environment and distinct credentials', async () => {
    const runtime = await runtimeConfig('sandbox');
    const provider = new PhotonRefillsProvider({
      enabled: runtime.FARDA_REFILL_PROVIDER_ENABLED,
      environment: runtime.FARDA_REFILL_PROVIDER_ENVIRONMENT,
      clientId: runtime.PHOTON_CLIENT_ID,
      clientSecret: runtime.PHOTON_CLIENT_SECRET,
    });

    expect(runtime.FARDA_REFILL_PROVIDER_ENABLED).toBe(true);
    expect(runtime.FARDA_REFILL_PROVIDER_ENVIRONMENT).toBe('sandbox');
    expect(provider.configured).toBe(true);
  });
});
