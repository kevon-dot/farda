-- APNs Live Activity tokens are encrypted in the application before storage.
CREATE TABLE "LiveActivityInstallation" (
    "installationId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "sessionId" TEXT NOT NULL,
    "tokenCiphertext" TEXT,
    "tokenFingerprint" TEXT,
    "expiresAt" TIMESTAMP(3),
    "revokedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "LiveActivityInstallation_pkey" PRIMARY KEY ("installationId")
);

CREATE TABLE "LiveActivityToken" (
    "activityId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "installationId" TEXT NOT NULL,
    "doseId" TEXT NOT NULL,
    "tokenCiphertext" TEXT NOT NULL,
    "tokenFingerprint" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "revokedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "LiveActivityToken_pkey" PRIMARY KEY ("activityId")
);

CREATE TABLE "LiveActivityAttempt" (
    "id" TEXT NOT NULL,
    "intentId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "targetFingerprint" TEXT NOT NULL,
    "targetKind" TEXT NOT NULL,
    "state" TEXT NOT NULL DEFAULT 'reserved',
    "providerStatus" TEXT,
    "reason" TEXT,
    "startedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "LiveActivityAttempt_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "LiveActivityInstallation_tokenFingerprint_key" ON "LiveActivityInstallation"("tokenFingerprint");
CREATE INDEX "LiveActivityInstallation_userId_revokedAt_expiresAt_idx" ON "LiveActivityInstallation"("userId", "revokedAt", "expiresAt");
CREATE INDEX "LiveActivityInstallation_sessionId_idx" ON "LiveActivityInstallation"("sessionId");
CREATE UNIQUE INDEX "LiveActivityToken_tokenFingerprint_key" ON "LiveActivityToken"("tokenFingerprint");
CREATE INDEX "LiveActivityToken_userId_doseId_revokedAt_expiresAt_idx" ON "LiveActivityToken"("userId", "doseId", "revokedAt", "expiresAt");
CREATE INDEX "LiveActivityToken_installationId_idx" ON "LiveActivityToken"("installationId");
CREATE UNIQUE INDEX "LiveActivityAttempt_intentId_targetFingerprint_key" ON "LiveActivityAttempt"("intentId", "targetFingerprint");
CREATE INDEX "LiveActivityAttempt_userId_state_updatedAt_idx" ON "LiveActivityAttempt"("userId", "state", "updatedAt");

ALTER TABLE "LiveActivityInstallation" ADD CONSTRAINT "LiveActivityInstallation_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "LiveActivityInstallation" ADD CONSTRAINT "LiveActivityInstallation_sessionId_fkey" FOREIGN KEY ("sessionId") REFERENCES "Session"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "LiveActivityToken" ADD CONSTRAINT "LiveActivityToken_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "LiveActivityToken" ADD CONSTRAINT "LiveActivityToken_installationId_fkey" FOREIGN KEY ("installationId") REFERENCES "LiveActivityInstallation"("installationId") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "LiveActivityToken" ADD CONSTRAINT "LiveActivityToken_doseId_fkey" FOREIGN KEY ("doseId") REFERENCES "Dose"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "LiveActivityAttempt" ADD CONSTRAINT "LiveActivityAttempt_intentId_fkey" FOREIGN KEY ("intentId") REFERENCES "ReminderIntent"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "LiveActivityAttempt" ADD CONSTRAINT "LiveActivityAttempt_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
