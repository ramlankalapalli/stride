import SwiftUI

// Screens 14-15. Handoff §6.

struct AvatarRevealScreen: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var app: AppState

    var body: some View {
        ScreenScaffold(top: 40) {
            MonoLabel(Copy.Reveal.status, size: 10, color: .steel)
                .padding(.bottom, Space.section)

            Spacer(minLength: 0)
            VStack(spacing: 30) {
                AvatarView(pose: .standing, size: 220)
                Headline(Copy.Reveal.loud, Copy.Reveal.soft, size: 26)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)

            PrimaryCTA(title: Copy.Reveal.cta) {
                router.push(.firstQuest)
            }
            .padding(.bottom, Space.block)
        }
    }
}

struct FirstQuestScreen: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var app: AppState

    var body: some View {
        ScreenScaffold(top: 40) {
            MonoLabel(Copy.FirstQuest.status, size: 10, color: .steel)
                .padding(.bottom, Space.section)

            Headline(Copy.FirstQuest.loud, Copy.FirstQuest.soft, size: 30)
                .padding(.bottom, Space.section)

            VStack(alignment: .leading, spacing: 6) {
                Text("\(Copy.FirstQuest.target)")
                    .font(Type.figure(64))
                    .foregroundStyle(Color.steel)
                MonoLabel(Copy.FirstQuest.unit, size: 11)
            }

            Text(Copy.FirstQuest.note)
                .font(Type.archivo(14))
                .foregroundStyle(Color.dim)
                .padding(.top, Space.block)

            Spacer(minLength: Space.section)
            MonoLabel(Copy.FirstQuest.expiry, size: 10, color: .dimmer)
                .padding(.bottom, 14)

            PrimaryCTA(title: Copy.FirstQuest.cta) {
                app.firstQuestComplete = true
                router.enterMain()
            }
            .padding(.bottom, Space.block)
        }
    }
}
