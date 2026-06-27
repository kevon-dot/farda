import env from "@src/common/constants/env";

// biome-ignore lint/complexity/noStaticOnlyClass: <explanation>
export class DeviceTrackingService {
	/**
	 * Helper method to proxy request to external device tracking API
	 */
	public static async proxyRequest(
		path: string,
		method: string,
		token: string | undefined,
		body?: any,
		queryParams?: Record<string, string>,
	) {
		let url = `${env.FARDA_API_URL}${path}`;

		if (queryParams && Object.keys(queryParams).length > 0) {
			const qs = new URLSearchParams(queryParams).toString();
			url += `?${qs}`;
		}

		const headers: Record<string, string> = {
			"Content-Type": "application/json",
			Accept: "application/json",
		};

		if (token) {
			headers.Authorization = token.startsWith("Bearer ")
				? token
				: `Bearer ${token}`;
		}

		try {
			const response = await fetch(url, {
				method,
				headers,
				body: body ? JSON.stringify(body) : undefined,
			});

			const data = await response.json().catch(() => ({}));
			return {
				status: response.status,
				data,
			};
		} catch (error: any) {
			return {
				status: 500,
				data: { error: error.message || "Internal Server Error during proxy" },
			};
		}
	}
}
