import { describe, expect, it } from "vitest";
import {
	canRefreshStatus,
	nextAction,
	nextProviderStatus,
	statusReason,
} from "../src/refills/workflow";

describe("refill request state machine", () => {
	it.each([
		["unknown", "ready", "ready"],
		["sent", "received", "received"],
		["sent", "unknown", "sent"],
		["received", "sent", "received"],
		["ready", "shipped", "ready"],
		["shipped", "ready", "shipped"],
		["delivered", "canceled", "delivered"],
	] as const)("moves %s + %s deterministically to %s", (current, incoming, expected) => {
		expect(nextProviderStatus(current, incoming)).toBe(expected);
	});

	it("fails closed for corrupt stored states", () => {
		expect(nextProviderStatus("private-upstream-text", "sent")).toBe("sent");
	});

	it.each([
		["unknown", "refresh_status", "submission_outcome_uncertain", true],
		["ready", "collect_refill", "provider_status_available", true],
		["delivered", "confirm_supply", "request_fulfilled", false],
		["completed", "confirm_supply", "provider_process_completed", false],
		["failed", "review_again", "request_not_submitted", false],
	] as const)("describes %s with a stable next step", (status, action, reason, refreshable) => {
		expect(nextAction(status)).toBe(action);
		expect(statusReason(status)).toBe(reason);
		expect(canRefreshStatus(status)).toBe(refreshable);
	});
});
