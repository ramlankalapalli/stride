import Foundation
import CoreMotion
import HealthKit
import Combine
import UIKit

// Step sources. Handoff §5.
//
// Priority:
//  1. Core Motion (CMPedometer) reads the phone sensor directly. This is the
//     Motion & Fitness entitlement — not HealthKit.
//  2. If the user connects a Watch, request HealthKit read-only access to
//     stepCount and nothing else.
//  3. When both exist, do NOT sum them. HealthKit already de-duplicates phone
//     and watch samples. Once connected, HealthKit is the source of truth and
//     CMPedometer is only the fallback.
//  4. The phone/watch split shown in the UI comes from HKSource metadata on the
//     samples — it is never calculated by hand.
//  5. Manual entry has been removed from the product — Stride is an
//     automatic-movement product. Automatic sensor/Health sources are the
//     sole source of truth for everything a record here feeds into.

// ActivityState lives in Shared/Design/AvatarView.swift — LiveAvatar (which
// the widget target also compiles) needs it, same reason UnlockTransform
// lives there instead of in Models.

@MainActor
final class StepProvider: ObservableObject {

    @Published private(set) var stepsFromPhone: Int = 0
    @Published private(set) var stepsFromWatch: Int = 0
    @Published private(set) var hourly: [Int] = Array(repeating: 0, count: 24)
    @Published private(set) var motionAuthorized: Bool = false
    @Published private(set) var healthConnected: Bool = false
    @Published private(set) var activityState: ActivityState = .idle
    /// Continuous read of how hard the last few seconds were moving, 0...1.
    /// activityState buckets this into idle/walking/active for pose choice;
    /// this is the finer-grained signal LiveAvatar uses to scale bob,
    /// lean and pace so the figure tracks real effort instead of snapping
    /// between three fixed looks.
    @Published private(set) var motionIntensity: Double = 0

    // MARK: - Inactivity / session / momentum signals (Phase 1.0.5)
    //
    // Foundation only — nothing here is consumed by any view yet. These
    // exist so a future Momentum/Figure phase has real signals to build on
    // instead of starting from nothing. See MovementClassifier for the pure
    // math behind them.

    /// Rising/steady/falling read on `motionIntensity` between ticks.
    @Published private(set) var movementTrend: MovementTrend = .steady
    /// A movement session survives short pauses (a stoplight, tying a shoe);
    /// only a sustained pause ends it — see MotionConfig.sessionEndInactivity.
    @Published private(set) var isInMovementSession: Bool = false
    @Published private(set) var movementSessionStartedAt: Date?
    @Published private(set) var movementSessionDuration: TimeInterval?
    @Published private(set) var lastMeaningfulMovementAt: Date?
    /// nil until the first meaningful movement of the session is observed —
    /// distinct from "0 seconds ago".
    @Published private(set) var inactiveDuration: TimeInterval?
    /// Rolling count of seconds spent in walking/active state today — a
    /// coarse "active minutes" proxy, reset on day rollover.
    @Published private(set) var activeSecondsToday: TimeInterval = 0

    /// True once HealthKit is the source of truth. The tracking screen uses this
    /// to choose between "Phone sensor — live" and "Phone + Watch — combined".
    var isCombined: Bool { healthConnected }

    private let pedometer = CMPedometer()
    private let health = HKHealthStore()
    private var healthObserver: HKObserverQuery?

    private var classifier = MovementClassifier()
    private var classifierTimer: Timer?
    private var hourlyRefreshTimer: Timer?
    private var midnightTimer: Timer?
    private var foregroundObserver: NSObjectProtocol?

    /// The local calendar day the live pedometer query is currently rebased
    /// to. Compared against on every delta and every timer tick to catch a
    /// midnight rollover while the app stays alive — see
    /// `rebaseForNewDayIfNeeded`.
    private var trackingDayStart: Date = DayBoundary.startOfDay()

    // MARK: - Core Motion

    func startPhoneTracking() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        trackingDayStart = DayBoundary.startOfDay()
        beginPedometerUpdates(from: trackingDayStart)

