import SwiftUI

/// 友達の投稿フィード。自分が今日投稿するまでは見られない。
/// 友達は名前で追加する（端末の中に保存）。友達の投稿は、その人の地域のお題で表示する。
/// 注意：友達の投稿はまだサンプル。写真がないので、お題の文字で代わりに表示する。
struct FriendsView: View {
    let onCapture: () -> Void
    /// タイムラインの中に入れるときは true（見出しを出さない）
    var embedded = false
    /// 友達を追加する画面を出すか（外から開けるように、外で持つ）
    @Binding var showAdd: Bool
    @EnvironmentObject private var store: PostStore
    @AppStorage("friendList") private var friendList: String = MyProfile.defaultFriends
    @State private var commentTarget: CommentTarget? = nil
    @State private var newFriend = ""
    @State private var showScanner = false
    @State private var showContacts = false
    @State private var message: String? = nil

    // サンプル投稿の持ち主（名前）と地域（グループ番号）
    private struct Sample: Identifiable {
        let id: String
        let owner: String
        let city: String
        let caption: String
        let region: Int
        let trophies: [Trophy]
        let rank: Rank
    }

    private let samples: [Sample] = [
        Sample(id: "s1", owner: "Kanta", city: "Tokyo, Japan", caption: L("やあ"), region: 0, trophies: [.streak7, .under30, .firstPost], rank: .gold),
        Sample(id: "s2", owner: "motohiro", city: "Vancouver, Canada", caption: "Hi", region: 3, trophies: [.streak3, .under60, .firstPost], rank: .silver),
        Sample(id: "s3", owner: "Alex", city: "Paris, France", caption: "Salut", region: 2, trophies: [.posts10, .under60, .firstPost], rank: .platinum),
        Sample(id: "s4", owner: "Sam", city: "Nairobi, Kenya", caption: "Jambo", region: 2, trophies: [.under30, .firstPost], rank: .silver),
        Sample(id: "s5", owner: "Mina", city: "Seoul, South Korea", caption: "안녕", region: 0, trophies: [.streak3, .firstPost], rank: .bronze),
        Sample(id: "s6", owner: "Lucas", city: "Toronto, Canada", caption: "Hey", region: 3, trophies: [.firstPost], rank: .bronze),
    ]

