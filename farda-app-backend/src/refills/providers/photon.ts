import { z } from 'zod';
import {
  RefillProviderError,
  type ProviderEnvironment, type ProviderLinkInput, type ProviderOrder,
  type RefillsProvider, type SubmitProviderOrder, type VerifiedProviderLink,
} from './types';

// Contract sources (checked 2026-10-16): docs.photon.health/docs/authentication,
// docs.photon.health/docs/place-orders, reference.photon.health (Clinical API).
// An externalId is a correlation reference, NOT a documented idempotency key.
const ENDPOINTS = {
  sandbox: { auth: 'https://auth.neutron.health/oauth/token', api: 'https://api.neutron.health/graphql', audience: 'https://api.neutron.health' },
  production: { auth: 'https://auth.photon.health/oauth/token', api: 'https://api.photon.health/graphql', audience: 'https://api.photon.health' },
} as const;

const id = z.string().min(1).max(256);
const addressSchema = z.object({
  street1: z.string().trim().min(1).max(256), street2: z.string().max(256).nullish(),
  postalCode: z.string().trim().min(1).max(32), country: z.string().trim().min(1).max(64),
  state: z.string().trim().min(1).max(64), city: z.string().trim().min(1).max(128),
});
const date = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(value => {
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
});
const orderSchema = z.object({
  id, externalId: id.nullable(), state: z.string().min(1).max(64),
  patient: z.object({ id }), pharmacy: z.object({ id }).nullable(),
  fills: z.array(z.object({ prescription: z.object({ id }).nullable() })).max(100),
  fulfillment: z.object({ type: z.string().max(64), state: z.string().max(64) }).nullable(),
});
const ORDER_FIELDS = `id externalId state patient { id } pharmacy { id }
  fills { prescription { id } } fulfillment { type state }`;

export type PhotonProviderConfig = {
  enabled?: boolean;
  environment?: ProviderEnvironment;
  clientId?: string;
  clientSecret?: string;
  timeoutMs?: number;
};

export class PhotonRefillsProvider implements RefillsProvider {
  readonly environment: ProviderEnvironment;
  readonly configured: boolean;
  readonly capabilities = {
    verifyEligibility: true, submitOrders: true,
    lookupOrders: true, reconcileUnknownOutcomes: true,
  } as const;
  private readonly config: PhotonProviderConfig;
  private readonly timeoutMs: number;
  private token?: { value: string; expiresAt: number };
  private tokenFlight?: Promise<string>;

  constructor(
    config: PhotonProviderConfig = {},
    private readonly fetcher: typeof fetch = fetch,
    private readonly now: () => number = Date.now,
  ) {
    this.config = { ...config };
    this.environment = config.environment === 'production' ? 'production' : 'sandbox';
    this.configured = config.enabled === true &&
      (config.environment === undefined || config.environment === 'sandbox' || config.environment === 'production') &&
      !!config.clientId?.trim() && !!config.clientSecret?.trim() && config.clientId.trim() !== config.clientSecret.trim();
    this.timeoutMs = Number.isFinite(config.timeoutMs)
      ? Math.max(100, Math.min(config.timeoutMs!, 30000)) : 10000;
  }

  async verifyLink(input: ProviderLinkInput): Promise<VerifiedProviderLink> {
    const data = await this.graphql(`query VerifyRefillLink($patientId: ID!, $prescriptionId: ID!, $pharmacyId: ID!) {
      patient(id: $patientId) { id externalId address { street1 street2 postalCode country state city } }
      prescription(id: $prescriptionId) { id patient { id } state fillsRemaining effectiveDate expirationDate instructions treatment { name } }
      pharmacy(id: $pharmacyId) { id name }
    }`, { patientId: input.patientId, prescriptionId: input.prescriptionId, pharmacyId: input.pharmacyId });
    const result = z.object({
      patient: z.object({ id, externalId: id.nullable(), address: z.unknown() }).nullable(),
      prescription: z.object({ id, patient: z.object({ id }), state: z.string(),
        fillsRemaining: z.number().int().nonnegative(), effectiveDate: date, expirationDate: date,
        instructions: z.string().min(1).max(20000), treatment: z.object({ name: z.string().min(1).max(2000) }),
      }).nullable(),
      pharmacy: z.object({ id, name: z.string().min(1).max(2000) }).nullable(),
    }).safeParse(data);
    if (!result.success) throw new RefillProviderError('provider_response_invalid');
    const { patient, prescription, pharmacy } = result.data;
    if (!patient || !prescription || !pharmacy || patient.id !== input.patientId ||
      patient.externalId !== input.userId || prescription.id !== input.prescriptionId ||
      prescription.patient.id !== patient.id || pharmacy.id !== input.pharmacyId) {
      throw new RefillProviderError('provider_link_invalid');
    }
    const today = new Date(this.now()).toISOString().slice(0, 10);
    if (prescription.state !== 'ACTIVE' || prescription.fillsRemaining < 1 ||
      prescription.effectiveDate > today || prescription.expirationDate < today) {
      throw new RefillProviderError('provider_prescription_unavailable');
    }
    const address = addressSchema.safeParse(patient.address);
    if (!address.success) throw new RefillProviderError('provider_address_missing');
    return {
      patientId: patient.id, prescriptionId: prescription.id, pharmacyId: pharmacy.id,
      pharmacyName: pharmacy.name, medicationName: prescription.treatment.name,
      instructions: prescription.instructions, fillsRemaining: prescription.fillsRemaining,
      effectiveDate: prescription.effectiveDate, expirationDate: prescription.expirationDate,
      prescriptionState: prescription.state,
      address: { ...address.data, street2: address.data.street2 ?? undefined },
    };
  }

