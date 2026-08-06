import SwiftUI
import CoreMotion
import UserNotifications

// Screens 9-10. Handoff §6.
// Motion explainer is built but skipped by default — see Flow.showsMotionExplainer.

private struct PermissionTemplate<Extra: View>: View {
    let status: String
    let loud: String
    let soft: String
    let facts: [String]
    let cta: String
    let ghost: String
    let onAllow: () -> Void
    let onSkip: () -> Void
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        ScreenScaffold(top: 40) {
            MonoLabel(status, size: 10, color: .steel)
                .padding(.bottom, Space.section)

            Headline(loud, soft, size: 32)
                .padding(.bottom, Space.block)

            extra()
                .padding(.bottom, Space.block)

            VStack(alignment: .leading, spacing: 18) {
                ForEach(facts, id: \.self) { FactLine(text: $0) }
            }

            Spacer(minLength: 0)

            PrimaryCTA(title: cta, action: onAllow)
                .padding(.bottom, 10)
            GhostButton(title: ghost, action: onSkip)
                .padding(.bottom, Space.block)
        }
    }
}

struct MotionPermissionScreen: View {
    @EnvironmentObject private var router: Router

    var body: some View {
        PermissionTemplate(status: Copy.MotionPermission.status,
                           loud: Copy.MotionPermission.loud, soft: Copy.MotionPermission.soft,
                           facts: Copy.MotionPermission.facts,
                           cta: Copy.MotionPermission.cta,
                           ghost: Copy.MotionPermission.ghost,
                           onAllow: advance, onSkip: advance) {
            AvatarView(pose: .standing, size: 140)
        }
    }

    private func advance() { router.push(.notificationPermission) }
}

struct NotificationPermissionScreen: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var app: AppState

    var body: some View {
        PermissionTemplate(status: Copy.NotificationPermission.status,
                           loud: Copy.NotificationPermission.loud, soft: Copy.NotificationPermission.soft,
                           facts: Copy.NotificationPermission.facts,
                           cta: Copy.NotificationPermission.cta,
                           ghost: Copy.NotificationPermission.ghost,
                           onAllow: {
                               Task {
                                   app.user.notificationsEnabled = await NudgeEngine.requestPermission()
                                   router.push(.onboardingQuestion(0))
                               }
                           },
                           onSkip: { router.push(.onboardingQuestion(0)) }) {
            BarRow(values: [3, 5, 2, 6, 4, 5, 1], peak: 6, liveIndex: 3)
                .frame(height: 70)
        }
    }
}
