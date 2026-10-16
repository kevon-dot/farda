CREATE TABLE "CircleInvitation" (
  "id" TEXT NOT NULL,
  "ownerId" TEXT NOT NULL,
  "recipientId" TEXT,
  "recipientPhoneHash" TEXT NOT NULL,
  "recipientPhoneLast4" TEXT NOT NULL,
  "secretHash" TEXT NOT NULL,
  "shareDoseStatus" BOOLEAN NOT NULL DEFAULT true,
  "shareReminders" BOOLEAN NOT NULL DEFAULT true,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "CircleInvitation_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "CircleInvitation_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "CircleInvitation_recipientId_fkey" FOREIGN KEY ("recipientId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX "CircleInvitation_ownerId_expiresAt_idx" ON "CircleInvitation"("ownerId", "expiresAt");
CREATE INDEX "CircleInvitation_recipientId_expiresAt_idx" ON "CircleInvitation"("recipientId", "expiresAt");
CREATE INDEX "CircleInvitation_recipientPhoneHash_expiresAt_idx" ON "CircleInvitation"("recipientPhoneHash", "expiresAt");
CREATE UNIQUE INDEX "CircleInvitation_ownerId_recipientPhoneHash_key" ON "CircleInvitation"("ownerId", "recipientPhoneHash");

CREATE TABLE "CircleGrant" (
  "id" TEXT NOT NULL,
  "ownerId" TEXT NOT NULL,
  "recipientId" TEXT NOT NULL,
  "shareDoseStatus" BOOLEAN NOT NULL DEFAULT true,
  "shareReminders" BOOLEAN NOT NULL DEFAULT true,
  "acceptedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "CircleGrant_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "CircleGrant_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "CircleGrant_recipientId_fkey" FOREIGN KEY ("recipientId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "CircleGrant_ownerId_recipientId_key" ON "CircleGrant"("ownerId", "recipientId");
CREATE INDEX "CircleGrant_recipientId_idx" ON "CircleGrant"("recipientId");
