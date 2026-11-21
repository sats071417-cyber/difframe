import SwiftUI

/// タイムライン：友達の投稿と、みんな（世界）の投稿を切り替えて見る。
struct TimelineScreen: View {
    let onCapture: () -> Void
    private enum Section: Hashable { case friends, everyone }
    @State private var section: Section = .friends
    @State private var showAdd = false
    @State private var showInvite = false
    @State private var offsets: [Int: CGFloat] = [:]

    /// 0（いちばん上）〜 1（少し下げた）：見出しを縮める度合い
    private var collapse: CGFloat {
        let y = offsets[section == .friends ? 0 : 1] ?? 0
        return min(1, max(0, -y / 70))
    }

    var body: some View {
        VStack(spacing: 10) {
            ScreenHeader(title: L("タイムライン")) {
                HStack(spacing: 10) {
                NotificationBell()
                Button {
                    showInvite = true
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Hi.tile))
                }
                .accessibilityLabel(L("友達を追加"))
                }
            }
            .scaleEffect(1 - 0.28 * collapse, anchor: .topLeading)
            .padding(.horizontal, 16)
            .animation(.easeOut(duration: 0.2), value: collapse)

            HiSegment(options: [(value: Section.friends, title: L("友達")), (value: Section.everyone, title: L("みんな"))],
                      selection: $section)
                .padding(.horizontal, 16)

            ZStack {
                FriendsView(onCapture: onCapture, embedded: true, showAdd: $showAdd)
                    .opacity(section == .friends ? 1 : 0)
                    .allowsHitTesting(section == .friends)
                WorldView(feedOnly: true)
                    .opacity(section == .everyone ? 1 : 0)
                    .allowsHitTesting(section == .everyone)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onPreferenceChange(ScrollOffsetKey.self) { offsets = $0 }
        .fullScreenCover(isPresented: $showInvite) { FriendInviteSheet() }
    }
}
