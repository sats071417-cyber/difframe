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
            if let cloudID, cloud.comments[cloudID] == nil { await cloud.loadComments(postID: cloudID) }
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
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
                }
                if let replyTo {
                    replyChip(replyTo)
                }
                inputBar
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(owner.isEmpty ? L("コメント") : owner)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("閉じる")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(.black)
        .preferredColorScheme(.dark)
        .onAppear {
            // 開いたら、すぐキーボードを出す（通知から開いたときは、そのコメントを見せるので出さない）
            if focusID == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { focused = true }
            }
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
        .sheet(isPresented: $editingCaption) {
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

    private var header: some View {
        VStack(spacing: 8) {
            if ownRecordID != nil, let image {
                // 自分の投稿：大きく見せる（押すと全画面で、指で拡大できる）
                Button { viewing = true } label: {
                    DualPhotoView(main: image, inset: ownFront)
                        .frame(width: 220, height: 293)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(Color.black.opacity(0.55)))
                                .padding(8)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("写真を大きく見る"))
                Button { editingCaption = true } label: {
                    Label(L("一言を編集"), systemImage: "pencil")
                }
                .buttonStyle(TileButtonStyle())
            } else {
                Group {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else if let prompt {
                        PromptArtView(prompt: prompt)
                    } else {
                        Hi.tile
                    }
                }
                .frame(width: 96, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if let c = currentCaption, !c.isEmpty {
                Text(c).font(.subheadline.weight(.semibold))
            }
            // リアクション（ここでも選べる）
            HStack(spacing: 6) {
                ForEach(Reactions.all, id: \.self) { emoji in
                    let chosen = store.reactions[postID] == emoji
                    Button {
                        store.toggleReaction(postID: postID, emoji: emoji)
                    } label: {
                        Text(emoji).font(.title3)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(chosen ? Hi.neon.opacity(0.9) : Hi.tile))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(emoji)
                }
            }
            likersList
        }
        .frame(maxWidth: .infinity)
        .task { if ownRecordID != nil { await cloud.loadInbox() } }
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
        return cloud.notices.filter { $0.type == "like" && $0.postID == postID }
    }

    @ViewBuilder
    private var likersList: some View {
        if ownRecordID != nil {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L("リアクション")).font(.caption.weight(.black))
                    Spacer()
                    Text("\(likers.count)").font(.caption.weight(.black)).foregroundStyle(Hi.neon)
                }
                ForEach(likers) { liker in
                    HStack(spacing: 8) {
                        Text(liker.text).font(.subheadline)
                        Text(liker.fromName.isEmpty ? liker.fromCode : liker.fromName)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.top, 6)
            .frame(maxWidth: 260, alignment: .leading)
        }
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
                .background(Capsule().fill(Hi.tile))
                .submitLabel(.send)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.headline.weight(.black))
                    .foregroundStyle(empty ? Hi.dim : Hi.onNeon)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(empty ? Hi.tile : Hi.neon))
            }
            .buttonStyle(.plain)
            .disabled(empty)
            .accessibilityLabel(L("送る"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black)
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
struct CommentTarget: Identifiable {
    let id: String
    var owner: String = ""
    var caption: String? = nil
    var image: UIImage? = nil
    var prompt: String? = nil
    var cloudID: String? = nil
    /// 自分の投稿の記録（写真を大きく見る・一言を直す、のため）
    var ownRecordID: String? = nil
    /// 開いたとき、このコメントまでスクロールする（通知から開いたとき）
    var focusID: String? = nil
}
