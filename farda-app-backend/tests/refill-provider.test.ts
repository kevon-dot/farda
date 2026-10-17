import { afterEach, describe, expect, it, vi } from 'vitest';
import { PhotonRefillsProvider } from '@src/refills/providers/photon';

const config = { enabled: true, environment: 'sandbox' as const, clientId: 'test-client', clientSecret: 'test-secret' };
const address = { street1: '123 Test St', postalCode: '11111', country: 'USA', state: 'NY', city: 'Test' };
const input = { externalId: 'request-1', patientId: 'pat-1', prescriptionId: 'rx-1', pharmacyId: 'phr-1', address };
const rawOrder = { id: 'ord-1', externalId: 'request-1', state: 'ROUTING', patient: { id: 'pat-1' }, pharmacy: { id: 'phr-1' },
  fills: [{ prescription: { id: 'rx-1' } }], fulfillment: null };
const rawLink = { patient: { id: 'pat-1', externalId: 'user-1', address },
  prescription: { id: 'rx-1', patient: { id: 'pat-1' }, state: 'ACTIVE', fillsRemaining: 2,
    effectiveDate: '2026-01-01', expirationDate: '2027-01-01', instructions: 'Printed instructions', treatment: { name: 'Example medicine 5 mg' } },
  pharmacy: { id: 'phr-1', name: 'Example Pharmacy' } };
const linkInput = { userId: 'user-1', patientId: 'pat-1', prescriptionId: 'rx-1', pharmacyId: 'phr-1' };
const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json' } });
const token = () => json({ access_token: 'test-token', token_type: 'Bearer', expires_in: 3600 });
const now = () => Date.parse('2026-10-16T12:00:00Z');
const fake = () => vi.fn<typeof fetch>().mockResolvedValueOnce(token());

afterEach(() => { vi.useRealTimers(); });

