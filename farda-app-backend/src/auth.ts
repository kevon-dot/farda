import env from '@src/common/constants/env';
import { prisma } from '@src/lib/prisma';
import { betterAuth } from 'better-auth';
import { prismaAdapter } from 'better-auth/adapters/prisma';
import { phoneNumber } from 'better-auth/plugins';
import { sendSmsOTP, verifyTwilioOTP } from './services/twilioService';

export const auth = betterAuth({
  database: prismaAdapter(prisma, { provider: 'postgresql' }),
  account: { fields: { providerId: 'provider', accountId: 'providerAccountId' } },
  // Never log provider responses, phone numbers, tokens or prescription text.
  logger: { disabled: true },
  socialProviders: {
    ...(env.GOOGLE_CLIENT_ID && env.GOOGLE_CLIENT_SECRET ? { google: { clientId: env.GOOGLE_CLIENT_ID, clientSecret: env.GOOGLE_CLIENT_SECRET } } : {}),
    ...(env.APPLE_CLIENT_ID && env.APPLE_CLIENT_SECRET ? { apple: { clientId: env.APPLE_CLIENT_ID, clientSecret: env.APPLE_CLIENT_SECRET } } : {}),
    ...(env.FACEBOOK_CLIENT_ID && env.FACEBOOK_CLIENT_SECRET ? { facebook: { clientId: env.FACEBOOK_CLIENT_ID, clientSecret: env.FACEBOOK_CLIENT_SECRET } } : {}),
  },
  plugins: [phoneNumber({
    phoneNumberValidator: number => /^\+[1-9]\d{7,14}$/.test(number),
    requireVerification: true, allowedAttempts: 5, expiresIn: 300,
    sendOTP: async ({ phoneNumber, code }) => { await sendSmsOTP(phoneNumber, code); },
    verifyOTP: async ({ phoneNumber, code }) => (await verifyTwilioOTP(phoneNumber, code)).status === 'approved',
    signUpOnVerification: {
      getTempEmail: number => `${number}@phone-only.local`,
      getTempName: () => 'Farda member',
    },
  })],
});
