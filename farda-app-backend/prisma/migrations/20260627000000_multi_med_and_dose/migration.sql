-- Multi-medicine + Dose data model (GTM-511, issues #12 / #13).
--
-- 1. The original init migration (20260312031911_init) never created the "Dose"
--    table even though the Prisma schema + application code rely on it, so every
--    dose operation fails on a freshly-migrated database (#12). Create it here.
-- 2. "Prescription.userId" was effectively unique (one prescription per user).
--    Drop any unique index and keep a plain index so a user can hold multiple
--    prescriptions (#13).
-- 3. Add the "Medicine" table so a prescription can persist EVERY medication the
--    OCR step extracts instead of only the first (#13). The single-medication
--    columns on "Prescription" (medicationName / dosageInstructions) are removed
--    in favour of the new one-to-many relation.
--
-- Guards (IF EXISTS / IF NOT EXISTS) make this safe whether or not the prior
-- init migration created the omitted objects.

-- DropIndex: remove one-prescription-per-user uniqueness, keep a plain index.
DROP INDEX IF EXISTS "Prescription_userId_key";

-- CreateIndex (idempotent): non-unique index on Prescription.userId.
CREATE INDEX IF NOT EXISTS "Prescription_userId_idx" ON "Prescription"("userId");

-- AlterTable: drop the single-medication columns now modelled by "Medicine".
ALTER TABLE "Prescription" DROP COLUMN IF EXISTS "medicationName";
ALTER TABLE "Prescription" DROP COLUMN IF EXISTS "dosageInstructions";

-- CreateTable: "Dose" (omitted by the init migration, #12).
CREATE TABLE IF NOT EXISTS "Dose" (
    "id" TEXT NOT NULL,
    "prescriptionId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "scheduledFor" TIMESTAMP(3) NOT NULL,
    "takenAt" TIMESTAMP(3),
    "mood" TEXT,
    "note" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Dose_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX IF NOT EXISTS "Dose_userId_idx" ON "Dose"("userId");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "Dose_prescriptionId_idx" ON "Dose"("prescriptionId");

-- CreateTable: "Medicine" (one-to-many from Prescription, #13).
CREATE TABLE "Medicine" (
    "id" TEXT NOT NULL,
    "prescriptionId" TEXT NOT NULL,
    "medicineName" TEXT NOT NULL,
    "genericName" TEXT,
    "dosageInstructions" TEXT,
    "strength" TEXT,
    "qty" TEXT,
    "frequency" TEXT,
    "refillsInfo" TEXT,
    "sideEffects" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Medicine_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "Medicine_prescriptionId_idx" ON "Medicine"("prescriptionId");

-- AddForeignKey: Dose -> User
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'Dose_userId_fkey'
    ) THEN
        ALTER TABLE "Dose" ADD CONSTRAINT "Dose_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;

-- AddForeignKey: Dose -> Prescription
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'Dose_prescriptionId_fkey'
    ) THEN
        ALTER TABLE "Dose" ADD CONSTRAINT "Dose_prescriptionId_fkey" FOREIGN KEY ("prescriptionId") REFERENCES "Prescription"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;

-- AddForeignKey: Medicine -> Prescription
ALTER TABLE "Medicine" ADD CONSTRAINT "Medicine_prescriptionId_fkey" FOREIGN KEY ("prescriptionId") REFERENCES "Prescription"("id") ON DELETE CASCADE ON UPDATE CASCADE;
