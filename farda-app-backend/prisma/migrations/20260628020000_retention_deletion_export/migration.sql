-- Data retention, deletion/export & consent-revocation workflows (GTM-542).
--
-- Builds ON the GTM-522 3-layer store + GTM-523 consent model. Adds three
-- data-subject-rights tables:
--
--   * RetentionPolicy  — per-data-class retention window (TTL) + legal-hold flag.
--   * DeletionRequest  — request to ERASE a user's IDENTIFIED (service) layer
--                        data (right to erasure / consent revocation).
--   * ExportRequest    — request to ASSEMBLE the user's identified-layer data
--                        into a portable structure (access / portability).
--
-- BOUNDARY: deletion erases the IDENTIFIED layer only. Already-projected
-- DE-IDENTIFIED / ANALYTIC rows are NOT recalled (pseudonymous, no user FK;
-- "can't recall de-identified"). Revocation stops FUTURE projection via the
-- GTM-523 consent gate (see src/services/DataRetentionService.ts).
--
-- Hand-authored (like the audit-log / reminder-engine / refill / data-layers /
-- consent migrations) because `prisma generate` / `migrate` need a live database
-- that is not available in this environment. Guards (IF NOT EXISTS, pg_type /
-- pg_constraint checks) make this idempotent and safe to re-apply.

-- ---------------------------------------------------------------------------
-- Shared lifecycle status enum for deletion + export requests:
-- PENDING -> PROCESSING -> COMPLETED. Created guarded so re-applying is a no-op.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'DataRequestStatus') THEN
        CREATE TYPE "DataRequestStatus" AS ENUM ('PENDING', 'PROCESSING', 'COMPLETED');
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Deletion scope enum. FULL = erase all identified-layer service data. Future
-- scopes can be added without a migration since callers branch on the label.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'DeletionScope') THEN
        CREATE TYPE "DeletionScope" AS ENUM ('FULL');
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- RetentionPolicy: per-data-class retention window + legal-hold flag. The
-- SELECTION of expired records is pure (DataRetentionService.selectExpired);
-- the scheduled sweep is infra.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "RetentionPolicy" (
    "id" TEXT NOT NULL,
    "dataClass" TEXT NOT NULL,
    "retentionDays" INTEGER NOT NULL,
    "legalHold" BOOLEAN NOT NULL DEFAULT false,
    "description" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "RetentionPolicy_pkey" PRIMARY KEY ("id")
);

-- One active policy per data class.
CREATE UNIQUE INDEX IF NOT EXISTS "RetentionPolicy_dataClass_key" ON "RetentionPolicy"("dataClass");
CREATE INDEX IF NOT EXISTS "RetentionPolicy_dataClass_idx" ON "RetentionPolicy"("dataClass");

-- ---------------------------------------------------------------------------
-- DeletionRequest: per-user erasure request (identified layer only).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "DeletionRequest" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "status" "DataRequestStatus" NOT NULL DEFAULT 'PENDING',
    "scope" "DeletionScope" NOT NULL DEFAULT 'FULL',
    "triggeredByRevocation" BOOLEAN NOT NULL DEFAULT false,
    "requestedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "DeletionRequest_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "DeletionRequest_userId_idx" ON "DeletionRequest"("userId");
CREATE INDEX IF NOT EXISTS "DeletionRequest_status_idx" ON "DeletionRequest"("status");

-- AddForeignKey: DeletionRequest -> User. ON DELETE CASCADE: the request is the
-- user's own data (its audit/provenance trail outlives it in the append-only
-- ledgers, which are not cascaded).
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'DeletionRequest_userId_fkey'
    ) THEN
        ALTER TABLE "DeletionRequest" ADD CONSTRAINT "DeletionRequest_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- ExportRequest: per-user data-access / portability request. The portable
-- payload is assembled on demand (DataRetentionService.buildExport); the row
-- tracks the lifecycle only (no PHI stored on the row).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "ExportRequest" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "status" "DataRequestStatus" NOT NULL DEFAULT 'PENDING',
    "format" TEXT NOT NULL DEFAULT 'json',
    "requestedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ExportRequest_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "ExportRequest_userId_idx" ON "ExportRequest"("userId");
CREATE INDEX IF NOT EXISTS "ExportRequest_status_idx" ON "ExportRequest"("status");

-- AddForeignKey: ExportRequest -> User. ON DELETE CASCADE: the request is the
-- user's own data.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ExportRequest_userId_fkey'
    ) THEN
        ALTER TABLE "ExportRequest" ADD CONSTRAINT "ExportRequest_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;
