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
    /// Continuous read of how hard the last few seconds were moving, 0...1.
    /// activityState buckets this into idle/walking/active for pose choice;
    /// this is the finer-grained signal LiveAvatar uses to scale bob,
    /// lean and pace so the figure tracks real effort instead of snapping
    /// between three fixed looks.
    @Published private(set) var motionIntensity: Double = 0

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
        cadenceTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
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
        cadenceSamples.removeAll { now.timeIntervalSince($0.date) > 12 }
        updateActivityState()
    }

    /// Absolute step count in a short recent window — deliberately *not* a
    /// rate. A rate divides by elapsed time, so one or two incidental steps
    /// (the sensor can register those just from picking up or tapping the
    /// phone) computed out to a misleadingly high "steps per minute" over a
    /// tiny sample, and stayed stuck reading as "walking" indefinitely.
    /// Requiring a real minimum count in the window is far more resistant
    /// to that. Re-checked every 3s and goes idle within ~6s of the last
    /// real step, instead of the ~20s lag before.
    private func updateActivityState() {
        let now = Date()
        cadenceSamples.removeAll { now.timeIntervalSince($0.date) > 12 }

        guard let newest = cadenceSamples.last, now.timeIntervalSince(newest.date) < 6,
              let oldest = cadenceSamples.first
        else {
            activityState = .idle
            motionIntensity = 0
            return
        }

        let stepsInWindow = newest.steps - oldest.steps
        if stepsInWindow >= 20 {
            activityState = .active   // ~100+ steps/min
        } else if stepsInWindow >= 4 {
            activityState = .walking  // a handful of real steps, not sensor noise
        } else {
            activityState = .idle
        }

        // Same window, read as a continuum rather than three buckets — floor
        // at the walking threshold, saturate around a brisk jog.
        motionIntensity = min(1, max(0, (Double(stepsInWindow) - 2) / 28))
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
