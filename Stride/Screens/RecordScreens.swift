import SwiftUI

// Screens 19-21. Handoff §6.

struct RecordScreen: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var app: AppState

    var body: some View {
        ScreenScaffold(top: 24) {
            MonoLabel(Copy.Record.status, size: 10, color: .steel)
                .padding(.bottom, 14)

            // displayedStreak — same-day goal hit shows immediately here
            // too, not just on Home.
            Text("\(app.displayedStreak.current)")
                .font(Type.figure(72))
                .foregroundStyle(Color.ink)

            Text(Copy.Record.subtitle(streak: app.displayedStreak))
                .font(Type.archivo(17, .medium))
                .foregroundStyle(Color.dim)
                .padding(.top, 6)
                .padding(.bottom, Space.section)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 0) {
                stat(Copy.Record.tracked(app.streak))
                stat(Copy.Record.hit(app.streak))
                stat(Copy.Record.missed(app.streak))
            }
            .padding(.bottom, Space.section)

            Button { router.push(.weeklyChallenge) } label: {
                HStack {
                    MonoLabel(Copy.Weekly.status, size: 10)
                    Spacer()
                    MonoLabel("\(app.weekly.daysHit)/\(app.weekly.target)", size: 10, color: .steel)
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
                    MonoLabel("\(app.daysBetween) days", size: 10, color: .dimmer)
                }
                .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            Hairline()

            Spacer(minLength: 0)
        }
    }

    private func stat(_ text: String) -> some View {
        Text(text)
            .font(Type.mono(10, medium: true))
            .foregroundStyle(Color.dim)
            .tracking(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WeeklyChallengeScreen: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var app: AppState

    var body: some View {
        ScreenScaffold(top: 20) {
            BackBar { router.pop() }
            MonoLabel(Copy.Weekly.status, size: 10, color: .steel)
                .padding(.top, 20)
                .padding(.bottom, 10)

            Text(Copy.Weekly.subtitle(daysHit: app.weekly.daysHit, target: app.weekly.target))
                .font(Type.archivo(24, .semibold))
                .foregroundStyle(Color.ink)
                .padding(.bottom, Space.section)
                .fixedSize(horizontal: false, vertical: true)

            BarRow(values: app.weekly.dailyBars,
                  peak: max(app.dailyGoal, app.weekly.dailyBars.max() ?? app.dailyGoal),
                  liveIndex: app.weeklyIndexToday,
                  hitThreshold: app.dailyGoal,
                  height: 140)
                .padding(.bottom, 14)

            HStack {
                ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) {
                    MonoLabel($0, size: 9, color: .dimmer).frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, Space.section)

            MonoLabel(Copy.Weekly.footnote(today: app.todayTotal, short: app.stepsShortToday), size: 10)

            Spacer(minLength: 0)
        }
    }
}

struct MilestoneScreen: View {
    let event: Milestones.Event
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScreenScaffold(top: 60) {
            Spacer(minLength: 0)

            VStack(spacing: 30) {
                MonoLabel(Copy.Milestone.status, size: 10, color: .steel)
                AvatarView(pose: .raised, size: 200, transforms: app.equipped)
                Text(Copy.Milestone.line(for: event.streak, isPersonalBest: event.isPersonalBest))
                    .font(Type.archivo(22, .semibold))
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                MonoLabel(Copy.Milestone.points(Points.perGoalDay), size: 12, color: .steel)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            GhostButton(title: Copy.Milestone.dismiss, color: .ink) {
                app.pendingMilestone = nil
                dismiss()
            }
            .padding(.bottom, Space.block)
        }
    }
}
