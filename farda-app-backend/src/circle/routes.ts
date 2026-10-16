import { Router } from "express";
import { z } from "zod";
import { prisma } from "../lib/prisma";
import { route } from "../reminders/routes";
import { CircleService } from "./service";
import { ConsumerError } from "../reminders/policy";
import { rateLimit } from "../middleware/rateLimit";
import { validTimeZone } from "../reminders/policy";
import { CircleAlertService } from "./alerts";

const id = z.string().min(1).max(160);
const permissions = z.object({ doseStatus: z.boolean(), reminders: z.boolean() }).strict();
const invitePermissions = permissions.refine(p => p.doseStatus || p.reminders, "Choose at least one permission");
const service = new CircleService(prisma);
export const circleAlertService = new CircleAlertService(prisma);
const clock = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/);
const alertSettings = z.object({ enabled: z.boolean(), gracePeriodMinutes: z.number().int().min(15).max(240), quietHoursStart: clock, quietHoursEnd: clock, timeZone: z.string().max(100).refine(validTimeZone) }).strict();
export function createCircleRouter(circle = service, alerts = circleAlertService) {
  const router = Router();
  router.get("/circle", route(async (req, res) => res.json(await circle.overview(req.user!.id))));
  router.post("/circle/invitations", rateLimit("circle-invite", 10), route(async (req, res) => {
    const body = z.object({ recipientPhone: z.string().max(20), permissions: invitePermissions }).strict().parse(req.body);
    res.status(202).json(await circle.invite(req.user!.id, body.recipientPhone, body.permissions));
  }));
  router.get("/circle/invitations", route(async (req, res) => res.json(await circle.received(req.user!.id))));
  router.post("/circle/invitations/:id/accept", route(async (req, res) => {
    const body = z.object({ inviteCode: z.string().min(20).max(100) }).strict().parse(req.body);
    res.json(await circle.accept(req.user!.id, id.parse(req.params.id), body.inviteCode));
  }));
  router.delete("/circle/invitations/:id/received", route(async (req, res) => res.json(await circle.decline(req.user!.id, id.parse(req.params.id)))));
  router.delete("/circle/invitations/:id", route(async (req, res) => res.json(await circle.cancel(req.user!.id, id.parse(req.params.id)))));
  router.patch("/circle/members/:id", route(async (req, res) => res.json(await circle.update(req.user!.id, id.parse(req.params.id), permissions.parse(req.body)))));
  router.delete("/circle/members/:id", route(async (req, res) => res.json(await circle.remove(req.user!.id, id.parse(req.params.id)))));
  router.get("/circle/members/:id/alert-policy", route(async (req, res) => res.json(await alerts.ownerPolicy(req.user!.id, id.parse(req.params.id)))));
  router.put("/circle/members/:id/alert-policy", route(async (req, res) => res.json(await alerts.saveOwnerPolicy(req.user!.id, id.parse(req.params.id), alertSettings.parse(req.body)))));
  router.get("/circle/shared-with-me", route(async (req, res) => res.json(await circle.shared(req.user!.id))));
  router.delete("/circle/shared-with-me/:id", route(async (req, res) => res.json(await circle.leave(req.user!.id, id.parse(req.params.id)))));
  router.get("/circle/shared-with-me/:id/alert-consent", route(async (req, res) => res.json(await alerts.recipientPolicy(req.user!.id, id.parse(req.params.id)))));
  router.put("/circle/shared-with-me/:id/alert-consent", route(async (req, res) => {
    const body = z.object({ consented: z.boolean() }).strict().parse(req.body);
    res.json(await alerts.saveRecipientConsent(req.user!.id, id.parse(req.params.id), body.consented));
  }));
  router.get("/circle/alerts", route(async (req, res) => {
    const query = z.object({ limit: z.coerce.number().int().min(1).max(100).optional() }).parse(req.query);
    res.json(await alerts.inbox(req.user!.id, query.limit));
  }));
  router.post("/circle/alerts/:id/read", route(async (req, res) => res.json(await alerts.markRead(req.user!.id, id.parse(req.params.id)))));
  router.get("/circle/shared-with-me/:id/routine", route(async (req, res) => {
    const query = z.object({ from: z.coerce.date(), to: z.coerce.date() }).parse(req.query);
    if (query.to <= query.from || query.to.getTime() - query.from.getTime() > 32 * 86_400_000) throw new ConsumerError(400, "Choose a date range of 32 days or less.");
    res.json(await circle.routine(req.user!.id, id.parse(req.params.id), query.from, query.to));
  }));
  return router;
}
