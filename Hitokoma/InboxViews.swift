import SwiftUI
import PhotosUI

// MARK: - 見出しの右上のボタン

/// 見出しの右上：通知（ベル）と DM（紙飛行機）。未読の数を黄緑のバッジで出す（サーバーを使うときだけ）
struct NotificationBell: View {
    @ObservedObject private var cloud = CloudSync.shared
    @State private var show = false
    @State private var showDM = false

    var body: some View {
        if cloud.isOn {
            HStack(spacing: 8) {
                badgeButton(symbol: "bell.fill", count: cloud.unreadCount, label: L("通知")) { show = true }
                badgeButton(symbol: "paperplane", count: cloud.unreadMessages, label: L("DM")) { showDM = true }
            }
            .sheet(isPresented: $show) { InboxSheet() }
            .sheet(isPresented: $showDM) { DMListSheet() }
        }
    }

    private func badgeButton(symbol: String, count: Int, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Hi.tile))
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text(count > 9 ? "9+" : "\(count)")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(Hi.onNeon)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 19, minHeight: 19)
                            .background(Capsule().fill(Hi.neon))
                            .overlay(Capsule().stroke(Color.black, lineWidth: 2))
                            .offset(x: 3, y: -3)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? "\(label) \(count)" : label)
    }
}

// MARK: - 共通の部品

/// シートの上の見出し（ほかの画面の見出しと同じ太さ）と、丸い閉じるボタン
private struct SheetHeader<Trailing: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            trailing
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Hi.tile))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("閉じる"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 6)
    }
}

/// 人のアイコン：名前から決まる光る色に、頭文字（お題カードと同じ色の作り）
struct GlowAvatar: View {
    let name: String
    var size: CGFloat = 46

    var body: some View {
        GlowBackground(palette: .forPrompt(name), focus: UnitPoint(x: 0.5, y: 0.35))
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 3)
            )
    }
}

/// 通知の種類ごとの印（アイコンの右下に出す）
private func noticeBadge(_ type: String) -> (symbol: String, color: Color) {
    switch type {
    case "like": return ("heart.fill", Color(red: 1.0, green: 0.36, blue: 0.56))
    case "comment": return ("bubble.left.fill", Hi.neon)
    case "friendRequest": return ("person.fill.badge.plus", Hi.neon)
    case "friendAccepted": return ("person.2.fill", Hi.neon)
    case "friendPost": return ("camera.fill", Hi.neon)
    default: return ("paperplane.fill", Hi.neon)
    }
}

/// 「3分前」「2時間前」のような、短い経過時間（アプリの言語で）
func agoText(_ date: Date) -> String {
    let f = RelativeDateTimeFormatter()
    f.locale = Locale(identifier: AppLanguage.current.rawValue)
    f.unitsStyle = .short
    return f.localizedString(for: date, relativeTo: Date())
}

/// 今日・昨日・これまで、に分ける
private enum DayGroup: Int, CaseIterable {
    case today, yesterday, earlier
    var title: String {
        switch self {
        case .today: return L("今日")
        case .yesterday: return L("昨日")
        case .earlier: return L("これまで")
        }
    }
    static func of(_ date: Date) -> DayGroup {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return .today }
        if cal.isDateInYesterday(date) { return .yesterday }
        return .earlier
    }
}

/// 中身がないときの案内（暗いタイルに、光る丸とひとこと）
private struct EmptyNote: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                GlowBackground(palette: .forPrompt(title), focus: .center)
                    .frame(width: 84, height: 84)
                    .clipShape(Circle())
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(title).font(.headline.weight(.black))
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Hi.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
        .background(Hi.tile)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

// MARK: - 通知

/// 通知の分け方：コメント・いいね ／ 友達（リクエスト・友達になった・友達の投稿）
enum InboxTab: Hashable { case social, friends }

