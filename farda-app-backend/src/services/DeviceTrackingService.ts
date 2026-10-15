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
		if (!env.FARDA_API_URL || !token) return { status: 503, data: { error: 'Vial service is unavailable', code: 'temporarily_unavailable' } };
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
			headers.Authorization = /^Bearer /i.test(token)
				? `Bearer ${token.slice(7)}`
				: `Bearer ${token}`;
		}

		try {
			const response = await fetch(url, {
				method,
				headers,
				body: body ? JSON.stringify(body) : undefined,
				signal: AbortSignal.timeout(15000),
				redirect: 'error',
			});

			const data = await response.json().catch(() => ({}));
			return {
				status: response.status,
				data,
			};
		} catch {
			return {
				status: 503,
				data: { error: 'Vial service is unavailable. Try again.', code: 'temporarily_unavailable' },
			};
		}
	}
}
