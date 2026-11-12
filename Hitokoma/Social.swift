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
    let postID: String
    var allowComments = true
    let onComment: () -> Void

    var body: some View {
        let list = store.comments(for: postID)
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
                        if let last = list.last {
                            Text(last.text).lineLimit(1).foregroundStyle(.white)
                            if list.count > 1 {
                                Text(LF("ほか{n}件", ["n": "\(list.count - 1)"])).foregroundStyle(Hi.dim)
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
    }
}

/// コメントの画面。開くとすぐに文字を打てる（BeReal と同じ）
struct CommentSheet: View {
    @EnvironmentObject private var store: PostStore
    @Environment(\.dismiss) private var dismiss
    let postID: String
    var owner: String = ""
    var caption: String? = nil
    var image: UIImage? = nil
    var prompt: String? = nil
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 14) {
                        header
                        Divider().overlay(Hi.tile)
                        let list = store.comments(for: postID)
                        if list.isEmpty {
                            VStack(spacing: 4) {
                                Text(L("まだ静かです")).font(.subheadline.weight(.black))
                                Text(L("最初にリアクションかコメントをしよう"))
                                    .font(.caption).foregroundStyle(Hi.dim)
                            }
                            .padding(.top, 12)
                        }
                        ForEach(list) { comment in
                            commentRow(comment)
                        }
                    }
                    .padding(16)
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
            // 開いたら、すぐキーボードを出す
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { focused = true }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
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
            if let caption, !caption.isEmpty {
                Text(caption).font(.subheadline.weight(.semibold))
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
        }
        .frame(maxWidth: .infinity)
    }

    private func commentRow(_ comment: Comment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let avatar = Avatar.load() {
                    Image(uiImage: avatar).resizable().scaledToFill()
                } else {
                    Hi.neon.overlay(Image(systemName: "person.fill").font(.caption).foregroundStyle(Hi.onNeon))
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(L("あなた")).font(.caption.weight(.black))
                    Text(comment.date, style: .relative).font(.caption2).foregroundStyle(Hi.dim)
                }
                Text(comment.text).font(.subheadline)
            }
            Spacer(minLength: 0)
        }
        .contextMenu {
            Button(role: .destructive) {
                store.deleteComment(postID: postID, commentID: comment.id)
            } label: {
                Label(L("コメントを削除"), systemImage: "trash")
            }
        }
    }

    private var inputBar: some View {
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 10) {
            TextField(L("コメントを追加…"), text: $text, axis: .vertical)
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

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addComment(postID: postID, text: trimmed)
        text = ""
    }
}

/// コメント画面を開く相手の投稿
struct CommentTarget: Identifiable {
    let id: String
    var owner: String = ""
    var caption: String? = nil
    var image: UIImage? = nil
    var prompt: String? = nil
}
