import ActivityKit
import Foundation

/// Shared by Runner and the widget extension. Never add prescription names,
/// quantities, phone numbers, or other private details to this payload.
@available(iOS 16.2, *)
struct FardaRoutineAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    enum Phase: String, Codable {
      case headsUp, due, snoozed, confirmed, cancelled, stale
    }

    var phase: Phase
    var revision: Int64
    // Unix seconds, intentionally not Codable Date's reference-date encoding.
    var dueAt: Double
    var windowEndsAt: Double
    var updatedAt: Double
    var callAt: Double?
    var snoozedUntil: Double?

    var isTerminal: Bool { phase == .confirmed || phase == .cancelled }
    var staleDate: Date {
      let boundary: Double
      switch phase {
      case .headsUp: boundary = dueAt
      case .snoozed: boundary = min(snoozedUntil ?? windowEndsAt, windowEndsAt)
      default: boundary = windowEndsAt
      }
      return Date(timeIntervalSince1970: boundary)
    }
  }

  let occurrenceId: String

  func url(action: String = "view") -> URL {
    var components = URLComponents()
    components.scheme = "farda"
    components.host = "routine"
    components.path = "/\(occurrenceId)"
    components.queryItems = [URLQueryItem(name: "action", value: action)]
    // IDs are validated before an activity is created. This fallback is still
    // navigation only; it can never mutate a routine record.
    return components.url ?? URL(string: "farda://routine")!
  }
}
