import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var router = Router()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch router.phase {
            case .intro, .auth, .onboarding:
                NavigationStack(path: $router.path) {
                    entryScreen
                        .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
                }
            case .main:
                MainShell()
            }
        }
        .environmentObject(router)
        .tint(.steel)
        .preferredColorScheme(.dark)
        .background(Color.void.ignoresSafeArea())
        .fullScreenCover(item: $app.pendingMilestone) { event in
            MilestoneScreen(event: event)
                .environmentObject(app)
                .environmentObject(router)
        }
        .task {
            app.reconcileStreak()
            app.refreshWeekly()
            app.steps.startPhoneTracking()
            if app.isSignedIn { router.enterMain() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Make sure nothing sitting in the persistence throttle's
            // trailing-write window is lost if the app gets suspended.
            if newPhase == .background { app.flushPendingState() }
        }
    }

    @ViewBuilder private var entryScreen: some View {
        switch router.phase {
        case .auth: LogInScreen()
        default:    IntroSlide1()
        }
    }

}

/// Maps a `Route` to its screen. A free-standing view (not a RootView method)
/// so both the intro/auth NavigationStack and MainShell's per-tab
/// NavigationStack can push into it without instantiating RootView itself.
struct RouteDestination: View {
    let route: Route

    var body: some View {
        switch route {
        case .introSlide1:           IntroSlide1()
        case .introSlide2:           IntroSlide2()
        case .introSlide3:           IntroSlide3()
        case .signUp:                SignUpScreen()
        case .logIn:                 LogInScreen()
        case .forgotPassword:        ForgotPasswordScreen()
        case .forgotPasswordSent:    ForgotPasswordSentScreen()
        case .setNewPassword:        SetNewPasswordScreen()
        case .motionPermission:      MotionPermissionScreen()
        case .notificationPermission: NotificationPermissionScreen()
        case .onboardingQuestion(let i): OnboardingQuestionScreen(index: i)
        case .reviewAnswers:         ReviewAnswersScreen()
        case .avatarReveal:          AvatarRevealScreen()
        case .firstQuest:            FirstQuestScreen()
        case .home:                  HomeScreen()
        case .stepTracking:          StepTrackingScreen()
        case .connectWatch:          ConnectWatchScreen()
        case .record:                RecordScreen()
        case .weeklyChallenge:       WeeklyChallengeScreen()
        // .milestone is not a Route case — see the comment in Route.swift.
        // MilestoneScreen is still fully in use, just reached exclusively
        // via AppState.pendingMilestone's fullScreenCover below.
        case .leaderboard:           LeaderboardScreen()
        case .addFriends:            AddFriendsScreen()
        case .unlocks:               UnlocksScreen()
        case .progression:           ProgressionScreen()
        case .profile:               ProfileScreen()
        case .settings:              SettingsScreen()
        case .deleteConfirm:         DeleteConfirmScreen()
        #if DEBUG || STRIDE_INTERNAL_TESTING
        case .figureLab:             FigureLabScreen()
        case .avatar3DLab:           Avatar3DLabScreen()
        #endif
        }
    }
}

extension Milestones.Event: Identifiable {
    var id: String { "\(streak)-\(isPersonalBest)-\(isFirstEver)" }
}

// MARK: - Main shell

/// The four-tab shell. Handoff §2 — house, calendar-grid, bar-chart,
/// person-in-circle. Active ink, inactive dimmer.
struct MainShell: View {
    @EnvironmentObject private var router: Router

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.void.ignoresSafeArea()

            NavigationStack(path: $router.path) {
                Group {
                    switch router.tab {
                    case .today:  HomeScreen()
                    case .record: RecordScreen()
                    case .others: LeaderboardScreen()
                    case .you:    ProfileScreen()
                    }
                }
                .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
            }
            .padding(.bottom, 64)

            NavBar(selection: $router.tab)
        }
    }
}

struct NavBar: View {
    @Binding var selection: Router.Tab

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 0) {
                item(.today,  Copy.Nav.today,  NavIcon.house)
                item(.record, Copy.Nav.record, NavIcon.calendar)
                item(.others, Copy.Nav.others, NavIcon.bars)
                item(.you,    Copy.Nav.you,    NavIcon.person)
            }
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
        .background(Color.void)
    }

    private func item(_ tab: Router.Tab, _ label: String, _ icon: NavIcon) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 7) {
                icon.shape
                    .stroke(selection == tab ? Color.ink : Color.dimmer,
                            style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .frame(width: 22, height: 22)
                MonoLabel(label, size: 9, color: selection == tab ? .ink : .dimmer)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}

enum NavIcon {
    case house, calendar, bars, person

    var shape: AnyShape {
        switch self {
        case .house:    return AnyShape(HouseIcon())
        case .calendar: return AnyShape(CalendarIcon())
        case .bars:     return AnyShape(BarsIcon())
        case .person:   return AnyShape(PersonIcon())
        }
    }
}

private struct HouseIcon: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 1, y: r.midY - 1))
        p.addLine(to: CGPoint(x: r.midX, y: r.minY + 2))
        p.addLine(to: CGPoint(x: r.maxX - 1, y: r.midY - 1))
        p.move(to: CGPoint(x: r.minX + 3.5, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX + 3.5, y: r.maxY - 2))
        p.addLine(to: CGPoint(x: r.maxX - 3.5, y: r.maxY - 2))
        p.addLine(to: CGPoint(x: r.maxX - 3.5, y: r.midY))
        return p
    }
}

private struct CalendarIcon: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addRect(CGRect(x: r.minX + 2, y: r.minY + 3.5, width: r.width - 4, height: r.height - 5.5))
        p.move(to: CGPoint(x: r.minX + 2, y: r.minY + 8))
        p.addLine(to: CGPoint(x: r.maxX - 2, y: r.minY + 8))
        for x in [r.minX + 8, r.minX + 14] {
            p.move(to: CGPoint(x: x, y: r.minY + 8))
            p.addLine(to: CGPoint(x: x, y: r.maxY - 2))
        }
        p.move(to: CGPoint(x: r.minX + 2, y: r.minY + 13.5))
        p.addLine(to: CGPoint(x: r.maxX - 2, y: r.minY + 13.5))
        return p
    }
}

private struct BarsIcon: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let heights: [CGFloat] = [6, 12, 9, 16]
        for (i, h) in heights.enumerated() {
            let x = r.minX + 2.5 + CGFloat(i) * 5.5
            p.move(to: CGPoint(x: x, y: r.maxY - 2))
            p.addLine(to: CGPoint(x: x, y: r.maxY - 2 - h))
        }
        return p
    }
}

private struct PersonIcon: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: r.insetBy(dx: 1, dy: 1))
        p.addEllipse(in: CGRect(x: r.midX - 3, y: r.minY + 5, width: 6, height: 6))
        p.move(to: CGPoint(x: r.midX - 6, y: r.maxY - 3))
        p.addQuadCurve(to: CGPoint(x: r.midX + 6, y: r.maxY - 3),
                       control: CGPoint(x: r.midX, y: r.maxY - 10))
        return p
    }
}