        classifierTimer?.invalidate()
        classifierTimer = Timer.scheduledTimer(withTimeInterval: MotionConfig.classifierTickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.classifierTick() }
        }

        hourlyRefreshTimer?.invalidate()
        hourlyRefreshTimer = Timer.scheduledTimer(withTimeInterval: MotionConfig.hourlyRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshCurrentHourOnly() }
        }

        scheduleMidnightRebase()

        if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.rebaseForNewDayIfNeeded()
                await self.refreshCurrentHourOnly()
            }
        }

        Task { await refreshHourlyFromMotion() }
    }

    func stopPhoneTracking() {
        pedometer.stopUpdates()
        classifierTimer?.invalidate()
        classifierTimer = nil
        hourlyRefreshTimer?.invalidate()
        hourlyRefreshTimer = nil
        midnightTimer?.invalidate()
        midnightTimer = nil
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
            self.foregroundObserver = nil
        }
    }

    /// The actual query + live-update wiring, factored out so both a fresh
    /// launch and a midnight rebase can issue it against whatever
    /// `trackingDayStart` currently is, without duplicating the callback code.
    private func beginPedometerUpdates(from start: Date) {
        pedometer.queryPedometerData(from: start, to: Date()) { [weak self] data, _ in
            guard let self, let data else { return }
            Task { @MainActor in
                self.motionAuthorized = true
                if !self.healthConnected {
                    self.stepsFromPhone = data.numberOfSteps.intValue
                }
            }
        }

        pedometer.startUpdates(from: start) { [weak self] data, _ in
            guard let self, let data else { return }
            Task { @MainActor in
                // Guard first: a step arriving right after local midnight
                // must not be applied against yesterday's query origin.
                self.rebaseForNewDayIfNeeded()
                self.motionAuthorized = true
                if !self.healthConnected {
                    self.stepsFromPhone = data.numberOfSteps.intValue
                }
                // Cadence tracking runs regardless of HealthKit combining —
                // it's about right-now movement, not the day's official total.
                self.classifier.record(steps: data.numberOfSteps.intValue)
                self.publishClassifierSnapshot()
            }
        }
    }

    // MARK: - Midnight rollover

    /// Detects a local calendar-day rollover while the app stays alive and
    /// rebases the pedometer query, the cadence classifier, and the hourly
    /// waveform for the new day. Without this, `pedometer.startUpdates(from:)`
    /// keeps reporting a cumulative count from yesterday's origin — since
    /// AppState.todayKey rolls to a fresh, empty DailyRecord at midnight on
    /// its own, the next live delta after midnight would otherwise write
    /// yesterday's large cumulative total into today's fresh record.
    ///
    /// Called from three places so the gap between actual midnight and the
    /// rebase taking effect stays as small as possible without polling
    /// aggressively: inline in the live-update handler (catches it the
    /// instant a step arrives), on every classifier timer tick (catches it
    /// within `MotionConfig.classifierTickInterval` even with zero steps),
    /// and from a dedicated one-shot timer scheduled for the next midnight
    /// itself (catches it immediately even with zero steps and no tick
    /// coincidence).
    private func rebaseForNewDayIfNeeded(now: Date = Date()) {
        guard DayBoundary.hasRolledOver(from: trackingDayStart, now: now) else { return }
        trackingDayStart = DayBoundary.startOfDay(now)

        pedometer.stopUpdates()
        classifier.reset()
        activityState = .idle
        motionIntensity = 0
        movementTrend = .steady
        isInMovementSession = false
        movementSessionStartedAt = nil
        movementSessionDuration = nil
        lastMeaningfulMovementAt = nil
        inactiveDuration = nil
        activeSecondsToday = 0

        guard !healthConnected else { return }
        stepsFromPhone = 0
        hourly = Array(repeating: 0, count: 24)
        beginPedometerUpdates(from: trackingDayStart)
        Task { await refreshHourlyFromMotion() }
    }

    private func scheduleMidnightRebase() {
        midnightTimer?.invalidate()
        let fireDate = DayBoundary.nextMidnight(after: Date())
        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.rebaseForNewDayIfNeeded()
                self?.scheduleMidnightRebase()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        midnightTimer = timer
    }

    // MARK: - Cadence / activity classification

    private func classifierTick() {
        rebaseForNewDayIfNeeded()
        let wasActive = activityState != .idle
        publishClassifierSnapshot()
        if wasActive { activeSecondsToday += MotionConfig.classifierTickInterval }
    }

    private func publishClassifierSnapshot() {
        let snap = classifier.evaluate()
        activityState = snap.activityState
        motionIntensity = snap.motionIntensity
        movementTrend = snap.trend
        isInMovementSession = snap.isInMovementSession
        movementSessionStartedAt = snap.movementSessionStartedAt
        movementSessionDuration = snap.movementSessionDuration
        lastMeaningfulMovementAt = snap.lastMeaningfulMovementAt
        inactiveDuration = snap.inactiveDuration
    }

    // MARK: - Hourly waveform

    /// 24 buckets for the waveform. Core Motion answers one window at a time, so
    /// this walks the day hour by hour. Only called once per day boundary
    /// (launch, midnight rebase) — for keeping the *current* hour fresh
    /// through the rest of the session, see `refreshCurrentHourOnly`.
    private func refreshHourlyFromMotion() async {
        guard CMPedometer.isStepCountingAvailable() else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        var buckets = Array(repeating: 0, count: 24)
        let currentHour = cal.component(.hour, from: Date())

        for hour in 0...currentHour {
            guard let from = cal.date(byAdding: .hour, value: hour, to: start),
                  let to = cal.date(byAdding: .hour, value: 1, to: from) else { continue }
            let count: Int = await withCheckedContinuation { cont in
                pedometer.queryPedometerData(from: from, to: min(to, Date())) { data, _ in
                    cont.resume(returning: data?.numberOfSteps.intValue ?? 0)
                }
            }
            buckets[hour] = count
        }
        if !healthConnected { hourly = buckets }
    }

    /// Re-queries only the current hour's bucket and updates it in place —
    /// deliberately not a 24-hour re-walk. Historical hours are already
    /// correct and untouched; this is the fix for the current-hour bar
    /// otherwise freezing at whatever it was when tracking started. Run on
    /// a conservative timer (MotionConfig.hourlyRefreshInterval), plus after
    /// a midnight rebase and after returning to foreground — never on the
    /// 3s classifier tick.
    private func refreshCurrentHourOnly() async {
        guard CMPedometer.isStepCountingAvailable(), !healthConnected else { return }
        let cal = Calendar.current
        let now = Date()
        guard let hourStart = cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: now)) else { return }
        let hourIndex = cal.component(.hour, from: now)
        guard hourly.indices.contains(hourIndex) else { return }

        let count: Int = await withCheckedContinuation { cont in
            pedometer.queryPedometerData(from: hourStart, to: now) { data, _ in
                cont.resume(returning: data?.numberOfSteps.intValue ?? 0)
            }
        }
        hourly[hourIndex] = count
    }

    // MARK: - HealthKit

    /// Read-only, stepCount only. Nothing else is ever requested.
    func connectWatch() async throws {
        guard HKHealthStore.isHealthDataAvailable(),
              let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)
        else { return }

        try await health.requestAuthorization(toShare: [], read: [stepType])
        healthConnected = true
        await refreshFromHealth()
        startHealthObserver(stepType)
    }

    func disconnectWatch() {
        if let q = healthObserver { health.stop(q) }
        healthObserver = nil
        healthConnected = false
        stepsFromWatch = 0
        startPhoneTracking()
    }

    private func startHealthObserver(_ type: HKQuantityType) {
        let q = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, done, _ in
            Task { @MainActor in await self?.refreshFromHealth() }
            done()
        }
        health.execute(q)
        healthObserver = q
        health.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
    }

    /// Splits today's HealthKit steps by source. The breakdown lines in the UI
    /// are read off HKSource metadata, never derived. Always predicated on
    /// `cal.startOfDay(for: Date())` freshly computed each call, so unlike
    /// the CMPedometer path this is naturally safe across a midnight
    /// rollover with no rebase logic needed.
    private func refreshFromHealth() async {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        let samples: [HKQuantitySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: stepType,
                                  predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, results, _ in
                cont.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            health.execute(q)
        }

        var phone = 0
        var watch = 0
        var buckets = Array(repeating: 0, count: 24)

        for s in samples {
            let count = Int(s.quantity.doubleValue(for: .count()))
            if Self.isWatch(s.sourceRevision) { watch += count } else { phone += count }
            let hour = cal.component(.hour, from: s.startDate)
            if buckets.indices.contains(hour) { buckets[hour] += count }
        }

        stepsFromPhone = phone
        stepsFromWatch = watch
        hourly = buckets
    }

    private static func isWatch(_ revision: HKSourceRevision) -> Bool {
        if let product = revision.productType, product.hasPrefix("Watch") { return true }
        return revision.source.name.localizedCaseInsensitiveContains("watch")
    }
}
