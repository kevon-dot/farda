CREATE TABLE "NativeBillingSubscription" (
    "userId" TEXT NOT NULL,
    "revenueCatAppUserId" TEXT NOT NULL,
    "tier" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "everPurchased" BOOLEAN NOT NULL DEFAULT false,
    "productId" TEXT,
    "store" TEXT,
    "isSandbox" BOOLEAN,
    "expiresAt" TIMESTAMP(3),
    "lastSyncedAt" TIMESTAMP(3) NOT NULL,
    "lastVerificationAttemptAt" TIMESTAMP(3),
    "purchaseReservedUntil" TIMESTAMP(3),
    "purchasePlatform" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "NativeBillingSubscription_pkey" PRIMARY KEY ("userId")
);

CREATE TABLE "NativeBillingWebhookEvent" (
    "revenueCatEventId" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "processedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "NativeBillingWebhookEvent_pkey" PRIMARY KEY ("revenueCatEventId")
);

CREATE UNIQUE INDEX "NativeBillingSubscription_revenueCatAppUserId_key" ON "NativeBillingSubscription"("revenueCatAppUserId");
CREATE INDEX "NativeBillingSubscription_tier_status_expiresAt_idx" ON "NativeBillingSubscription"("tier", "status", "expiresAt");
CREATE INDEX "NativeBillingSubscription_purchaseReservedUntil_idx" ON "NativeBillingSubscription"("purchaseReservedUntil");
ALTER TABLE "NativeBillingSubscription" ADD CONSTRAINT "NativeBillingSubscription_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
