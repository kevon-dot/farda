export const requestStatuses = [
	"submitting",
	"unknown",
	"sent",
	"received",
	"ready",
	"shipped",
	"delivered",
	"picked_up",
	"completed",
	"canceled",
	"failed",
] as const;

export type RefillRequestStatus = (typeof requestStatuses)[number];
export type RefillReasonCode =
	| "review_ready"
	| "request_in_progress"
	| "provider_not_configured"
	| "provider_submission_unsupported"
	| "provider_status_unsupported"
	| "prescription_not_linked"
	| "prescription_not_eligible"
	| "delivery_address_required"
	| "link_verification_failed"
	| "eligibility_check_unavailable"
	| "eligibility_check_failed"
	| "request_already_recorded"
	| "submission_in_progress"
	| "submission_outcome_uncertain"
	| "provider_status_available"
	| "provider_status_pending"
	| "status_check_recent"
	| "status_check_unavailable"
	| "request_not_submitted"
	| "request_canceled"
	| "provider_process_completed"
	| "request_fulfilled";

export type RefillNextAction =
	| "confirm_and_submit"
	| "wait"
	| "refresh_status"
	| "contact_pharmacy"
	| "collect_refill"
	| "track_delivery"
	| "confirm_supply"
	| "review_again";

const terminal = new Set<RefillRequestStatus>([
	"delivered",
	"picked_up",
	"completed",
	"canceled",
]);

const allowed: Record<RefillRequestStatus, ReadonlySet<RefillRequestStatus>> = {
	submitting: new Set(requestStatuses),
	unknown: new Set(
		requestStatuses.filter(
			(status) => status !== "submitting" && status !== "failed",
		),
	),
	sent: new Set([
		"sent",
		"received",
		"ready",
		"shipped",
		"delivered",
		"picked_up",
		"completed",
		"canceled",
	]),
	received: new Set([
		"received",
		"ready",
		"shipped",
		"delivered",
		"picked_up",
		"completed",
		"canceled",
	]),
	ready: new Set(["ready", "picked_up", "completed", "canceled"]),
	shipped: new Set(["shipped", "delivered", "completed", "canceled"]),
	delivered: new Set(["delivered"]),
	picked_up: new Set(["picked_up"]),
	completed: new Set(["completed"]),
	canceled: new Set(["canceled"]),
	failed: new Set(["failed"]),
};

export function isRequestStatus(value: string): value is RefillRequestStatus {
	return (requestStatuses as readonly string[]).includes(value);
}

/** Provider reads can advance a request, but can never erase known progress,
 * switch between pickup and shipping, or reopen a terminal request. */
export function nextProviderStatus(
	currentValue: string,
	incoming: RefillRequestStatus,
): RefillRequestStatus {
	const current = isRequestStatus(currentValue) ? currentValue : "unknown";
	return allowed[current].has(incoming) ? incoming : current;
}

export function statusReason(status: RefillRequestStatus): RefillReasonCode {
	if (status === "submitting") return "submission_in_progress";
	if (status === "unknown") return "submission_outcome_uncertain";
	if (status === "failed") return "request_not_submitted";
	if (status === "canceled") return "request_canceled";
	if (status === "completed") return "provider_process_completed";
	if (status === "delivered" || status === "picked_up") return "request_fulfilled";
	return "provider_status_available";
}

export function nextAction(status: RefillRequestStatus): RefillNextAction {
	if (status === "submitting") return "wait";
	if (status === "unknown") return "refresh_status";
	if (status === "ready") return "collect_refill";
	if (status === "shipped") return "track_delivery";
	if (
		status === "delivered" ||
		status === "picked_up" ||
		status === "completed"
	)
		return "confirm_supply";
	if (status === "canceled" || status === "failed") return "review_again";
	return "refresh_status";
}

export function canRefreshStatus(status: RefillRequestStatus): boolean {
	return !terminal.has(status) && status !== "failed";
}
