import "dotenv/config";
import { PrismaPg } from "@prisma/adapter-pg";
import env from "@src/common/constants/env";
import { PrismaClient } from "../../generated/prisma/client";

const connectionString = `${env.DATABASE_URL}`;

const adapter = new PrismaPg({ connectionString });
const prisma = new PrismaClient({ adapter });

export { prisma };
