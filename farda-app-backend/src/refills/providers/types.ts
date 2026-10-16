export type ProviderEnvironment = 'sandbox' | 'production';

export type ProviderAddress = {
  street1: string;
  street2?: string;
  postalCode: string;
  country: string;
  state: string;
  city: string;
};

/** IDs must come from a trusted server-side mapping, never a mobile request. */
export type ProviderLinkInput = {
  userId: string;
  patientId: string;
  prescriptionId: string;
  pharmacyId: string;
};

export type VerifiedProviderLink = {
  patientId: string;
  prescriptionId: string;
  pharmacyId: string;
  pharmacyName: string;
  medicationName: string;
  instructions: string;
  fillsRemaining: number;
  expirationDate: string;
  effectiveDate: string;
  prescriptionState: string;
  address: ProviderAddress;
};

export type ProviderOrder = {
  id: string;
  externalId: string | null;
  patientId: string;
  prescriptionIds: string[];
  pharmacyId: string | null;
  orderState: string;
  fulfillmentType: string | null;
  fulfillmentState: string | null;
};

export type SubmitProviderOrder = {
  externalId: string;
  patientId: string;
  prescriptionId: string;
  pharmacyId: string;
  address: ProviderAddress;
};

export interface RefillsProvider {
  readonly configured: boolean;
  readonly environment: ProviderEnvironment;
  verifyLink(input: ProviderLinkInput): Promise<VerifiedProviderLink>;
  submitOrder(input: SubmitProviderOrder): Promise<ProviderOrder>;
  getOrder(orderId: string): Promise<ProviderOrder | null>;
  /** null means no match observed, NEVER permission to resubmit an uncertain order. */
  findOrder(input: { patientId: string; externalId: string }): Promise<ProviderOrder | null>;
}

export type ProviderErrorCode =
  | 'provider_unavailable' | 'provider_authentication' | 'provider_timeout'
  | 'provider_response_invalid' | 'provider_request_failed' | 'provider_link_invalid'
  | 'provider_prescription_unavailable' | 'provider_address_missing'
  | 'provider_reconciliation_incomplete' | 'provider_reconciliation_ambiguous';

/** Never include provider response bodies, credentials or clinical details in errors. */
export class RefillProviderError extends Error {
  constructor(
    readonly code: ProviderErrorCode,
    readonly outcome: 'not_submitted' | 'unknown' = 'not_submitted',
  ) {
    super(code);
    this.name = 'RefillProviderError';
  }
}
