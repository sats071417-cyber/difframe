import SwiftUI
import UIKit
import Photos

/// 自分の投稿を、ストーリーなどに上げられる縦長の1枚にする（1080×1920）。
/// お題・タイム・写真・アプリ名・日付を入れる。
struct ShareCardView: View {
    let prompt: String
    let photo: UIImage
    let inset: UIImage?
    let time: String?
    let caption: String?
    let handle: String
    let dateText: String

    var body: some View {
        ZStack {
            GlowBackground(palette: .forPrompt(prompt), focus: .center)
            VStack(spacing: 44) {
                HStack {
                    Text("Difframe")
                        .font(.system(size: 54, weight: .black))
                    Spacer()
                    Text(dateText)
                        .font(.system(size: 38, weight: .bold))
                }
                Text(prompt)
                    .font(.system(size: 112, weight: .black))
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.35), radius: 10)

                ZStack(alignment: .topTrailing) {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 840, height: 1120)
                        .clipShape(RoundedRectangle(cornerRadius: 64, style: .continuous))
                    if let inset {
                        Image(uiImage: inset)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 250, height: 333)
                            .clipShape(RoundedRectangle(cornerRadius: 52, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 52, style: .continuous).stroke(Color.black.opacity(0.7), lineWidth: 6))
                            .padding(30)
                    }
                }

                if let time {
                    DotText(text: time, pitch: 12, color: Hi.neon)
                }
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 46, weight: .bold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                Spacer(minLength: 0)
                Text("@" + handle)
                    .font(.system(size: 40, weight: .heavy))
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(60)
        }
        .frame(width: 1080, height: 1920)
    }
}

enum ShareCard {
    /// 投稿から、共有用の画像を作る
    @MainActor
    static func make(record: PromptRecord, photo: UIImage, inset: UIImage?, handle: String) -> UIImage? {
        let date = record.postedAt?.formatted(date: .abbreviated, time: .omitted) ?? record.dayKey
        let view = ShareCardView(
            prompt: L(record.prompt),
            photo: photo,
            inset: inset,
            time: record.elapsed.map { TimeFormat.string($0) },
            caption: record.caption,
            handle: handle.isEmpty ? L("あなた") : handle,
            dateText: date
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.uiImage
    }

    /// 写真アプリに保存する。結果は (成功, 文言) で返す
    static func saveToLibrary(_ image: UIImage, completion: @escaping (String) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(L("写真へのアクセスが許可されていません。設定アプリで、Difframeの写真への追加を許可してください。")) }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { ok, _ in
                DispatchQueue.main.async {
                    completion(ok ? L("カメラロールに保存しました") : L("保存できませんでした"))
                }
            }
        }
    }
}

/// 共有シート（インスタのストーリーなど、アプリを選べる）
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
