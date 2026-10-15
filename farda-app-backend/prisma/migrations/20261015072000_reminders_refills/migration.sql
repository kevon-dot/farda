-- AlterTable
ALTER TABLE "Dose" ADD COLUMN     "canceledAt" TIMESTAMP(3),
ADD COLUMN     "snoozedUntil" TIMESTAMP(3);

-- CreateTable
CREATE TABLE "ReminderPreference" (
    "userId" TEXT NOT NULL,
    "callsEnabled" BOOLEAN NOT NULL DEFAULT false,
    "liveActivitiesEnabled" BOOLEAN NOT NULL DEFAULT false,
    "timeZone" TEXT NOT NULL DEFAULT 'UTC',
    "quietHoursStart" TEXT NOT NULL DEFAULT '21:00',
    "quietHoursEnd" TEXT NOT NULL DEFAULT '08:00',
    "maxCallsPerDay" INTEGER NOT NULL DEFAULT 2,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ReminderPreference_pkey" PRIMARY KEY ("userId")
);

-- CreateTable
CREATE TABLE "ChannelConsent" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "channel" TEXT NOT NULL DEFAULT 'voice',
    "phoneNumber" TEXT NOT NULL,
    "wordingVersion" TEXT NOT NULL,
    "grantedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "withdrawnAt" TIMESTAMP(3),

    CONSTRAINT "ChannelConsent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ReminderIntent" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "doseId" TEXT NOT NULL,
    "channel" TEXT NOT NULL,
    "stage" TEXT NOT NULL,
    "dueAt" TIMESTAMP(3) NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "state" TEXT NOT NULL DEFAULT 'pending',
    "reason" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ReminderIntent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DeliveryAttempt" (
    "id" TEXT NOT NULL,
    "intentId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "channel" TEXT NOT NULL,
    "phoneNumber" TEXT,
    "state" TEXT NOT NULL DEFAULT 'reserved',
    "providerId" TEXT,
    "providerStatus" TEXT,
    "providerSequence" INTEGER NOT NULL DEFAULT -1,
    "reason" TEXT,
    "startedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "DeliveryAttempt_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RefillIntent" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "prescriptionId" TEXT NOT NULL,
    "kind" TEXT NOT NULL DEFAULT 'refill',
    "status" TEXT NOT NULL DEFAULT 'planned',
    "plannedFor" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "RefillIntent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RefillEvent" (
    "id" TEXT NOT NULL,
    "refillId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "source" TEXT NOT NULL DEFAULT 'user_report',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RefillEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "InventoryBalance" (
    "prescriptionId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "quantity" INTEGER NOT NULL,
    "observedAt" TIMESTAMP(3) NOT NULL,
    "source" TEXT NOT NULL DEFAULT 'user_count',
    "revision" INTEGER NOT NULL DEFAULT 1,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "InventoryBalance_pkey" PRIMARY KEY ("prescriptionId")
);

-- CreateTable
CREATE TABLE "InventoryEntry" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "prescriptionId" TEXT NOT NULL,
    "refillId" TEXT,
    "kind" TEXT NOT NULL,
    "quantity" INTEGER NOT NULL,
    "delta" INTEGER NOT NULL,
    "requestKey" TEXT NOT NULL,
    "requestHash" TEXT NOT NULL,
    "observedAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "InventoryEntry_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ChannelConsent_userId_channel_withdrawnAt_idx" ON "ChannelConsent"("userId", "channel", "withdrawnAt");

-- CreateIndex
CREATE INDEX "ReminderIntent_state_dueAt_idx" ON "ReminderIntent"("state", "dueAt");

-- CreateIndex
CREATE INDEX "ReminderIntent_userId_doseId_idx" ON "ReminderIntent"("userId", "doseId");

-- CreateIndex
CREATE UNIQUE INDEX "ReminderIntent_doseId_channel_stage_key" ON "ReminderIntent"("doseId", "channel", "stage");

-- CreateIndex
CREATE UNIQUE INDEX "DeliveryAttempt_intentId_key" ON "DeliveryAttempt"("intentId");

-- CreateIndex
CREATE UNIQUE INDEX "DeliveryAttempt_providerId_key" ON "DeliveryAttempt"("providerId");

-- CreateIndex
CREATE INDEX "DeliveryAttempt_userId_channel_createdAt_idx" ON "DeliveryAttempt"("userId", "channel", "createdAt");

-- CreateIndex
CREATE INDEX "DeliveryAttempt_state_updatedAt_idx" ON "DeliveryAttempt"("state", "updatedAt");

-- CreateIndex
CREATE INDEX "RefillIntent_userId_prescriptionId_idx" ON "RefillIntent"("userId", "prescriptionId");

-- CreateIndex
CREATE INDEX "RefillEvent_refillId_createdAt_idx" ON "RefillEvent"("refillId", "createdAt");

-- CreateIndex
CREATE INDEX "InventoryBalance_userId_idx" ON "InventoryBalance"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "InventoryEntry_refillId_key" ON "InventoryEntry"("refillId");

-- CreateIndex
CREATE INDEX "InventoryEntry_prescriptionId_createdAt_idx" ON "InventoryEntry"("prescriptionId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "InventoryEntry_userId_requestKey_key" ON "InventoryEntry"("userId", "requestKey");

-- AddForeignKey
ALTER TABLE "ReminderPreference" ADD CONSTRAINT "ReminderPreference_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ChannelConsent" ADD CONSTRAINT "ChannelConsent_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ReminderIntent" ADD CONSTRAINT "ReminderIntent_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ReminderIntent" ADD CONSTRAINT "ReminderIntent_doseId_fkey" FOREIGN KEY ("doseId") REFERENCES "Dose"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DeliveryAttempt" ADD CONSTRAINT "DeliveryAttempt_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DeliveryAttempt" ADD CONSTRAINT "DeliveryAttempt_intentId_fkey" FOREIGN KEY ("intentId") REFERENCES "ReminderIntent"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RefillIntent" ADD CONSTRAINT "RefillIntent_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RefillIntent" ADD CONSTRAINT "RefillIntent_prescriptionId_fkey" FOREIGN KEY ("prescriptionId") REFERENCES "Prescription"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RefillEvent" ADD CONSTRAINT "RefillEvent_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RefillEvent" ADD CONSTRAINT "RefillEvent_refillId_fkey" FOREIGN KEY ("refillId") REFERENCES "RefillIntent"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "InventoryBalance" ADD CONSTRAINT "InventoryBalance_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "InventoryBalance" ADD CONSTRAINT "InventoryBalance_prescriptionId_fkey" FOREIGN KEY ("prescriptionId") REFERENCES "Prescription"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "InventoryEntry" ADD CONSTRAINT "InventoryEntry_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "InventoryEntry" ADD CONSTRAINT "InventoryEntry_prescriptionId_fkey" FOREIGN KEY ("prescriptionId") REFERENCES "Prescription"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "InventoryEntry" ADD CONSTRAINT "InventoryEntry_refillId_fkey" FOREIGN KEY ("refillId") REFERENCES "RefillIntent"("id") ON DELETE CASCADE ON UPDATE CASCADE;
