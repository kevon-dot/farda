import { DeviceTrackingService } from "@src/services/DeviceTrackingService";
import type { Request, Response } from "express";

function extractToken(req: Request): string | undefined {
	return req.headers.authorization;
}

const CaregiverRoutes = {
	claimDevice: async (req: Request, res: Response) => {
		const result = await DeviceTrackingService.proxyRequest(
			"/api/caregiver/claim-device",
			"POST",
			extractToken(req),
			req.body,
		);
		res.status(result.status).json(result.data);
	},

	removeCaregiver: async (req: Request, res: Response) => {
		const { deviceId } = req.params;
		const result = await DeviceTrackingService.proxyRequest(
			`/api/user/devices/${deviceId}/caregiver`,
			"DELETE",
			extractToken(req),
		);
		res.status(result.status).json(result.data);
	},

	getDevices: async (req: Request, res: Response) => {
		const result = await DeviceTrackingService.proxyRequest(
			"/api/caregiver/devices",
			"GET",
			extractToken(req),
		);
		res.status(result.status).json(result.data);
	},

	getDeviceSummary: async (req: Request, res: Response) => {
		const { deviceId } = req.params;
		// According to postman this route uses GET /api/caregiver/devices/:deviceId/summary with a body,
		// but standard REST APIs shouldn't pass bodies in GET requests. We will pass it as query or pass body if fetch allows.
		// Fetch API technically allows GET with a body if it's explicitly done, but let's handle it as in the Postman collection.
		const result = await DeviceTrackingService.proxyRequest(
			`/api/caregiver/devices/${deviceId}/summary`,
			"GET", // The postman collection had it as a GET request.
			extractToken(req),
			undefined,
			req.query as Record<string, string>,
		);
		res.status(result.status).json(result.data);
	},

	searchDevice: async (req: Request, res: Response) => {
		const result = await DeviceTrackingService.proxyRequest(
			"/api/caregiver/search/device",
			"GET",
			extractToken(req),
			undefined,
			req.query as Record<string, string>,
		);
		res.status(result.status).json(result.data);
	},

	filterEvents: async (req: Request, res: Response) => {
		const result = await DeviceTrackingService.proxyRequest(
			"/api/caregiver/events/filter/date",
			"GET",
			extractToken(req),
			undefined,
			req.query as Record<string, string>,
		);
		res.status(result.status).json(result.data);
	},
};

export default CaregiverRoutes;
