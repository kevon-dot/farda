import HttpStatusCodes from "@src/common/constants/HttpStatusCodes";
import { prisma } from "@src/lib/prisma";
import type { NextFunction, Request, Response } from "express";

export const isAuthenticated = async (
	req: Request,
	res: Response,
	next: NextFunction,
) => {
	try {
		const authHeader = req.headers.authorization;

		if (!authHeader || !authHeader.startsWith("Bearer ")) {
			return res
				.status(HttpStatusCodes.UNAUTHORIZED)
				.json({ error: "Missing or invalid Authorization header" });
		}

		const token = authHeader.split(" ")[1];

		if (!token) {
			return res
				.status(HttpStatusCodes.UNAUTHORIZED)
				.json({ error: "Invalid token format" });
		}

		// Find session by token
		const session = await prisma.session.findUnique({
			where: { token },
			include: { user: true },
		});

		if (!session) {
			return res
				.status(HttpStatusCodes.UNAUTHORIZED)
				.json({ error: "Session not found" });
		}

		// Check expiration
		if (new Date(session.expiresAt) < new Date()) {
			return res
				.status(HttpStatusCodes.UNAUTHORIZED)
				.json({ error: "Session expired" });
		}

		// Attach user to request
		req.user = {
			id: session.user.id,
		};

		next();
	} catch (error: any) {
		return res
			.status(HttpStatusCodes.INTERNAL_SERVER_ERROR)
			.json({ error: error.message });
	}
};
