import Foundation
import CoreMotion
import HealthKit
import Combine

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
//  5. Manual entries are always additive on top of whichever automatic source is
//     live, and stay tagged separately.

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

    /// True once HealthKit is the source of truth. The tracking screen uses this
    /// to choose between "Phone sensor — live" and "Phone + Watch — combined".
    var isCombined: Bool { healthConnected }

    private let pedometer = CMPedometer()
    private let health = HKHealthStore()
    private var healthObserver: HKObserverQuery?

    // MARK: - Core Motion

    func startPhoneTracking() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        let start = Calendar.current.startOfDay(for: Date())

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
                self.motionAuthorized = true
                if !self.healthConnected {
                    self.stepsFromPhone = data.numberOfSteps.intValue
                }
                // Cadence tracking runs regardless of HealthKit combining —
                // it's about right-now movement, not the day's official total.
                self.recordCadenceSample(data.numberOfSteps.intValue)
            }
        }

        cadenceTimer?.invalidate()
        cadenceTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateActivityState() }
        }

        Task { await refreshHourlyFromMotion() }
    }

    func stopPhoneTracking() {
        pedometer.stopUpdates()
        cadenceTimer?.invalidate()
        cadenceTimer = nil
    }

    // MARK: - Cadence / activity state

    private var cadenceSamples: [(date: Date, steps: Int)] = []
    private var cadenceTimer: Timer?

    private func recordCadenceSample(_ cumulative: Int) {
        let now = Date()
        cadenceSamples.append((now, cumulative))
        cadenceSamples.removeAll { now.timeIntervalSince($0.date) > 45 }
        updateActivityState()
    }

    /// Steps-per-minute over a short rolling window. No new callback means
    /// no motion, so a stale window (nothing in the last 20s) reads as idle
    /// even though CMPedometer itself only speaks when spoken to.
    private func updateActivityState() {
        let now = Date()
        guard let last = cadenceSamples.last,
              now.timeIntervalSince(last.date) < 20,
              let first = cadenceSamples.first,
              last.date.timeIntervalSince(first.date) >= 5
        else {
            activityState = .idle
            return
        }
        let elapsedMinutes = last.date.timeIntervalSince(first.date) / 60
        let stepsDelta = last.steps - first.steps
        let stepsPerMinute = elapsedMinutes > 0 ? Double(stepsDelta) / elapsedMinutes : 0

        if stepsPerMinute >= 100 {
            activityState = .active
        } else if stepsPerMinute >= 10 {
            activityState = .walking
        } else {
            activityState = .idle
        }
    }

    /// 24 buckets for the waveform. Core Motion answers one window at a time, so
    /// this walks the day hour by hour.
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
    /// are read off HKSource metadata, never derived.
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
