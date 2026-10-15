import { auth } from '@src/auth';
import { prisma } from '@src/lib/prisma';
import { sendSmsOTP } from '@src/services/twilioService';
import { z } from 'zod';
import type { Request, Response } from 'express';

const phone = z.string().regex(/^\+[1-9]\d{7,14}$/);
const sendInput = z.object({ phoneNumber: phone }).strict();
const verifyInput = sendInput.extend({ code: z.string().regex(/^\d{4,10}$/) });
function authError(res: Response, error: unknown) {
  if (error instanceof z.ZodError) return res.status(400).json({ error: 'Check the phone number and verification code', code: 'invalid_input' });
  const status = typeof error === 'object' && error ? Number(('statusCode' in error && error.statusCode) || ('status' in error && error.status) || 503) : 503;
  if (status === 429) return res.status(429).json({ error: 'Too many attempts. Try again later.', code: 'rate_limited' });
  if (status >= 400 && status < 500) return res.status(400).json({ error: 'The verification could not be completed. Check your code or request a new one.', code: 'verification_failed' });
  return res.status(503).json({ error: 'Verification is temporarily unavailable. Please try again.', code: 'temporarily_unavailable' });
}
const PhoneAuthRoutes = {
  sendOTP: async (req: Request, res: Response) => {
    try {
      const body = sendInput.parse(req.body);
      // Better Auth 1.4's send hook swallows background-task rejections. Await
      // Twilio Verify directly so a delivery failure cannot become HTTP 200.
      // Verify owns challenge issuance/expiry; its custom verify hook below
      // creates the Better Auth session only after provider approval.
      const result = await sendSmsOTP(body.phoneNumber, '');
      if (result.status !== 'pending') throw new Error('Verification was not accepted');
      return res.json({ message: 'code sent' });
    }
    catch (error) { return authError(res, error); }
  },
  verifyOTP: async (req: Request, res: Response) => {
    try { const body = verifyInput.parse(req.body); return res.json(await auth.api.verifyPhoneNumber({ body })); }
    catch (error) { return authError(res, error); }
  },
  socialLogin: async (req: Request, res: Response) => {
    try {
      const input = z.object({ provider: z.enum(['google', 'apple', 'facebook']), idToken: z.string().min(1).max(20000) }).strict().parse(req.body);
      return res.json(await auth.api.signInSocial({ body: { provider: input.provider, idToken: { token: input.idToken } } }));
    } catch (error) { return authError(res, error); }
  },
  session: async (req: Request, res: Response) => {
    try {
      const token = req.headers.authorization!.slice(7);
      const session = await prisma.session.findUnique({ where: { token }, select: { expiresAt: true, user: { select: { id: true, name: true, email: true, phoneNumber: true, phoneNumberVerified: true } } } });
      if (!session || session.expiresAt <= new Date()) return res.status(401).json({ error: 'Sign in to continue', code: 'unauthorized' });
      return res.json({ data: session });
    } catch (error) { return authError(res, error); }
  },
  signOut: async (req: Request, res: Response) => {
    try {
      await prisma.session.deleteMany({ where: { token: req.headers.authorization!.slice(7), userId: req.user!.id } });
      return res.status(204).end();
    } catch (error) { return authError(res, error); }
  },
};
export default PhoneAuthRoutes;
