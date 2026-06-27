-- Reminder + notification engine (GTM-537).
--
-- Adds the data the reminder/notification engine needs to (a) survive reinstall,
-- (b) respect quiet hours / timezone, (c) register push tokens, and (d) log the
-- reminder-response event stream that feeds the dose-event analytics pipeline.
--
-- Hand-authored (like the multi-med / audit-log migrations) because `prisma
-- generate` / `migrate` need a live database that is not available in this
-- environment. Guards (IF EXISTS / IF NOT EXISTS) make this idempotent and safe
-- to apply to a database created by any prior migration.

-- ---------------------------------------------------------------------------
-- 1. User: delivery-preference columns (timezone + quiet hours).
--    The app enforces timing; the backend only stores these so preferences
--    survive reinstall and feed analytics.
-- ---------------------------------------------------------------------------
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "timezone" TEXT;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "quietHoursStart" INTEGER;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "quietHoursEnd" INTEGER;

-- ---------------------------------------------------------------------------
-- 2. Prescription: thin reminder config. Doses remain the source of truth for
--    WHEN; this only governs reminder on/off + any user-customised times.
--    `reminderEnabled` defaults true so existing prescriptions keep reminding.
-- ---------------------------------------------------------------------------
ALTER TABLE "Prescription" ADD COLUMN IF NOT EXISTS "reminderEnabled" BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE "Prescription" ADD COLUMN IF NOT EXISTS "reminderTimes" JSONB;

-- ---------------------------------------------------------------------------
-- 3. ReminderResponseEvent: the reminder lifecycle log (delivered / opened /
--    snoozed / dismissed / actioned). Keyed to the session user + dose. The
--    FK to Dose is ON DELETE SET NULL so deleting a dose never destroys the
--    historical events (they outlive the dose for analytics).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "ReminderResponseEvent" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "doseId" TEXT,
    "eventType" TEXT NOT NULL,
    "scheduledFor" TIMESTAMP(3),
    "occurredAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "snoozeMinutes" INTEGER,
    "timeToActionMs" INTEGER,
    "channel" TEXT NOT NULL DEFAULT 'LOCAL',
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ReminderResponseEvent_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX IF NOT EXISTS "ReminderResponseEvent_userId_idx" ON "ReminderResponseEvent"("userId");
CREATE INDEX IF NOT EXISTS "ReminderResponseEvent_doseId_idx" ON "ReminderResponseEvent"("doseId");
CREATE INDEX IF NOT EXISTS "ReminderResponseEvent_eventType_idx" ON "ReminderResponseEvent"("eventType");
CREATE INDEX IF NOT EXISTS "ReminderResponseEvent_scheduledFor_idx" ON "ReminderResponseEvent"("scheduledFor");

-- AddForeignKey: ReminderResponseEvent -> User (ON DELETE CASCADE)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ReminderResponseEvent_userId_fkey'
    ) THEN
        ALTER TABLE "ReminderResponseEvent" ADD CONSTRAINT "ReminderResponseEvent_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;

-- AddForeignKey: ReminderResponseEvent -> Dose (nullable, ON DELETE SET NULL)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ReminderResponseEvent_doseId_fkey'
    ) THEN
        ALTER TABLE "ReminderResponseEvent" ADD CONSTRAINT "ReminderResponseEvent_doseId_fkey" FOREIGN KEY ("doseId") REFERENCES "Dose"("id") ON DELETE SET NULL ON UPDATE CASCADE;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 4. PushToken: one push-notification token per user device. SCAFFOLD ONLY --
--    sending push (FCM/APNs) is not implemented (needs a Firebase project +
--    APNs cert). The token column is unique so re-registering upserts cleanly.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "PushToken" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "token" TEXT NOT NULL,
    "platform" TEXT NOT NULL,
    "deviceId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PushToken_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "PushToken_token_key" ON "PushToken"("token");
CREATE INDEX IF NOT EXISTS "PushToken_userId_idx" ON "PushToken"("userId");

-- AddForeignKey: PushToken -> User (ON DELETE CASCADE)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'PushToken_userId_fkey'
    ) THEN
        ALTER TABLE "PushToken" ADD CONSTRAINT "PushToken_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;
