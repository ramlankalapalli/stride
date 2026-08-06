import Foundation

// Every string in the app. Handoff §6, verbatim.
//
// Voice: cold, honest, evidence-based. Never encouraging. States facts plainly,
// including failures. No exclamation marks. Short sentences. "The record", "the
// file", "the figure". Never says "AI" anywhere.
//
// Nothing here is built by string concatenation with a mood — where a number
// varies, the function takes it and returns the whole line.

enum Copy {

    // MARK: - Intro

    enum Intro {
        static let oneLoud  = "No one is coming."
        static let oneSoft  = "Walk anyway."
        static let oneBody  = "Motivation is a mood. This is a record."
        static let oneCTA   = "Prove it"

        static let twoLoud  = "You are the data."
        static let twoSoft  = "Own it."
        static let twoBody  = "Your figure is built from what you do. Not what you planned."
        static let twoCTA   = "Next"

        static let threeLoud = "Streaks forgive"
        static let threeSoft = "nothing."
        static let threeBody = "Miss a day and the record shows it."
        static let threeCTA  = "Start day 01"
    }

    // MARK: - Auth

    enum SignUp {
        static let status  = "Day 00 · No streak"
        static let body    = "Nothing on you yet."
        static let name    = "What do we call you"
        static let email   = "Where do we find you"
        static let pass    = "Something you won't forget"
        static let cta     = "Start day 01"
        static let footer  = "Already on record? Log in"
    }

    enum LogIn {
        static let status  = "Day 06 · Streak alive"   // replaced at runtime by the real record
        static let body    = "Still here then."
        static let email   = "Where we find you"
        static let pass    = "The one you picked"
        static let forgot  = "Forgot it already?"
        static let cta     = "Back on record"
        static let footer  = "No file yet? Start one"

        /// The status line reflects the actual record once one exists.
        static func status(day: Int, streakAlive: Bool) -> String {
            let d = String(format: "%02d", day)
            return "Day \(d) · \(streakAlive ? "Streak alive" : "No streak")"
        }
    }

    enum Forgot {
        static let status  = "Streak on hold"
        static let loud    = "Told you you'd"
        static let soft    = "forget."
        static let body    = "Your record is fine. Only the key is missing."
        static let cta     = "Send the key"

        static let sentLoud = "Sent."
        static let sentSoft = "Go look."
        static let sentNote = "It expires in fifteen minutes."
        static let spam     = "Spam folder is a real place. We don't control it."
        static let resend   = "Nothing came? Send again"

        /// "Check r***@gmail.com. It expires in fifteen minutes."
        static func sentBody(email: String) -> String {
            "Check \(mask(email)). \(sentNote)"
        }

        /// r***@gmail.com
        static func mask(_ email: String) -> String {
            let parts = email.split(separator: "@", maxSplits: 1)
            guard let local = parts.first, parts.count == 2 else { return email }
            let head = local.prefix(1)
            return "\(head)***@\(parts[1])"
        }
    }

    enum NewPassword {
        static let status = "Last step"
        static let loud   = "Pick something"
        static let soft   = "new this time."
        static let cta    = "Lock it in"
    }

    // MARK: - Permissions

    enum MotionPermission {
        // TODO(open): §9 — this explainer may be unnecessary given Core Motion's
        // lighter permission model. Screen is built; the default flow skips it.
        // Flip `Flow.showsMotionExplainer` to re-enable.
        static let status = "Before we start"
        static let loud   = "The phone already"
        static let soft   = "counts you."
        static let facts  = [
            "Step count only, nothing else.",
            "No location. No GPS. Ever.",
            "Say no and the app still works. Type it in yourself."
        ]
        static let cta   = "Allow motion access"
        static let ghost = "Not now"
        /// Result state, shown on the tracking screen.
        static let liveLabel = "Phone sensor — live"
    }

    enum NotificationPermission {
        static let status = "One more thing"
        static let loud   = "We'll tell you"
        static let soft   = "when it matters."
        static let facts  = [
            "Only when your streak is at risk. Not daily noise.",
            "Some are spoken out loud if you want that, off by default.",
            "Say no now, turn it on later in settings."
        ]
        static let cta   = "Allow notifications"
        static let ghost = "Not now"
    }

    // MARK: - Onboarding questions

    enum Onboarding {
        static let ageQuestion = "How old are you really?"
        static let ageHint     = "The figure doesn't judge. It just needs the number."

        static let heightQuestion = "How tall?"
        static let heightHint     = "It changes what a step is worth. Nothing else."

        static let weightQuestion = "And your weight?"
        static let weightHint     = "Skip it if you'd rather. The record works without."

