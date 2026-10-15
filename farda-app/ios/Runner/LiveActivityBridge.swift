import ActivityKit
import Flutter
import UIKit

/// One owner for both Flutter channels and incoming navigation. No channel
/// method records a dose or calls a phone number.
final class LiveActivityBridge: NSObject, FlutterStreamHandler {
  private var channel: FlutterMethodChannel?
  private var events: FlutterEventChannel?
  private var eventSink: FlutterEventSink?
  private var managerStorage: AnyObject?
  private var pendingOpen: [String: Any]?

  func register(with messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "farda/live_activity", binaryMessenger: messenger)
    events = FlutterEventChannel(name: "farda/live_activity_events", binaryMessenger: messenger)
    events?.setStreamHandler(self)
    channel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(FlutterError(code: "unavailable", message: "Bridge unavailable", details: nil)) }
      if call.method == "consumePendingOpen" {
        result(self.pendingOpen)
        self.pendingOpen = nil
        return
      }
      guard #available(iOS 16.2, *) else {
        if call.method == "availability" {
          result(["supported": false, "enabled": false, "supportsPushToStart": false,
                  "backgroundDeliveryConfigured": false])
        } else if call.method == "activeActivities" {
          result([])
        } else if call.method == "endAll" || call.method == "end" {
          result(["status": "unsupported"])
        } else {
          result(FlutterError(code: "unsupported", message: "Live Activities require iOS 16.2 or later", details: nil))
        }
        return
      }
      self.manager.handle(call, result: result)
    }
    if #available(iOS 16.2, *) { manager.startObserving() }
  }

  @available(iOS 16.2, *)
  private var manager: FardaActivityManager {
    if let manager = managerStorage as? FardaActivityManager { return manager }
    let manager = FardaActivityManager { [weak self] event in self?.eventSink?(event) }
    managerStorage = manager
    return manager
  }

  /// Accept an opaque occurrence identifier and a navigation intent only.
  /// The authenticated Flutter route must re-fetch it before offering check-in.
  @discardableResult
  func open(_ url: URL) -> Bool {
    guard url.scheme == "farda", url.host == "routine",
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
    let parts = url.pathComponents.filter { $0 != "/" }
    guard parts.count == 1, Self.validIdentifier(parts[0]) else { return false }
    let action = components.queryItems?.first(where: { $0.name == "action" })?.value ?? "view"
    guard ["view", "checkIn", "snooze"].contains(action) else { return false }
    let event: [String: Any] = ["type": "openRoutine", "occurrenceId": parts[0], "action": action]
    if let eventSink = eventSink { eventSink(event) } else { pendingOpen = event }
    return true
  }

  static func validIdentifier(_ value: String) -> Bool {
    value.range(of: "^[A-Za-z0-9._:-]{1,128}$", options: .regularExpression) != nil
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    if let pending = pendingOpen { events(pending); pendingOpen = nil }
    if #available(iOS 16.2, *) { manager.emitSnapshot() }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}

@available(iOS 16.2, *)
private final class FardaActivityManager {
  typealias Routine = Activity<FardaRoutineAttributes>
  private let emit: ([String: Any]) -> Void
  private var tasks: [String: Task<Void, Never>] = [:]
  private var operation: Task<Void, Never>?
  private var observing = false
  private let terminalKey = "farda.liveActivity.terminal.v1"
  private var pushToStartToken: String?

  init(emit: @escaping ([String: Any]) -> Void) { self.emit = emit }
  deinit { tasks.values.forEach { $0.cancel() }; operation?.cancel() }

  // ActivityKit work and channel callbacks stay on the main actor. The queue
  // prevents a delayed update racing an explicit end of the same occurrence.
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let previous = operation
    operation = Task { @MainActor [weak self] in
      await previous?.value
      guard let self = self else { return }
      do {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "availability": result(self.availability())
        case "activeActivities": result(Routine.activities.map(self.snapshot))
        case "upsert": result(try await self.upsert(args))
        case "end": result(try await self.end(args))
        case "endAll":
          for activity in Routine.activities {
            self.rememberTerminal(activity.attributes.occurrenceId)
            await activity.end(nil, dismissalPolicy: .immediate)
          }
          result(["status": "ended"])
        default: result(FlutterMethodNotImplemented)
        }
      } catch let error as BridgeError {
        result(FlutterError(code: error.code, message: error.message, details: nil))
      } catch {
        // Do not expose native payloads or token values in Flutter error logs.
        result(FlutterError(code: "activity_failed", message: "The Live Activity could not be updated", details: nil))
      }
    }
  }

  func startObserving() {
    guard !observing else { return }
    observing = true
    for activity in Routine.activities { observe(activity) }
    tasks["activities"] = Task { @MainActor [weak self] in
      for await activity in Routine.activityUpdates {
        guard let self = self else { return }
        self.observe(activity)
      }
    }
    tasks["authorization"] = Task { @MainActor [weak self] in
      for await enabled in ActivityAuthorizationInfo().activityEnablementUpdates {
        self?.emit(["type": "authorization", "enabled": enabled])
      }
    }
    if #available(iOS 17.2, *) {
      tasks["pushToStart"] = Task { @MainActor [weak self] in
        for await token in Routine.pushToStartTokenUpdates {
          let value = token.map { String(format: "%02x", $0) }.joined()
          self?.pushToStartToken = value
          self?.emit(["type": "pushToStartToken", "token": value])
        }
      }
    }
  }

  func emitSnapshot() {
    emit(["type": "authorization", "enabled": ActivityAuthorizationInfo().areActivitiesEnabled])
    for activity in Routine.activities {
      emitLifecycle(activity)
      if let token = activity.pushToken { emitToken(token, for: activity) }
    }
    if let token = pushToStartToken { emit(["type": "pushToStartToken", "token": token]) }
  }

  private func observe(_ activity: Routine) {
    guard tasks["state:\(activity.id)"] == nil else { return }
    tasks["state:\(activity.id)"] = Task { @MainActor [weak self] in
      for await state in activity.activityStateUpdates {
        guard let self = self else { return }
        self.emitLifecycle(activity)
        if state == .dismissed || state == .ended {
          // Ending a duplicate must not suppress the remaining live instance.
          let anotherIsActive = Routine.activities.contains {
            $0.id != activity.id && $0.attributes.occurrenceId == activity.attributes.occurrenceId &&
              ($0.activityState == .active || $0.activityState == .stale)
          }
          if !anotherIsActive { self.rememberTerminal(activity.attributes.occurrenceId) }
          self.tasks.removeValue(forKey: "token:\(activity.id)")?.cancel()
          self.tasks.removeValue(forKey: "state:\(activity.id)")
          break
        }
      }
    }
    tasks["token:\(activity.id)"] = Task { @MainActor [weak self] in
      for await token in activity.pushTokenUpdates { self?.emitToken(token, for: activity) }
    }
    emitLifecycle(activity)
  }

  private func emitToken(_ token: Data, for activity: Routine) {
    emit(["type": "pushToken", "activityId": activity.id,
          "occurrenceId": activity.attributes.occurrenceId,
          "token": token.map { String(format: "%02x", $0) }.joined()])
  }

  private func emitLifecycle(_ activity: Routine) {
    var event = snapshot(activity)
    event["type"] = "lifecycle"
    emit(event)
  }

  private func availability() -> [String: Any] {
    var pushToStart = false
    if #available(iOS 17.2, *) { pushToStart = true }
    return ["supported": true, "enabled": ActivityAuthorizationInfo().areActivitiesEnabled,
            "supportsPushToStart": pushToStart, "backgroundDeliveryConfigured": false]
  }

  private func snapshot(_ activity: Routine) -> [String: Any] {
    let state: String
    switch activity.activityState {
    case .active: state = "active"
    case .stale: state = "stale"
    case .ended: state = "ended"
    case .dismissed: state = "dismissed"
    @unknown default: state = "unknown"
    }
    return ["activityId": activity.id, "occurrenceId": activity.attributes.occurrenceId,
            "state": state, "revision": activity.content.state.revision,
            "phase": activity.content.state.phase.rawValue]
  }

  @MainActor
  private func upsert(_ args: [String: Any]) async throws -> [String: Any] {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      throw BridgeError("disabled", "Live Activities are disabled in Settings")
    }
    let id = try identifier(args)
    let state = try content(args)
    guard !isTerminal(id) else { return ["status": "already_ended"] }
    let now = Date().timeIntervalSince1970
    guard now >= state.dueAt - 600, now < state.windowEndsAt else {
      throw BridgeError("outside_window", "This routine is outside its reminder window")
    }
    if state.phase == .headsUp && now >= state.dueAt {
      throw BridgeError("stale_payload", "Refresh this occurrence before showing its reminder")
    }
    if state.phase == .due && now < state.dueAt {
      throw BridgeError("invalid_phase", "The routine has not reached its reminder time")
    }
    let current = Routine.activities.filter { $0.attributes.occurrenceId == id }
    let liveContent = ActivityContent(state: state, staleDate: state.staleDate, relevanceScore: 1)
    if let activity = current.first {
      guard activity.activityState == .active || activity.activityState == .stale else {
        return ["status": "already_ended"]
      }
      guard state.revision >= activity.content.state.revision,
            state.updatedAt >= activity.content.state.updatedAt else { return ["status": "ignored_stale"] }
      await activity.update(liveContent)
      // Reconcile duplicates left by interrupted launches or remote starts.
      for duplicate in current.dropFirst() { await duplicate.end(nil, dismissalPolicy: .immediate) }
      return ["status": "updated", "activityId": activity.id]
    }
    guard UIApplication.shared.applicationState == .active else {
      throw BridgeError("foreground_required", "Open Farda to start this Live Activity")
    }
    let activity = try Routine.request(attributes: FardaRoutineAttributes(occurrenceId: id),
      content: liveContent, pushType: args["requestPushToken"] as? Bool == true ? .token : nil)
    observe(activity)
    return ["status": "started", "activityId": activity.id]
  }

  @MainActor
  private func end(_ args: [String: Any]) async throws -> [String: Any] {
    let id = try identifier(args)
    guard let outcome = args["outcome"] as? String, ["confirmed", "cancelled"].contains(outcome),
          let revision = args["revision"] as? NSNumber, revision.int64Value >= 0 else {
      throw BridgeError("invalid_arguments", "An explicit terminal outcome and revision are required")
    }
    let matching = Routine.activities.filter { $0.attributes.occurrenceId == id }
    guard !matching.contains(where: { $0.content.state.revision > revision.int64Value }) else {
      return ["status": "ignored_stale"]
    }
    rememberTerminal(id)
    for activity in matching {
      var state = activity.content.state
      state.phase = outcome == "confirmed" ? .confirmed : .cancelled
      state.revision = revision.int64Value
      state.updatedAt = Date().timeIntervalSince1970
      state.callAt = nil
      await activity.end(ActivityContent(state: state, staleDate: nil),
        dismissalPolicy: outcome == "confirmed" ? .after(Date().addingTimeInterval(60)) : .immediate)
    }
    return ["status": "ended"]
  }

  private func identifier(_ args: [String: Any]) throws -> String {
    guard let id = args["occurrenceId"] as? String, LiveActivityBridge.validIdentifier(id) else {
      throw BridgeError("invalid_arguments", "A valid occurrence identifier is required")
    }
    return id
  }

  private func content(_ args: [String: Any]) throws -> FardaRoutineAttributes.ContentState {
    guard let raw = args["phase"] as? String,
          let phase = FardaRoutineAttributes.ContentState.Phase(rawValue: raw),
          [.headsUp, .due, .snoozed].contains(phase),
          let revision = args["revision"] as? NSNumber, revision.int64Value >= 0 else {
      throw BridgeError("invalid_arguments", "An active phase and non-negative revision are required")
    }
    func seconds(_ key: String) throws -> Double {
      guard let value = args[key] as? NSNumber, value.doubleValue.isFinite else {
        throw BridgeError("invalid_arguments", "A finite timestamp is required for \(key)")
      }
      return value.doubleValue / 1000
    }
    let due = try seconds("dueAt")
    let end = try seconds("windowEndsAt")
    let updated = try seconds("updatedAt")
    guard end > due, end - (due - 600) <= 8 * 60 * 60,
          updated <= Date().addingTimeInterval(60).timeIntervalSince1970 else {
      throw BridgeError("invalid_arguments", "Invalid reminder window or update timestamp")
    }
    let call = args["callAt"] == nil ? nil : try seconds("callAt")
    let snooze = args["snoozedUntil"] == nil ? nil : try seconds("snoozedUntil")
    if let call = call, call < due || call > end { throw BridgeError("invalid_arguments", "Call time is outside the reminder window") }
    if phase == .snoozed && (snooze == nil || snooze! > end || snooze! <= Date().timeIntervalSince1970) {
      throw BridgeError("invalid_arguments", "A future snooze time within the window is required")
    }
    return .init(phase: phase, revision: revision.int64Value, dueAt: due, windowEndsAt: end,
                 updatedAt: updated, callAt: phase == .snoozed ? nil : call, snoozedUntil: snooze)
  }

  private func rememberTerminal(_ id: String) {
    var entries = UserDefaults.standard.dictionary(forKey: terminalKey) as? [String: Double] ?? [:]
    let now = Date().timeIntervalSince1970
    entries = entries.filter { now - $0.value < 48 * 60 * 60 }
    entries[id] = now
    if entries.count > 256 {
      entries = Dictionary(uniqueKeysWithValues: entries.sorted { $0.value > $1.value }.prefix(256).map { ($0.key, $0.value) })
    }
    UserDefaults.standard.set(entries, forKey: terminalKey)
  }

  private func isTerminal(_ id: String) -> Bool {
    let entries = UserDefaults.standard.dictionary(forKey: terminalKey) as? [String: Double] ?? [:]
    return entries[id].map { Date().timeIntervalSince1970 - $0 < 48 * 60 * 60 } ?? false
  }

  private struct BridgeError: Error {
    let code: String
    let message: String
    init(_ code: String, _ message: String) { self.code = code; self.message = message }
  }
}
