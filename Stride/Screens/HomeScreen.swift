import SwiftUI
import UIKit

// Screen 16. Handoff §6.

struct HomeScreen: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var app: AppState

    private var stateLine: String {
        if app.goalMetToday { return Copy.Home.done }
        if app.todayTotal > 0 { return Copy.Home.inProgress }
        return Copy.Home.notStarted
    }

    private var sensorLabel: String {
        if !app.steps.motionAuthorized && !app.steps.healthConnected { return "Waiting for motion access" }
        return app.steps.isCombined ? Copy.Tracking.combined : Copy.Tracking.phoneOnly
    }

    var body: some View {
        ScreenScaffold(top: 24) {
            HStack {
                MonoLabel(Copy.Home.status, size: 10, color: .steel)
                Spacer()
                MonoLabel("Day \(String(format: "%02d", app.user.daysSinceDayZero))", size: 10)
            }
            .padding(.bottom, Space.section)

            HStack(alignment: .center, spacing: 12) {
                Text(stateLine)
                    .font(Type.archivo(22, .semibold))
                    .foregroundStyle(app.goalMetToday ? Color.ink : Color.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // The one place on this screen the figure reacts to what's
                // actually happening right now, not a fixed portrait.
                LiveAvatar(activityState: app.steps.activityState,
                          intensity: app.steps.motionIntensity,
                          size: 76,
                          transforms: app.equipped,
                          breakthroughTick: app.goalBreakthroughTick)
            }
            .padding(.bottom, Space.block)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text("\(app.todayTotal.formattedSteps)")
                        .font(Type.figure(52))
                        .foregroundStyle(Color.ink)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: app.todayTotal)
                    MonoLabel("/ \(app.dailyGoal.formattedSteps)", size: 13, color: .dim)
                }
                ProgressTrack(fraction: app.progressToday, live: !app.goalMetToday,
                             pulseTrigger: app.goalBreakthroughTick)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: app.progressToday)
                if !app.goalMetToday {
                    MonoLabel(Copy.Home.remaining(app.stepsShortToday), size: 10, color: .dim)
                }
            }
            .padding(.bottom, Space.block)

            // Today's shape, not just its total — the same waveform the
            // detail screen shows, live as the sensor reports in.
            BarRow(values: app.today.hourlyBreakdown,
                  peak: app.today.hourlyBreakdown.max() ?? 1,
                  liveIndex: Calendar.current.component(.hour, from: Date()),
                  height: 44, spacing: 3)
                .padding(.bottom, Space.section)

            Button { router.push(.stepTracking) } label: {
                HStack {
                    Circle()
                        .fill(app.steps.motionAuthorized || app.steps.healthConnected ? Color.steel : Color.dimmer)
                        .frame(width: 6, height: 6)
                    MonoLabel(sensorLabel, size: 10, color: .steel)
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

            Button { router.push(.weeklyChallenge) } label: {
                HStack {
                    MonoLabel("This week", size: 10)
                    Spacer()
                    MonoLabel("\(app.weekly.daysHit)/\(app.weekly.target)", size: 10, color: .dim)
                }
                .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            Hairline()

            Button { router.push(.unlocks) } label: {
                HStack {
                    MonoLabel("Points banked", size: 10)
                    Spacer()
                    Text("\(app.user.points)")
                        .font(Type.figure(16, medium: true))
                        .foregroundStyle(Color.ink)
                }
                .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            Hairline()

            Spacer(minLength: 0)
        }
        .onAppear { app.refreshWeekly() }
        .onChange(of: app.goalBreakthroughTick) { _, _ in
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
    }
}
