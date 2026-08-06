import Foundation
import SwiftUI
import Combine

// The single source of truth the screens read from.
//
// Persistence is JSON in Application Support plus the shared app group (the
// widget reads today's figure from there). Firestore replaces the store later —
// §8 — without touching any screen.

@MainActor
final class AppState: ObservableObject {

    // MARK: Stored

    @Published var user = User()
    @Published var streak = Streak()
    @Published var dailyGoal: Int = 6_000
    @Published var records: [Date: DailyRecord] = [:]
    @Published var weekly = WeeklyChallenge(weekStart: Date().startOfWeek, target: 5)
    @Published var friends: [Friend] = []
    @Published var unlocks: [Unlock] = Unlock.catalog
    @Published var equipped: Set<UnlockTransform> = []
    @Published var isSignedIn = false
    @Published var firstQuestComplete = false
    @Published var lastProcessedDay: Date?

    /// Set when a milestone should interrupt. The root view presents it.
    @Published var pendingMilestone: Milestones.Event?

    // MARK: Services

    let steps = StepProvider()
    let auth: AuthService = LocalAuthService()

    private var bag = Set<AnyCancellable>()
    private static let storeKey = "stride.state.v1"
    private static let appGroup = "group.com.stride.app"

    init() {
        load()
        // Live step counts flow straight into today's record.
        steps.$stepsFromPhone
            .combineLatest(steps.$stepsFromWatch, steps.$hourly)
            .sink { [weak self] phone, watch, hourly in
                self?.applyLiveSteps(phone: phone, watch: watch, hourly: hourly)
            }
            .store(in: &bag)
    }

    // MARK: - Today

    var todayKey: Date { Calendar.current.startOfDay(for: Date()) }

    var today: DailyRecord {
        get { records[todayKey] ?? DailyRecord(date: todayKey) }
        set { records[todayKey] = newValue; persist() }
    }

    var todayTotal: Int { today.total }
    var goalMetToday: Bool { todayTotal >= dailyGoal }
    var stepsShortToday: Int { max(0, dailyGoal - todayTotal) }
    var progressToday: Double {
        dailyGoal > 0 ? min(1, Double(todayTotal) / Double(dailyGoal)) : 0
    }

    private func applyLiveSteps(phone: Int, watch: Int, hourly: [Int]) {
        var r = today
        r.stepsFromPhone = phone
        r.stepsFromWatch = watch
        r.hourlyBreakdown = hourly
        let wasMet = r.goalMet
        r.goalMet = r.total >= dailyGoal
        records[todayKey] = r

        if r.goalMet && !wasMet { creditGoalDay() }
        persist()
        publishToWidget()
    }

    /// Manual entries sit on top of whichever automatic source is live, tagged
    /// separately so they stay distinguishable. Handoff §5.
    func addManualSteps(_ n: Int) {
        guard n > 0 else { return }
        var r = today
        r.stepsManualAdd += n
        let wasMet = r.goalMet
        r.goalMet = r.total >= dailyGoal
        records[todayKey] = r
        if r.goalMet && !wasMet { creditGoalDay() }
        persist()
        publishToWidget()
    }

    // MARK: - Streak and points

    /// Called the moment today crosses the goal — the streak itself still only
    /// commits at midnight rollover.
    private func creditGoalDay() {
        let previousBest = streak.best
        let isFirstEver = streak.totalDaysHit == 0

        user.points += Points.award(for: today, goal: dailyGoal)

        var provisional = streak
        provisional.current += 1
        provisional.best = max(provisional.best, provisional.current)

        pendingMilestone = Milestones.event(after: provisional,
                                            previousBest: previousBest,
                                            isFirstGoalDayEver: isFirstEver)
        refreshWeekly()
        unlockEarnedItems()
    }

    /// Fold every completed day since the last launch into the streak.
    func reconcileStreak() {
        let result = StreakEngine.reconcile(streak: streak,
                                            lastProcessed: lastProcessedDay,
                                            records: records,
                                            goal: dailyGoal)
        streak = result.streak
        lastProcessedDay = result.lastProcessed
        unlockEarnedItems()
        persist()
    }

    // MARK: - Weekly

