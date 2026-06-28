-- 3-layer data store + de-identification + provenance ledger (GTM-522).
--
-- Adds the de-identified layer (DeidentifiedSubject + DeidentifiedEvent), the
-- analytic layer (AnalyticMetric) and the append-only, tamper-evident
-- ProvenanceLedgerEntry. The existing PHI tables (User/Prescription/Medicine/
-- Dose/...) are the IDENTIFIED layer and are left untouched.
--
-- De-identified layer: keyed by a one-way salted pseudonym (subjectKey =
-- sha256(DEID_SALT + identifiedUserId), computed in application code; see
-- src/services/DeidentificationService.ts). There is intentionally NO foreign
-- key from this layer back to "User" — re-identification must be impossible
-- from the de-id layer alone (HIPAA Safe-Harbor).
--
-- ProvenanceLedgerEntry: APPEND-ONLY, tamper-evident SHA-256 hash chain
-- (hash = sha256(prevHash + canonical(entry))) computed in application code
-- (see src/services/ProvenanceService.ts), mirroring AuditLog. There is
-- intentionally NO `updatedAt` column. Its FK to "User" is nullable + ON DELETE
-- SET NULL so the ledger outlives the actor.
--
-- Hand-authored (like the multi-med / audit-log / reminder-engine / refill
-- migrations) because `prisma generate` / `migrate` need a live database that
-- is not available in this environment. Guards (IF NOT EXISTS, pg_constraint
-- checks) make this idempotent and safe to re-apply.

-- ---------------------------------------------------------------------------
-- DE-IDENTIFIED layer: DeidentifiedSubject (pseudonymous subject; no user FK).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "DeidentifiedSubject" (
    "id" TEXT NOT NULL,
    "subjectKey" TEXT NOT NULL,
    "ageBand" TEXT,
    "region" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "DeidentifiedSubject_pkey" PRIMARY KEY ("id")
);

-- The pseudonym is unique so re-projecting the same user upserts (idempotent).
CREATE UNIQUE INDEX IF NOT EXISTS "DeidentifiedSubject_subjectKey_key" ON "DeidentifiedSubject"("subjectKey");
CREATE INDEX IF NOT EXISTS "DeidentifiedSubject_subjectKey_idx" ON "DeidentifiedSubject"("subjectKey");

-- ---------------------------------------------------------------------------
-- DE-IDENTIFIED layer: DeidentifiedEvent (date-shifted, PHI-free events).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "DeidentifiedEvent" (
    "id" TEXT NOT NULL,
    "subjectId" TEXT NOT NULL,
    "eventType" TEXT NOT NULL,
    "dayOffset" INTEGER NOT NULL,
    "hourBucket" INTEGER,
    "value" DOUBLE PRECISION,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DeidentifiedEvent_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "DeidentifiedEvent_subjectId_idx" ON "DeidentifiedEvent"("subjectId");
CREATE INDEX IF NOT EXISTS "DeidentifiedEvent_eventType_idx" ON "DeidentifiedEvent"("eventType");
CREATE INDEX IF NOT EXISTS "DeidentifiedEvent_dayOffset_idx" ON "DeidentifiedEvent"("dayOffset");

-- AddForeignKey: DeidentifiedEvent -> DeidentifiedSubject (ON DELETE CASCADE).
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'DeidentifiedEvent_subjectId_fkey'
    ) THEN
        ALTER TABLE "DeidentifiedEvent" ADD CONSTRAINT "DeidentifiedEvent_subjectId_fkey" FOREIGN KEY ("subjectId") REFERENCES "DeidentifiedSubject"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- ANALYTIC layer: AnalyticMetric (PHI-free roll-ups; no subject/user FK).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "AnalyticMetric" (
    "id" TEXT NOT NULL,
    "metric" TEXT NOT NULL,
    "cohort" TEXT,
    "period" TEXT NOT NULL,
    "value" DOUBLE PRECISION NOT NULL,
    "sampleSize" INTEGER NOT NULL DEFAULT 0,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AnalyticMetric_pkey" PRIMARY KEY ("id")
);

-- One row per (metric, cohort, period) so re-aggregation upserts in place.
CREATE UNIQUE INDEX IF NOT EXISTS "AnalyticMetric_metric_cohort_period_key" ON "AnalyticMetric"("metric", "cohort", "period");
CREATE INDEX IF NOT EXISTS "AnalyticMetric_metric_idx" ON "AnalyticMetric"("metric");
CREATE INDEX IF NOT EXISTS "AnalyticMetric_period_idx" ON "AnalyticMetric"("period");

-- ---------------------------------------------------------------------------
-- PROVENANCE LEDGER: ProvenanceLedgerEntry. APPEND-ONLY, tamper-evident
-- SHA-256 hash chain (no `updatedAt`). FK to "User" is ON DELETE SET NULL so
-- the ledger outlives the actor, mirroring AuditLog.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "ProvenanceLedgerEntry" (
    "id" TEXT NOT NULL,
    "actorUserId" TEXT,
    "operation" TEXT NOT NULL,
    "layer" TEXT NOT NULL,
    "sourceLayer" TEXT,
    "resourceType" TEXT NOT NULL,
    "resourceId" TEXT,
    "ip" TEXT,
    "userAgent" TEXT,
    "metadata" JSONB,
    "prevHash" TEXT,
    "hash" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ProvenanceLedgerEntry_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "ProvenanceLedgerEntry_actorUserId_idx" ON "ProvenanceLedgerEntry"("actorUserId");
CREATE INDEX IF NOT EXISTS "ProvenanceLedgerEntry_operation_idx" ON "ProvenanceLedgerEntry"("operation");
CREATE INDEX IF NOT EXISTS "ProvenanceLedgerEntry_layer_idx" ON "ProvenanceLedgerEntry"("layer");
CREATE INDEX IF NOT EXISTS "ProvenanceLedgerEntry_resourceType_idx" ON "ProvenanceLedgerEntry"("resourceType");
CREATE INDEX IF NOT EXISTS "ProvenanceLedgerEntry_createdAt_idx" ON "ProvenanceLedgerEntry"("createdAt");

-- AddForeignKey: ProvenanceLedgerEntry -> User (nullable, ON DELETE SET NULL).
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ProvenanceLedgerEntry_actorUserId_fkey'
    ) THEN
        ALTER TABLE "ProvenanceLedgerEntry" ADD CONSTRAINT "ProvenanceLedgerEntry_actorUserId_fkey" FOREIGN KEY ("actorUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
    END IF;
END $$;
