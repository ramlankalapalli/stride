import Foundation

// Product decision (Phase 1.1 prep): Stride is an automatic-movement
// product. Manual step entry has been removed from the experience entirely
// (see AppState — addManualSteps no longer exists, and StepTrackingScreen
// no longer has an entry field). Automatic sensor/Core Motion sources —
// later HealthKit/Apple Watch too — are the sole source of truth for
// anything competitive or reward-bearing: daily goal completion, streak
// credit, milestones, weekly-challenge hits, leaderboard ranking, points.
//
// This file used to hold a 20%-of-goal manual-entry cap (Phase 1.0.5,
// closing the exploit where an uncapped manual number could qualify a day
// on its own). That cap logic is gone now that manual entry can't be
// created going forward, which is what "do not maintain unnecessarily
// complicated anti-manual-cheat logic for newly generated records" means in
// practice — there's nothing left to cap.
//
// What's left is strictly a migration concern: DailyRecord.stepsManualAdd
// still exists as a stored field (old, already-persisted days may still
// have a nonzero value there — that data is never deleted, and
// DailyRecord.total still includes it for historical transparency). This
// file is what makes sure that legacy value is *never counted* toward
// qualification, for old records exactly the same as new ones — automatic
// is the only source that ever grants a reward, past or present. New
// records can never have a nonzero stepsManualAdd at all, so for them this
// is equivalent to just reading the total directly; for old records, it's
// what prevents a historical manual entry from silently re-qualifying
// something on a future re-evaluation (e.g. the weekly waveform scanning
// past days, or StreakEngine.reconcile walking a backlog).

enum CreditedSteps {

    /// Whether a record's automatic total alone clears the goal. The one
    /// qualification check every reward-bearing path shares — old records
    /// and new ones alike, always automatic-only. There's deliberately no
    /// separate "credited total" number anymore: for a record with no
    /// manual steps (every record going forward), that would just be
    /// `record.automatic` restated, and nothing needs it as a standalone
    /// value — only the yes/no qualification question does.
    static func qualifies(_ record: DailyRecord, goal: Int) -> Bool {
        guard goal > 0 else { return false }
        return record.automatic >= goal
    }
}
