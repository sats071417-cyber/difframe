import SwiftUI

// MARK: - 投稿へのリアクションとコメント（BeReal のように、写真の右下のボタンから）

/// リアクションに使える絵文字（最初の ❤️ は、ダブルタップのいいね）
enum Reactions {
    static let like = "❤️"
    static let all = ["❤️", "😂", "😮", "😍", "👍", "🔥"]
}

/// 写真に、リアクションとコメントの操作をつける
/// ・ダブルタップで ❤️（いいね）。大きなハートが出る
/// ・右下に、コメントのボタンと、絵文字のボタン。絵文字を押すと、写真の下に絵文字が並ぶ
struct SocialPhotoModifier: ViewModifier {
    @EnvironmentObject private var store: PostStore
    let postID: String
    var canReact = true
    var allowComments = true
    let onComment: () -> Void

    @State private var showPicker = false
    @State private var burst = false

    func body(content: Content) -> some View {
        content
            .onTapGesture(count: 2) { like() }
            // 1回タップで、コメント欄を開く（コメントを受け付けないときは開かない）
            .onTapGesture { if allowComments { onComment() } }
            .overlay {
                // ダブルタップのハート
                Image(systemName: "heart.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 12)
                    .scaleEffect(burst ? 1 : 0.4)
                    .opacity(burst ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomTrailing) {
                VStack(spacing: 10) {
                    if allowComments {
                        roundButton("bubble.left.fill", label: L("コメントする"), action: onComment)
                    }
                    if canReact {
                        roundButton(store.reactions[postID] == nil ? "face.smiling" : "face.smiling.inverse",
                                    label: L("絵文字でリアクション")) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showPicker.toggle() }
                        }
                    }
                }
                .padding(12)
            }
            .overlay(alignment: .bottom) {
                if showPicker {
                    HStack(spacing: 8) {
                        ForEach(Reactions.all, id: \.self) { emoji in
                            let chosen = store.reactions[postID] == emoji
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                store.toggleReaction(postID: postID, emoji: emoji)
                                CloudSync.shared.notifyReaction(postID: postID, emoji: emoji)
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showPicker = false }
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 26))
                                    .frame(width: 44, height: 44)
                                    .background(Circle().fill(chosen ? Hi.neon.opacity(0.9) : Color.black.opacity(0.55)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(emoji)
                        }
                    }
                    .padding(6)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .padding(.bottom, 12)
                    .padding(.trailing, 50)
                    .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
                }
            }
    }

    private func like() {
        guard canReact else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        store.setReaction(postID: postID, emoji: Reactions.like)
        CloudSync.shared.notifyReaction(postID: postID, emoji: Reactions.like)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { burst = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000)
            withAnimation(.easeOut(duration: 0.25)) { burst = false }
        }
    }

    private func roundButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.black.opacity(0.45)))
                .shadow(color: .black.opacity(0.3), radius: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

extension View {
    func socialPhoto(postID: String, canReact: Bool = true, allowComments: Bool = true,
                     onComment: @escaping () -> Void) -> some View {
        modifier(SocialPhotoModifier(postID: postID, canReact: canReact, allowComments: allowComments, onComment: onComment))
    }
}

/// 写真の下の行：つけたリアクションと、「コメントを追加…」（コメントがオフなら、その知らせ）
struct CommentLine: View {
    @EnvironmentObject private var store: PostStore
    @ObservedObject private var cloud = CloudSync.shared
    let postID: String
    var allowComments = true
    /// サーバーの投稿なら、その名前（コメントはサーバーから読む）
    var cloudID: String? = nil
    let onComment: () -> Void

    /// 最後のコメントの文字と、コメントの数
    private var summary: (last: String?, count: Int) {
        if let cloudID {
            let list = cloud.comments[cloudID] ?? []
            return (list.last.map { "\($0.name): \($0.text)" }, list.count)
        }
        let list = store.comments(for: postID)
        return (list.last?.text, list.count)
    }

    /// 自分の投稿についた、友達のリアクション（絵文字と人数）
    private func friendReactions(_ serverID: String) -> [(emoji: String, count: Int)] {
        guard serverID.hasPrefix((cloud.uid ?? "?") + "_") else { return [] }
        var order: [String] = []; var counts: [String: Int] = [:]
        for n in cloud.notices where n.type == "like" && n.postID == serverID && !cloud.blocked.contains(n.fromUID) {
            if counts[n.text] == nil { order.append(n.text) }
            counts[n.text, default: 0] += 1
        }
        return order.map { ($0, counts[$0] ?? 0) }
    }

    var body: some View {
        let info = summary
        HStack(spacing: 10) {
            if let mine = store.reactions[postID] {
                Button {
                    store.toggleReaction(postID: postID, emoji: mine)
                } label: {
                    Text(mine).font(.subheadline)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Hi.tile))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LF("{e} のリアクションを外す", ["e": mine]))
            }
            if let cloudID, !friendReactions(cloudID).isEmpty {
                // 友達からのリアクション（絵文字ごとの数）
                HStack(spacing: 4) {
                    ForEach(friendReactions(cloudID), id: \.emoji) { r in
                        Text(r.count > 1 ? "\(r.emoji)\(r.count)" : r.emoji).font(.subheadline)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Hi.neon.opacity(0.25)))
            }
            if allowComments {
                Button(action: onComment) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left").font(.caption)
                        if let last = info.last {
                            Text(last).lineLimit(1).foregroundStyle(.white)
                            if info.count > 1 {
                                Text(LF("ほか{n}件", ["n": "\(info.count - 1)"])).foregroundStyle(Hi.dim)
                            }
                        } else {
                            Text(L("コメントを追加…")).foregroundStyle(Hi.dim)
                        }
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Label(L("コメントはオフになっています"), systemImage: "bubble.left.and.exclamationmark.bubble.right")
                    .font(.caption)
                    .foregroundStyle(Hi.dim)
                Spacer(minLength: 0)
            }
        }
        .task(id: cloudID) {
            if let cloudID {
                await cloud.loadComments(postID: cloudID)
                if cloudID.hasPrefix((cloud.uid ?? "?") + "_") { await cloud.loadInbox() }
            }
        }
    }
}

