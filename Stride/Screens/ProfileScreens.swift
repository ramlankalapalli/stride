import SwiftUI

// Screens 26-28. Handoff §6.

struct ProfileScreen: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var app: AppState

    var body: some View {
        ScreenScaffold(top: 24) {
            HStack {
                MonoLabel(Copy.Profile.status, size: 10, color: .steel)
                Spacer()
                Button { router.push(.settings) } label: {
                    MonoLabel("Settings", size: 10, color: .dim)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, Space.section)

            AvatarView(pose: .standing, size: 160, transforms: app.equipped)
                .frame(maxWidth: .infinity)
                .padding(.bottom, Space.block)

            Text(app.user.name.isEmpty ? "Unnamed file" : app.user.name)
                .font(Type.archivo(22, .bold))
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, alignment: .center)

            Text(Copy.Profile.subtitle(app.streak))
                .font(Type.archivo(14))
                .foregroundStyle(Color.dim)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 6)
                .padding(.bottom, Space.section)

            HStack(spacing: 0) {
                stat("\(app.user.points)", "Points")
                stat("\(app.streak.best)", "Best streak")
                stat(app.user.inviteCode, "Invite")
            }
            .padding(.bottom, Space.section)

            Button { router.push(.unlocks) } label: {
                HStack {
                    Text("Unlocks")
                        .font(Type.archivo(15, .medium))
                        .foregroundStyle(Color.ink)
                    Spacer()
                    MonoLabel("\(app.unlocks.filter(\.owned).count)/\(app.unlocks.count)", size: 10, color: .dimmer)
                }
                .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            Hairline()

            Button { router.push(.progression) } label: {
                HStack {
                    Text("Progression")
                        .font(Type.archivo(15, .medium))
                        .foregroundStyle(Color.ink)
                    Spacer()
                }
                .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            Hairline()

            Spacer(minLength: 0)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(Type.mono(18, medium: true))
                .foregroundStyle(Color.ink)
            MonoLabel(label, size: 9, color: .dim)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SettingsScreen: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var app: AppState

    var body: some View {
        ScreenScaffold(top: 20) {
            BackBar { router.pop() }
            Text(Copy.Settings.title)
                .font(Type.archivo(26, .bold))
                .foregroundStyle(Color.ink)
                .padding(.top, 16)
                .padding(.bottom, Space.section)

            ScrollView(showsIndicators: false) {
                group(Copy.Settings.trackingGroup) {
                    navRow(Copy.Settings.theNumber, "\(app.dailyGoal.formattedSteps)") {
                        router.push(.onboardingQuestion(4))
                    }
                    navRow(Copy.Settings.healthSync, app.steps.isCombined ? "On" : "Off") {
                        router.push(.connectWatch)
                    }
                    picker(Copy.Settings.measuredIn, app.user.unitPreference)
                }

                group(Copy.Settings.notificationsGroup) {
                    toggle(Copy.Settings.nagMe, $app.user.notificationsEnabled)
                    toggle(Copy.Settings.streakWarnings, $app.user.notificationsEnabled)
                    toggle(Copy.Settings.spokenNudges, $app.user.spokenNudgesEnabled)
                }

                group(Copy.Settings.leavingGroup) {
                    Button { app.signOut(); router.phase = .auth; router.popToRoot() } label: {
                        rowLabel(Copy.Settings.logOut, color: .ink)
                    }.buttonStyle(.plain)
                    Hairline()
                    Button { router.push(.deleteConfirm) } label: {
                        rowLabel(Copy.Settings.eraseAll, color: .danger)
                    }.buttonStyle(.plain)
                    Hairline()
                }

                MonoLabel(Copy.Settings.footer, size: 9, color: .dimmer)
                    .padding(.top, Space.block)
                    .padding(.bottom, Space.block)
            }
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MonoLabel(title, size: 10, color: .dim)
                .padding(.bottom, 10)
            content()
        }
        .padding(.bottom, Space.section)
    }

    private func rowLabel(_ text: String, color: Color) -> some View {
        HStack {
            Text(text).font(Type.archivo(15, .medium)).foregroundStyle(color)
            Spacer()
        }
        .padding(.vertical, 15)
    }

    private func navRow(_ label: String, _ value: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack {
                    Text(label).font(Type.archivo(15, .medium)).foregroundStyle(Color.ink)
                    Spacer()
                    MonoLabel(value, size: 10, color: .dim)
                }
                .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
            Hairline()
        }
    }

    private func toggle(_ label: String, _ binding: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label).font(Type.archivo(15, .medium)).foregroundStyle(Color.ink)
                Spacer()
                Toggle("", isOn: binding).labelsHidden().tint(.steel)
            }
            .padding(.vertical, 12)
            Hairline()
        }
    }

    private func picker(_ label: String, _ current: UnitPreference) -> some View {
        VStack(spacing: 0) {
            Menu {
                ForEach(UnitPreference.allCases) { u in
                    Button(u.label) { app.user.unitPreference = u }
                }
            } label: {
                HStack {
                    Text(label).font(Type.archivo(15, .medium)).foregroundStyle(Color.ink)
                    Spacer()
                    MonoLabel(current == .imperial ? "Imperial" : "Metric", size: 10, color: .dim)
                }
                .padding(.vertical, 15)
            }
            Hairline()
        }
    }
}

struct DeleteConfirmScreen: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var app: AppState
    @State private var confirmText = ""

    var body: some View {
        ScreenScaffold(top: 20) {
            BackBar { router.pop() }
            MonoLabel(Copy.DeleteAccount.status, size: 10, color: .danger)
                .padding(.top, 16)
                .padding(.bottom, Space.section)
            Headline(Copy.DeleteAccount.loud, Copy.DeleteAccount.soft, size: 30)
                .padding(.bottom, Space.block)

            Text(Copy.DeleteAccount.warning(days: app.streak.totalDaysTracked))
                .font(Type.archivo(14))
                .foregroundStyle(Color.dim)
                .padding(16)
                .overlay(Rectangle().stroke(Color.danger.opacity(0.4), lineWidth: 1))
                .padding(.bottom, Space.block)

            StrideField(label: Copy.DeleteAccount.field, value: $confirmText)

            Spacer(minLength: 0)
            MonoLabel(Copy.DeleteAccount.footer, size: 9, color: .dimmer)
                .padding(.bottom, 14)

            PrimaryCTA(title: Copy.DeleteAccount.cta,
                      destructive: true,
                      enabled: confirmText == Copy.DeleteAccount.confirmWord) {
                app.eraseEverything()
                router.phase = .intro
                router.popToRoot()
            }
            .padding(.bottom, 10)
            GhostButton(title: Copy.DeleteAccount.ghost) { router.pop() }
                .padding(.bottom, Space.block)
        }
    }
}