    func refreshWeekly() {
        let cal = Calendar.current
        let start = Date().startOfWeek
        if !cal.isDate(weekly.weekStart, inSameDayAs: start) {
            weekly = WeeklyChallenge(weekStart: start, target: 5)
        }
        var bars = Array(repeating: 0, count: 7)
        var hits = 0
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: start) else { continue }
            let key = cal.startOfDay(for: day)
            let total = records[key]?.total ?? 0
            bars[offset] = total
            if total >= dailyGoal { hits += 1 }
        }
        weekly.dailyBars = bars
        weekly.daysHit = hits
    }

    var weeklyIndexToday: Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: Date().startOfWeek, to: todayKey).day ?? 0
    }

    // MARK: - Unlocks

    func purchase(_ unlock: Unlock) {
        guard unlock.isPurchasable,
              !unlock.owned,
              user.points >= unlock.cost,
              let i = unlocks.firstIndex(where: { $0.id == unlock.id })
        else { return }
        user.points -= unlock.cost
        unlocks[i].owned = true
        user.avatarUnlocks.append(unlock.id)
        persist()
    }

    func toggleEquip(_ unlock: Unlock) {
        guard unlock.owned else { return }
        if equipped.contains(unlock.transform) {
            equipped.remove(unlock.transform)
        } else {
            equipped.insert(unlock.transform)
        }
        persist()
    }

    /// The thirty-day mark is earned, not bought. Handoff §7.
    private func unlockEarnedItems() {
        guard streak.totalDaysTracked >= 30,
              let i = unlocks.firstIndex(where: { $0.transform == .thirtyDayMark }),
              !unlocks[i].owned
        else { return }
        unlocks[i].owned = true
        equipped.insert(.thirtyDayMark)
    }

    // MARK: - Leaderboard

    var leaderboard: [Friend] {
        var all = friends
        all.append(Friend(name: user.name.isEmpty ? "You" : user.name,
                          todaySteps: todayTotal,
                          isMe: true))
        return all.sorted { $0.todaySteps > $1.todaySteps }
    }

    var myRank: Int {
        (leaderboard.firstIndex(where: { $0.isMe }) ?? 0) + 1
    }

    /// How far behind the person directly above.
    var stepsBehindNext: Int {
        let board = leaderboard
        guard let i = board.firstIndex(where: { $0.isMe }), i > 0 else { return 0 }
        return max(0, board[i - 1].todaySteps - board[i].todaySteps)
    }

    // MARK: - Progression

    var dayOneRecord: DailyRecord? {
        let key = Calendar.current.startOfDay(for: user.createdAt)
        return records[key]
    }

    var daysBetween: Int { user.daysSinceDayZero }

    // MARK: - Account

    func signOut() {
        Task { try? await auth.logOut() }
        isSignedIn = false
        persist()
    }

    func eraseEverything() {
        Task { try? await auth.deleteAccount() }
        user = User()
        streak = Streak()
        records = [:]
        friends = []
        unlocks = Unlock.catalog
        equipped = []
        isSignedIn = false
        firstQuestComplete = false
        lastProcessedDay = nil
        UserDefaults.standard.removeObject(forKey: Self.storeKey)
        UserDefaults(suiteName: Self.appGroup)?.removeObject(forKey: "today")
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var user: User
        var streak: Streak
        var dailyGoal: Int
        var records: [DailyRecord]
        var weekly: WeeklyChallenge
        var friends: [Friend]
        var unlocks: [Unlock]
        var equipped: [UnlockTransform]
        var isSignedIn: Bool
        var firstQuestComplete: Bool
        var lastProcessedDay: Date?
    }

    func persist() {
        let snap = Snapshot(user: user, streak: streak, dailyGoal: dailyGoal,
                            records: Array(records.values), weekly: weekly,
                            friends: friends, unlocks: unlocks,
                            equipped: Array(equipped), isSignedIn: isSignedIn,
                            firstQuestComplete: firstQuestComplete,
                            lastProcessedDay: lastProcessedDay)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        UserDefaults.standard.set(data, forKey: Self.storeKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storeKey),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }
        user = snap.user
        streak = snap.streak
        dailyGoal = snap.dailyGoal
        records = Dictionary(uniqueKeysWithValues: snap.records.map { ($0.date, $0) })
        weekly = snap.weekly
        friends = snap.friends
        unlocks = snap.unlocks
        equipped = Set(snap.equipped)
        isSignedIn = snap.isSignedIn
        firstQuestComplete = snap.firstQuestComplete
        lastProcessedDay = snap.lastProcessedDay
    }

    /// The widget reads this. Handoff §3 — StrideWidget is a separate target.
    private func publishToWidget() {
        guard let defaults = UserDefaults(suiteName: Self.appGroup) else { return }
        let payload: [String: Any] = [
            "steps": todayTotal,
            "goal": dailyGoal,
            "streak": streak.current,
            "goalMet": goalMetToday
        ]
        defaults.set(payload, forKey: "today")
    }
}

extension Date {
    /// Monday-first week start, matching `WeeklyChallenge.dailyBars`.
    var startOfWeek: Date {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return cal.date(from: comps) ?? cal.startOfDay(for: self)
    }
}