/// 通知の一覧。開いているあいだは未読を黄緑の点で示し、閉じると既読にする
struct InboxSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var cloud = CloudSync.shared
    @State private var profile: CodeTarget? = nil
    @State private var post: CommentTarget? = nil
    @State private var tab: InboxTab = .social

    private static let socialTypes = ["comment", "like"]
    private static let friendTypes = ["friendAccepted", "friendPost"]

    private func unread(_ types: [String]) -> Int {
        cloud.notices.filter { types.contains($0.type) && !$0.read && !NotifySettings.isMuted($0.type) }.count
    }

    /// 来ている友達リクエスト（友達タブの一番上に、まとめて出す。ミュート中は出さない）
    private var requests: [CloudNotice] {
        cloud.notices.filter { $0.type == "friendRequest" && !NotifySettings.isMuted($0.type) }
    }

    /// いま選んでいる分け方の通知（リクエストとメッセージは除く。ミュート中の種類は出さない）
    private var shown: [CloudNotice] {
        let types = tab == .social ? Self.socialTypes : Self.friendTypes
        return cloud.notices.filter { types.contains($0.type) && !NotifySettings.isMuted($0.type) }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: L("通知"), onClose: { dismiss() }) { EmptyView() }
            HiSegment(options: [(value: InboxTab.social, title: segmentTitle(L("コメント・いいね"), unread(Self.socialTypes))),
                                (value: InboxTab.friends, title: segmentTitle(L("友達"), unread(Self.friendTypes + ["friendRequest"])))],
                      selection: $tab)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if tab == .friends && !requests.isEmpty {
                        sectionTitle(L("友達リクエスト"), count: requests.count)
                        ForEach(requests) { requestCard($0) }
                    }
                    if shown.isEmpty && (tab == .social || requests.isEmpty) {
                        EmptyNote(symbol: tab == .social ? "heart.fill" : "person.2.fill",
                                  title: L("通知はありません"),
                                  detail: tab == .social ? L("コメントやいいねが届くと、ここに出ます。")
                                                         : L("友達リクエストや、友達の投稿が届くと、ここに出ます。"))
                            .padding(.top, 8)
                    }
                    ForEach(DayGroup.allCases, id: \.self) { group in
                        let items = shown.filter { DayGroup.of($0.date) == group }
                        if !items.isEmpty {
                            sectionTitle(group.title)
                            ForEach(items) { noticeCard($0) }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .refreshable { await cloud.refresh(force: true) }
        }
        .background(Color.black.ignoresSafeArea())
        .task { await cloud.refresh(force: true) }
        .onDisappear { Task { await cloud.markAllRead() } }
        .sheet(item: $profile) { PersonProfileSheet(code: $0.id) }
        .sheet(item: $post) { target in
            CommentSheet(postID: target.id, owner: target.owner, caption: target.caption, image: target.image,
                         prompt: target.prompt, cloudID: target.cloudID, ownRecordID: target.ownRecordID,
                         focusID: target.focusID)
                .environmentObject(PostStore.shared)
        }
        .presentationDetents([.large])
        .presentationBackground(.black)
        .preferredColorScheme(.dark)
    }

    /// 通知を開く：コメント・いいねは、その投稿のコメント画面へ（返信もそこでできる）。ほかは相手のプロフィールへ
    private func open(_ n: CloudNotice) {
        if ["comment", "like"].contains(n.type), let postID = n.postID, !postID.isEmpty {
            let owner = postID.split(separator: "_").first.map(String.init) ?? ""
            let recordID = postID.split(separator: "_", maxSplits: 1).last.map(String.init) ?? ""
            if owner == cloud.uid, let record = PostStore.shared.records.first(where: { $0.id == recordID }) {
                // 自分の投稿：写真・一言も、そのまま見られる
                let image = record.postedPhotoFile.flatMap { PostStore.shared.image(for: $0) }
                post = CommentTarget(id: recordID, owner: L("あなた"), caption: record.caption, image: image,
                                     cloudID: postID, ownRecordID: recordID)
            } else {
                // コメントの通知は、そのコメントまで開く
                let focus = n.id.hasPrefix("comment_") ? String(n.id.dropFirst("comment_".count)) : nil
                post = CommentTarget(id: postID, owner: name(n), cloudID: postID, focusID: focus)
            }
            return
        }
        if !n.fromCode.isEmpty { profile = CodeTarget(id: n.fromCode) }
    }

    private func segmentTitle(_ title: String, _ count: Int) -> String {
        count > 0 ? "\(title) \(count)" : title
    }

    private func sectionTitle(_ title: String, count: Int? = nil) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.subheadline.weight(.black))
            if let count {
                Text("\(count)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Hi.onNeon)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Hi.neon))
            }
        }
        .foregroundStyle(.white)
        .padding(.top, 10)
    }

    private func name(_ n: CloudNotice) -> String { n.fromName.isEmpty ? n.fromCode : n.fromName }

    private func title(_ n: CloudNotice) -> String {
        switch n.type {
        case "friendRequest": return LF("{n} さんから友達リクエストが届きました", ["n": name(n)])
        case "friendAccepted": return LF("{n} さんと友達になりました", ["n": name(n)])
        case "comment": return LF("{n} さんがコメントしました", ["n": name(n)])
        case "friendPost": return LF("{n} さんが投稿しました", ["n": name(n)])
        case "like": return LF("{n} さんがリアクションしました", ["n": name(n)])
        default: return LF("{n} さんからメッセージ", ["n": name(n)])
        }
    }

    /// アイコン（右下に種類の印）
    private func avatar(_ n: CloudNotice) -> some View {
        let badge = noticeBadge(n.type)
        return PersonAvatar(uid: n.fromUID, name: name(n))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: badge.symbol)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(badge.color == Hi.neon ? Hi.onNeon : .white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(badge.color))
                    .overlay(Circle().stroke(Hi.tile, lineWidth: 2.5))
                    .offset(x: 4, y: 4)
            }
    }

    /// 通知1件：暗いタイルのカード。未読は左に黄緑の点
    private func noticeCard(_ n: CloudNotice) -> some View {
        Button {
            open(n)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                avatar(n)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title(n))
                        .font(.subheadline.weight(n.read ? .semibold : .black))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                    detail(n)
                    Text(agoText(n.date))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Hi.dim)
                }
                Spacer(minLength: 0)
                trailing(n)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Hi.tile)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .topLeading) {
                if !n.read {
                    Circle().fill(Hi.neon).frame(width: 9, height: 9).offset(x: 6, y: 6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// カードの中の、ひとこと（コメントの文、投稿のお題）
    @ViewBuilder
    private func detail(_ n: CloudNotice) -> some View {
        switch n.type {
        case "comment" where !n.text.isEmpty:
            Text("「\(n.text)」")
                .font(.subheadline)
                .foregroundStyle(Hi.dim)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        case "friendPost" where !n.text.isEmpty:
            Text(L(n.text))
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(GlowBackground(palette: .forPrompt(n.text), focus: .center).clipShape(Capsule()))
        default:
            EmptyView()
        }
    }

    /// カードの右：いいねは絵文字を大きく、友達の投稿は「見る」の印
    @ViewBuilder
    private func trailing(_ n: CloudNotice) -> some View {
        switch n.type {
        case "like" where !n.text.isEmpty:
            Text(n.text).font(.system(size: 30))
        case "friendPost":
            Image(systemName: "chevron.right").font(.caption.weight(.black)).foregroundStyle(Hi.dim)
        default:
            EmptyView()
        }
    }

    /// 友達リクエスト：名前と、承認・削除の大きなボタン
    private func requestCard(_ n: CloudNotice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                if !n.fromCode.isEmpty { profile = CodeTarget(id: n.fromCode) }
            } label: {
                HStack(spacing: 12) {
                    avatar(n)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name(n)).font(.headline.weight(.black)).foregroundStyle(.white)
                        Text("@\(n.fromCode)・" + agoText(n.date))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Hi.dim)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: 10) {
                Button { Task { try? await cloud.accept(n) } } label: {
                    Label(L("承認"), systemImage: "checkmark")
                        .font(.subheadline.weight(.black))
                        .frame(maxWidth: .infinity).frame(height: 42)
                        .background(Capsule().fill(Hi.neon))
                        .foregroundStyle(Hi.onNeon)
                }
                Button { Task { await cloud.decline(n) } } label: {
                    Text(L("削除"))
                        .font(.subheadline.weight(.black))
                        .frame(maxWidth: .infinity).frame(height: 42)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Hi.tile)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Hi.neon.opacity(0.55), lineWidth: 1.5)
        )
    }
}

