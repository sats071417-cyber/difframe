import SwiftUI
import UIKit

/// 「友達になろう」を呼びかける、縦長の1枚（1080×1920）。ストーリーなどに上げられる。
/// 名前・ハンドル名・QRコード・友達コードを入れる。投稿の共有カードと同じ作り方。
struct FriendInviteCardView: View {
    let name: String
    let handle: String
    let code: String
    let avatar: UIImage?
    let qr: UIImage?

    var body: some View {
        ZStack {
            GlowBackground(palette: .forColor(.purple), focus: .center)
            VStack(spacing: 0) {
                HStack {
                    Text("Difframe").font(.system(size: 58, weight: .black))
                    Spacer()
                    Image(systemName: "camera.fill").font(.system(size: 54, weight: .black))
                }

                Spacer(minLength: 40)

                Text(L("友達になろう"))
                    .font(.system(size: 168, weight: .black))
                    .lineLimit(2)
                    .minimumScaleFactor(0.4)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.25), radius: 24)
                Text(L("同じお題を、同じ時間に撮る。"))
                    .font(.system(size: 54, weight: .bold))
                    .opacity(0.9)
                    .padding(.top, 18)

                Spacer(minLength: 56)

                // 白い台紙：名前とQRコード
                VStack(spacing: 40) {
                    HStack(spacing: 34) {
                        avatarView
                        VStack(alignment: .leading, spacing: 6) {
                            Text(name)
                                .font(.system(size: 66, weight: .black))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            Text("@" + handle)
                                .font(.system(size: 44, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.5))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                        Spacer(minLength: 0)
                    }
                    if let qr {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 600, height: 600)
                    }
                }
                .foregroundStyle(Color.black)
                .padding(56)
                .background(RoundedRectangle(cornerRadius: 76, style: .continuous).fill(Color.white))
                .shadow(color: .black.opacity(0.3), radius: 40, y: 18)

                Spacer(minLength: 48)

                Text(L("QRコードを読み取ると、友達に追加できます"))
                    .font(.system(size: 46, weight: .bold))
                    .multilineTextAlignment(.center)
                    .opacity(0.95)
                Text(code)
                    .font(.system(size: 52, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 36).padding(.vertical, 14)
                    .background(Capsule().fill(Color.black.opacity(0.28)))
                    .padding(.top, 22)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 84)
            .padding(.vertical, 96)
        }
        .frame(width: 1080, height: 1920)
    }

    @ViewBuilder
    private var avatarView: some View {
        if let avatar {
            Image(uiImage: avatar)
                .resizable()
                .scaledToFill()
                .frame(width: 150, height: 150)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Hi.neon)
                .frame(width: 150, height: 150)
                .overlay(Text(String(name.prefix(1)))
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundStyle(Hi.onNeon))
        }
    }
}

enum FriendInviteCard {
    /// 自分の情報から、共有用の画像を作る
    @MainActor
    static func make(name: String, handle: String, code: String, avatar: UIImage?) -> UIImage? {
        let view = FriendInviteCardView(
            name: name, handle: handle, code: code, avatar: avatar,
            qr: FriendCode.qrImage(for: FriendCode.shareURL, size: 700))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.uiImage
    }
}

/// 友達追加の画面。左右にスワイプして、相手のQRを読み取る ⇄ 友達追加カード ⇄ 自分の大きなQRコード
struct FriendInviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("myName") private var myName: String = L("あなた")
    @AppStorage("myHandle") private var myHandle: String = ""
    @State private var card: UIImage? = nil
    @State private var showShare = false
    @State private var message: String? = nil
    /// 0: 読み取り、1: 友達追加カード（最初に出る）、2: 大きなQRコード
    @State private var page = 1
    @State private var scanned: CodeTarget? = nil

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                scanPage.tag(0)
                cardPage.tag(1)
                qrPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(titleForPage)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("閉じる")) { dismiss() } }
            }
        }
        .presentationBackground(.black)
        .preferredColorScheme(.dark)
        .task {
            card = FriendInviteCard.make(name: myName, handle: MyProfile.handle(myHandle),
                                         code: FriendCode.myID, avatar: Avatar.load())
        }
        .sheet(isPresented: $showShare) {
            if let card { ActivitySheet(items: [card]) }
        }
        .sheet(item: $scanned) { target in
            PersonProfileSheet(code: target.id, canAdd: true)
        }
    }

    private var titleForPage: String {
        switch page {
        case 0: return L("相手のQRコードを読み取る")
        case 2: return L("自分のQRコード")
        default: return L("友達追加カード")
        }
    }

    /// 読み取り：このページを開いている間だけカメラを動かす
    private var scanPage: some View {
        ZStack {
            if page == 0 {
                QRScannerView { value in
                    guard let id = FriendCode.parse(value) else { return }
                    scanned = CodeTarget(id: id)
                }
                .ignoresSafeArea()
            } else {
                Color.black
            }
            VStack {
                Spacer()
                Text(L("相手のQRコードを読み取ると、友達追加できます"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .padding(.bottom, 40)
            }
        }
    }

    private var cardPage: some View {
        VStack(spacing: 16) {
            if let card {
                Image(uiImage: card)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
                    .padding(.horizontal, 36)
                    .accessibilityLabel(L("友達追加カード"))
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }

            Button { showShare = true } label: {
                Label(L("ストーリーなどで共有"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(NeonButtonStyle())
            .disabled(card == nil)

            HStack(spacing: 10) {
                Button {
                    guard let card else { return }
                    ShareCard.saveToLibrary(card) { message = $0 }
                } label: {
                    Label(L("写真に保存"), systemImage: "arrow.down.to.line")
                }
                .buttonStyle(TileButtonStyle())
                .disabled(card == nil)

                ShareLink(item: FriendCode.shareURL) {
                    Label(L("リンクを送る"), systemImage: "link")
                }
                .buttonStyle(TileButtonStyle())
            }

            if let message {
                Text(message).font(.caption).foregroundStyle(Hi.dim).multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 大きなQRコード（相手のカメラで読み取ってもらう）
    private var qrPage: some View {
        VStack(spacing: 24) {
            Spacer()
            if let qr = FriendCode.qrImage(for: FriendCode.shareURL, size: 800) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 300, height: 300)
                    .padding(24)
                    .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.white))
            }
            Text(FriendCode.myID)
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .foregroundStyle(.white)
                .textSelection(.enabled)
            Text(L("相手にこの画面を読み取ってもらうと、友達追加できます"))
                .font(.footnote).foregroundStyle(Hi.dim).multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
