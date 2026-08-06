import SwiftUI

// Screens 1-3. Handoff §6, §7 (running pose, slide 1 only).

private struct IntroTemplate<Extra: View>: View {
    let index: Int
    let loud: String
    let soft: String
    let body_: String
    let cta: String
    let onCTA: () -> Void
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        ScreenScaffold(top: 60) {
            StepDots(count: 3, index: index)
                .padding(.bottom, Space.section)

            Spacer(minLength: 0)

            extra()
                .frame(maxWidth: .infinity)
                .padding(.bottom, Space.section)

            Headline(loud, soft, size: 34)
            Text(body_)
                .font(Type.archivo(16))
                .foregroundStyle(Color.dim)
                .padding(.top, 14)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            PrimaryCTA(title: cta, action: onCTA)
                .padding(.bottom, Space.block)
        }
    }
}

struct IntroSlide1: View {
    @EnvironmentObject private var router: Router
    var body: some View {
        IntroTemplate(index: 0, loud: Copy.Intro.oneLoud, soft: Copy.Intro.oneSoft,
                     body_: Copy.Intro.oneBody, cta: Copy.Intro.oneCTA) {
            router.push(.introSlide2)
        } extra: {
            AvatarView(pose: .running, size: 180, speedLines: true)
        }
    }
}

struct IntroSlide2: View {
    @EnvironmentObject private var router: Router
    var body: some View {
        IntroTemplate(index: 1, loud: Copy.Intro.twoLoud, soft: Copy.Intro.twoSoft,
                     body_: Copy.Intro.twoBody, cta: Copy.Intro.twoCTA) {
            router.push(.introSlide3)
        } extra: {
            AvatarView(pose: .standing, size: 180, transforms: [.steelOutline])
        }
    }
}

struct IntroSlide3: View {
    @EnvironmentObject private var router: Router
    var body: some View {
        IntroTemplate(index: 2, loud: Copy.Intro.threeLoud, soft: Copy.Intro.threeSoft,
                     body_: Copy.Intro.threeBody, cta: Copy.Intro.threeCTA) {
            router.push(.signUp)
        } extra: {
            BarRow(values: [1, 1, 0, 1, 1, 1, 0], peak: 1, liveIndex: 6)
                .frame(height: 60)
                .padding(.horizontal, 20)
        }
    }
}

#Preview { IntroSlide1().environmentObject(Router()) }
