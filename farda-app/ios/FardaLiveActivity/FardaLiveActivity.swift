import ActivityKit
import SwiftUI
import WidgetKit

@main
struct FardaLiveActivityBundle: WidgetBundle {
  var body: some Widget { FardaLiveActivity() }
}

struct FardaLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: FardaRoutineAttributes.self) { context in
      RoutineLockScreen(context: context)
        .activityBackgroundTint(Color("SurfaceCanvas"))
        .activitySystemActionForegroundColor(Color("TextPrimary"))
        .widgetURL(context.attributes.url())
    } dynamicIsland: { context in
      let presentation = RoutinePresentation(context: context)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text("farda.").font(.custom("Outfit-SemiBold", size: 20, relativeTo: .headline))
            .accessibilityLabel("Farda")
        }
        DynamicIslandExpandedRegion(.trailing) {
          RoutineTime(state: context.state, phase: presentation.phase)
            .font(.headline.monospacedDigit())
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 8) {
            Text(presentation.title).font(.headline).lineLimit(1)
            Text(presentation.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 12) {
              Link(presentation.primaryLabel, destination: context.attributes.url(action: presentation.action))
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(Color("TextInverse"))
                .background(Color("BrandButton"), in: RoundedRectangle(cornerRadius: 14))
              if presentation.phase == .due {
                Link("Snooze", destination: context.attributes.url(action: "snooze"))
                  .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                  .foregroundStyle(Color("TextInverse"))
              }
            }
          }
          .padding(.top, 4)
        }
      } compactLeading: {
        Text("f.").font(.custom("Outfit-SemiBold", size: 18, relativeTo: .headline))
          .accessibilityLabel("Farda routine")
      } compactTrailing: {
        RoutineTime(state: context.state, phase: presentation.phase)
          .font(.caption.monospacedDigit()).frame(maxWidth: 52)
      } minimal: {
        Text("f.")
          .font(.custom("Outfit-SemiBold", size: 17, relativeTo: .headline))
          .accessibilityLabel(presentation.title)
      }
      .widgetURL(context.attributes.url(action: presentation.action))
      .keylineTint(Color("IslandAccent"))
    }
  }
}

private struct RoutinePresentation {
  let phase: FardaRoutineAttributes.ContentState.Phase
  init(context: ActivityViewContext<FardaRoutineAttributes>) {
    phase = context.isStale && !context.state.isTerminal ? .stale : context.state.phase
  }
  var title: String {
    switch phase {
    case .headsUp: return "A little heads-up."
    case .due: return "Your routine is ready."
    case .snoozed: return "A moment for you."
    case .confirmed: return "Your entry is saved."
    case .cancelled: return "Reminder ended."
    case .stale: return "Let’s get you up to date."
    }
  }
  var subtitle: String {
    switch phase {
    case .headsUp: return "Your routine is coming up."
    case .due: return "Open Farda to check in."
    case .snoozed: return "Your reminder is paused."
    case .confirmed: return "You can review or correct it in Farda."
    case .cancelled: return "Open Farda to review your routine."
    case .stale: return "Open Farda for the latest."
    }
  }
  var action: String { phase == .due ? "checkIn" : "view" }
  var primaryLabel: String { phase == .due ? "Open & log" : phase == .headsUp ? "View my routine" : "Open Farda" }
}

private struct RoutineLockScreen: View {
  let context: ActivityViewContext<FardaRoutineAttributes>
  @Environment(\.dynamicTypeSize) private var textSize
  private var presentation: RoutinePresentation { .init(context: context) }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("farda.").font(.custom("Outfit-SemiBold", size: 19, relativeTo: .headline))
          .accessibilityLabel("Farda")
        Spacer(minLength: 8)
        Image("FardaLock").accessibilityHidden(true)
        Text("Private preview").font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
          .foregroundStyle(Color("TextSecondary"))
      }
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(presentation.title)
          .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .headline))
          .lineLimit(1).minimumScaleFactor(0.8)
        Spacer(minLength: 0)
        RoutineTime(state: context.state, phase: presentation.phase)
          .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .headline).monospacedDigit())
          .fixedSize(horizontal: true, vertical: false)
      }
      if !textSize.isAccessibilitySize {
        Group {
          if presentation.phase == .due, let callAt = context.state.callAt {
            Text("Call reminder at ") + Text(Date(timeIntervalSince1970: callAt), style: .time)
          } else {
            Text(presentation.subtitle)
          }
        }
        .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
        .foregroundStyle(Color("TextSecondary")).lineLimit(1)
      }
      HStack(spacing: 10) {
        Link(destination: context.attributes.url(action: presentation.action)) {
          Text(presentation.primaryLabel)
            .font(.custom("Outfit-SemiBold", size: 14, relativeTo: .subheadline))
            .lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(Color("TextInverse"))
            .background(Color("BrandButton"), in: RoundedRectangle(cornerRadius: 14))
        }
        if presentation.phase == .due {
          Link(destination: context.attributes.url(action: "snooze")) {
            HStack(spacing: 2) {
              Text("Snooze").font(.custom("Outfit-SemiBold", size: 14, relativeTo: .subheadline))
              Image("FardaArrow").accessibilityHidden(true)
            }
            .frame(minWidth: 64, minHeight: 44)
          }
          .accessibilityLabel("Open Farda to snooze this reminder")
        }
      }
    }
    .padding(.horizontal, 14).padding(.vertical, 12)
    .foregroundStyle(Color("TextPrimary"))
    // A native Live Activity is a compact surface; the app owns the full card.
    .accessibilityElement(children: .contain)
  }
}

private struct RoutineTime: View {
  let state: FardaRoutineAttributes.ContentState
  let phase: FardaRoutineAttributes.ContentState.Phase
  @ViewBuilder var body: some View {
    switch phase {
    case .headsUp:
      Text(timerInterval: Date(timeIntervalSince1970: state.dueAt - 600)...Date(timeIntervalSince1970: state.dueAt), countsDown: true)
        .accessibilityLabel("Time until your routine")
    case .snoozed:
      if let until = state.snoozedUntil, until > state.updatedAt {
        Text(timerInterval: Date(timeIntervalSince1970: state.updatedAt)...Date(timeIntervalSince1970: until), countsDown: true)
          .accessibilityLabel("Time until your reminder resumes")
      } else { Text("Paused") }
    case .due: Text("Now")
    case .confirmed: Text("Saved")
    case .cancelled: Text("Ended")
    case .stale: Text("Refresh")
    }
  }
}
