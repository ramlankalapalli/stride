import SwiftUI

// Screen 16. Handoff §6.

struct HomeScreen: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var app: AppState

    private var stateLine: String {
        if app.goalMetToday { return Copy.Home.done }
        if app.todayTotal > 0 { return Copy.Home.inProgress }
        return Copy.Home.notStarted
    }

    var body: some View {
        ScreenScaffold(top: 24) {
            HStack {
                MonoLabel(Copy.Home.status, size: 10, color: .steel)
                Spacer()
                MonoLabel("Day \(String(format: "%02d", app.user.daysSinceDayZero))", size: 10)
            }
            .padding(.bottom, Space.section)

            Text(stateLine)
                .font(Type.archivo(22, .semibold))
                .foregroundStyle(app.goalMetToday ? Color.ink : Color.dim)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Space.block)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text("\(app.todayTotal.formattedSteps)")
                        .font(Type.figure(52))
                        .foregroundStyle(Color.ink)
                    MonoLabel("/ \(app.dailyGoal.formattedSteps)", size: 13, color: .dim)
                }
                ProgressTrack(fraction: app.progressToday, live: !app.goalMetToday)
                if !app.goalMetToday {
                    MonoLabel(Copy.Home.remaining(app.stepsShortToday), size: 10, color: .dim)
                }
            }
            .padding(.bottom, Space.section)

            Button { router.push(.stepTracking) } label: {
                HStack {
                    MonoLabel(app.steps.isCombined ? Copy.Tracking.combined : Copy.Tracking.phoneOnly,
                             size: 10, color: .steel)
                    Spacer()
                    MonoLabel("Detail", size: 10, color: .dimmer)
                }
                .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            Hairline()

            Button { router.push(.record) } label: {
                HStack {
                    MonoLabel("Current streak", size: 10)
                    Spacer()
                    Text("\(app.streak.current)")
                        .font(Type.figure(16, medium: true))
                        .foregroundStyle(Color.ink)
                }
                .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            Hairline()

            Spacer(minLength: 0)
        }
    }
}