  async submitOrder(input: SubmitProviderOrder): Promise<ProviderOrder> {
    const validated = z.object({ externalId: id, patientId: id, prescriptionId: id, pharmacyId: id,
      address: addressSchema }).safeParse(input);
    if (!validated.success) throw new RefillProviderError('provider_link_invalid');
    const data = await this.graphql(`mutation CreateRefillOrder($externalId: ID, $patientId: ID!, $fills: [FillInput!]!, $address: AddressInput!, $pharmacyId: ID) {
      createOrder(externalId: $externalId, patientId: $patientId, fills: $fills, address: $address, pharmacyId: $pharmacyId) { ${ORDER_FIELDS} }
    }`, {
      externalId: input.externalId, patientId: input.patientId,
      fills: [{ prescriptionId: input.prescriptionId }], pharmacyId: input.pharmacyId,
      address: validated.data.address,
    }, true);
    const result = z.object({ createOrder: orderSchema }).safeParse(data);
    if (!result.success) throw new RefillProviderError('provider_response_invalid', 'unknown');
    const order = this.presentOrder(result.data.createOrder);
    if (order.externalId !== input.externalId || order.patientId !== input.patientId ||
      order.prescriptionIds.length !== 1 || order.prescriptionIds[0] !== input.prescriptionId ||
      (order.pharmacyId !== null && order.pharmacyId !== input.pharmacyId)) {
      throw new RefillProviderError('provider_response_invalid', 'unknown');
    }
    return order;
  }

  async getOrder(orderId: string): Promise<ProviderOrder | null> {
    const data = await this.graphql(`query RefillOrder($id: ID!) { order(id: $id) { ${ORDER_FIELDS} } }`, { id: orderId });
    const result = z.object({ order: orderSchema.nullable() }).safeParse(data);
    if (!result.success || (result.data.order && result.data.order.id !== orderId)) {
      throw new RefillProviderError('provider_response_invalid');
    }
    return result.data.order ? this.presentOrder(result.data.order) : null;
  }

  async findOrder(input: { patientId: string; externalId: string }): Promise<ProviderOrder | null> {
    // The documented filter has no externalId field. Scan only this patient's bounded pages.
    let after: string | undefined;
    let match: ProviderOrder | null = null;
    const seen = new Set<string>();
    for (let page = 0; page < 5; page++) {
      const data = await this.graphql(`query FindRefillOrder($filter: OrderFilter, $after: ID, $first: Int) {
        orders(filter: $filter, after: $after, first: $first) { ${ORDER_FIELDS} }
      }`, { filter: { patientId: input.patientId }, after, first: 50 });
      const result = z.object({ orders: z.array(orderSchema).max(50) }).safeParse(data);
      if (!result.success) throw new RefillProviderError('provider_response_invalid');
      for (const raw of result.data.orders) {
        if (raw.patient.id !== input.patientId) throw new RefillProviderError('provider_link_invalid');
        if (seen.has(raw.id)) throw new RefillProviderError('provider_reconciliation_incomplete');
        seen.add(raw.id);
        if (raw.externalId === input.externalId) {
          if (match) throw new RefillProviderError('provider_reconciliation_ambiguous');
          match = this.presentOrder(raw);
        }
      }
      if (result.data.orders.length < 50) return match;
      after = result.data.orders[result.data.orders.length - 1].id;
    }
    throw new RefillProviderError('provider_reconciliation_incomplete');
  }