describe('Photon documented refill provider contract', () => {
  it('is disabled by default and does no networking', async () => {
    const fetcher = fake();
    const provider = new PhotonRefillsProvider({}, fetcher);
    expect(provider.configured).toBe(false);
    expect(provider.capabilities).toEqual({
      verifyEligibility: true, submitOrders: true,
      lookupOrders: true, reconcileUnknownOutcomes: true,
    });
    await expect(provider.submitOrder(input)).rejects.toMatchObject({ code: 'provider_unavailable', outcome: 'not_submitted' });
    expect(fetcher).not.toHaveBeenCalled();
  });

  it.each([undefined, 'staging'])('requires an explicit recognized environment before networking: %s', async environment => {
    const fetcher = fake();
    const provider = new PhotonRefillsProvider({
      enabled: true, environment: environment as 'sandbox' | undefined,
      clientId: 'test-client', clientSecret: 'test-secret',
    }, fetcher);
    expect(provider.configured).toBe(false);
    await expect(provider.submitOrder(input)).rejects.toMatchObject({ code: 'provider_unavailable', outcome: 'not_submitted' });
    expect(fetcher).not.toHaveBeenCalled();
  });

  it.each(['sandbox', 'production'] as const)('uses only fixed %s auth/API endpoints and the documented createOrder shape', async environment => {
    const fetcher = fake().mockResolvedValueOnce(json({ data: { createOrder: rawOrder } }));
    const provider = new PhotonRefillsProvider({ ...config, environment }, fetcher);
    const result = await provider.submitOrder(input);
    const domain = environment === 'sandbox' ? 'neutron' : 'photon';
    expect(fetcher.mock.calls[0][0]).toBe(`https://auth.${domain}.health/oauth/token`);
    expect(JSON.parse(fetcher.mock.calls[0][1]!.body as string)).toEqual({
      client_id: 'test-client', client_secret: 'test-secret', audience: `https://api.${domain}.health`, grant_type: 'client_credentials',
    });
    expect(fetcher.mock.calls[1][0]).toBe(`https://api.${domain}.health/graphql`);
    const request = fetcher.mock.calls[1][1]!;
    expect(request.redirect).toBe('error');
    expect(request.headers).toMatchObject({ authorization: 'Bearer test-token' });
    const body = JSON.parse(request.body as string);
    expect(body.query).toContain('$fills: [FillInput!]!');
    expect(body.variables).toEqual({ externalId: 'request-1', patientId: 'pat-1', fills: [{ prescriptionId: 'rx-1' }], pharmacyId: 'phr-1', address });
    expect(result).toMatchObject({ id: 'ord-1', patientId: 'pat-1', prescriptionIds: ['rx-1'], orderState: 'ROUTING', fulfillmentState: null });
  });

  it('verifies external patient ownership, prescription relation, active fill and address before returning provider facts', async () => {
    const fetcher = fake().mockResolvedValueOnce(json({ data: rawLink }));
    const provider = new PhotonRefillsProvider(config, fetcher, now);
    await expect(provider.verifyLink(linkInput)).resolves.toMatchObject({ medicationName: 'Example medicine 5 mg', fillsRemaining: 2, pharmacyName: 'Example Pharmacy', address });
    const request = JSON.parse(fetcher.mock.calls[1][1]!.body as string);
    expect(request.variables).toEqual({ patientId: 'pat-1', prescriptionId: 'rx-1', pharmacyId: 'phr-1' });
    expect(request.query).not.toContain('dateOfBirth');
  });

  it.each([
    { ...rawLink, patient: { ...rawLink.patient, externalId: 'another-user' } },
    { ...rawLink, prescription: { ...rawLink.prescription, patient: { id: 'another-patient' } } },
    { ...rawLink, pharmacy: { ...rawLink.pharmacy, id: 'another-pharmacy' } },
  ])('rejects mismatched trusted mapping without mutation', async data => {
    const fetcher = fake().mockResolvedValueOnce(json({ data }));
    await expect(new PhotonRefillsProvider(config, fetcher, now).verifyLink(linkInput)).rejects.toMatchObject({ code: 'provider_link_invalid' });
    expect(fetcher).toHaveBeenCalledTimes(2);
  });

  it.each([
    { state: 'DEPLETED' }, { fillsRemaining: 0 }, { expirationDate: '2026-10-15' }, { effectiveDate: '2026-10-17' },
  ])('rejects unavailable prescriptions %j', async changed => {
    const fetcher = fake().mockResolvedValueOnce(json({ data: { ...rawLink, prescription: { ...rawLink.prescription, ...changed } } }));
    await expect(new PhotonRefillsProvider(config, fetcher, now).verifyLink(linkInput)).rejects.toMatchObject({ code: 'provider_prescription_unavailable' });
  });

  it('fails closed on missing address and malformed dates', async () => {
    for (const [data, code] of [
      [{ ...rawLink, patient: { ...rawLink.patient, address: null } }, 'provider_address_missing'],
      [{ ...rawLink, prescription: { ...rawLink.prescription, expirationDate: '2026-02-30' } }, 'provider_response_invalid'],
    ] as const) {
      const fetcher = fake().mockResolvedValueOnce(json({ data }));
      await expect(new PhotonRefillsProvider(config, fetcher, now).verifyLink(linkInput)).rejects.toMatchObject({ code });
    }
  });

  it('shares an in-flight token exchange and refreshes before token expiry', async () => {
    let time = 0;
    const fetcher = vi.fn<typeof fetch>(async url => String(url).includes('/oauth/') ? token() : json({ data: { order: rawOrder } }));
    const provider = new PhotonRefillsProvider(config, fetcher, () => time);
    await Promise.all([provider.getOrder('ord-1'), provider.getOrder('ord-1'), provider.getOrder('ord-1')]);
    expect(fetcher.mock.calls.filter(call => String(call[0]).includes('/oauth/'))).toHaveLength(1);
    time = 3_540_000;
    await provider.getOrder('ord-1');
    expect(fetcher.mock.calls.filter(call => String(call[0]).includes('/oauth/'))).toHaveLength(2);
  });

  it('does not retry a createOrder on network failure or leak the upstream error', async () => {
    const fetcher = fake().mockRejectedValueOnce(new Error('secret and private clinical response'));
    await expect(new PhotonRefillsProvider(config, fetcher).submitOrder(input)).rejects.toMatchObject({
      message: 'provider_request_failed', code: 'provider_request_failed', outcome: 'unknown',
    });
    expect(fetcher).toHaveBeenCalledTimes(2);
  });

  it.each([
    () => json({ errors: [{ message: 'private clinical error' }] }),
    () => json({ data: { createOrder: { ...rawOrder, patient: { id: 'wrong-patient' } } } }),
    () => json({ data: { createOrder: rawOrder }, errors: [{ message: 'partial response' }] }),
    () => json({ message: 'private auth error' }, 401),
    () => new Response('not json'),
  ])('treats any unverified mutation response as uncertain with no automatic retry', async response => {
    const fetcher = fake().mockResolvedValueOnce(response());
    await expect(new PhotonRefillsProvider(config, fetcher).submitOrder(input)).rejects.toMatchObject({ outcome: 'unknown' });
    expect(fetcher).toHaveBeenCalledTimes(2);
  });

  it('token failure is definitely before submit and retries only on a later explicit operation', async () => {
    const fetcher = vi.fn<typeof fetch>().mockResolvedValueOnce(json({}, 503));
    await expect(new PhotonRefillsProvider(config, fetcher).submitOrder(input)).rejects.toMatchObject({ outcome: 'not_submitted' });
    expect(fetcher).toHaveBeenCalledTimes(1);
  });

  it('times out a slow body and never repeats the mutation', async () => {
    vi.useFakeTimers();
    const stream = new ReadableStream<Uint8Array>({ start() {} });
    const fetcher = fake().mockResolvedValueOnce(new Response(stream));
    const provider = new PhotonRefillsProvider({ ...config, timeoutMs: 100 }, fetcher);
    const assertion = expect(provider.submitOrder(input)).rejects.toMatchObject({ code: 'provider_timeout', outcome: 'unknown' });
    await vi.advanceTimersByTimeAsync(110);
    await assertion;
    expect(fetcher).toHaveBeenCalledTimes(2);
    expect(fetcher.mock.calls[1][1]!.signal!.aborted).toBe(true);
  });

  it('rejects oversized response bodies', async () => {
    const fetcher = fake().mockResolvedValueOnce(new Response('x'.repeat(1_048_577)));
    await expect(new PhotonRefillsProvider(config, fetcher).getOrder('ord-1')).rejects.toMatchObject({ code: 'provider_response_invalid' });
  });

  it('preserves distinct pickup and delivery fulfillment states without inventing confirmation', async () => {
    const fetcher = fake().mockResolvedValueOnce(json({ data: { order: { ...rawOrder, fulfillment: { type: 'PICK_UP', state: 'SENT' } } } }));
    await expect(new PhotonRefillsProvider(config, fetcher).getOrder('ord-1')).resolves.toMatchObject({ fulfillmentType: 'PICK_UP', fulfillmentState: 'SENT' });
  });

  it('reconciles by documented patient-filtered orders and external reference', async () => {
    const fetcher = fake().mockResolvedValueOnce(json({ data: { orders: [rawOrder] } }));
    await expect(new PhotonRefillsProvider(config, fetcher).findOrder({ patientId: 'pat-1', externalId: 'request-1' })).resolves.toMatchObject({ id: 'ord-1' });
    expect(JSON.parse(fetcher.mock.calls[1][1]!.body as string).variables).toEqual({ filter: { patientId: 'pat-1' }, first: 50 });
  });

  it('rejects ambiguous correlation and cross-patient responses', async () => {
    const duplicate = fake().mockResolvedValueOnce(json({ data: { orders: [rawOrder, { ...rawOrder, id: 'ord-2' }] } }));
    await expect(new PhotonRefillsProvider(config, duplicate).findOrder({ patientId: 'pat-1', externalId: 'request-1' })).rejects.toMatchObject({ code: 'provider_reconciliation_ambiguous' });
    const wrong = fake().mockResolvedValueOnce(json({ data: { orders: [{ ...rawOrder, patient: { id: 'wrong' } }] } }));
    await expect(new PhotonRefillsProvider(config, wrong).findOrder({ patientId: 'pat-1', externalId: 'request-1' })).rejects.toMatchObject({ code: 'provider_link_invalid' });
  });

  it('bounds reconciliation and rejects repeated pagination', async () => {
    const page = Array.from({ length: 50 }, (_, i) => ({ ...rawOrder, id: `ord-${i}`, externalId: `other-${i}` }));
    const fetcher = fake().mockImplementation(async () => json({ data: { orders: page } }));
    const provider = new PhotonRefillsProvider(config, fetcher);
    await expect(provider.findOrder({ patientId: 'pat-1', externalId: 'request-1' })).rejects.toMatchObject({ code: 'provider_reconciliation_incomplete' });
    expect(fetcher).toHaveBeenCalledTimes(3);
  });
});
