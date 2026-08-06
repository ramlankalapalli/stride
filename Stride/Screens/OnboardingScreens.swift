import SwiftUI

// Screens 11-13. Handoff §3 — one component reused ×5, param-driven by index.

struct OnboardingQuestionScreen: View {
    let index: Int
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var app: AppState

    @State private var numberValue: Double = 0
    @State private var choiceIndex: Int = 1

    private var spec: OnboardingQuestionSpec { Flow.questions[index] }

    var body: some View {
        ScreenScaffold(top: 20) {
            BackBar { router.pop() }
            StepDots(count: Flow.questions.count, index: index)
                .padding(.top, 20)
                .padding(.bottom, Space.section)

            Headline(spec.question, size: 28)
            Text(spec.hint)
                .font(Type.archivo(14))
                .foregroundStyle(Color.dim)
                .padding(.top, 10)

            Spacer(minLength: Space.section)

            switch spec.kind {
            case .number(let range, let unit, let step):
                numberPicker(range: range, unit: unit, step: step)
            case .choice(let options):
                choicePicker(options: options)
            }

            Spacer(minLength: Space.section)

            PrimaryCTA(title: "Next", action: commitAndAdvance)
                .padding(.bottom, 10)
            if spec.skippable {
                GhostButton(title: Copy.Onboarding.skip) { advance() }
            }
            Spacer().frame(height: Space.block)
        }
        .onAppear(perform: preload)
    }

    @ViewBuilder
    private func numberPicker(range: ClosedRange<Int>, unit: String?, step: Int) -> some View {
        VStack(spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int(numberValue))")
                    .font(Type.figure(56))
                    .foregroundStyle(Color.ink)
                if let unit {
                    MonoLabel(unit, size: 13, color: .dim)
                }
            }
            Slider(value: $numberValue,
                  in: Double(range.lowerBound)...Double(range.upperBound),
                  step: Double(step))
                .tint(.steel)
            MonoLabel(Copy.Onboarding.heardBack("\(Int(numberValue))"), size: 9, color: .dimmer)
        }
    }

    @ViewBuilder
    private func choicePicker(options: [String]) -> some View {
        VStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                Button { choiceIndex = i } label: {
                    HStack {
                        Text(options[i])
                            .font(Type.archivo(17, .medium))
                            .foregroundStyle(choiceIndex == i ? Color.ink : Color.dim)
                        Spacer()
                        Circle()
                            .strokeBorder(choiceIndex == i ? Color.steel : Color.dimmer, lineWidth: 1.5)
                            .background(Circle().fill(choiceIndex == i ? Color.steel : .clear))
                            .frame(width: 16, height: 16)
                    }
                    .frame(height: 54)
                }
                .buttonStyle(.plain)
                Hairline()
            }
        }
    }

    private func preload() {
        switch spec.field {
        case .age:      numberValue = Double(app.user.age ?? 32)
        case .height:   numberValue = app.user.heightCm ?? 170
        case .weight:   numberValue = app.user.weightKg ?? 70
        case .goal:     numberValue = Double(app.dailyGoal)
        case .activity: choiceIndex = ActivityLevel.allCases.firstIndex(of: app.user.activityLevel) ?? 1
        }
    }

    private func commitAndAdvance() {
        switch spec.field {
        case .age:      app.user.age = Int(numberValue)
        case .height:   app.user.heightCm = numberValue
        case .weight:   app.user.weightKg = numberValue
        case .goal:     app.dailyGoal = Int(numberValue)
        case .activity: app.user.activityLevel = ActivityLevel.allCases[choiceIndex]
        }
        advance()
    }

    private func advance() { router.advanceQuestion(after: index) }
}

struct ReviewAnswersScreen: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var app: AppState

    var body: some View {
        ScreenScaffold(top: 20) {
            BackBar { router.pop() }
            MonoLabel(Copy.Review.status, size: 10, color: .steel)
                .padding(.top, 20)
                .padding(.bottom, Space.section)
            Headline(Copy.Review.loud, Copy.Review.soft, size: 30)
                .padding(.bottom, Space.section)

            VStack(spacing: 0) {
                row("Age", app.user.age.map { "\($0)" } ?? "—")
                row("Height", app.user.heightCm.map { "\(Int($0)) cm" } ?? "—")
                row("Weight", app.user.weightKg.map { "\(Int($0)) kg" } ?? "Skipped")
                row("Moves", app.user.activityLevel.label)
                row(Copy.goalLabel, "\(app.dailyGoal.formattedSteps) steps")
            }

            Spacer(minLength: 0)
            PrimaryCTA(title: Copy.Review.cta) {
                router.push(.avatarReveal)
            }
            .padding(.bottom, Space.block)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                MonoLabel(label, size: 10)
                Spacer()
                Text(value)
                    .font(Type.archivo(16, .medium))
                    .foregroundStyle(Color.ink)
            }
            .frame(height: 52)
            Hairline()
        }
    }
}
