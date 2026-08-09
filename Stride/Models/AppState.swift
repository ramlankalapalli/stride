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

    /// Bumped the instant today's total first crosses the goal — the
    /// in-the-moment Home screen reaction, distinct from pendingMilestone
    /// (which only fires for streak/best-day moments and routes to its own
    /// screen). Not persisted; a transient signal for this launch only.
    @Published private(set) var goalBreakthroughTick: Int = 0

    // MARK: Services

    let steps = StepProvider()
    let auth: AuthService = LocalAuthService()

    private var bag = Set<AnyCancellable>()
    private static let storeKey = "stride.state.v1"
    private static let appGroup = "group.com.stride.app"

    /// Phase 1.0.5: high-frequency step deltas used to call persist() (a
    /// full JSON re-encode of the whole app) and publishToWidget() on every
    /// single CMPedometer update — unbounded while walking. Coalesced here;
    /// reward/lifecycle events still bypass this via persistImmediately.
    private let persistenceThrottle = Throttler(interval: MotionConfig.persistenceDebounceInterval)

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

    /// Manual entry no longer exists (see the removed addManualSteps
    /// below), so `today.total` and `today.automatic` are now always
    /// identical — there's no separate "credited" number needed for the
    /// live experience. Goal completion, progress, and the remaining-steps
    /// line all read the one trustworthy total directly. CreditedSteps
    /// still exists, but only for evaluating *other* days (streak
    /// reconciliation, the weekly waveform) that might be old enough to
    /// carry a legacy manual value — see CreditedSteps.swift.
    var goalMetToday: Bool { todayTotal >= dailyGoal }
    var stepsShortToday: Int { max(0, dailyGoal - todayTotal) }
    var progressToday: Double {
        dailyGoal > 0 ? min(1, Double(todayTotal) / Double(dailyGoal)) : 0
    }

    /// Phase 1.0.5: the streak as it should actually be shown right now —
    /// `streak` plus a live +1 if today already qualifies, without ever
    /// writing that bump back early. See StreakEngine.displayedStreak for
    /// why this can't cause reconcileStreak() to double-count.
    var displayedStreak: Streak {
        StreakEngine.displayedStreak(base: streak, todayQualifies: goalMetToday)
    }

    private func applyLiveSteps(phone: Int, watch: Int, hourly: [Int]) {
        var r = today
        r.stepsFromPhone = phone
        r.stepsFromWatch = watch
        r.hourlyBreakdown = hourly
        let wasMet = r.goalMet
        // today.total == today.automatic always, now that manual entry is
        // gone — a plain comparison is the whole rule.
        r.goalMet = r.total >= dailyGoal
        let newlyQualified = r.goalMet && !wasMet
        records[todayKey] = r

        if newlyQualified { creditGoalDay() } // mutates points/streak-display inputs only, doesn't persist
        if newlyQualified {
            persistImmediately() // reward transaction — never delayed
        } else {
            persistThrottled() // raw cadence of pedometer deltas — coalesced
        }
    }

    // Manual step entry (addManualSteps) has been removed from the product.
    // Stride is an automatic-movement product — every DailyRecord created
    // from here on can only ever be populated by StepProvider's automatic
    // sensor/Health sources. DailyRecord.stepsManualAdd remains as a stored
    // field purely so already-persisted historical records keep decoding
    // and displaying correctly; nothing writes to it anymore.

    // MARK: - Streak and points

    /// Called the moment today crosses the goal. The *persisted* streak
    /// still only commits at midnight rollover (via reconcileStreak) — that
    /// part is unchanged and is what keeps this idempotent and consistent
    /// with lastProcessedDay. What changed in Phase 1.0.5: this used to
    /// compute a "provisional" streak just for the milestone check and throw
    /// it away, which is exactly why Home/Record/Profile kept showing
    /// yesterday's streak after a legitimate same-day goal hit. Now
    /// `displayedStreak` (computed fresh from `streak` + today's
    /// qualification) is the one source of truth for both the UI and the
    /// milestone check below — nothing provisional, nothing duplicated.
    private func creditGoalDay() {
        let previousBest = streak.best
        let isFirstEver = streak.totalDaysHit == 0

        goalBreakthroughTick += 1
        user.points += Points.award(for: today, goal: dailyGoal)

        pendingMilestone = Milestones.event(after: displayedStreak,
                                            previousBest: previousBest,
                                            isFirstGoalDayEver: isFirstEver)
        refreshWeekly()
        unlockEarnedItems()
        // Persistence is applyLiveSteps's responsibility — it already knows
        // whether this is the throttle-bypassing branch.
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
        persistImmediately() // once per launch — correctness-critical, never delayed
    }

    // MARK: - Persistence throttling
    //
    // Phase 1.0.5. persist() (full JSON snapshot) and publishToWidget() used
    // to run on every raw CMPedometer delta. High-frequency step updates now
    // go through persistThrottled(); anything reward-bearing or a lifecycle
    // boundary goes through persistImmediately() instead — never delayed.
    // Trade-off: if the app is killed before a throttled trailing write
    // fires, only the last few seconds of raw step count are at risk —
    // never a goal crossing, a purchase, or a sign-out/erase, all of which
    // are exempted below.

    private func persistAndPublish() {
        persist()
        publishToWidget()
    }

    private func persistThrottled() {
        persistenceThrottle.call { [weak self] in self?.persistAndPublish() }
    }

    private func persistImmediately() {
        persistenceThrottle.flushNow { [weak self] in self?.persistAndPublish() }
    }

    /// Called when the app is about to background — makes sure nothing
    /// still sitting in the throttle's trailing-call window is lost.
    func flushPendingState() {
        persistImmediately()
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
            let record = records[key]
            bars[offset] = record?.total ?? 0
            // Credited, not raw — a day that wouldn't count toward the daily
            // streak shouldn't count toward the weekly target either.
            if let record, CreditedSteps.qualifies(record, goal: dailyGoal) { hits += 1 }
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
        persistImmediately() // a spend — never delayed
    }

    func toggleEquip(_ unlock: Unlock) {
        guard unlock.owned else { return }
        if equipped.contains(unlock.transform) {
            equipped.remove(unlock.transform)
        } else {
            equipped.insert(unlock.transform)
        }
        persistImmediately()
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
        // todayTotal, not a separate credited figure — today can only ever
        // contain automatic steps now, so there's nothing left to exploit.
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
        persistImmediately()
    }

    func eraseEverything() {
        // Cancel any pending throttled trailing write first — otherwise a
        // stale pre-erase snapshot could land in UserDefaults *after* the
        // removeObject calls below and partially resurrect what was just
        // erased.
        persistenceThrottle.flushNow {}

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
            "streak": displayedStreak.current,
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
