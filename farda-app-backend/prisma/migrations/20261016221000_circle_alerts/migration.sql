CREATE TABLE "CircleAlertPolicy" (
  "grantId" TEXT NOT NULL,
  "enabled" BOOLEAN NOT NULL DEFAULT false,
  "recipientConsented" BOOLEAN NOT NULL DEFAULT false,
  "gracePeriodMinutes" INTEGER NOT NULL DEFAULT 30,
  "quietHoursStart" TEXT NOT NULL DEFAULT '21:00',
  "quietHoursEnd" TEXT NOT NULL DEFAULT '08:00',
  "timeZone" TEXT NOT NULL DEFAULT 'UTC',
  "lastEvaluatedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "CircleAlertPolicy_pkey" PRIMARY KEY ("grantId"),
  CONSTRAINT "CircleAlertPolicy_grantId_fkey" FOREIGN KEY ("grantId") REFERENCES "CircleGrant"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "CircleAlertPolicy_grace_check" CHECK ("gracePeriodMinutes" BETWEEN 15 AND 240),
  CONSTRAINT "CircleAlertPolicy_clock_check" CHECK ("quietHoursStart" ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' AND "quietHoursEnd" ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$')
);

CREATE TABLE "CircleAlert" (
  "id" TEXT NOT NULL,
  "grantId" TEXT NOT NULL,
  "ownerId" TEXT NOT NULL,
  "recipientId" TEXT NOT NULL,
  "doseId" TEXT NOT NULL,
  "kind" TEXT NOT NULL DEFAULT 'confirmation_not_recorded',
  "scheduledFor" TIMESTAMP(3) NOT NULL,
  "state" TEXT NOT NULL DEFAULT 'active',
  "cancelReason" TEXT,
  "readAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "CircleAlert_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "CircleAlert_grantId_fkey" FOREIGN KEY ("grantId") REFERENCES "CircleGrant"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "CircleAlert_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "CircleAlert_recipientId_fkey" FOREIGN KEY ("recipientId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "CircleAlert_doseId_fkey" FOREIGN KEY ("doseId") REFERENCES "Dose"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "CircleAlert_state_check" CHECK ("state" IN ('active', 'cancelled')),
  CONSTRAINT "CircleAlert_kind_check" CHECK ("kind" = 'confirmation_not_recorded')
);

CREATE INDEX "CircleAlertPolicy_enabled_recipientConsented_idx" ON "CircleAlertPolicy"("enabled", "recipientConsented");
CREATE INDEX "CircleAlertPolicy_lastEvaluatedAt_idx" ON "CircleAlertPolicy"("lastEvaluatedAt");
CREATE UNIQUE INDEX "CircleAlert_grantId_doseId_kind_key" ON "CircleAlert"("grantId", "doseId", "kind");
CREATE INDEX "CircleAlert_recipientId_state_createdAt_idx" ON "CircleAlert"("recipientId", "state", "createdAt");
CREATE INDEX "CircleAlert_state_scheduledFor_idx" ON "CircleAlert"("state", "scheduledFor");
