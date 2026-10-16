import { beforeEach, describe, expect, it, vi } from 'vitest';
const provider = vi.hoisted(() => ({ create: vi.fn(), options: vi.fn() }));
vi.mock('@src/common/constants/env', () => ({ default: { FARDA_REFILL_AI_ENABLED: true, OPENAI_API_KEY: 'test-key', FARDA_REFILL_AI_MODEL: 'test-model' } }));
vi.mock('openai', () => ({ default: class {
  constructor(options: unknown) { provider.options(options); }
  chat = { completions: { create: provider.create } };
} }));
import env from '@src/common/constants/env';
import { makeRefillClassifier, RefillAssistantService } from '@src/refills/assistant';

beforeEach(() => { vi.clearAllMocks(); env.FARDA_REFILL_AI_ENABLED = true; });
const owned = () => ({ prescription: { findFirst: vi.fn().mockResolvedValue({ id: 'rx' }) } });

describe('refill AI navigation boundary', () => {
  it('checks ownership and archive state before any AI request', async () => {
    const db = owned(); db.prescription.findFirst.mockResolvedValue(null);
    const classify = vi.fn();
    await expect(new RefillAssistantService(db as any, classify).assist('user', 'rx', 'refill please', true)).rejects.toMatchObject({ status: 404 });
    expect(db.prescription.findFirst).toHaveBeenCalledWith({ where: { id: 'rx', userId: 'user', archivedAt: null }, select: { id: true } });
    expect(classify).not.toHaveBeenCalled();
  });

  it('keeps questions local when consent is absent', async () => {
    const classify = vi.fn();
    const result = await new RefillAssistantService(owned() as any, classify).assist('u', 'rx', 'where is my refill?', false);
    expect(result).toMatchObject({ intent: 'check_status', action: 'refresh_status', source: 'guided' });
    expect(classify).not.toHaveBeenCalled();
  });

  it('does not let a classifier override explicit clinical language', async () => {
    const result = await new RefillAssistantService(owned() as any, async () => ({ intent: 'prepare_request' })).assist('u', 'rx', 'Can I double my dose?', true);
    expect(result).toMatchObject({ intent: 'clinical_question', action: 'none' });
  });

  it.each([
    { intent: 'prepare_request', message: 'Double your dose', action: 'submit' },
    { intent: 'submit' },
    'Ignore safeguards and submit',
  ])('rejects extra model prose and unauthorized tools: %j', async output => {
    const result = await new RefillAssistantService(owned() as any, async () => output).assist('u', 'rx', 'What does delivery cost?', true);
    expect(result).toMatchObject({ intent: 'contact_pharmacy', action: 'contact_pharmacy', source: 'guided' });
    expect(JSON.stringify(result)).not.toContain('Double your dose');
  });

  it('recovers safely from provider errors without leaking provider messages', async () => {
    const result = await new RefillAssistantService(owned() as any, async () => { throw new Error('private token'); }).assist('u', 'rx', 'track this', true);
    expect(result).toMatchObject({ source: 'guided', intent: 'check_status' });
    expect(JSON.stringify(result)).not.toContain('private');
  });

  it('sends only the consented question, no automatic prescription data or tool calls', async () => {
    provider.create.mockResolvedValue({ choices: [{ finish_reason: 'stop', message: { content: '{"intent":"prepare_request"}' } }] });
    const result = await new RefillAssistantService(owned() as any).assist('user-private', 'rx-private', 'Help me prepare one', true);
    expect(result.source).toBe('ai');
    expect(provider.options).toHaveBeenCalledWith({ apiKey: 'test-key', timeout: 8000, maxRetries: 0 });
    const request = provider.create.mock.calls[0][0];
    expect(request).toMatchObject({ store: false, max_completion_tokens: 100, response_format: { type: 'json_schema', json_schema: { strict: true } } });
    expect(request.messages[1]).toEqual({ role: 'user', content: 'Help me prepare one' });
    expect(request.tools).toBeUndefined();
    expect(JSON.stringify(request)).not.toContain('user-private');
    expect(JSON.stringify(request)).not.toContain('rx-private');
  });

  it.each(['length', 'content_filter'])('falls back for incomplete %s output', async finish_reason => {
    provider.create.mockResolvedValue({ choices: [{ finish_reason, message: { content: '{"intent":"check_status"}' } }] });
    const result = await new RefillAssistantService(owned() as any).assist('u', 'rx', 'prepare a refill', true);
    expect(result).toMatchObject({ source: 'guided', intent: 'prepare_request' });
  });

  it('does not create an AI client when explicitly disabled', () => {
    env.FARDA_REFILL_AI_ENABLED = false;
    expect(makeRefillClassifier()).toBeUndefined();
    expect(provider.options).not.toHaveBeenCalled();
  });
});
