import SwiftUI

// Screens 24-25. Handoff §6, §7.

struct UnlocksScreen: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var app: AppState

    private var purchasable: [Unlock] { app.unlocks.filter(\.isPurchasable) }

    var body: some View {
        ScreenScaffold(top: 20) {
            BackBar { router.pop() }
            MonoLabel(Copy.Unlocks.status, size: 10, color: .steel)
                .padding(.top, 16)
            Text("\(app.user.points)")
                .font(Type.figure(48))
                .foregroundStyle(Color.ink)
                .padding(.top, 6)
            MonoLabel(Copy.Unlocks.note, size: 10, color: .dim)
                .padding(.bottom, Space.section)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(purchasable) { unlock in
                        row(unlock)
                        Hairline()
                    }
                }

                if let thirty = app.unlocks.first(where: { !$0.isPurchasable }) {
                    MonoLabel(Copy.Unlocks.later, size: 10, color: .dimmer)
                        .padding(.top, Space.block)
                        .padding(.bottom, 10)
                    row(thirty)
                    Hairline()
                }
            }
        }
    }

    private func row(_ unlock: Unlock) -> some View {
        HStack(spacing: 16) {
            AvatarView(pose: .standing, size: 44, transforms: [unlock.transform])
            VStack(alignment: .leading, spacing: 4) {
                Text(unlock.name)
                    .font(Type.archivo(15, .medium))
                    .foregroundStyle(unlock.owned ? Color.ink : Color.dim)
                MonoLabel(
                    unlock.owned ? Copy.Unlocks.owned
                        : unlock.isPurchasable ? Copy.Unlocks.cost(unlock.cost)
                        : Copy.Unlocks.lockedAt(days: 30),
                    size: 9, color: .dimmer)
            }
            Spacer()
            if unlock.owned {
                Button {
                    app.toggleEquip(unlock)
                } label: {
                    MonoLabel(app.equipped.contains(unlock.transform) ? Copy.Unlocks.equipped : Copy.Unlocks.equip,
                             size: 9, color: app.equipped.contains(unlock.transform) ? .steel : .dim)
                }
                .buttonStyle(.plain)
            } else if unlock.isPurchasable {
                Button {
                    app.purchase(unlock)
                } label: {
                    MonoLabel("Buy", size: 9, color: app.user.points >= unlock.cost ? .steel : .dimmer)
                }
                .buttonStyle(.plain)
                .disabled(app.user.points < unlock.cost)
            }
        }
        .padding(.vertical, 14)
    }
}

struct ProgressionScreen: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var app: AppState

    var body: some View {
        ScreenScaffold(top: 20) {
            BackBar { router.pop() }
            MonoLabel(Copy.Progression.header(app.daysBetween), size: 10, color: .steel)
                .padding(.top, 16)
                .padding(.bottom, Space.section)

            HStack(spacing: 0) {
                side(pose: .slumped, label: Copy.Progression.before, steps: app.dayOneRecord?.total ?? 0)
                Rectangle().fill(Color.line).frame(width: Space.hairline)
                side(pose: .standing, label: Copy.Progression.after, steps: app.todayTotal, transforms: app.equipped)
            }
            .frame(height: 260)
            .padding(.bottom, Space.section)

            Headline(Copy.Progression.loud, Copy.Progression.soft, size: 26)

            Spacer(minLength: Space.section)

            PrimaryCTA(title: Copy.Progression.cta) {
                // Share sheet target — wired at build time.
            }
            .padding(.bottom, 14)
            MonoLabel(Copy.Progression.footer, size: 9, color: .dimmer)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, Space.block)
        }
    }

    private func side(pose: AvatarPose, label: String, steps: Int, transforms: Set<UnlockTransform> = []) -> some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            AvatarView(pose: pose, size: 130, transforms: transforms)
            MonoLabel(label, size: 10, color: .dim)
            MonoLabel(steps.formattedSteps, size: 10, color: .dimmer)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}
