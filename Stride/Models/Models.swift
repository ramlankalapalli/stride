import Foundation

// Data models. Handoff §4.

enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case barely, someDays, mostDays, everyDay
    var id: String { rawValue }

    var label: String {
        switch self {
        case .barely:   return "Barely at all"
        case .someDays: return "Some days"
        case .mostDays: return "Most days"
        case .everyDay: return "Every day"
        }
    }
}

enum UnitPreference: String, Codable, CaseIterable, Identifiable {
    case imperial, metric
    var id: String { rawValue }
    var label: String { self == .imperial ? "Feet and pounds" : "Centimetres and kilos" }
}

// UnlockTransform lives in Design/AvatarView.swift — it's a rendering concept
// the widget target also needs, and Design is the folder shared with it.

typealias UnlockID = String

struct User: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var email: String = ""
    /// Day 0 anchor. Every "N days" figure in the app counts from here.
    var createdAt: Date = Date()
    var age: Int?
    /// Stored metric internally; displayed per `unitPreference`.
    var heightCm: Double?
    /// nil if skipped.
    var weightKg: Double?
    var activityLevel: ActivityLevel = .someDays
    var unitPreference: UnitPreference = .imperial
    var avatarUnlocks: [UnlockID] = []
    var points: Int = 0
    var inviteCode: String = ""
    var notificationsEnabled: Bool = false
    /// Opt-in. Off by default — handoff §4.
    var spokenNudgesEnabled: Bool = false
    var watchConnected: Bool = false

    var daysSinceDayZero: Int {
        max(0, Calendar.current.dateComponents([.day], from: createdAt, to: Date()).day ?? 0)
    }
}

struct DailyRecord: Codable, Identifiable {
    var id: Date { date }
    var date: Date
    var stepsFromPhone: Int = 0
    /// 0 when no Watch is connected.
    var stepsFromWatch: Int = 0
    var stepsManualAdd: Int = 0
    var goalMet: Bool = false
    /// 24 values, one per hour. Drives the waveform chart.
    var hourlyBreakdown: [Int] = Array(repeating: 0, count: 24)

    var total: Int { stepsFromPhone + stepsFromWatch + stepsManualAdd }
    var automatic: Int { stepsFromPhone + stepsFromWatch }
}

struct Streak: Codable {
    var current: Int = 0
    /// Kept permanently, even after a reset. This is what powers
    /// "YOU'VE HAD 11. YOU THREW IT AWAY."
    var best: Int = 0
    var totalDaysTracked: Int = 0
    var totalDaysHit: Int = 0
    var totalDaysMissed: Int = 0
}

struct WeeklyChallenge: Codable {
    var weekStart: Date
    var target: Int
    var daysHit: Int = 0
    /// 7 values, Monday first.
    var dailyBars: [Int] = Array(repeating: 0, count: 7)
}

struct Unlock: Codable, Identifiable {
    var id: UnlockID
    var name: String
    var cost: Int
    var owned: Bool = false
    var transform: UnlockTransform

    /// The thirty-day mark is earned at 30 days tracked, not bought.
    var isPurchasable: Bool { transform != .thirtyDayMark }

    static let catalog: [Unlock] = [
        Unlock(id: "heavier",  name: "Heavier line", cost: 300,  transform: .heavierLine),
        Unlock(id: "shadow",   name: "Long shadow",  cost: 600,  transform: .longShadow),
        Unlock(id: "steel",    name: "Steel outline", cost: 900, transform: .steelOutline),
        Unlock(id: "trail",    name: "Motion trail", cost: 1400, transform: .motionTrail),
        Unlock(id: "inverted", name: "Inverted",     cost: 2000, transform: .inverted),
        Unlock(id: "thirty",   name: "Thirty day mark", cost: 0, transform: .thirtyDayMark)
    ]
}

struct Friend: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var todaySteps: Int
    /// Drives leaderboard highlight logic.
    var isMe: Bool = false
}

enum NudgeTrigger: String, Codable, CaseIterable {
    case streakAtRiskAM, streakAtRiskPM, missedYesterday, longSilence
}

struct AppNotification: Codable, Identifiable {
    var id: UUID = UUID()
    var trigger: NudgeTrigger
    /// Pulled from the copy table, §6.
    var copy: String
    /// Whether AVSpeechSynthesizer reads it if the user opens from the notification.
    var spoken: Bool = false
    var scheduledFor: Date = Date()
}
