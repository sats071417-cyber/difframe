import SwiftUI

/// サーバーから届いた、ほかの人の投稿のカード（友達・みんな の両方で使う）
struct CloudPostCard: View {
    let post: CloudPost
    @State private var profileCode: CodeTarget? = nil
    @State private var shareOpen = false
    @State private var mapOpen = false
    /// 友達として見ているか（友達からのコメントは、いつでも受け付ける）
    var asFriend = false
    let onComment: (CommentTarget) -> Void

    private var commentsOn: Bool { asFriend || !post.commentsOff }

    private var target: CommentTarget {
        CommentTarget(id: post.id, owner: post.name.isEmpty ? L("ユーザー") : post.name,
                      caption: post.caption, image: post.photo, front: post.front, cloudID: post.id)
    }

    private func openProfile() {
        if !post.code.isEmpty { profileCode = CodeTarget(id: post.code) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                // アイコンと名前を押すと、その人のプロフィール
                Circle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay(Text(String((post.name.isEmpty ? post.handle : post.name).prefix(1)))
                        .font(.system(.subheadline, design: .rounded).bold())
                        .foregroundStyle(.white))
                    .onTapGesture(perform: openProfile)
                VStack(alignment: .leading, spacing: 1) {
                    Text(post.name.isEmpty ? L("ユーザー") : post.name)
                        .font(.subheadline.weight(.black)).lineLimit(1)
                        .onTapGesture(perform: openProfile)
                    HStack(spacing: 4) {
                        Text(LF("現地 {t}", ["t": post.localTime]))
                        // 場所を押すと、大まかな地図が開く
                        if let city = post.city, !city.isEmpty {
                            Button { mapOpen = true } label: {
                                Label { CityText(city: city, latitude: post.latitude, longitude: post.longitude) } icon: { Image(systemName: "mappin") }
                                    .labelStyle(.titleAndIcon).foregroundStyle(Hi.neon)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .font(.caption).foregroundStyle(Hi.dim).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let elapsed = post.elapsed {
                    DotText(text: TimeFormat.string(elapsed), pitch: 3, color: Hi.neon)
                }
            }

            Group {
                if let photo = post.photo {
                    DualPhotoView(main: photo, inset: post.front)
                } else {
                    PromptArtView(prompt: post.prompt)
                }
            }
            .aspectRatio(PhotoShape.ratio, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(post.alt ?? L(post.prompt))
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
                TranslateLine(text: caption)
            }
            CommentLine(postID: post.id, allowComments: commentsOn, cloudID: post.id) { onComment(target) }
        }
        .fullScreenCover(item: $profileCode) { PersonProfileSheet(code: $0.id) }
        .fullScreenCover(isPresented: $mapOpen) {
            LocationMapSheet(city: post.city ?? "", latitude: post.latitude, longitude: post.longitude, photo: post.photo)
        }
        .fullScreenCover(isPresented: $shareOpen) { ShareToDMSheet(post: post) }
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
                    Text(LF("つながっています（{t}）", ["t": sync.appFormatted(date: .omitted, time: .shortened)]))
                } else {
                    Text(L("つないでいます…"))
                }
            }
            .foregroundStyle(.secondary)
            .font(.subheadline)
        }
    }
}