        static let goalQuestion = "What are you aiming at daily?"
        static let goalHint     = "Pick something you'll actually hit. You can move it later."

        static let activityQuestion = "Be honest. How much do you move?"
        static let activityHint     = "Nobody is checking. Only the figure."

        static let heard = "We heard"
        /// "32 — change it if we're wrong"
        static func heardBack(_ value: String) -> String { "\(value) — change it if we're wrong" }

        static let skip = "Skip this one"
    }

    enum Review {
        static let status = "Last look"
        static let loud   = "Check it before"
        static let soft   = "it's permanent."
        static let cta    = "Confirm and build the figure"
    }

    enum Reveal {
        static let status = "File opened"
        static let loud   = "This is you."
        static let soft   = "Everything else is proof."
        static let cta    = "Start day 01"
    }

    enum FirstQuest {
        static let status  = "Your first target"
        static let loud    = "Small."
        static let soft    = "On purpose."
        static let target  = 1_000
        static let unit    = "Steps to open the file"
        static let note    = "Not the daily goal. Just proof the record works."
        static let expiry  = "Expires in 24 hours"
        static let cta     = "Start now"
    }

    // MARK: - Home

    enum Home {
        static let status = "Today so far"
        static let inProgress = "Not finished. Not yet failed."
        static let done       = "Done. Do it again tomorrow."
        static let notStarted = "Nothing on the record yet today."

        static func remaining(_ n: Int) -> String { "\(n.formattedSteps) short" }
    }

    // MARK: - Tracking

    enum Tracking {
        static let phoneOnly   = "Phone sensor — live"
        static let combined    = "Phone + Watch — combined"
        static let counted     = "Counted the second you moved"
        static let watchPrompt = "Got an Apple Watch? Connect Health too"

        static func fromPhone(_ n: Int) -> String { "\(n.formattedSteps) from phone" }
        static func fromWatch(_ n: Int) -> String { "\(n.formattedSteps) from watch" }
        static func manual(_ n: Int) -> String { "\(n.formattedSteps) typed in" }
    }

    enum ConnectWatch {
        static let status = "Only if you want more counted"
        static let loud   = "Your phone already"
        static let soft   = "counts you."
        static let body   = "This just adds Watch steps on top. Skip it and nothing changes."
        static let cta    = "Connect Watch"
        static let ghost  = "Skip — phone is enough"
    }

    // MARK: - Record / streak

    enum Record {
        static let status = "Current streak"

        /// The subtitle rotates on state. This is where the app is least kind.
        static func subtitle(streak: Streak) -> String {
            if streak.current == 0 && streak.best > 1 {
                return "You've had \(streak.best). You threw it away."
            }
            if streak.current == 0 { return "Nothing running. Start again." }
            if streak.current == streak.best && streak.current > 1 {
                return "Longest you've held it. So far."
            }
            if streak.best > streak.current {
                return "\(streak.best) was your best. This isn't it yet."
            }
            return "Day \(streak.current). Keep it or don't."
        }

        static func tracked(_ s: Streak) -> String { "\(s.totalDaysTracked) days tracked" }
        static func hit(_ s: Streak) -> String { "\(s.totalDaysHit) hit" }
        static func missed(_ s: Streak) -> String { "\(s.totalDaysMissed) missed" }
    }

    enum Weekly {
        static let status = "This week"

        static func subtitle(daysHit: Int, target: Int) -> String {
            if daysHit >= target { return "Done. It counted." }
            if daysHit == target - 1 { return "\(daysHit.spelled.capitalized) isn't \(target.spelled)." }
            return "\(daysHit.spelled.capitalized) of \(target.spelled)."
        }

        /// "3,120 today. 1,880 short."
        static func footnote(today: Int, short: Int) -> String {
            short <= 0
                ? "\(today.formattedSteps) today. Nothing owed."
                : "\(today.formattedSteps) today. \(short.formattedSteps) short."
        }
    }

    enum Milestone {
        static let status = "Streak extended"
        static let dismiss = "Back to it"
        static func points(_ n: Int) -> String { "+\(n) points" }

        // TODO(open): §9 asked for a milestone copy table beyond 7. This is it.
        // Same voice — flat, unimpressed, factual.
        private static let table: [Int: String] = [
            1:   "Day one. The file is open.",
            7:   "Seven. Nobody noticed.",
            14:  "Fourteen. Still nothing special.",
            21:  "Three weeks. That's a habit, not a feat.",
            28:  "Twenty-eight. The figure has changed. Slightly.",
            35:  "Thirty-five. You stopped negotiating with yourself.",
            50:  "Fifty. Most people quit around four.",
            75:  "Seventy-five. The record is longer than the excuse.",
            100: "One hundred. Say nothing. Walk tomorrow."
        ]

