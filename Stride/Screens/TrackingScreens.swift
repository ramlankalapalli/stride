import SwiftUI

// Screens 17-18. Handoff §5, §6.

struct StepTrackingScreen: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var app: AppState
    @State private var manualEntry = ""

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

            VStack(alignment: .leading, spacing: 12) {
                if app.steps.isCombined {
                    HStack {
                        MonoLabel(Copy.Tracking.fromPhone(app.today.stepsFromPhone), size: 11)
                        Spacer()
                    }
                    HStack {
                        MonoLabel(Copy.Tracking.fromWatch(app.today.stepsFromWatch), size: 11)
                        Spacer()
                    }
                }
                if app.today.stepsManualAdd > 0 {
                    HStack {
                        MonoLabel(Copy.Tracking.manual(app.today.stepsManualAdd), size: 11, color: .dimmer)
                        Spacer()
                    }
                }
            }
            .padding(.bottom, Space.block)

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

            Spacer(minLength: Space.block)

            HStack(spacing: 12) {
                TextField("Add steps manually", text: $manualEntry)
                    .keyboardType(.numberPad)
                    .font(Type.mono(15))
                    .foregroundStyle(Color.ink)
                    .padding(.vertical, 14)
                Button("Add") {
                    if let n = Int(manualEntry) { app.addManualSteps(n) }
                    manualEntry = ""
                }
                .font(Type.archivo(13, .semibold))
                .foregroundStyle(Color.steel)
            }
            Hairline()
                .padding(.bottom, Space.block)
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
