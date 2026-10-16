-- CreateTable
CREATE TABLE "RefillProviderLink" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "prescriptionId" TEXT NOT NULL,
    "environment" TEXT NOT NULL,
    "patientId" TEXT NOT NULL,
    "providerPrescriptionId" TEXT NOT NULL,
    "pharmacyId" TEXT NOT NULL,
    "enabled" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "RefillProviderLink_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RefillAgentReview" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "prescriptionId" TEXT NOT NULL,
    "snapshot" JSONB NOT NULL,
    "snapshotHash" TEXT NOT NULL,
    "localRevision" TIMESTAMP(3) NOT NULL,
    "linkRevision" TIMESTAMP(3) NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RefillAgentReview_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RefillAgentRequest" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "prescriptionId" TEXT NOT NULL,
    "reviewId" TEXT NOT NULL,
    "requestKey" TEXT NOT NULL,
    "environment" TEXT NOT NULL,
    "patientId" TEXT NOT NULL,
    "providerPrescriptionId" TEXT NOT NULL,
    "pharmacyId" TEXT NOT NULL,
    "providerOrderId" TEXT,
    "status" TEXT NOT NULL DEFAULT 'submitting',
    "providerConfirmed" BOOLEAN NOT NULL DEFAULT false,
    "failureCode" TEXT,
    "lastCheckedAt" TIMESTAMP(3),
    "refreshClaimedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "RefillAgentRequest_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "RefillProviderLink_prescriptionId_key" ON "RefillProviderLink"("prescriptionId");

-- CreateIndex
CREATE INDEX "RefillProviderLink_userId_idx" ON "RefillProviderLink"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "RefillProviderLink_environment_patientId_providerPrescripti_key" ON "RefillProviderLink"("environment", "patientId", "providerPrescriptionId");

-- CreateIndex
CREATE INDEX "RefillAgentReview_userId_prescriptionId_expiresAt_idx" ON "RefillAgentReview"("userId", "prescriptionId", "expiresAt");

-- CreateIndex
CREATE UNIQUE INDEX "RefillAgentRequest_reviewId_key" ON "RefillAgentRequest"("reviewId");

-- CreateIndex
CREATE INDEX "RefillAgentRequest_userId_prescriptionId_createdAt_idx" ON "RefillAgentRequest"("userId", "prescriptionId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "RefillAgentRequest_userId_requestKey_key" ON "RefillAgentRequest"("userId", "requestKey");

-- AddForeignKey
ALTER TABLE "RefillProviderLink" ADD CONSTRAINT "RefillProviderLink_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RefillProviderLink" ADD CONSTRAINT "RefillProviderLink_prescriptionId_fkey" FOREIGN KEY ("prescriptionId") REFERENCES "Prescription"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RefillAgentReview" ADD CONSTRAINT "RefillAgentReview_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RefillAgentReview" ADD CONSTRAINT "RefillAgentReview_prescriptionId_fkey" FOREIGN KEY ("prescriptionId") REFERENCES "Prescription"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RefillAgentRequest" ADD CONSTRAINT "RefillAgentRequest_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RefillAgentRequest" ADD CONSTRAINT "RefillAgentRequest_prescriptionId_fkey" FOREIGN KEY ("prescriptionId") REFERENCES "Prescription"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RefillAgentRequest" ADD CONSTRAINT "RefillAgentRequest_reviewId_fkey" FOREIGN KEY ("reviewId") REFERENCES "RefillAgentReview"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