/// コメントの画面。開くとすぐに文字を打てる（BeReal と同じ）。
/// 自分の投稿では、写真を大きく見られて（押すと全画面）、一言を直せる。コメントには返信もできる。
struct CommentSheet: View {
    @EnvironmentObject private var store: PostStore
    @Environment(\.dismiss) private var dismiss
    let postID: String
    var owner: String = ""
    var caption: String? = nil
    var image: UIImage? = nil
    var front: UIImage? = nil      // 内カメラの写真（左上に小さく出す）
    var prompt: String? = nil
    var cloudID: String? = nil
    /// 自分の投稿の記録（写真を大きく見る・一言を直す、のため）
    var ownRecordID: String? = nil
    /// 開いたとき、このコメントまでスクロールして光らせる（通知から開いたとき）
    var focusID: String? = nil
    @ObservedObject private var cloud = CloudSync.shared
    @State private var text = ""
    @State private var replyTo: Row? = nil
    @State private var flash: String? = nil
    @State private var reportTarget: Row? = nil
    @State private var reported = false
    @State private var editingCaption = false
    @State private var viewing = false
    @State private var expanded = false            // 写真を大きく広げているか
    @State private var remote: CloudPost? = nil    // 他の人の投稿：時刻・場所・内カメラの写真を読んだもの
    @State private var mapOpen = false
    @State private var shareOpen = false
    @State private var profileCode: CodeTarget? = nil
    @State private var reactorsFor: EmojiTarget? = nil
    @State private var postReportOpen = false
    @State private var scrollY: CGFloat = 0        // コメントの一覧を、どれだけ下にスクロールしているか（0 = いちばん上）
    @State private var dragDY: CGFloat = 0         // 指で、いま縦に動かしている量
    @State private var dragAtTop: Bool? = nil      // 指を置いたとき、いちばん上だったか
    @GestureState private var gestureActive = false
    @FocusState private var focused: Bool

    /// 画面に出す1件のコメント（返信の元は source で持つ）
    private struct Row: Identifiable {
        let id: String
        let name: String
        let mine: Bool
        let text: String
        let date: Date
        let source: CloudComment?
        let replyName: String?
        let replyText: String?
    }