  private presentOrder(raw: z.infer<typeof orderSchema>): ProviderOrder {
    return { id: raw.id, externalId: raw.externalId, patientId: raw.patient.id,
      prescriptionIds: raw.fills.flatMap(fill => fill.prescription ? [fill.prescription.id] : []),
      pharmacyId: raw.pharmacy?.id ?? null, orderState: raw.state,
      fulfillmentType: raw.fulfillment?.type ?? null, fulfillmentState: raw.fulfillment?.state ?? null };
  }

  private async accessToken(): Promise<string> {
    if (!this.configured) throw new RefillProviderError('provider_unavailable');
    if (this.token && this.now() < this.token.expiresAt) return this.token.value;
    if (this.tokenFlight) return this.tokenFlight;
    this.tokenFlight = this.loadToken();
    try { return await this.tokenFlight; }
    finally { this.tokenFlight = undefined; }
  }

  private async loadToken(): Promise<string> {
    const endpoint = ENDPOINTS[this.environment];
    const data = await this.json(endpoint.auth, {
      client_id: this.config.clientId, client_secret: this.config.clientSecret,
      audience: endpoint.audience, grant_type: 'client_credentials',
    });
    const parsed = z.object({ access_token: z.string().min(1).max(16000),
      token_type: z.literal('Bearer'), expires_in: z.number().positive().max(604800) }).safeParse(data);
    if (!parsed.success) throw new RefillProviderError('provider_authentication');
    const ttl = parsed.data.expires_in * 1000;
    this.token = { value: parsed.data.access_token, expiresAt: this.now() + ttl - Math.min(60000, ttl / 10) };
    return this.token.value;
  }

  private async graphql(query: string, variables: Record<string, unknown>, mutation = false): Promise<unknown> {
    // Token failure happens before a mutation is dispatched: safe to prepare again.
    const token = await this.accessToken();
    const envelope = await this.json(ENDPOINTS[this.environment].api, { query, variables }, token, mutation);
    const parsed = z.object({ data: z.unknown(), errors: z.array(z.unknown()).optional() }).safeParse(envelope);
    if (!parsed.success || !parsed.data.data || parsed.data.errors?.length) {
      throw new RefillProviderError('provider_request_failed', mutation ? 'unknown' : 'not_submitted');
    }
    return parsed.data.data;
  }

  private async json(url: string, body: unknown, token?: string, mutation = false): Promise<unknown> {
    const controller = new AbortController();
    const outcome = mutation ? 'unknown' : 'not_submitted';
    let timer: ReturnType<typeof setTimeout> | undefined;
    // Deadline includes response body decoding; a slow body cannot hold the route open.
    const deadline = new Promise<never>((_, reject) => {
      timer = setTimeout(() => {
        controller.abort();
        reject(new RefillProviderError('provider_timeout', outcome));
      }, this.timeoutMs);
    });
    try {
      return await Promise.race([deadline, (async () => {
        const response = await this.fetcher(url, {
          method: 'POST', headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
          body: JSON.stringify(body), redirect: 'error', signal: controller.signal,
        });
        if (!response.ok) {
          void response.body?.cancel().catch(() => undefined);
          if (response.status === 401 || response.status === 403) this.token = undefined;
          throw new RefillProviderError(response.status === 401 || response.status === 403
            ? 'provider_authentication' : 'provider_request_failed', outcome);
        }
        // Bounded JSON body; don't retain error text or arbitrarily large clinical payloads.
        if (Number(response.headers.get('content-length')) > 1_048_576) {
          controller.abort();
          throw new RefillProviderError('provider_response_invalid', outcome);
        }
        const reader = response.body?.getReader();
        if (!reader) throw new RefillProviderError('provider_response_invalid', outcome);
        const chunks: Uint8Array[] = [];
        let size = 0;
        try {
          while (true) {
            const chunk = await reader.read();
            if (chunk.done) break;
            size += chunk.value.byteLength;
            if (size > 1_048_576) {
              controller.abort();
              void reader.cancel().catch(() => undefined);
              throw new RefillProviderError('provider_response_invalid', outcome);
            }
            chunks.push(chunk.value);
          }
          return JSON.parse(Buffer.concat(chunks).toString('utf8')) as unknown;
        } finally { reader.releaseLock(); }
      })()]);
    } catch (error) {
      if (error instanceof RefillProviderError) throw error;
      throw new RefillProviderError(controller.signal.aborted ? 'provider_timeout' : 'provider_request_failed', outcome);
    } finally { if (timer) clearTimeout(timer); }
  }
}
