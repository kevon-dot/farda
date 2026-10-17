-- Persist the Photon read/reconciliation schedule. Existing nonterminal
-- attempts become due after deployment; no provider mutation is performed.
ALTER TABLE "RefillAgentRequest"
ADD COLUMN "reconcileAttempts" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN "nextReconcileAt" TIMESTAMP(3),
ADD COLUMN "operatorAlertedAt" TIMESTAMP(3);

UPDATE "RefillAgentRequest"
SET "nextReconcileAt" = CURRENT_TIMESTAMP
WHERE "status" IN ('submitting', 'unknown', 'sent', 'received', 'ready', 'shipped');

CREATE INDEX "RefillAgentRequest_environment_status_nextReconcileAt_idx"
ON "RefillAgentRequest"("environment", "status", "nextReconcileAt");
