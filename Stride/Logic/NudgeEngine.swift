import Foundation
import UserNotifications

// Smart nudges. Handoff §5.
//
// Delivery is always a plain push notification. The spoken version only plays
// if the user opens the app from that notification AND has opted in — see
// SpokenNudge. On-device, no network call.

enum NudgeEngine {

    struct Context {
        var now: Date
        var todaySteps: Int
        var goal: Int
        var streak: Int
        var yesterdayWasMiss: Bool
        var hoursSinceLastActivity: Double
        /// Once `longSilence` has fired, nothing more is sent until the user
        /// re-opens the app.
        var silenceNudgeAlreadySent: Bool
    }

    static func due(_ c: Context, calendar: Calendar = .current) -> NudgeTrigger? {
        let hour = calendar.component(.hour, from: c.now)

        // Last nudge. Nothing follows it.
        if c.hoursSinceLastActivity >= 48 {
            return c.silenceNudgeAlreadySent ? nil : .longSilence
        }
        if c.silenceNudgeAlreadySent { return nil }

        if c.yesterdayWasMiss && c.todaySteps == 0 && hour >= 10 {
            return .missedYesterday
        }
        if hour >= 19 && c.todaySteps < c.goal && c.streak >= 1 {
            return .streakAtRiskPM
        }
        if hour >= 12 && Double(c.todaySteps) < Double(c.goal) * 0.5 && c.streak >= 1 {
            return .streakAtRiskAM
        }
        return nil
    }

    static func makeNotification(_ trigger: NudgeTrigger,
                                 streak: Int,
                                 short: Int,
                                 spokenEnabled: Bool) -> AppNotification {
        AppNotification(trigger: trigger,
                        copy: Copy.Nudge.text(for: trigger, streak: streak, short: short),
                        spoken: spokenEnabled)
    }

    // MARK: - Scheduling

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func schedule(_ note: AppNotification, at date: Date) {
        let content = UNMutableNotificationContent()
        content.body = note.copy
        content.sound = .default
        content.userInfo = ["trigger": note.trigger.rawValue, "spoken": note.spoken]

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let request = UNNotificationRequest(
            identifier: note.trigger.rawValue,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
