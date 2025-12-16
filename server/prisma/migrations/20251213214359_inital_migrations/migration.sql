-- CreateTable
CREATE TABLE "photobooths" (
    "id" TEXT NOT NULL,
    "boothId" TEXT NOT NULL,
    "name" TEXT,
    "lastPing" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "photobooths_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "health_logs" (
    "id" TEXT NOT NULL,
    "photoboothId" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "message" TEXT,
    "metadata" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "health_logs_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "photobooths_boothId_key" ON "photobooths"("boothId");

-- AddForeignKey
ALTER TABLE "health_logs" ADD CONSTRAINT "health_logs_photoboothId_fkey" FOREIGN KEY ("photoboothId") REFERENCES "photobooths"("id") ON DELETE CASCADE ON UPDATE CASCADE;
