import { createHash } from 'node:crypto';
import { prisma } from '@src/lib/prisma';
import type { RequestHandler } from 'express';

/** Shared database counters work across API replicas. Keys contain no raw PII. */
export function rateLimit(scope: string, limit: number, windowSeconds = 900): RequestHandler {
  return async (req, res, next) => {
    const now = Date.now();
    const bucket = Math.floor(now / (windowSeconds * 1000));
    const subjects = [req.user?.id ? `user:${req.user.id}` : `ip:${req.ip ?? 'unknown'}`];
    if (!req.user?.id && typeof req.body?.phoneNumber === 'string') subjects.push(`phone:${req.body.phoneNumber}`);
    try {
      const rows = await prisma.$transaction(subjects.map(subject => {
        const key = createHash('sha256').update(`${scope}:${bucket}:${subject}`).digest('hex');
        return prisma.apiRateLimit.upsert({ where: { key }, create: { key, count: 1, expiresAt: new Date((bucket + 1) * windowSeconds * 1000) }, update: { count: { increment: 1 } } });
      }));
      if (rows.some(row => row.count > limit)) {
        res.setHeader('Retry-After', String(Math.ceil(((bucket + 1) * windowSeconds * 1000 - now) / 1000)));
        return res.status(429).json({ error: 'Too many attempts. Please try again later.', code: 'rate_limited' });
      }
      // Expired counters carry no authorization meaning; cleanup failure cannot
      // bypass the already committed limit decision.
      void prisma.apiRateLimit.deleteMany({ where: { expiresAt: { lt: new Date(now - 86400000) } } }).catch(() => undefined);
      return next();
    } catch { return res.status(503).json({ error: 'This service is temporarily unavailable', code: 'temporarily_unavailable' }); }
  };
}
