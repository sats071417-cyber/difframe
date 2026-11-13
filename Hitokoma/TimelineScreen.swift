import SwiftUI

/// タイムライン：友達の投稿と、みんな（世界）の投稿を切り替えて見る。
struct TimelineScreen: View {
    let onCapture: () -> Void
    private enum Section: Hashable { case friends, everyone }
    @State private var section: Section = .friends
    @State private var showAdd = false

    var body: some View {
        VStack(spacing: 10) {
            ScreenHeader(title: L("タイムライン")) {
                HStack(spacing: 10) {
                NotificationBell()
                Button {
                    showAdd = true
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
            .padding(.horizontal, 16)

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
    }
}
