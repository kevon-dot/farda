import { DeviceTrackingService } from "@src/services/DeviceTrackingService";
import type { Request, Response } from "express";

function extractToken(req: Request): string | undefined {
	return req.headers.authorization;
}

const DeviceUserRoutes = {
	claim: async (req: Request, res: Response) => {
		const result = await DeviceTrackingService.proxyRequest(
			"/api/user/claim",
			"POST",
			extractToken(req),
			req.body,
		);
		res.status(result.status).json(result.data);
	},

	getDevices: async (req: Request, res: Response) => {
		const result = await DeviceTrackingService.proxyRequest(
			"/api/user/devices",
			"GET",
			extractToken(req),
		);
		res.status(result.status).json(result.data);
	},

	unclaimDevice: async (req: Request, res: Response) => {
		const { deviceId } = req.params;
		const result = await DeviceTrackingService.proxyRequest(
			`/api/user/devices/${deviceId}/unclaim`,
			"DELETE",
			extractToken(req),
		);
		res.status(result.status).json(result.data);
	},

	getDeviceEvents: async (req: Request, res: Response) => {
		const { deviceId } = req.params;
		const result = await DeviceTrackingService.proxyRequest(
			`/api/user/devices/${deviceId}/events`,
			"GET",
			extractToken(req),
		);
		res.status(result.status).json(result.data);
	},

	deleteDeviceEvents: async (req: Request, res: Response) => {
		const { deviceId } = req.params;
		const result = await DeviceTrackingService.proxyRequest(
			`/api/user/devices/${deviceId}/events`,
			"DELETE",
			extractToken(req),
		);
		res.status(result.status).json(result.data);
	},

	searchDeviceEvents: async (req: Request, res: Response) => {
		const { deviceId } = req.params;
		const result = await DeviceTrackingService.proxyRequest(
			`/api/user/devices/${deviceId}/events/search`,
			"GET",
			extractToken(req),
			undefined,
			req.query as Record<string, string>,
		);
		res.status(result.status).json(result.data);
	},

	getAllEvents: async (req: Request, res: Response) => {
		const result = await DeviceTrackingService.proxyRequest(
			"/api/user/events/all",
			"GET",
			extractToken(req),
		);
		res.status(result.status).json(result.data);
	},
};

export default DeviceUserRoutes;
