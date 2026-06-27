-- HIPAA PHI audit trail (GTM-512, GitHub #6).
--
-- Append-only, tamper-evident log of who accessed/modified which patient's PHI
-- (HIPAA §164.312(b)). Tamper-evidence is provided by a per-row SHA-256 hash
-- chain computed in application code (see src/services/AuditService.ts); this
-- table only stores the resulting `prevHash` / `hash` values.
--
-- APPEND-ONLY: there is intentionally NO `updatedAt` column. Application code
-- must NEVER UPDATE or DELETE rows here.
--
-- The FK to "User" is nullable and ON DELETE SET NULL so that deleting a user
-- never deletes or cascades away their audit history -- the trail must outlive
-- the actor.

-- CreateTable: "AuditLog"
CREATE TABLE "AuditLog" (
    "id" TEXT NOT NULL,
    "actorUserId" TEXT,
    "action" TEXT NOT NULL,
    "resourceType" TEXT NOT NULL,
    "resourceId" TEXT,
    "ip" TEXT,
    "userAgent" TEXT,
    "metadata" JSONB,
    "prevHash" TEXT,
    "hash" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AuditLog_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX IF NOT EXISTS "AuditLog_actorUserId_idx" ON "AuditLog"("actorUserId");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "AuditLog_resourceType_idx" ON "AuditLog"("resourceType");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "AuditLog_createdAt_idx" ON "AuditLog"("createdAt");

-- AddForeignKey: AuditLog -> User (nullable, ON DELETE SET NULL)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'AuditLog_actorUserId_fkey'
    ) THEN
        ALTER TABLE "AuditLog" ADD CONSTRAINT "AuditLog_actorUserId_fkey" FOREIGN KEY ("actorUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
    END IF;
END $$;
