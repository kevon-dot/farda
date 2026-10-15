import express from 'express';
import type { Server } from 'node:http';
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

const provider = vi.hoisted(() => ({ create: vi.fn(), options: vi.fn() }));
vi.mock('@src/common/constants/env', () => ({ default: { OPENAI_API_KEY: 'test-only-key' } }));
vi.mock('@src/lib/prisma', () => ({ prisma: {} }));
vi.mock('openai', async importOriginal => {
  const actual = await importOriginal<typeof import('openai')>();
  return { default: class {
    static APIConnectionTimeoutError = actual.default.APIConnectionTimeoutError;
    constructor(options: unknown) { provider.options(options); }
    chat = { completions: { create: provider.create } };
  } };
});

import OpenAI from 'openai';
import env from '@src/common/constants/env';
import OcrRoutes from '@src/routes/OcrRoutes';
import { EXTRACTION_PROMPT, extractPrescriptionFromBuffers } from '@src/services/OcrService';

const png = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
const medicine = { medicine_name: 'Example', generic_name: null, instructions: 'Visible directions\nwith a continuation line.', qty: null, refills_info: null, side_effects: null };
const draft = { pharmacy_or_doctor_name: null, contact_details: null, date_filled: null, date_expired: null, address: null, rx_number: null, store_number: null, medicines_names: [medicine] };
const completion = (data: unknown = draft, finish_reason = 'stop') => ({ choices: [{ finish_reason, message: { content: JSON.stringify(data) } }] });

beforeEach(() => {
  vi.clearAllMocks();
  provider.create.mockReset();
  env.OPENAI_API_KEY = 'test-only-key';
});

describe('multi-view label extraction boundary', () => {
  it('sends all four views in one bounded high-detail request and preserves exact directions for review', async () => {
    provider.create.mockResolvedValue(completion());
    const result = await extractPrescriptionFromBuffers([png, png, png, png]);
    expect(provider.create).toHaveBeenCalledTimes(1);
    expect(provider.options).toHaveBeenCalledWith(expect.objectContaining({ timeout: 45000, maxRetries: 0 }));
    const request = provider.create.mock.calls[0][0];
    expect(request.messages[1].content).toHaveLength(4);
    expect(request.messages[1].content.every((image: any) => image.image_url.detail === 'high')).toBe(true);
    expect(result.medicines_names[0].instructions).toBe(medicine.instructions);
    expect(result).toMatchObject({ requires_review: true, source: 'label_ocr' });
  });

  it('retains separate prescriptions, including same-name medicines, for the client to reject a mixed batch', async () => {
    provider.create.mockResolvedValue(completion({ ...draft, medicines_names: [medicine, { ...medicine, instructions: 'Different visible directions' }] }));
    const result = await extractPrescriptionFromBuffers([png, png]);
    expect(result.medicines_names).toHaveLength(2);
    expect(result.medicines_names[1].instructions).toBe('Different visible directions');
  });

  it('instructs overlap-only reconstruction, null conflicts and no partial directions', () => {
    expect(EXTRACTION_PROMPT).toContain('matching visible overlap');
    expect(EXTRACTION_PROMPT).toContain('If views disagree about a field, return null');
    expect(EXTRACTION_PROMPT).toContain('not a partial instruction');
    expect(EXTRACTION_PROMPT).toContain('Do not merge distinct prescriptions');
  });

  it.each(['length', 'content_filter'])('rejects %s completions even if the JSON parses', async reason => {
    provider.create.mockResolvedValue(completion(draft, reason));
    await expect(extractPrescriptionFromBuffers([png])).rejects.toMatchObject({ code: 'ocr_incomplete' });
  });

  it('rejects oversized directions instead of silently shortening them', async () => {
    provider.create.mockResolvedValue(completion({ ...draft, medicines_names: [{ ...medicine, instructions: 'x'.repeat(2001) }] }));
    await expect(extractPrescriptionFromBuffers([png])).rejects.toMatchObject({ code: 'ocr_incomplete' });
  });

  it('normalizes malformed provider output without returning model text', async () => {
    provider.create.mockResolvedValue({ choices: [{ finish_reason: 'stop', message: { content: 'private malformed provider output' } }] });
    await expect(extractPrescriptionFromBuffers([png])).rejects.toMatchObject({ code: 'ocr_incomplete' });
  });

  it('allows manual fallback when no provider key is configured without making a request', async () => {
    env.OPENAI_API_KEY = undefined;
    await expect(extractPrescriptionFromBuffers([png])).rejects.toMatchObject({ code: 'ocr_unavailable' });
    expect(provider.create).not.toHaveBeenCalled();
  });
});

describe('label upload HTTP recovery', () => {
  let server: Server, base: string;
  beforeAll(async () => {
    const app = express();
    app.use((req, _res, next) => { req.user = { id: 'test-owner' } as typeof req.user; next(); });
    app.post('/ocr', ...OcrRoutes.extractFromImages);
    server = await new Promise<Server>(resolve => {
      const instance = app.listen(0, '127.0.0.1', () => resolve(instance));
    });
    base = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
  });
  afterAll(() => new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve())));

  const upload = async (types = ['image/png']) => {
    const form = new FormData();
    for (const type of types) form.append('image', new Blob([png], { type }), 'label.png');
    return fetch(base + '/ocr', { method: 'POST', body: form });
  };

  it('returns a safe timeout with a manual route forward', async () => {
    provider.create.mockRejectedValue(new OpenAI.APIConnectionTimeoutError({ message: 'secret provider details' }));
    const response = await upload();
    expect(response.status).toBe(504);
    expect(await response.json()).toEqual({ code: 'ocr_timeout', error: 'Label scanning took too long. Try again or enter the label details manually.' });
  });

  it('hides provider errors behind an unavailable response', async () => {
    provider.create.mockRejectedValue(new Error('secret provider details'));
    const response = await upload();
    expect(response.status).toBe(503);
    const body = await response.json();
    expect(body.code).toBe('ocr_unavailable');
    expect(body.error).not.toContain('secret');
  });

  it('returns an incomplete-draft error instead of saving an invalid extraction', async () => {
    provider.create.mockResolvedValue(completion({ ...draft, labelReviewed: true }));
    const response = await upload();
    expect(response.status).toBe(422);
    expect((await response.json()).code).toBe('ocr_incomplete');
  });

  it('rejects a mixed supported/unsupported batch instead of silently losing a view', async () => {
    const response = await upload(['image/png', 'image/heic']);
    expect(response.status).toBe(400);
    expect((await response.json()).code).toBe('invalid_image');
    expect(provider.create).not.toHaveBeenCalled();
  });

  it('enforces four-photo limit before any provider request', async () => {
    const response = await upload(Array(5).fill('image/png'));
    expect(response.status).toBe(413);
    expect((await response.json()).code).toBe('upload_limit');
    expect(provider.create).not.toHaveBeenCalled();
  });
});
