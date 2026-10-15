import { prisma } from '@src/lib/prisma';
import type { NextFunction, Request, Response } from 'express';

export const isAuthenticated = async (req: Request, res: Response, next: NextFunction) => {
  const match = /^Bearer ([^\s]+)$/i.exec(req.headers.authorization ?? '');
  if (!match || match[1].length > 512) return res.status(401).json({ error: 'Sign in to continue', code: 'unauthorized' });
  try {
    const session = await prisma.session.findUnique({ where: { token: match[1] }, select: { userId: true, expiresAt: true } });
    if (!session || session.expiresAt.getTime() <= Date.now()) return res.status(401).json({ error: 'Your session has expired. Sign in again.', code: 'unauthorized' });
    req.user = { id: session.userId };
    return next();
  } catch { return res.status(503).json({ error: 'Sign-in verification is temporarily unavailable', code: 'temporarily_unavailable' }); }
};
