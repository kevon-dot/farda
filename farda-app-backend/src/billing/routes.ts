import express, { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../lib/prisma';
import { isAuthenticated } from '../middleware/isAuthenticated';
import { route } from '../reminders/routes';
import { priceCatalog } from './catalog';
import { BillingError, createBillingService, type BillingService } from './service';

const send = (error: unknown, res: express.Response) => error instanceof BillingError ? res.status(error.status).json({ error: error.message, code: error.code }) : res.status(503).json({ error: 'Billing is temporarily unavailable.', code: 'billing_unavailable' });
export function createBillingRouter(service: BillingService = createBillingService(prisma)) {
  const router = Router(); router.use(isAuthenticated);
  router.get('/billing/catalog', route(async (_req, res) => res.json(service.catalog())));
  router.get('/billing/status', route(async (req, res) => { res.setHeader('Cache-Control', 'no-store'); res.json(await service.status(req.user!.id)); }));
  router.post('/billing/checkout', async (req, res) => { try { const body = z.object({ priceKey: z.enum(Object.keys(priceCatalog) as [keyof typeof priceCatalog, ...(keyof typeof priceCatalog)[]]), successUrl: z.string().max(2048), cancelUrl: z.string().max(2048), channel: z.literal('web') }).strict().parse(req.body); res.json(await service.checkout(req.user!.id, body)); } catch (e) { if (e instanceof z.ZodError) return res.status(400).json({ error: 'Invalid checkout request.', code: 'invalid_input' }); return send(e, res); } });
  router.post('/billing/portal', async (req, res) => { try { const body = z.object({ returnUrl: z.string().max(2048) }).strict().parse(req.body); res.json(await service.portal(req.user!.id, body.returnUrl)); } catch (e) { if (e instanceof z.ZodError) return res.status(400).json({ error: 'Invalid portal request.', code: 'invalid_input' }); return send(e, res); } });
  return router;
}

// Mount this exact router before express.json(); Stripe verifies the original bytes.
export function createBillingWebhookRouter(service: BillingService = createBillingService(prisma)) {
  const router = Router();
  router.post('/api/billing/webhook', express.raw({ type: 'application/json', limit: '256kb' }), async (req, res) => { try { res.json(await service.webhook(req.body as Buffer, req.get('stripe-signature'))); } catch (e) { return send(e, res); } });
  return router;
}
