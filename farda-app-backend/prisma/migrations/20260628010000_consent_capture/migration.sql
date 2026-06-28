-- In-product tiered consent capture (GTM-523).
--
-- Adds the per-user, APPEND-ONLY Consent history and its ordered tier enum
-- (ConsentTier). Consent is the SOURCE OF TRUTH the provenance ledger
-- (ProvenanceLedgerEntry) + data pipeline (DataPipelineService) read to stamp
-- the consent tier + version onto every de-identified / analytic row and to gate
-- whether data may cross into the analytic / sale layer (see
-- src/services/ConsentService.ts + DataPipelineService.ts).
--
-- Append-only: every consent change INSERTs a new row; existing rows are never
-- mutated. The "current" consent for a user is the latest non-revoked row
-- (revokedAt IS NULL) by grantedAt. Revoking writes a row with revokedAt set.
--
-- Hand-authored (like the audit-log / reminder-engine / refill / data-layers
-- migrations) because `prisma generate` / `migrate` need a live database that is
-- not available in this environment. Guards (IF NOT EXISTS, pg_type / pg_constraint
-- checks) make this idempotent and safe to re-apply.

-- ---------------------------------------------------------------------------
-- Ordered consent tier enum. Each tier is a SUPERSET of the ones below it:
-- NONE < CARE_TEAM < RESEARCH < COMMERCIAL_AI_TRAINING. The numeric ordering
-- lives in application code (CONSENT_TIER_RANK); this enum only constrains the
-- persisted value. Created guarded so re-applying the migration is a no-op.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'ConsentTier') THEN
        CREATE TYPE "ConsentTier" AS ENUM ('NONE', 'CARE_TEAM', 'RESEARCH', 'COMMERCIAL_AI_TRAINING');
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Consent: per-user append-only consent history.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "Consent" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "tier" "ConsentTier" NOT NULL,
    "version" TEXT NOT NULL,
    "scopes" JSONB,
    "purpose" TEXT,
    "grantedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "revokedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Consent_pkey" PRIMARY KEY ("id")
);

-- "current consent" lookups (latest non-revoked per user) + history scans.
CREATE INDEX IF NOT EXISTS "Consent_userId_idx" ON "Consent"("userId");
CREATE INDEX IF NOT EXISTS "Consent_userId_grantedAt_idx" ON "Consent"("userId", "grantedAt");
CREATE INDEX IF NOT EXISTS "Consent_tier_idx" ON "Consent"("tier");

-- AddForeignKey: Consent -> User. ON DELETE CASCADE: a user's consent history is
-- their own data and is removed with the user (unlike the audit / provenance
-- ledgers, which outlive the actor by design).
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'Consent_userId_fkey'
    ) THEN
        ALTER TABLE "Consent" ADD CONSTRAINT "Consent_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;
