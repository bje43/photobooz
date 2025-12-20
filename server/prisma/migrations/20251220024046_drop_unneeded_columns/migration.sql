/*
  Warnings:

  - You are about to drop the column `assignedTech` on the `photobooths` table. All the data in the column will be lost.
  - You are about to drop the column `geographicArea` on the `photobooths` table. All the data in the column will be lost.

*/
-- AlterTable
ALTER TABLE "photobooths" DROP COLUMN "assignedTech",
DROP COLUMN "geographicArea";