    private var friends: [String] {
        friendList.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var todayKey: String { store.activeDayKey() }

    private var hasPostedToday: Bool {
        store.hasPosted(day: todayKey)
    }

    private var visible: [Sample] {
        samples.filter { friends.contains($0.owner) }
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
        .sheet(isPresented: $showAdd) {
            addSheet
        }
        .sheet(item: $commentTarget) { target in
            CommentSheet(postID: target.id, owner: target.owner, caption: target.caption,
                         image: target.image, prompt: target.prompt)
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
                // 自分の今日の投稿を、いちばん上に
                ForEach(myPosts, id: \.record.id) { item in
                    myCard(item.record, image: item.image)
                }
                if visible.isEmpty {
                    VStack(spacing: 12) {
                        Text(L("友達がいません")).foregroundStyle(.secondary)
                        Text(L("右上の人のマークから、友達を追加できます"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)
                } else {
                    ForEach(visible) { item in
                        card(item)
                    }
                }
            }
            .padding(.vertical)
        }
        .background(Color.black)
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
                        Text("@" + MyProfile.handle(myHandle) + (record.postedAt.map { " ・ " + $0.formatted(date: .omitted, time: .shortened) } ?? ""))
                        if let city = record.city {
                            Label(city, systemImage: "mappin").labelStyle(.titleAndIcon)
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
                .frame(height: 360)
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
            CommentLine(postID: record.id) { openComments(for: record, image: image) }
                .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }

    private func card(_ item: Sample) -> some View {
        let prompt = store.activePrompt() ?? "？" 
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(String(item.owner.prefix(1)))
                            .font(.system(.subheadline, design: .rounded).bold())
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(item.owner)
                            .font(.subheadline.weight(.black))
                            .lineLimit(1)
                            .fixedSize()
                        // 他の人からも見える、珍しいトロフィー
                        RankBadge(rank: item.rank)
                        TrophyBadges(trophies: item.trophies)
                    }
                    Text("@\(item.owner.lowercased()) ・ \(item.city)")
                        .font(.caption).foregroundStyle(.gray)
                }
                Spacer()
            }
            .padding(.horizontal)

            // 写真（サンプルのため、お題の文字を大きく表示）
            PromptArtView(prompt: prompt)
                .frame(height: 360)
                .overlay(alignment: .topLeading) {
                    Text(L(prompt))
                        .font(.title3.weight(.black))
                        .foregroundStyle(.white)
                        .padding(16)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .socialPhoto(postID: item.id) { openComments(for: item, prompt: prompt) }
                .padding(.horizontal)

            Text(item.caption)
                .font(.subheadline)
                .padding(.horizontal)

            // 友達の投稿：コメントはいつでもオン
            CommentLine(postID: item.id) { openComments(for: item, prompt: prompt) }
                .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }

    // 友達の追加・削除
    private var addSheet: some View {
        NavigationStack {
            List {
                Section(L("友達を追加")) {
                    Button {
                        showContacts = true
                    } label: {
                        Label(L("連絡先から招待"), systemImage: "person.crop.circle.badge.plus")
                    }
                    Button {
                        showScanner = true
                    } label: {
                        Label(L("相手のQRコードを読み取る"), systemImage: "qrcode.viewfinder")
                    }
                    HStack {
                        TextField(L("リンクまたはIDを貼る"), text: $newFriend)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button(L("追加")) {
                            addFriend(from: newFriend)
                        }
                        .disabled(newFriend.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let message {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section(L("自分のコード（相手に見せる）")) {
                    VStack(spacing: 12) {
                        if let qr = FriendCode.qrImage(for: FriendCode.shareURL) {
                            Image(uiImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 180, height: 180)
                        }
                        Text(FriendCode.myID)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        ShareLink(item: FriendCode.shareURL) {
                            Label(L("リンクを送る（LINEなど）"), systemImage: "square.and.arrow.up")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }

                Section(L("いまの友達（サンプルを含む）")) {
                    if friends.isEmpty {
                        Text(L("まだ友達がいません")).foregroundStyle(.secondary)
                    }
                    ForEach(friends, id: \.self) { name in
                        Text(name)
                    }
                    .onDelete(perform: removeFriends)
                }
            }
            .navigationTitle(L("友達を追加"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("閉じる")) { showAdd = false }
                }
            }
            .sheet(isPresented: $showContacts) {
                ContactsView()
            }
            .sheet(isPresented: $showScanner) {
                QRScannerView { value in
                    showScanner = false
                    addFriend(from: value)
                }
                .ignoresSafeArea()
            }
        }
    }

    private func openComments(for record: PromptRecord, image: UIImage) {
        commentTarget = CommentTarget(id: record.id, owner: L("あなた"), caption: record.caption, image: image)
    }

    private func openComments(for item: Sample, prompt: String) {
        commentTarget = CommentTarget(id: item.id, owner: item.owner, caption: item.caption, prompt: prompt)
    }

    private func addFriend(from text: String) {
        guard let id = FriendCode.parse(text) else {
            message = L("リンクかIDを読み取れませんでした")
            return
        }
        if id == FriendCode.myID {
            message = L("自分は追加できません")
            return
        }
        if friends.contains(id) {
            message = L("すでに友達です")
            return
        }
        friendList = (friends + [id]).joined(separator: ",")
        newFriend = ""
        message = LF("{id} を追加しました", ["id": id])
    }

    private func removeFriends(at offsets: IndexSet) {
        var list = friends
        list.remove(atOffsets: offsets)
        friendList = list.joined(separator: ",")
    }
}