        static func line(for streak: Int, isPersonalBest: Bool) -> String {
            if let exact = table[streak] { return exact }
            if isPersonalBest { return "\(streak). Longer than you've ever held it." }
            return "\(streak). The record keeps itself."
        }
    }

    // MARK: - Social

    enum Leaderboard {
        static let status = "Your position"

        static func subtitle(rank: Int, of total: Int) -> String {
            if total <= 1 { return "Nobody to lose to yet." }
            if rank == 1 { return "First. For now." }
            if rank == 2 { return "First of the losers." }
            if rank == total { return "Last. Plainly." }
            return "\(rank.ordinal) of \(total). Not the top."
        }

        /// "1,240 short. Three days."
        static func footnote(short: Int, days: Int) -> String {
            "\(short.formattedSteps) short. \(days.spelled.capitalized) day\(days == 1 ? "" : "s")."
        }
    }

    enum AddFriends {
        static let status = "Right now it's just you"
        static let loud   = "Add someone"
        static let soft   = "to lose to."
        static let empty  = "Nobody found yet. That's fine."
        static let cta    = "Share invite link"
        static let field  = "Their invite code"
    }

    // MARK: - Points and unlocks

    enum Unlocks {
        static let status = "Points banked"
        static let note   = "Spend them or don't."
        static let later  = "Later"
        static let owned  = "Owned"
        static let equip  = "Equip"
        static let equipped = "Equipped"
        static func cost(_ n: Int) -> String { "\(n) points" }
        static func lockedAt(days: Int) -> String { "Earned at \(days) days tracked" }
    }

    enum Progression {
        static func header(_ days: Int) -> String { "\(days) days between these" }
        static let loud   = "Same figure."
        static let soft   = "Different person."
        static let cta    = "Share this"
        static let footer = "Nobody made you do this"
        static let before = "Day 01"
        static let after  = "Now"
    }

    // MARK: - Profile and settings

    enum Profile {
        static let status = "The figure"

        /// "42 days tracked. 13 wasted."
        static func subtitle(_ s: Streak) -> String {
            "\(s.totalDaysTracked) days tracked. \(s.totalDaysMissed) wasted."
        }
    }

    enum Settings {
        static let title = "Settings"

        static let trackingGroup = "Tracking"
        static let theNumber     = "The number"
        static let healthSync    = "Health sync"
        static let measuredIn    = "Measured in"

        static let notificationsGroup = "Notifications"
        static let nagMe          = "Nag me"
        static let streakWarnings  = "Streak warnings"
        static let spokenNudges    = "Read them out loud"

        static let leavingGroup = "Leaving"
        static let logOut       = "Log out"
        static let eraseAll     = "Erase everything"

        // TODO(open): §9 — app name is still a placeholder.
        static let footer = "Stride 1.0 — nothing to sell you"
    }

    enum DeleteAccount {
        static let status = "No going back"
        static let loud   = "Erase the"
        static let soft   = "whole file?"
        static let confirmWord = "ERASE"
        static let field  = "Type \(confirmWord) to confirm"
        static let footer = "This is the only thing we make hard to do."
        static let cta    = "Erase everything"
        static let ghost  = "Never mind"

        /// "This deletes everything — 42 days of steps. Every streak. The figure.
        ///  Gone, not paused. There's no recovering it."
        static func warning(days: Int) -> String {
            "This deletes everything — \(days) days of steps. Every streak. The figure. Gone, not paused. There's no recovering it."
        }
    }

    // MARK: - Nudges

    enum Nudge {
        static func text(for trigger: NudgeTrigger, streak: Int, short: Int) -> String {
            switch trigger {
            case .streakAtRiskAM:
                return "Half the day is gone. \(short.formattedSteps) short. The streak is \(streak)."
            case .streakAtRiskPM:
                return "\(short.formattedSteps) short with hours left. \(streak) days end tonight if you sit."
            case .missedYesterday:
                return "Yesterday is a miss. It's on the record. Nothing today yet."
            case .longSilence:
                return "Two days of nothing. The file is still open. That's all we'll say."
            }
        }
    }

    // MARK: - Shared

    enum Nav {
        static let today  = "Today"
        static let record = "Record"
        static let others = "Others"
        static let you    = "You"
    }

    static let back = "Back"
    static let stepsLabel = "Steps"
    static let goalLabel = "Goal"
}

// Number formatting (formattedSteps, spelled, ordinal) lives in
// Design/NumberFormatting.swift — shared with the widget target.
