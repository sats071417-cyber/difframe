import SwiftUI

/// サーバーから届いた、ほかの人の投稿のカード（友達・みんな の両方で使う）
struct CloudPostCard: View {
    let post: CloudPost
    @State private var profileCode: CodeTarget? = nil
    @State private var shareOpen = false
    /// 友達として見ているか（友達からのコメントは、いつでも受け付ける）
    var asFriend = false
    let onComment: (CommentTarget) -> Void

    private var commentsOn: Bool { asFriend || !post.commentsOff }

    private var target: CommentTarget {
        CommentTarget(id: post.id, owner: post.name.isEmpty ? "@" + post.handle : post.name,
                      caption: post.caption, image: post.photo, cloudID: post.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay(Text(String((post.name.isEmpty ? post.handle : post.name).prefix(1)))
                        .font(.system(.subheadline, design: .rounded).bold())
                        .foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 1) {
                    Text(post.name.isEmpty ? "@" + post.handle : post.name)
                        .font(.subheadline.weight(.black)).lineLimit(1)
                    HStack(spacing: 4) {
                        Text("@\(post.handle) ・ " + LF("現地 {t}", ["t": post.localTime]))
                        if let city = post.city {
                            Label(city, systemImage: "mappin").labelStyle(.titleAndIcon)
                        }
                    }
                    .font(.caption).foregroundStyle(Hi.dim).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let elapsed = post.elapsed {
                    DotText(text: TimeFormat.string(elapsed), pitch: 3, color: Hi.neon)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if !post.code.isEmpty { profileCode = CodeTarget(id: post.code) } }

            Group {
                if let photo = post.photo {
                    DualPhotoView(main: photo, inset: post.front)
                } else {
                    PromptArtView(prompt: post.prompt)
                }
            }
            .aspectRatio(PhotoShape.ratio, contentMode: .fit)
            .overlay(alignment: .bottomLeading) {
                Text(L(post.prompt)).font(.title3.weight(.black)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4).padding(16)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .socialPhoto(postID: post.id, allowComments: commentsOn) { onComment(target) }
            .contextMenu {
                if post.photo != nil {
                    Button { shareOpen = true } label: { Label(L("DMで送る"), systemImage: "paperplane") }
                }
            }

            if let caption = post.caption, !caption.isEmpty {
                Text(caption).font(.subheadline)
            }
            CommentLine(postID: post.id, allowComments: commentsOn, cloudID: post.id) { onComment(target) }
        }
        .sheet(item: $profileCode) { PersonProfileSheet(code: $0.id) }
        .sheet(isPresented: $shareOpen) { ShareToDMSheet(post: post) }
    }
}

/// サーバーの状態（設定画面などに出す）
struct CloudStatusRow: View {
    @ObservedObject private var cloud = CloudSync.shared

    var body: some View {
        HStack {
            Label(L("サーバー"), systemImage: "icloud")
            Spacer()
            Group {
                if !cloud.isOn {
                    Text(L("オフ（この端末だけ）"))
                } else if cloud.lastError != nil {
                    Text(L("つながりません"))
                } else if let sync = cloud.lastSync {
                    Text(LF("つながっています（{t}）", ["t": sync.formatted(date: .omitted, time: .shortened)]))
                } else {
                    Text(L("つないでいます…"))
                }
            }
            .foregroundStyle(.secondary)
            .font(.subheadline)
        }
    }
}
