-- Additive reconciliation: the original checked-in migration omitted Dose even
-- though deployed installations may have created it with db push. Preserve both.
DROP INDEX IF EXISTS "Prescription_userId_key";
ALTER TABLE "Prescription" ADD COLUMN IF NOT EXISTS "labelReviewedAt" TIMESTAMP(3), ADD COLUMN IF NOT EXISTS "archivedAt" TIMESTAMP(3);
ALTER TABLE "Prescription" ADD COLUMN IF NOT EXISTS "clientRequestId" TEXT, ADD COLUMN IF NOT EXISTS "requestHash" TEXT;
CREATE UNIQUE INDEX "Prescription_userId_clientRequestId_key" ON "Prescription"("userId", "clientRequestId");
CREATE TABLE IF NOT EXISTS "Dose" (
  "id" TEXT PRIMARY KEY, "prescriptionId" TEXT NOT NULL, "userId" TEXT NOT NULL,
  "scheduledFor" TIMESTAMP(3) NOT NULL, "takenAt" TIMESTAMP(3), "mood" TEXT, "note" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "Dose_prescriptionId_fkey" FOREIGN KEY ("prescriptionId") REFERENCES "Prescription"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "Dose_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
ALTER TABLE "Dose" ADD COLUMN IF NOT EXISTS "status" TEXT NOT NULL DEFAULT 'unconfirmed',
  ADD COLUMN IF NOT EXISTS "source" TEXT NOT NULL DEFAULT 'legacy_unverified',
  ADD COLUMN IF NOT EXISTS "revision" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "scheduleVersionId" TEXT;
-- Legacy takenAt values are retained as evidence, but cannot establish an
-- explicit self-report because the old mood endpoint populated takenAt too.
ALTER TABLE "Dose" ALTER COLUMN "source" SET DEFAULT 'self_report';
CREATE INDEX IF NOT EXISTS "Dose_userId_idx" ON "Dose"("userId");
CREATE INDEX IF NOT EXISTS "Dose_prescriptionId_idx" ON "Dose"("prescriptionId");
CREATE INDEX IF NOT EXISTS "Dose_userId_scheduledFor_idx" ON "Dose"("userId", "scheduledFor");
CREATE TABLE "ScheduleVersion" (
  "id" TEXT PRIMARY KEY, "prescriptionId" TEXT NOT NULL, "version" INTEGER NOT NULL,
  "timezone" TEXT NOT NULL, "recurrence" TEXT NOT NULL, "times" JSONB NOT NULL,
  "startDate" TIMESTAMP(3) NOT NULL, "durationDays" INTEGER NOT NULL,
  "effectiveAt" TIMESTAMP(3) NOT NULL, "endedAt" TIMESTAMP(3), "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ScheduleVersion_prescriptionId_fkey" FOREIGN KEY ("prescriptionId") REFERENCES "Prescription"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "ScheduleVersion_prescriptionId_version_key" ON "ScheduleVersion"("prescriptionId", "version");
ALTER TABLE "Dose" ADD CONSTRAINT "Dose_scheduleVersionId_fkey" FOREIGN KEY ("scheduleVersionId") REFERENCES "ScheduleVersion"("id") ON DELETE SET NULL ON UPDATE CASCADE;
CREATE UNIQUE INDEX "Dose_scheduleVersionId_scheduledFor_key" ON "Dose"("scheduleVersionId", "scheduledFor");
ALTER TABLE "Dose" ADD CONSTRAINT "Dose_status_check" CHECK ("status" IN ('unconfirmed','taken','skipped','cancelled'));
CREATE TABLE "DoseCorrection" (
  "id" TEXT PRIMARY KEY, "doseId" TEXT NOT NULL, "actorId" TEXT NOT NULL, "revision" INTEGER NOT NULL,
  "before" JSONB NOT NULL, "after" JSONB NOT NULL, "reason" TEXT, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "DoseCorrection_doseId_fkey" FOREIGN KEY ("doseId") REFERENCES "Dose"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "DoseCorrection_doseId_revision_key" ON "DoseCorrection"("doseId", "revision");
ALTER TABLE "Account" ALTER COLUMN "type" SET DEFAULT 'oauth';
CREATE TABLE "ApiRateLimit" ("key" TEXT PRIMARY KEY, "count" INTEGER NOT NULL, "expiresAt" TIMESTAMP(3) NOT NULL);
CREATE INDEX "ApiRateLimit_expiresAt_idx" ON "ApiRateLimit"("expiresAt");
ALTER TABLE "Account" ADD COLUMN IF NOT EXISTS "refreshTokenExpiresAt" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "idToken" TEXT, ADD COLUMN IF NOT EXISTS "scope" TEXT,
  ADD COLUMN IF NOT EXISTS "password" TEXT,
  ADD COLUMN IF NOT EXISTS "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ADD COLUMN IF NOT EXISTS "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;
