// Operator-only: reads private JSON from stdin; never prints patient or medication
// details. Defaults to verification only. This command never places an order.
import { readFileSync } from 'node:fs';
import { prisma } from '../src/lib/prisma';
import env from '../src/common/constants/env';
import { PhotonRefillsProvider } from '../src/refills/providers/photon';
import { providerLinkInput, provisionRefillLink } from '../src/refills/provision';

async function main() {
  const flags = new Set(process.argv.slice(2));
  if ([...flags].some(flag => !['--apply', '--confirm-production'].includes(flag))) throw new Error('Invalid arguments');
  const raw = readFileSync(0, 'utf8');
  if (Buffer.byteLength(raw) > 8192) throw new Error('Input too large');
  const input = providerLinkInput.parse(JSON.parse(raw));
  if (input.environment === 'production' && !flags.has('--confirm-production')) throw new Error('Explicit environment confirmation required');
  const provider = new PhotonRefillsProvider({ enabled: env.FARDA_REFILL_PROVIDER_ENABLED, environment: env.FARDA_REFILL_PROVIDER_ENVIRONMENT, clientId: env.PHOTON_CLIENT_ID, clientSecret: env.PHOTON_CLIENT_SECRET });
  const result = await provisionRefillLink(prisma, provider, input, flags.has('--apply'));
  process.stdout.write(JSON.stringify(result) + '\n');
}
void main().catch(() => {
  process.stderr.write('Link not provisioned. Check the environment, record ownership, provider eligibility and operator-reviewed medication match. No refill was submitted.\n');
  process.exitCode = 1;
}).finally(() => prisma.$disconnect());
