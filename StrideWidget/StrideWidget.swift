import WidgetKit
import SwiftUI

// Screen 29. Handoff §3 — separate WidgetKit target.
// Reads the payload AppState.publishToWidget() writes to the shared app group.
// Same voice, same tokens — no color the app doesn't already use.

struct TodayEntry: TimelineEntry {
    let date: Date
    let steps: Int
    let goal: Int
    let streak: Int
    let goalMet: Bool
}

struct TodayProvider: TimelineProvider {
    private static let appGroup = "group.com.stride.app"

    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), steps: 4_200, goal: 6_000, streak: 4, goalMet: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let entry = readEntry()
        // The record only changes when the app writes to it. Fifteen minutes
        // is a safety net, not a refresh strategy.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func readEntry() -> TodayEntry {
        guard let defaults = UserDefaults(suiteName: Self.appGroup),
              let payload = defaults.dictionary(forKey: "today")
        else {
            return TodayEntry(date: Date(), steps: 0, goal: 6_000, streak: 0, goalMet: false)
        }
        return TodayEntry(
            date: Date(),
            steps: payload["steps"] as? Int ?? 0,
            goal: payload["goal"] as? Int ?? 6_000,
            streak: payload["streak"] as? Int ?? 0,
            goalMet: payload["goalMet"] as? Bool ?? false
        )
    }
}

struct StrideWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    private var fraction: Double {
        entry.goal > 0 ? min(1, Double(entry.steps) / Double(entry.goal)) : 0
    }

    var body: some View {
        ZStack {
            Color.void
            switch family {
            case .systemSmall: small
            default: medium
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(entry.goalMet ? "Done" : "Today", size: 9, color: .steel)
            Text("\(entry.steps.formattedSteps)")
                .font(Type.figure(26, medium: true))
                .foregroundStyle(Color.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            ProgressTrack(fraction: fraction, live: !entry.goalMet)
            MonoLabel("Streak \(entry.streak)", size: 8, color: .dim)
        }
        .padding(16)
    }

    private var medium: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                MonoLabel(entry.goalMet ? "Done. Do it again tomorrow." : "Not finished. Not yet failed.",
                         size: 9, color: .dim)
                Text("\(entry.steps.formattedSteps)")
                    .font(Type.figure(30, medium: true))
                    .foregroundStyle(Color.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                ProgressTrack(fraction: fraction, live: !entry.goalMet)
            }
            Spacer()
            VStack(spacing: 4) {
                Text("\(entry.streak)")
                    .font(Type.figure(22, medium: true))
                    .foregroundStyle(Color.steel)
                MonoLabel("Streak", size: 8, color: .dim)
            }
        }
        .padding(18)
    }
}

struct StrideWidget: Widget {
    let kind = "StrideWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            StrideWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("The number so far. Nothing else.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
