import { prisma } from '@src/lib/prisma';
import type { NextFunction, Request, Response } from 'express';

export const isAuthenticated = async (req: Request, res: Response, next: NextFunction) => {
  const match = /^Bearer ([^\s]+)$/i.exec(req.headers.authorization ?? '');
  if (!match || match[1].length > 512) return res.status(401).json({ error: 'Sign in to continue', code: 'unauthorized' });
  try {
    const session = await prisma.session.findUnique({ where: { token: match[1] }, select: { id: true, userId: true, expiresAt: true } });
    if (!session) return res.status(401).json({ error: 'Your session has expired. Sign in again.', code: 'unauthorized' });
    if (session.expiresAt.getTime() <= Date.now()) {
      // Cascades only registrations authenticated by this expired session.
      await prisma.session.deleteMany({ where: { id: session.id, expiresAt: { lte: new Date() } } });
      return res.status(401).json({ error: 'Your session has expired. Sign in again.', code: 'unauthorized' });
    }
    req.user = { id: session.userId, sessionId: session.id };
    return next();
  } catch { return res.status(503).json({ error: 'Sign-in verification is temporarily unavailable', code: 'temporarily_unavailable' }); }
};
