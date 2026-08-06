import SwiftUI

// Screens 22-23. Handoff §6.

struct LeaderboardScreen: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var app: AppState

    var body: some View {
        ScreenScaffold(top: 24) {
            HStack {
                MonoLabel(Copy.Leaderboard.status, size: 10, color: .steel)
                Spacer()
                Button { router.push(.addFriends) } label: {
                    MonoLabel("Add", size: 10, color: .dim)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 10)

            Text(Copy.Leaderboard.subtitle(rank: app.myRank, of: app.leaderboard.count))
                .font(Type.archivo(22, .semibold))
                .foregroundStyle(Color.ink)
                .padding(.bottom, 8)

            if app.stepsBehindNext > 0 {
                MonoLabel(Copy.Leaderboard.footnote(short: app.stepsBehindNext, days: 3), size: 10, color: .dim)
                    .padding(.bottom, Space.section)
            } else {
                Spacer().frame(height: Space.section)
            }

            VStack(spacing: 0) {
                ForEach(Array(app.leaderboard.enumerated()), id: \.element.id) { i, friend in
                    HStack(spacing: 14) {
                        MonoLabel(String(format: "%02d", i + 1), size: 11, color: friend.isMe ? .steel : .dimmer)
                            .frame(width: 24, alignment: .leading)
                        Text(friend.name)
                            .font(Type.archivo(15, friend.isMe ? .semibold : .regular))
                            .foregroundStyle(friend.isMe ? Color.ink : Color.dim)
                        Spacer()
                        Text(friend.todaySteps.formattedSteps)
                            .font(Type.mono(13, medium: friend.isMe))
                            .foregroundStyle(friend.isMe ? Color.ink : Color.dim)
                    }
                    .padding(.vertical, 14)
                    Hairline()
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct AddFriendsScreen: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var app: AppState
    @State private var code = ""

    var body: some View {
        ScreenScaffold(top: 20) {
            BackBar { router.pop() }
            Spacer().frame(height: 24)

            MonoLabel(Copy.AddFriends.status, size: 10, color: .steel)
                .padding(.bottom, Space.section)
            Headline(Copy.AddFriends.loud, Copy.AddFriends.soft, size: 30)
                .padding(.bottom, Space.section)

            StrideField(label: Copy.AddFriends.field, value: $code)
                .padding(.bottom, Space.block)

            if app.friends.isEmpty {
                MonoLabel(Copy.AddFriends.empty, size: 11, color: .dimmer)
            }

            Spacer(minLength: 0)

            HStack {
                MonoLabel("Your code", size: 10, color: .dim)
                Spacer()
                MonoLabel(app.user.inviteCode, size: 12, color: .ink)
            }
            .padding(.bottom, Space.block)

            PrimaryCTA(title: Copy.AddFriends.cta) {
                // Share sheet target — wired at build time.
            }
            .padding(.bottom, Space.block)
        }
    }
}
