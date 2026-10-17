import { afterEach, describe, expect, it, vi } from "vitest";
import { startReminderWorker } from "../src/reminders/service";

afterEach(() => {
	vi.useRealTimers();
	vi.restoreAllMocks();
});
describe("reminder worker lifecycle", () => {
	it("does not run or send anything while disabled", async () => {
		vi.useFakeTimers();
		const tick = vi.fn(async () => {});
		const stop = startReminderWorker({ tick }, false);
		await vi.advanceTimersByTimeAsync(60_000);
		await stop();
		expect(tick).not.toHaveBeenCalled();
	});
	it("drains in-flight work before shutdown and prevents overlapping ticks", async () => {
		vi.useFakeTimers();
		let finish!: () => void;
		const tick = vi.fn(
			() =>
				new Promise<void>((resolve) => {
					finish = resolve;
				}),
		);
		const stop = startReminderWorker({ tick }, true);
		vi.advanceTimersByTime(45_000);
		expect(tick).toHaveBeenCalledTimes(1);
		let drained = false;
		const stopping = stop().then(() => {
			drained = true;
		});
		await Promise.resolve();
		expect(drained).toBe(false);
		finish();
		await stopping;
		expect(drained).toBe(true);
		await vi.advanceTimersByTimeAsync(60_000);
		expect(tick).toHaveBeenCalledTimes(1);
	});
	it("redacts a failed tick and can run the next tick", async () => {
		vi.useFakeTimers();
		const log = vi.spyOn(console, "error").mockImplementation(() => {});
		const tick = vi
			.fn(async () => {})
			.mockRejectedValueOnce(new Error("sensitive provider payload"));
		const stop = startReminderWorker({ tick }, true);
		await vi.advanceTimersByTimeAsync(30_000);
		await stop();
		expect(tick).toHaveBeenCalledTimes(2);
		expect(JSON.parse(log.mock.calls[0][0])).toEqual({
			event: "reminder_worker_failed",
		});
		expect(JSON.stringify(log.mock.calls)).not.toContain("sensitive");
	});
});
