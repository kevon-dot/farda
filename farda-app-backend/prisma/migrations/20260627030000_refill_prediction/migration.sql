-- Refill prediction + refill-event capture (GTM-541).
--
-- Adds the RefillEvent log: one row per refill action (requested / completed /
-- delayed) keyed to the session user + prescription, feeding refill-adherence
-- metrics and acting as the seam a real pharmacy auto-refill provider would
-- write to. The predicted-depletion / refill-due CALC is pure application code
-- (see src/services/RefillService.ts) and needs no schema of its own — it is
-- derived on read from existing Prescription qty + Dose rows.
--
-- Hand-authored (like the multi-med / audit-log / reminder-engine migrations)
-- because `prisma generate` / `migrate` need a live database that is not
-- available in this environment. Guards (IF EXISTS / IF NOT EXISTS) make this
-- idempotent and safe to apply on top of any prior migration.

-- ---------------------------------------------------------------------------
-- RefillEvent: the refill lifecycle log. The FK to Prescription is ON DELETE
-- SET NULL so deleting a prescription never destroys the historical refill
-- events (they outlive the Rx for adherence analytics), mirroring the
-- ReminderResponseEvent -> Dose pattern.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "RefillEvent" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "prescriptionId" TEXT,
    "eventType" TEXT NOT NULL,
    "outcome" TEXT,
    "refillDueDate" TIMESTAMP(3),
    "occurredAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "channel" TEXT NOT NULL DEFAULT 'MANUAL',
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RefillEvent_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX IF NOT EXISTS "RefillEvent_userId_idx" ON "RefillEvent"("userId");
CREATE INDEX IF NOT EXISTS "RefillEvent_prescriptionId_idx" ON "RefillEvent"("prescriptionId");
CREATE INDEX IF NOT EXISTS "RefillEvent_eventType_idx" ON "RefillEvent"("eventType");

-- AddForeignKey: RefillEvent -> User (ON DELETE CASCADE)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'RefillEvent_userId_fkey'
    ) THEN
        ALTER TABLE "RefillEvent" ADD CONSTRAINT "RefillEvent_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;

-- AddForeignKey: RefillEvent -> Prescription (nullable, ON DELETE SET NULL)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'RefillEvent_prescriptionId_fkey'
    ) THEN
        ALTER TABLE "RefillEvent" ADD CONSTRAINT "RefillEvent_prescriptionId_fkey" FOREIGN KEY ("prescriptionId") REFERENCES "Prescription"("id") ON DELETE SET NULL ON UPDATE CASCADE;
    END IF;
END $$;
