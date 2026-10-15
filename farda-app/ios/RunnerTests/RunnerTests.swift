import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testRoutineLinksAcceptOnlyNavigationActionsAndOpaqueIDs() {
    let bridge = LiveActivityBridge()
    XCTAssertTrue(bridge.open(URL(string: "farda://routine/dose-123?action=checkIn")!))
    XCTAssertTrue(bridge.open(URL(string: "farda://routine/dose-123?action=snooze")!))
    XCTAssertFalse(bridge.open(URL(string: "farda://routine/dose-123?action=confirmTaken")!))
    XCTAssertFalse(bridge.open(URL(string: "farda://routine/a/b?action=view")!))
    XCTAssertFalse(bridge.open(URL(string: "https://routine/dose-123?action=view")!))
    XCTAssertFalse(bridge.open(URL(string: "farda://account/dose-123?action=view")!))
  }

  func testLiveContentUsesUnixSecondsAndContainsNoPrescriptionDetails() throws {
    guard #available(iOS 16.2, *) else { throw XCTSkip("ActivityKit requires iOS 16.2") }
    let state = FardaRoutineAttributes.ContentState(phase: .headsUp, revision: 2,
      dueAt: 1_800_000_000, windowEndsAt: 1_800_003_600, updatedAt: 1_799_999_400)
    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    XCTAssertEqual(payload["dueAt"] as? Double, 1_800_000_000)
    XCTAssertEqual(Set(payload.keys), Set(["phase", "revision", "dueAt", "windowEndsAt", "updatedAt"]))
    XCTAssertEqual(state.staleDate.timeIntervalSince1970, state.dueAt)
  }

  func testSnoozeContentBecomesStaleAtResumeBoundary() throws {
    guard #available(iOS 16.2, *) else { throw XCTSkip("ActivityKit requires iOS 16.2") }
    let state = FardaRoutineAttributes.ContentState(phase: .snoozed, revision: 3,
      dueAt: 1_800_000_000, windowEndsAt: 1_800_003_600, updatedAt: 1_800_000_000,
      snoozedUntil: 1_800_000_900)
    XCTAssertEqual(state.staleDate.timeIntervalSince1970, 1_800_000_900)
    XCTAssertFalse(state.isTerminal)
  }

  func testCheckInURLCannotCarryAConfirmationCommand() throws {
    guard #available(iOS 16.2, *) else { throw XCTSkip("ActivityKit requires iOS 16.2") }
    let url = FardaRoutineAttributes(occurrenceId: "dose-123").url(action: "checkIn")
    XCTAssertEqual(url.host, "routine")
    XCTAssertEqual(url.path, "/dose-123")
    XCTAssertEqual(url.query, "action=checkIn")
  }

}