// MARK: - DM

/// DM の一覧：友達ごとの会話。未読の数を出し、新しい会話が上に来る。入力中も出す
struct DMListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var cloud = CloudSync.shared
    @State private var chat: CloudFriend? = nil

    /// その友達から届いた、いちばん新しいメッセージの知らせ
    private func last(_ friend: CloudFriend) -> CloudNotice? {
        cloud.notices.first { $0.id == "msg_\(friend.uid)" }
    }

    /// 自分がまだ読んでいない、相手からのメッセージの数
    private func unread(_ friend: CloudFriend) -> Int {
        if NotifySettings.isMuted("message") { return 0 }
        let readAt = cloud.myReadAt[friend.uid] ?? .distantPast
        return (cloud.messages[friend.uid] ?? []).filter { $0.from == friend.uid && $0.date > readAt }.count
    }

    private func typing(_ friend: CloudFriend) -> Bool {
        cloud.friendTypingAt[friend.uid].map { Date().timeIntervalSince($0) < 4 } ?? false
    }

    private var ordered: [CloudFriend] {
        cloud.friends.sorted { a, b in
            let ua = unread(a) > 0, ub = unread(b) > 0
            if ua != ub { return ua }
            return (last(a)?.date ?? .distantPast) > (last(b)?.date ?? .distantPast)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: L("DM"), onClose: { dismiss() }) { EmptyView() }
            ScrollView {
                LazyVStack(spacing: 10) {
                    if cloud.friends.isEmpty {
                        EmptyNote(symbol: "paperplane.fill",
                                  title: L("まだ友達がいません"),
                                  detail: L("友達になると、ここからメッセージを送れます。"))
                            .padding(.top, 8)
                    }
                    ForEach(ordered) { friend in row(friend) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .refreshable { await reloadAll() }
        }
        .background(Color.black.ignoresSafeArea())
        .task {
            // 開いているあいだ、友達ごとの会話を数秒ごとに読み直す（未読と入力中）
            while !Task.isCancelled {
                await reloadAll()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
        .sheet(item: $chat) { ChatView(friend: $0) }
        .presentationDetents([.large])
        .presentationBackground(.black)
        .preferredColorScheme(.dark)
    }

    private func reloadAll() async {
        await cloud.refresh(force: true)
        for friend in cloud.friends {
            await cloud.loadMessages(with: friend.uid)
            await cloud.refreshReadAt(friend.uid)
        }
    }

    private func row(_ friend: CloudFriend) -> some View {
        let name = friend.name.isEmpty ? friend.code : friend.name
        let note = last(friend)
        let count = unread(friend)
        let isTyping = typing(friend)
        return Button { chat = friend } label: {
            HStack(spacing: 12) {
                PersonAvatar(uid: friend.uid, name: name, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if isTyping {
                        Text(L("入力中…"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Hi.neon)
                    } else if let note {
                        Text(note.text)
                            .font(.subheadline.weight(count > 0 ? .bold : .regular))
                            .foregroundStyle(count > 0 ? .white : Hi.dim)
                            .lineLimit(1)
                    } else {
                        Text(L("メッセージを送る…"))
                            .font(.subheadline)
                            .foregroundStyle(Hi.dim)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    if let note {
                        Text(agoText(note.date))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Hi.dim)
                    }
                    if count > 0 {
                        Text(count > 9 ? "9+" : "\(count)")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(Hi.onNeon)
                            .padding(.horizontal, 7)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(Capsule().fill(Hi.neon))
                    } else {
                        Image(systemName: "paperplane")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Hi.dim)
                    }
                }
            }
            .padding(12)
            .background(Hi.tile)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 友達とのメッセージ（DM）：文字・写真・ボイス、絵文字のリアクション、既読
struct ChatView: View {
    let friend: CloudFriend
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var cloud = CloudSync.shared
    @StateObject private var recorder = VoiceRecorder()
    @State private var text = ""
    @State private var picked: PhotosPickerItem? = nil
    @State private var sendingMedia = false
    @State private var hint: String? = nil
    @State private var holding = false
    @State private var lastTyping = Date.distantPast
    @State private var profileCode: CodeTarget? = nil
    @State private var showCamera = false
    @FocusState private var focused: Bool

    private var list: [CloudMessage] { cloud.messages[friend.uid] ?? [] }
    private var name: String { friend.name.isEmpty ? friend.code : friend.name }
    /// 自分の最後のメッセージ（既読の表示を出す場所）
    private var myLastID: String? { list.last(where: { $0.from == cloud.uid })?.id }
    private var readAt: Date? { cloud.friendReadAt[friend.uid] }
    /// 相手が4秒以内に入力していたら、「入力中…」を出す
    private var typingNow: Bool {
        cloud.friendTypingAt[friend.uid].map { Date().timeIntervalSince($0) < 4 } ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        if list.isEmpty {
                            VStack(spacing: 10) {
                                PersonAvatar(uid: friend.uid, name: name, size: 84)
                                Text(name).font(.title3.weight(.black))
                                Text(L("まだメッセージはありません"))
                                    .font(.subheadline).foregroundStyle(Hi.dim)
                            }
                            .padding(.top, 60)
                        }
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, message in
                            // 前のメッセージから10分以上あいたら、時刻を出す
                            if index == 0 || message.date.timeIntervalSince(list[index - 1].date) > 600 {
                                Text(timeLabel(message.date))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Hi.dim)
                                    .padding(.top, 12).padding(.bottom, 4)
                            }
                            bubble(message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: list.last?.id) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
                .onAppear {
                    if let id = list.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            if let hint {
                Text(hint).font(.caption).foregroundStyle(Hi.dim).padding(.bottom, 4)
            }
            inputBar
        }
        .background(Color.black.ignoresSafeArea())
        .task {
            // 開いているあいだ、1.5秒ごとに読み直す。読んだら、既読を知らせる
            var readThrough: Date? = nil
            while !Task.isCancelled {
                await cloud.loadMessages(with: friend.uid)
                await cloud.markMessagesRead(from: friend.uid)
                if let last = cloud.messages[friend.uid]?.last, last.from == friend.uid, last.date != readThrough {
                    await cloud.markRead(friendUID: friend.uid)
                    readThrough = last.date
                }
                await cloud.refreshReadAt(friend.uid)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
        .sheet(item: $profileCode) { PersonProfileSheet(code: $0.id) }
        .fullScreenCover(isPresented: $showCamera) {
            // 投稿と同じ撮影画面（両方撮り・ズーム・前後切り替え）。撮った写真は、この会話に送る
            CaptureFlow(directSend: { image in
                Task {
                    do { try await cloud.sendPhoto(to: friend.uid, image: image) }
                    catch { hint = L("写真を送れませんでした") }
                }
            })
            .environmentObject(PostStore.shared)
        }
        .onChange(of: text) { _, value in
            // 入力中を知らせる（2秒に一度まで）
            guard !value.isEmpty, Date().timeIntervalSince(lastTyping) > 2 else { return }
            lastTyping = Date()
            Task { await cloud.setTyping(friend.uid) }
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task { await sendPicked(item) }
        }
        .presentationDetents([.large])
        .presentationBackground(.black)
        .preferredColorScheme(.dark)
    }

    private func timeLabel(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }

    /// 上：相手のアイコンと名前、閉じるボタン
    private var header: some View {
        HStack(spacing: 12) {
            Button { profileCode = CodeTarget(id: friend.code) } label: {
            HStack(spacing: 12) {
            PersonAvatar(uid: friend.uid, name: name, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.headline.weight(.black)).lineLimit(1)
                if typingNow {
                    Text(L("入力中…")).font(.caption.weight(.bold)).foregroundStyle(Hi.neon)
                } else {
                    Text("@" + friend.code).font(.caption).foregroundStyle(Hi.dim)
                }
            }
            }
            }
            .buttonStyle(.plain)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Hi.tile))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("閉じる"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .background(Color.black)
        .overlay(alignment: .bottom) { Rectangle().fill(Hi.tile).frame(height: 1) }
    }

    /// 1件の吹き出し。長押しで絵文字を選ぶ。下に、リアクションと既読
    private func bubble(_ m: CloudMessage) -> some View {
        let mine = m.from == cloud.uid
        return VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            HStack(alignment: .bottom) {
                if mine { Spacer(minLength: 60) }
                content(m, mine: mine)
                    .contextMenu {
                        ForEach(Reactions.all, id: \.self) { emoji in
                            Button(emoji) {
                                Task { await cloud.react(messageID: m.id, friendUID: friend.uid, emoji: emoji) }
                            }
                        }
                        if m.reactions[cloud.uid ?? ""] != nil {
                            Button(L("リアクションを外す"), role: .destructive) {
                                Task { await cloud.react(messageID: m.id, friendUID: friend.uid, emoji: nil) }
                            }
                        }
                    }
                if !mine { Spacer(minLength: 60) }
            }
            if !m.reactions.isEmpty {
                reactionChip(m)
            }
            if mine && m.id == myLastID {
                let read = readAt.map { $0 >= m.date } ?? false
                Text(read ? L("既読") : L("送信済み"))
                    .font(.caption2.weight(.black))
                    .foregroundStyle(read ? Hi.neon : Hi.dim)
                    .padding(.trailing, 4)
            }
        }
    }

    /// 中身：文字・写真・ボイス
    @ViewBuilder
    private func content(_ m: CloudMessage, mine: Bool) -> some View {
        switch m.kind {
        case "photo":
            VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
                if let from = m.sharedFrom {
                    // 友達の投稿を送ったとき：誰の投稿か、お題
                    Text(LF("{n} さんの投稿", ["n": from]) + (m.prompt.map { " · " + L($0) } ?? ""))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Hi.dim)
                }
                if let photo = m.photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 220, height: 293)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    Text(L("写真")).font(.subheadline).foregroundStyle(Hi.dim)
                }
                if let caption = m.caption, !caption.isEmpty {
                    Text(caption).font(.subheadline)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Hi.tile))
                        .foregroundStyle(.white)
                }
            }
        case "voice":
            if let data = m.voice {
                VoiceBubble(data: data, duration: m.duration, mine: mine)
            }
        default:
            Text(m.text)
                .font(.body)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: mine ? 20 : 6,
                                           bottomTrailingRadius: mine ? 6 : 20, topTrailingRadius: 20,
                                           style: .continuous)
                        .fill(mine ? Hi.neon : Hi.tile)
                )
                .foregroundStyle(mine ? Hi.onNeon : .white)
                .textSelection(.enabled)
        }
    }

    /// リアクションの印：絵文字ごとに数を出す
    private func reactionChip(_ m: CloudMessage) -> some View {
        let counts = Dictionary(grouping: m.reactions.values, by: { $0 }).mapValues { $0.count }
        return HStack(spacing: 6) {
            ForEach(counts.sorted { $0.key < $1.key }, id: \.key) { emoji, count in
                HStack(spacing: 3) {
                    Text(emoji).font(.caption)
                    if count > 1 { Text("\(count)").font(.caption2.weight(.black)).foregroundStyle(.white) }
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Hi.tile))
            }
        }
    }

    /// 下の入力欄：写真、文字（送信）、押している間の録音（マイク）
    private var inputBar: some View {
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(alignment: .bottom, spacing: 10) {
            PhotosPicker(selection: $picked, matching: .images) {
                Image(systemName: "photo")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Hi.tile))
            }
            .disabled(sendingMedia)
            .accessibilityLabel(L("写真を送る"))

            Button {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showCamera = true
                } else {
                    hint = L("カメラは使えません")
                }
            } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Hi.tile))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("カメラで撮って送る"))

            TextField(L("メッセージを送る…"), text: $text, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Hi.tile))

            if empty {
                micButton
            } else {
                Button {
                    let sending = text
                    text = ""
                    Task { await cloud.sendMessage(to: friend.uid, text: sending) }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(Hi.onNeon)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Hi.neon))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("送る"))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.black)
    }

    /// 押している間だけ録音し、離したら送る
    private var micButton: some View {
        Image(systemName: recorder.recording ? "waveform" : "mic.fill")
            .font(.system(size: 17, weight: .black))
            .foregroundStyle(recorder.recording ? Hi.onNeon : .white)
            .frame(width: 44, height: 44)
            .background(Circle().fill(recorder.recording ? Hi.neon : Hi.tile))
            .scaleEffect(recorder.recording ? 1.12 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: recorder.recording)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !holding else { return }
                        holding = true
                        hint = L("録音中…（離すと送信）")
                        Task {
                            if await recorder.start() == false {
                                hint = L("マイクを使うには許可が必要です")
                                holding = false
                            }
                        }
                    }
                    .onEnded { _ in
                        holding = false
                        guard let rec = recorder.stop() else {
                            hint = nil
                            return
                        }
                        hint = nil
                        Task {
                            do {
                                try await cloud.sendVoice(to: friend.uid, data: rec.data, duration: rec.duration)
                            } catch {
                                hint = L("ボイスが大きすぎます。短く録ってください。")
                            }
                        }
                    }
            )
            .accessibilityLabel(L("ボイスを送る（押したまま録音）"))
    }

    /// 選んだ写真を送る
    private func sendPicked(_ item: PhotosPickerItem) async {
        defer { picked = nil }
        sendingMedia = true
        hint = L("送信中…")
        defer { sendingMedia = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            hint = L("写真を読み込めませんでした")
            return
        }
        do {
            try await cloud.sendPhoto(to: friend.uid, image: image)
            hint = nil
        } catch {
            hint = L("写真が大きすぎます。別の写真を選んでください。")
        }
    }
}

