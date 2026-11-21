import SwiftUI

/// 友達の投稿フィード。自分が今日投稿するまでは見られない。
/// 友達は名前で追加する（端末の中に保存）。友達の投稿は、その人の地域のお題で表示する。
struct FriendsView: View {
    let onCapture: () -> Void
    /// タイムラインの中に入れるときは true（見出しを出さない）
    var embedded = false
    /// 友達を追加する画面を出すか（外から開けるように、外で持つ）
    @Binding var showAdd: Bool
    @EnvironmentObject private var store: PostStore
    @ObservedObject private var cloud = CloudSync.shared
    @AppStorage("friendList") private var friendList: String = MyProfile.defaultFriends
    @State private var commentTarget: CommentTarget? = nil
    @State private var mapCity: String? = nil

    private var friends: [String] {
        friendList.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var todayKey: String { store.activeDayKey() }

    private var hasPostedToday: Bool {
        store.hasPosted(day: todayKey)
    }

    var body: some View {
        VStack(spacing: 10) {
            if !embedded {
            ScreenHeader(title: L("友達")) {
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
            .padding(.horizontal, 16)
            }

            Group {
                if hasPostedToday {
                    feed
                } else {
                    locked
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.ignoresSafeArea())
        .fullScreenCover(isPresented: $showAdd) {
            AddFriendSheet(isPresented: $showAdd)
        }
        .fullScreenCover(item: $commentTarget) { target in
            CommentSheet(postID: target.id, owner: target.owner, caption: target.caption,
                         image: target.image, front: target.front, prompt: target.prompt, cloudID: target.cloudID, ownRecordID: target.ownRecordID)
                .environmentObject(store)
        }
    }

    // 未投稿：友達の投稿は見えない
    private var locked: some View {
        ZStack {
            GlowBackground(palette: .forPrompt(store.activePrompt() ?? "?"), focus: .center)
            VStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.black.opacity(0.8))
                Text(L("今日のお題を投稿すると、\n友達の投稿が見られます"))
                    .font(.headline.weight(.black))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.black.opacity(0.8))
                Button(action: onCapture) {
                    Label(L("お題を撮る"), systemImage: "camera.fill")
                }
                .buttonStyle(NeonButtonStyle())
                .padding(.horizontal, 40)
                Button(L("友達を追加する")) { showAdd = true }
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(Color.black.opacity(0.75))
            }
            .padding(24)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // 投稿後：友達のフィード
    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: 28) {
                Color.clear.frame(height: 0).reportScroll(tag: 0)
                // 自分の今日の投稿を、いちばん上に
                if !myPosts.isEmpty { myStrip }
                if cloud.isOn {
                    // サーバーにつながっているとき：本物の友達の投稿だけを出す（サンプルは出さない）
                    if cloud.friendPosts.isEmpty {
                        VStack(spacing: 12) {
                            Text(cloud.friends.isEmpty ? L("友達がいません") : L("友達の今日の投稿は、まだありません"))
                                .foregroundStyle(.secondary)
                            Text(cloud.friends.isEmpty ? L("右上の人のマークから、友達を追加できます") : L("下に引っぱると、読み直します"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 20)
                    }
                    ForEach(cloud.friendPosts) { post in
                        CloudPostCard(post: post, asFriend: true) { commentTarget = $0 }
                            .padding(.horizontal)
                            .riseIn()
                    }
                } else {
                    VStack(spacing: 12) {
                        Text(L("友達がいません")).foregroundStyle(.secondary)
                        Text(L("右上の人のマークから、友達を追加できます"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)
                }
            }
            .padding(.vertical)
        }
        .coordinateSpace(name: "feedScroll")
        .refreshable { await cloud.refresh(force: true) }
        .background(Color.black)
        .fullScreenCover(item: Binding(get: { mapCity.map { MapCityTarget(id: $0) } }, set: { mapCity = $0?.id })) {
            LocationMapSheet(city: $0.id, latitude: nil, longitude: nil, photo: nil)
        }
    }

    @AppStorage("myName") private var myName: String = "あなた"
    @AppStorage("myHandle") private var myHandle: String = ""

    /// 今日の自分の投稿（新しい順）
    private var myPosts: [(record: PromptRecord, image: UIImage)] {
        store.records(day: todayKey)
            .filter { $0.postedPhotoFile != nil && $0.isForFriends }
            .sorted { ($0.postedAt ?? .distantPast) > ($1.postedAt ?? .distantPast) }
            .compactMap { r in r.postedPhotoFile.flatMap { store.image(for: $0) }.map { (r, $0) } }
    }

    /// 自分の今日の投稿は、フィードの上に小さく一列にまとめる（押すと、写真とコメントを開く）
    private var myStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(myPosts, id: \.record.id) { item in
                    Button {
                        openComments(for: item.record, image: item.image)
                    } label: {
                        VStack(spacing: 6) {
                            Image(uiImage: item.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 66, height: 66)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Hi.neon, lineWidth: 2.5))
                            Text(L("自分")).font(.caption.weight(.black)).foregroundStyle(.white)
                            if let at = item.record.postedAt {
                                Text(at.appFormatted(date: .omitted, time: .shortened))
                                    .font(.caption2).foregroundStyle(Hi.dim)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .blocksTabSwipe(.friends, id: "row")
    }

    /// 自分の投稿のカード（友達の投稿と同じ形）
    private func myCard(_ record: PromptRecord, image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Group {
                    if let avatar = Avatar.load() {
                        Image(uiImage: avatar).resizable().scaledToFill()
                    } else {
                        Hi.neon.overlay(Text(String(myName.prefix(1))).font(.system(.subheadline, design: .rounded).bold()).foregroundStyle(Hi.onNeon))
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(myName == "あなた" ? L("あなた") : myName).font(.subheadline.weight(.black)).lineLimit(1)
                        Text(L("自分")).font(.caption2.weight(.black))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Hi.neon)).foregroundStyle(Hi.onNeon)
                    }
                    HStack(spacing: 4) {
                        Text("@" + MyProfile.handle(myHandle) + (record.postedAt.map { " ・ " + $0.appFormatted(date: .omitted, time: .shortened) } ?? ""))
                        if let city = record.city {
                            Button { mapCity = city } label: {
                                Label(city, systemImage: "mappin").labelStyle(.titleAndIcon).foregroundStyle(Hi.neon)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .font(.caption).foregroundStyle(.gray).lineLimit(1)
                }
                Spacer()
                if let elapsed = record.elapsed {
                    DotText(text: TimeFormat.string(elapsed), pitch: 3, color: Hi.neon)
                }
                DeletePostMenu(recordID: record.id)
            }
            .padding(.horizontal)

            DualPhotoView(main: image, inset: record.frontPhotoFile.flatMap { store.image(for: $0) })
                .aspectRatio(PhotoShape.ratio, contentMode: .fit)
                .overlay(alignment: .bottomLeading) {
                    Text(L(record.prompt)).font(.title3.weight(.black)).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 4).padding(16)
                        .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                // 自分の投稿：友達からのコメントは、いつでも受け付ける（自分にはリアクションしない）
                .socialPhoto(postID: record.id, canReact: false) { openComments(for: record, image: image) }
                .padding(.horizontal)

            if let caption = record.caption, !caption.isEmpty {
                Text(caption).font(.subheadline).padding(.horizontal)
            }
            CommentLine(postID: record.id, cloudID: cloud.cloudID(for: record.id)) { openComments(for: record, image: image) }
                .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }

    private func openComments(for record: PromptRecord, image: UIImage) {
        commentTarget = CommentTarget(id: record.id, owner: L("あなた"), caption: record.caption, image: image,
                                      cloudID: cloud.cloudID(for: record.id), ownRecordID: record.id)
    }
}