    /// 一言：自分の投稿は、記録の今の一言（直したら、すぐ変わる）
    private var currentCaption: String? {
        if let ownRecordID { return store.records.first { $0.id == ownRecordID }?.caption }
        return caption
    }

    private var rows: [Row] {
        if let cloudID {
            return (cloud.comments[cloudID] ?? []).filter { !cloud.blocked.contains($0.uid) }.map {
                Row(id: $0.id, name: $0.name, mine: $0.uid == cloud.uid, text: $0.text, date: $0.date,
                    source: $0, replyName: $0.replyName, replyText: $0.replyText)
            }
        }
        return store.comments(for: postID).map {
            Row(id: $0.id, name: L("あなた"), mine: true, text: $0.text, date: $0.date,
                source: nil, replyName: nil, replyText: nil)
        }
    }

    var body: some View { bodyContent.edgeSwipeBack() }

    private var bodyContent: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        Color.clear.frame(height: 0).reportScroll(tag: 7, space: "commentScroll").id("top")
                        header
                        Divider().overlay(Hi.tile)
                        let list = rows
                        if list.isEmpty {
                            VStack(spacing: 4) {
                                Text(L("まだ静かです")).font(.subheadline.weight(.black))
                                Text(L("最初にリアクションかコメントをしよう"))
                                    .font(.caption).foregroundStyle(Hi.dim)
                            }
                            .padding(.top, 12)
                        }
                        ForEach(list) { row in
                            commentRow(row)
                                .id(row.id)
                                .padding(6)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Hi.neon.opacity(flash == row.id ? 0.18 : 0)))
                        }
                    }
                    .padding(16)
                }
                .onAppear { scrollToFocus(proxy) }
                .coordinateSpace(name: "commentScroll")
                // 下に引くと、写真が広がって、そのまま。上に払うと、小さくなって、そのまま
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .updating($gestureActive) { _, state, _ in state = true }
                        .onChanged { v in
                            if dragAtTop == nil { dragAtTop = scrollY <= 2 }
                            dragDY = abs(v.translation.width) > abs(v.translation.height) ? 0 : v.translation.height
                        }
                        .onEnded { v in
                            let dy = abs(v.translation.width) > abs(v.translation.height) ? 0 : v.translation.height
                            let startedAtTop = dragAtTop ?? false
                            var next = expanded
                            if !expanded, startedAtTop, dy > 50 { next = true }
                            if expanded, dy < -50 { next = false }
                            let changed = next != expanded
                            if changed { UISelectionFeedbackGenerator().selectionChanged() }
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                expanded = next
                                dragDY = 0
                                dragAtTop = nil
                            }
                            // 大きさが変わったときだけ、いちばん上へ戻す（普通のスクロールは、そのまま）
                            if changed { withAnimation { proxy.scrollTo("top", anchor: .top) } }
                        }
                )
                .onChange(of: gestureActive) { _, active in
                    // 途中で取り消されたときも、元に戻す
                    if !active, dragDY != 0 { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { dragDY = 0; dragAtTop = nil } }
                }
                // コメント欄は、内容の上に浮かせる（内容は、欄の後ろにも続く）
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        if let replyTo { replyChip(replyTo) }
                        inputBar
                    }
                }
                // 止まっているときの位置は、上の余白（padding 16）の分だけ下がっている。それを引いた量が、引っぱった量
                .onPreferenceChange(ScrollOffsetKey.self) { scrollY = -(($0[7] ?? 16) - 16) }
                }
            }
            .background {
                // 写真の色が、上のほうに、うっすら染みる
                ZStack {
                    Color.black
                    LinearGradient(colors: [(shownImage.map { DominantColor.of($0, key: "c-" + (cloudID ?? postID)) } ?? .clear).opacity(0.32), .clear],
                                   startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.5))
                }
                .ignoresSafeArea()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationBackground(.black)
        .preferredColorScheme(.dark)
        .task {
            // 開いている間は、友達のコメント・リアクションを読み直し続ける
            while !Task.isCancelled {
                if let cloudID { await cloud.loadComments(postID: cloudID) }
                if ownRecordID != nil { await cloud.loadInbox() }
                try? await Task.sleep(nanoseconds: 6_000_000_000)
            }
        }
        .task(id: cloudID) {
            // 他の人の投稿：時刻・場所・内カメラの写真を読む（通知から開いたときは、写真もここで入る）
            guard ownRecordID == nil, let cloudID else { return }
            remote = await cloud.friendPost(cloudID)
        }
        .fullScreenCover(item: $profileCode) { PersonProfileSheet(code: $0.id) }
        .fullScreenCover(isPresented: $shareOpen) {
            if let remote { ShareToDMSheet(post: remote) }
        }
        .confirmationDialog(L("通報の理由"), isPresented: $postReportOpen, titleVisibility: .visible) {
            ForEach([L("嫌がらせ・不快"), L("不適切な内容"), L("その他")], id: \.self) { reason in
                Button(reason) {
                    guard let uid = ownerUID, let cloudID else { return }
                    reported = true
                    Task { await cloud.sendReport(against: uid, postID: cloudID, reason: reason) }
                }
            }
            Button(L("キャンセル"), role: .cancel) {}
        }
        .fullScreenCover(isPresented: $mapOpen) {
            LocationMapSheet(city: shownCity ?? "", latitude: remote?.latitude, longitude: remote?.longitude, photo: shownImage)
        }
        .confirmationDialog(L("通報の理由"), isPresented: Binding(get: { reportTarget != nil }, set: { if !$0 { reportTarget = nil } }), titleVisibility: .visible) {
            Button(L("嫌がらせ・不快")) { sendReport(L("嫌がらせ・不快")) }
            Button(L("不適切な内容")) { sendReport(L("不適切な内容")) }
            Button(L("その他")) { sendReport(L("その他")) }
            Button(L("キャンセル"), role: .cancel) { reportTarget = nil }
        }
        .alert(L("通報を受け付けました。ありがとうございます。"), isPresented: $reported) {
            Button("OK", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $editingCaption) {
            if let ownRecordID {
                CaptionEditSheet(recordID: ownRecordID)
                    .environmentObject(store)
            }
        }
        .fullScreenCover(isPresented: $viewing) {
            if let ownRecordID {
                PhotoViewer(startID: ownRecordID)
                    .environmentObject(store)
            }
        }
    }

    // MARK: 投稿の表示（上の行・写真・一言・場所・リアクション）

    /// 写真の大きさ：0（小さい）〜 1（画面の幅いっぱい）
    private var photoProgress: CGFloat {
        let live = (expanded || dragAtTop == true) ? dragDY : 0
        return min(1, max(0, (expanded ? 1 : 0) + live / 200))
    }

    private var ownRecord: PromptRecord? { ownRecordID.flatMap { id in store.records.first { $0.id == id } } }
    private var shownImage: UIImage? { image ?? remote?.photo }
    private var shownFront: UIImage? { ownRecordID != nil ? ownFront : (front ?? remote?.front) }
    private var shownCity: String? { ownRecordID != nil ? ownRecord?.city : remote?.city }
    private var shownElapsed: Double? { ownRecordID != nil ? ownRecord?.elapsed : remote?.elapsed }
    private var shownTime: Date? { ownRecordID != nil ? ownRecord?.postedAt : remote?.postedAt }
    /// 投稿した人の友達コード（友達一覧のものが最新。なければ、投稿に付いているもの）
    private var ownerCode: String? {
        guard ownRecordID == nil, let uid = ownerUID else { return nil }
        let fromFriends = cloud.friends.first { $0.uid == uid }?.code
        if let c = fromFriends, !c.isEmpty { return c }
        return remote?.code.isEmpty == false ? remote?.code : nil
    }

    private var ownerUID: String? { ownRecordID != nil ? cloud.uid : cloudID?.split(separator: "_").first.map(String.init) }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: AppLanguage.current.rawValue)
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    /// 上の行：戻る、投稿した人のアイコンと名前、何分前か
    private var topBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold))
                    .frame(width: 38, height: 38).background(Circle().fill(Hi.tile))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("戻る"))
            // アイコンと名前を押すと、その人のプロフィール（全画面）。場所は別のボタン（自分の投稿でも押せるように）
            Button {
                if let code = ownerCode { profileCode = CodeTarget(id: code) }
            } label: {
                Group {
                    if ownRecordID != nil, let avatar = Avatar.load() {
                        Image(uiImage: avatar).resizable().scaledToFill().frame(width: 32, height: 32).clipShape(Circle())
                    } else {
                        PersonAvatar(uid: ownerUID ?? "", name: owner.isEmpty ? "?" : owner, size: 32)
                    }
                }
            }
            .buttonStyle(.plain)
            .allowsHitTesting(ownRecordID == nil && ownerCode != nil)
            VStack(alignment: .leading, spacing: 1) {
                Button {
                    if let code = ownerCode { profileCode = CodeTarget(id: code) }
                } label: {
                    Text(owner.isEmpty ? L("コメント") : owner).font(.subheadline.weight(.black)).lineLimit(1)
                }
                .buttonStyle(.plain)
                .allowsHitTesting(ownRecordID == nil && ownerCode != nil)
                HStack(spacing: 6) {
                    if let time = shownTime { Text(relative(time)).foregroundStyle(Hi.dim).layoutPriority(1) }
                    if let city = shownCity, !city.isEmpty {
                        // 場所：「何分前」の横に、同じ大きさの黄色い文字で（押すと、大まかな地図）
                        Button { mapOpen = true } label: {
                            Label(city, systemImage: "location.fill")
                                .imageScale(.small).foregroundStyle(Hi.neon).fontWeight(.semibold)
                                .lineLimit(1).truncationMode(.tail)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .font(.caption2)
            }
            Spacer(minLength: 0)
            // 右：送る（友達のDMへ）と、その他のメニュー
            HStack(spacing: 4) {
                if ownRecordID == nil {
                    Button { shareOpen = true } label: {
                        Image(systemName: "paperplane.fill").font(.system(size: 16, weight: .bold))
                            .frame(width: 40, height: 38)
                    }
                    .disabled(remote?.photo == nil)
                    .accessibilityLabel(L("DMで送る"))
                }
                Menu {
                    if ownRecordID != nil {
                        Button { editingCaption = true } label: { Label(L("一言を編集"), systemImage: "pencil") }
                    } else if let uid = ownerUID, uid != cloud.uid {
                        Button { postReportOpen = true } label: { Label(L("通報"), systemImage: "flag") }
                        Button(role: .destructive) {
                            Task { await cloud.block(uid); dismiss() }
                        } label: { Label(L("ブロック"), systemImage: "hand.raised") }
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold))
                        .frame(width: 40, height: 38)
                }
                .accessibilityLabel(L("その他"))
            }
            .foregroundStyle(.white)
            .background(Capsule().fill(Color.white.opacity(0.14)))
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
    }

    private var header: some View {
        VStack(spacing: 8) {
            // その日のタイム（通知が届いてから投稿するまで）。写真の上に、黄色い文字で
            if let elapsed = shownElapsed {
                Label(TimeFormat.string(elapsed), systemImage: "timer")
                    .font(.caption.weight(.black).monospacedDigit()).foregroundStyle(Hi.neon)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Hi.neon.opacity(0.15)))
                    .accessibilityLabel(LF("タイム {t}", ["t": TimeFormat.string(elapsed)]))
            }
            // 写真：小さく出して、押すと、その場で大きく広がる
            Group {
                if let img = shownImage {
                    DualPhotoView(main: img, inset: shownFront)
                } else if let prompt {
                    PromptArtView(prompt: prompt)
                } else {
                    Hi.tile
                }
            }
            .aspectRatio(PhotoShape.ratio, contentMode: .fit)
            // 下に引くほど、少しずつ大きくなる（離すと戻る）。押すと、大きいまま
            .frame(width: 115 + (UIScreen.main.bounds.width - 16 - 115) * photoProgress)
            .clipShape(RoundedRectangle(cornerRadius: 12 + 10 * photoProgress, style: .continuous))
            .onTapGesture {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { expanded.toggle() }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(L("写真を大きく見る"))

            // 一言：自分の投稿は、押して直せる
            if ownRecordID != nil {
                Button { editingCaption = true } label: {
                    let c = currentCaption ?? ""
                    Text(c.isEmpty ? L("ひとことを追加…") : c)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(c.isEmpty ? 0.85 : 1))
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(.plain)
            } else if let c = currentCaption, !c.isEmpty {
                Text(c).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
            }

            reactionsRow

            // 絵文字で、リアクションする（自分の投稿には、しない）
            if ownRecordID == nil {
            HStack(spacing: 6) {
                ForEach(Reactions.all, id: \.self) { emoji in
                    let chosen = store.reactions[postID] == emoji
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        store.toggleReaction(postID: postID, emoji: emoji)
                        if cloudID != nil { CloudSync.shared.notifyReaction(postID: cloudID ?? postID, emoji: emoji) }
                    } label: {
                        Text(emoji).font(.body)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(chosen ? Hi.neon.opacity(0.9) : Hi.tile))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(emoji)
                }
            }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// 自分の投稿の、内カメラの写真（あれば）
    private var ownFront: UIImage? {
        guard let ownRecordID, let record = store.records.first(where: { $0.id == ownRecordID }),
              let file = record.frontPhotoFile else { return nil }
        return store.image(for: file)
    }

    /// この投稿にリアクションした人（自分の投稿だけ。通知から読む）
    private var likers: [CloudNotice] {
        guard ownRecordID != nil else { return [] }
        let serverID = cloudID ?? postID
        return cloud.notices.filter { $0.type == "like" && $0.postID == serverID && !cloud.blocked.contains($0.fromUID) }
    }

    /// 絵文字ごとの、リアクションした人（同じ人は、いちばん新しい1件だけ。自分の投稿だけ）
    private var reactionGroups: [(emoji: String, people: [CloudNotice])] {
        guard ownRecordID != nil else { return [] }
        let latest = Dictionary(grouping: likers, by: \.fromUID).compactMap { $0.value.max { $0.date < $1.date } }
        let groups = Dictionary(grouping: latest, by: \.text)
        let order = Reactions.all + groups.keys.filter { !Reactions.all.contains($0) }.sorted()
        return order.compactMap { e in groups[e].map { (emoji: e, people: $0.sorted { $0.date > $1.date }) } }
    }

    /// リアクション：絵文字ごとに人数を出す。押すと、その絵文字をつけた人の一覧が開く
    @ViewBuilder
    private var reactionsRow: some View {
        let groups = reactionGroups
        if !groups.isEmpty {
            HStack(spacing: 8) {
                ForEach(groups, id: \.emoji) { group in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        reactorsFor = EmojiTarget(id: group.emoji)
                    } label: {
                        HStack(spacing: 6) {
                            Text(group.emoji).font(.title3)
                            Text("\(group.people.count)").font(.subheadline.weight(.black))
                        }
                        .padding(.horizontal, 14).frame(height: 40)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(group.emoji) \(group.people.count)")
                    .accessibilityHint(L("リアクションした人を見る"))
                }
            }
            .padding(.top, 2)
            // 下から出る一覧（ここだけは、シート）
            .sheet(item: $reactorsFor) { target in
                reactorsSheet(emoji: target.id)
            }
        }
    }

    /// 1つの絵文字をつけた人の一覧（名前と、何分前か）
    private func reactorsSheet(emoji: String) -> some View {
        let people = reactionGroups.first { $0.emoji == emoji }?.people ?? []
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(emoji).font(.system(size: 38))
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(people.count)").font(.title2.weight(.black).monospacedDigit())
                    Text(L("リアクション")).font(.caption).foregroundStyle(Hi.dim)
                }
                Spacer()
                Button { reactorsFor = nil } label: {
                    Image(systemName: "xmark").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(Circle().fill(Hi.tile))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("閉じる"))
            }
            .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 14)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                        HStack {
                            Text(person.fromName.isEmpty ? person.fromCode : person.fromName)
                                .font(.body.weight(.semibold)).lineLimit(1)
                            Spacer()
                            Text(relative(person.date)).font(.caption).foregroundStyle(Hi.dim)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 14)
                        if index < people.count - 1 { Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 20) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Hi.tile))
                .padding(.horizontal, 16)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.black)
        .preferredColorScheme(.dark)
    }

    private func commentRow(_ comment: Row) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if comment.mine, let avatar = Avatar.load() {
                    Image(uiImage: avatar).resizable().scaledToFill()
                } else if comment.mine {
                    Hi.neon.overlay(Image(systemName: "person.fill").font(.caption).foregroundStyle(Hi.onNeon))
                } else {
                    Hi.tile.overlay(Text(String(comment.name.prefix(1))).font(.caption.weight(.black)).foregroundStyle(.white))
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(comment.mine ? L("あなた") : comment.name).font(.caption.weight(.black))
                    Text(comment.date, style: .relative).font(.caption2).foregroundStyle(Hi.dim)
                }
                // 返信の引用（返信先の名前と文）
                if let replyName = comment.replyName, let replyText = comment.replyText {
                    HStack(spacing: 4) {
                        Image(systemName: "arrowshape.turn.up.left.fill").font(.caption2)
                        Text("\(replyName)：\(replyText)").lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(Hi.dim)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Hi.tile))
                }
                Text(comment.text).font(.subheadline)
                TranslateLine(text: comment.text)
                if cloudID != nil, comment.source != nil {
                    Button(L("返信")) {
                        replyTo = comment
                        focused = true
                    }
                    .font(.caption.weight(.black))
                    .foregroundStyle(Hi.neon)
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .contextMenu {
            if comment.mine {
                Button(role: .destructive) {
                    if let cloudID {
                        Task { await cloud.deleteComment(postID: cloudID, commentID: comment.id) }
                    } else {
                        store.deleteComment(postID: postID, commentID: comment.id)
                    }
                } label: {
                    Label(L("コメントを削除"), systemImage: "trash")
                }
            } else if let src = comment.source {
                Button { reportTarget = comment } label: {
                    Label(L("通報"), systemImage: "flag")
                }
                Button(role: .destructive) {
                    Task { await cloud.block(src.uid) }
                } label: {
                    Label(L("ブロック"), systemImage: "hand.raised")
                }
            }
        }
    }

    /// 返信先の表示（×で取り消す）
    private func replyChip(_ row: Row) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrowshape.turn.up.left.fill").font(.caption)
            Text(LF("{n} に返信", ["n": row.name])).font(.caption.weight(.bold)).lineLimit(1)
            Spacer()
            Button { replyTo = nil } label: {
                Image(systemName: "xmark").font(.caption.weight(.black))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Hi.neon)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Hi.tile)
    }

    private var inputBar: some View {
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 10) {
            TextField(replyTo == nil ? L("コメントを追加…") : LF("{n} に返信", ["n": replyTo?.name ?? ""]),
                      text: $text, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .submitLabel(.send)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.headline.weight(.black))
                    .foregroundStyle(empty ? Color.white.opacity(0.5) : Hi.onNeon)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(empty ? Color.white.opacity(0.12) : Hi.neon))
            }
            .buttonStyle(.plain)
            .disabled(empty)
            .accessibilityLabel(L("送る"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
    }

    /// 通報の理由を選んだら、記録を送る
    private func sendReport(_ reason: String) {
        guard let target = reportTarget, let src = target.source, let cloudID else {
            reportTarget = nil
            return
        }
        reportTarget = nil
        reported = true
        Task { await cloud.sendReport(against: src.uid, postID: cloudID, commentID: src.id, reason: reason) }
    }

    /// 通知から開いたとき、そのコメントまでスクロールして、少しのあいだ光らせる
    private func scrollToFocus(_ proxy: ScrollViewProxy) {
        guard let focusID else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation { proxy.scrollTo(focusID, anchor: .center) }
            withAnimation { flash = focusID }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation { flash = nil }
            }
        }
    }

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let cloudID {
            let target = replyTo?.source
            Task { await cloud.addComment(postID: cloudID, text: trimmed, replyTo: target) }
        } else {
            store.addComment(postID: postID, text: trimmed)
        }
        text = ""
        replyTo = nil
    }
}

/// コメント画面を開く相手の投稿
/// リアクションした人の一覧を開く、絵文字の目印
struct EmojiTarget: Identifiable { let id: String }

struct CommentTarget: Identifiable {
    let id: String
    var owner: String = ""
    var caption: String? = nil
    var image: UIImage? = nil
    var front: UIImage? = nil
    var prompt: String? = nil
    var cloudID: String? = nil
    /// 自分の投稿の記録（写真を大きく見る・一言を直す、のため）
    var ownRecordID: String? = nil
    /// 開いたとき、このコメントまでスクロールする（通知から開いたとき）
    var focusID: String? = nil
}
