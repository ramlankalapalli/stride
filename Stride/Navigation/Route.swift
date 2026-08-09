import SwiftUI

// Routes. Handoff §3 — names match the table exactly.

enum Route: Hashable {
    // 1–3
    case introSlide1, introSlide2, introSlide3
    // 4–8
    case signUp, logIn, forgotPassword, forgotPasswordSent, setNewPassword
    // 9–10
    case motionPermission, notificationPermission
    // 11–12 — one component, param-driven, reused ×5
    case onboardingQuestion(Int)
    // 13–15
    case reviewAnswers, avatarReveal, firstQuest
    // 16–18 — also tab roots (MainShell instantiates HomeScreen directly for
    // the .today tab). These cases exist so RouteDestination stays complete
    // for any future push-based/deep-link entry point, but nothing in the
    // app currently pushes .home — it's reached by selecting the tab.
    case home, stepTracking, connectWatch
    // 19–21
    case record, weeklyChallenge
    // Note: the Milestone screen is intentionally NOT a Route case. It's
    // presented via AppState.pendingMilestone + RootView's
    // .fullScreenCover(item:), a parallel mechanism independent of the
    // NavigationStack path — see RootView.swift. A .milestone(Event) case
    // used to exist here but was never pushed anywhere (confirmed dead);
    // removed in Phase 1.0.5 rather than left as a second, unused way to
    // reach the same screen.
    // 22–25 — .leaderboard and .profile below are also tab roots, same
    // situation as .home above.
    case leaderboard, addFriends, unlocks, progression
    // 26–28
    case profile, settings, deleteConfirm
    // Development-only — Phase 1.1A Figure Motion Engine visual tuning.
    // Never reachable in a normal release build; see FigureLabScreen.swift.
    #if DEBUG || STRIDE_INTERNAL_TESTING
    case figureLab
    #endif
}

enum Flow {
    /// TODO(open): §9 — Core Motion's permission model is lighter than
    /// HealthKit's, so the explainer is skipped by default. The screen exists;
    /// flip this to put it back in the sequence.
    static let showsMotionExplainer = false

    /// The five onboarding questions, in order. Handoff §3 rows 11–12: one
    /// component, driven by this table.
    static let questions: [OnboardingQuestionSpec] = [
        .init(kind: .number(range: 13...100, unit: nil, step: 1),
              question: Copy.Onboarding.ageQuestion,
              hint: Copy.Onboarding.ageHint,
              field: .age),
        .init(kind: .number(range: 120...220, unit: "cm", step: 1),
              question: Copy.Onboarding.heightQuestion,
              hint: Copy.Onboarding.heightHint,
              field: .height),
        .init(kind: .number(range: 30...200, unit: "kg", step: 1),
              question: Copy.Onboarding.weightQuestion,
              hint: Copy.Onboarding.weightHint,
              field: .weight,
              skippable: true),
        .init(kind: .choice(ActivityLevel.allCases.map(\.label)),
              question: Copy.Onboarding.activityQuestion,
              hint: Copy.Onboarding.activityHint,
              field: .activity),
        .init(kind: .number(range: 1_000...30_000, unit: "steps", step: 500),
              question: Copy.Onboarding.goalQuestion,
              hint: Copy.Onboarding.goalHint,
              field: .goal)
    ]
}

struct OnboardingQuestionSpec {
    enum Kind {
        // Enum case associated values can't carry default parameter values in
        // Swift — every call site below passes `step` explicitly.
        case number(range: ClosedRange<Int>, unit: String?, step: Int)
        case choice([String])
    }
    enum Field { case age, height, weight, activity, goal }

    var kind: Kind
    var question: String
    var hint: String
    var field: Field
    var skippable: Bool = false
}

// MARK: - Router

@MainActor
final class Router: ObservableObject {

    enum Phase { case intro, auth, onboarding, main }

    @Published var phase: Phase = .intro
    @Published var path: [Route] = []
    @Published var tab: Tab = .today

    enum Tab: Hashable { case today, record, others, you }

    func push(_ route: Route) { path.append(route) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path.removeAll() }

    func enterMain() {
        path.removeAll()
        phase = .main
        tab = .today
    }

    /// After sign-up: permissions, then the five questions, then review.
    func startOnboarding() {
        phase = .onboarding
        path = Flow.showsMotionExplainer ? [.motionPermission] : [.notificationPermission]
    }

    func advanceQuestion(after index: Int) {
        if index + 1 < Flow.questions.count {
            push(.onboardingQuestion(index + 1))
        } else {
            push(.reviewAnswers)
        }
    }
}
