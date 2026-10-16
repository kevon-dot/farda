import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../lib/prisma';
import { isAuthenticated } from '../middleware/isAuthenticated';
import { rateLimit } from '../middleware/rateLimit';
import { route } from '../reminders/routes';
import { RefillAssistantService } from './assistant';

export function createRefillAssistantRouter(service = new RefillAssistantService(prisma)) {
  const router = Router();
  router.use(isAuthenticated);
  router.post('/refills/agent/:prescriptionId/assist', rateLimit('refill-assist', 12), route(async (req, res) => {
    const id = z.string().min(1).max(160).parse(req.params.prescriptionId);
    const body = z.object({ question: z.string().trim().min(1).max(1000), consent: z.boolean().default(false) }).strict().parse(req.body);
    res.setHeader('Cache-Control', 'no-store');
    res.json(await service.assist(req.user!.id, id, body.question, body.consent));
  }));
  return router;
}
