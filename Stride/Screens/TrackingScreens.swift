import SwiftUI

// Screens 17-18. Handoff §5, §6.
//
// Product decision (Phase 1.1 prep): Stride is an automatic-movement
// product — manual step entry has been removed from the experience
// entirely. Automatic sensor/Health sources are the sole source of truth
// for everything competitive or reward-bearing. See CreditedSteps.swift and
// AppState.swift for the model-layer side of this.

struct StepTrackingScreen: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var app: AppState

    var body: some View {
        ScreenScaffold(top: 20) {
            BackBar { router.pop() }

            MonoLabel(app.steps.isCombined ? Copy.Tracking.combined : Copy.Tracking.phoneOnly,
                     size: 10, color: .steel)
                .padding(.top, 16)
            Text(app.steps.isCombined ? " " : Copy.Tracking.counted)
                .font(Type.archivo(13))
                .foregroundStyle(Color.dim)
                .opacity(app.steps.isCombined ? 0 : 1)
                .padding(.top, 4)
                .padding(.bottom, Space.block)

            Text("\(app.todayTotal.formattedSteps)")
                .font(Type.figure(48))
                .foregroundStyle(Color.ink)
                .padding(.bottom, Space.block)

            BarRow(values: app.today.hourlyBreakdown, peak: app.today.hourlyBreakdown.max() ?? 1,
                  liveIndex: Calendar.current.component(.hour, from: Date()), height: 100)
                .padding(.bottom, Space.block)

            if app.steps.isCombined {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        MonoLabel(Copy.Tracking.fromPhone(app.today.stepsFromPhone), size: 11)
                        Spacer()
                    }
                    HStack {
                        MonoLabel(Copy.Tracking.fromWatch(app.today.stepsFromWatch), size: 11)
                        Spacer()
                    }
                }
                .padding(.bottom, Space.block)
            }

            if !app.steps.isCombined {
                Button { router.push(.connectWatch) } label: {
                    HStack {
                        Text(Copy.Tracking.watchPrompt)
                            .font(Type.archivo(14, .medium))
                            .foregroundStyle(Color.ink)
                        Spacer()
                    }
                    .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
                Hairline()
            }

            Spacer(minLength: 0)
        }
    }
}

struct ConnectWatchScreen: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var app: AppState
    @State private var error: String?

    var body: some View {
        ScreenScaffold(top: 20) {
            BackBar { router.pop() }
            Spacer().frame(height: 30)

            MonoLabel(Copy.ConnectWatch.status, size: 10, color: .steel)
                .padding(.bottom, Space.section)
            Headline(Copy.ConnectWatch.loud, Copy.ConnectWatch.soft, size: 30)
                .padding(.bottom, Space.block)
            Text(Copy.ConnectWatch.body)
                .font(Type.archivo(15))
                .foregroundStyle(Color.dim)

            if let error {
                MonoLabel(error, size: 10, color: .danger).padding(.top, 20)
            }

            Spacer(minLength: 0)
            PrimaryCTA(title: Copy.ConnectWatch.cta) {
                Task {
                    do {
                        try await app.steps.connectWatch()
                        app.user.watchConnected = true
                        router.pop()
                    } catch {
                        self.error = "Health wouldn't connect. Try again from Settings."
                    }
                }
            }
            .padding(.bottom, 10)
            GhostButton(title: Copy.ConnectWatch.ghost) { router.pop() }
                .padding(.bottom, Space.block)
        }
    }
}
