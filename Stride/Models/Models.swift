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
    /// General notification permission/master switch.
    var notificationsEnabled: Bool = false
    /// Phase 1.0.5: split out from notificationsEnabled — Settings
    /// previously bound both "Nag me" and "Streak warnings" to this single
    /// property, so toggling one silently toggled the other. Streak-risk
    /// reminders specifically (NudgeEngine's .streakAtRiskAM/.streakAtRiskPM
    /// triggers).
    var streakRiskNudgesEnabled: Bool = false
    /// Phase 1.0.5: inactivity/long-silence reminders specifically
    /// (NudgeEngine's .longSilence/.missedYesterday triggers) — distinct
    /// from both the general switch and streak-risk reminders.
    var inactivityNudgesEnabled: Bool = false
    /// Opt-in. Off by default — handoff §4.
    var spokenNudgesEnabled: Bool = false
    var watchConnected: Bool = false

    init() {}

    /// Phase 1.0.5: Swift's synthesized Decodable does NOT fall back to a
    /// property's declared default when a key is missing — it throws. Real
    /// devices already have a persisted snapshot from before
    /// streakRiskNudgesEnabled/inactivityNudgesEnabled existed; without this
    /// custom decoder, AppState.load() would fail on that old JSON (the
    /// `try?` swallows the error) and silently reset the whole profile —
    /// name, points, streak, every record — back to defaults on next
    /// launch. decodeIfPresent + a fallback keeps old snapshots loading
    /// exactly as before, with the two new fields simply defaulting to off.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        age = try c.decodeIfPresent(Int.self, forKey: .age)
        heightCm = try c.decodeIfPresent(Double.self, forKey: .heightCm)
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg)
        activityLevel = try c.decodeIfPresent(ActivityLevel.self, forKey: .activityLevel) ?? .someDays
        unitPreference = try c.decodeIfPresent(UnitPreference.self, forKey: .unitPreference) ?? .imperial
        avatarUnlocks = try c.decodeIfPresent([UnlockID].self, forKey: .avatarUnlocks) ?? []
        points = try c.decodeIfPresent(Int.self, forKey: .points) ?? 0
        inviteCode = try c.decodeIfPresent(String.self, forKey: .inviteCode) ?? ""
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
        streakRiskNudgesEnabled = try c.decodeIfPresent(Bool.self, forKey: .streakRiskNudgesEnabled) ?? false
        inactivityNudgesEnabled = try c.decodeIfPresent(Bool.self, forKey: .inactivityNudgesEnabled) ?? false
        spokenNudgesEnabled = try c.decodeIfPresent(Bool.self, forKey: .spokenNudgesEnabled) ?? false
        watchConnected = try c.decodeIfPresent(Bool.self, forKey: .watchConnected) ?? false
    }

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
    /// Legacy field. Manual step entry was removed from the product —
    /// nothing writes to this anymore (AppState no longer has
    /// addManualSteps). Kept only so already-persisted historical records
    /// keep decoding and displaying their true recorded total; never used
    /// to decide goal completion, streaks, milestones, or ranking — see
    /// CreditedSteps, which is automatic-only for every record, old or new.
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