/// ボイスの吹き出し：押すと再生する
private struct VoiceBubble: View {
    let data: Data
    let duration: Double
    let mine: Bool
    @StateObject private var player = VoicePlayer()

    var body: some View {
        Button { player.toggle(data) } label: {
            HStack(spacing: 10) {
                Image(systemName: player.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .black))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(mine ? Hi.onNeon.opacity(0.15) : Color.white.opacity(0.12)))
                HStack(spacing: 3) {
                    ForEach(0..<18, id: \.self) { i in
                        Capsule()
                            .frame(width: 3, height: CGFloat(6 + ((i * 7 + 3) % 11)))
                            .opacity(0.85)
                    }
                }
                Text(String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60))
                    .font(.caption.weight(.bold).monospacedDigit())
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Capsule().fill(mine ? Hi.neon : Hi.tile))
            .foregroundStyle(mine ? Hi.onNeon : .white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("ボイスを再生"))
    }
}

/// 相手のアイコン：設定している人は、そのアイコンを出す。ない人は、名前の頭文字
struct PersonAvatar: View {
    let uid: String
    let name: String
    var size: CGFloat = 46
    @ObservedObject private var cloud = CloudSync.shared

    var body: some View {
        Group {
            if let image = (uid == cloud.uid ? Avatar.load() : cloud.avatars[uid]) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                GlowAvatar(name: name, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: uid) { await cloud.loadAvatar(uid) }
    }
}

/// 投稿を、友達の DM に送る（選んだ人の会話に入る。フィードには出ない）
struct ShareToDMSheet: View {
    let post: CloudPost
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var cloud = CloudSync.shared
    @State private var sending: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: L("DMで送る"), onClose: { dismiss() }) { EmptyView() }
            ScrollView {
                LazyVStack(spacing: 10) {
                    if cloud.friends.isEmpty {
                        EmptyNote(symbol: "person.2.fill", title: L("まだ友達がいません"),
                                  detail: L("友達になると、投稿を送れます。"))
                    }
                    ForEach(cloud.friends) { friend in
                        Button {
                            sending = friend.uid
                            Task {
                                try? await cloud.sharePost(to: friend.uid, post: post)
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                PersonAvatar(uid: friend.uid, name: friend.name.isEmpty ? friend.code : friend.name, size: 46)
                                Text(friend.name.isEmpty ? friend.code : friend.name)
                                    .font(.subheadline.weight(.black)).foregroundStyle(.white)
                                Spacer()
                                Image(systemName: sending == friend.uid ? "hourglass" : "paperplane.fill")
                                    .foregroundStyle(Hi.neon)
                            }
                            .padding(12)
                            .background(Hi.tile)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationBackground(.black)
        .preferredColorScheme(.dark)
    }
}
