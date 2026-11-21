import SwiftUI
import Vision
import NaturalLanguage
import Translation

// MARK: - 写真の説明（端末の中の画像認識。写真は外へ出さない）

/// 写真に写っているものを、お題の言葉で短く言う。ひとことの候補と、目の不自由な人への読み上げに使う
enum PhotoDescriber {
    /// 画像認識の言葉 → お題の言葉
    private static let reverse: [String: String] = {
        var map: [String: String] = [:]
        for (prompt, words) in PromptCatalog.labels {
            for word in words where map[word] == nil { map[word] = prompt }
        }
        return map
    }()

    /// 写っているもの（その言語の名前）。最大 limit 個。分からないときは空
    static func objects(in image: UIImage, limit: Int = 3) async -> [String] {
        guard let cg = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNClassifyImageRequest()
                let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation)
                guard (try? handler.perform([request])) != nil else { continuation.resume(returning: []); return }
                var names: [String] = []
                for o in (request.results ?? []).prefix(25) where o.confidence >= 0.2 {
                    if let prompt = reverse[o.identifier.lowercased()], !names.contains(prompt) { names.append(prompt) }
                    if names.count == limit { break }
                }
                continuation.resume(returning: names)
            }
        }
    }

    /// 読み上げ用の説明文（例：「写真：猫、ソファ」）
    static func altText(for image: UIImage) async -> String? {
        let names = await objects(in: image)
        guard !names.isEmpty else { return nil }
        return LF("写真：{a}", ["a": names.map { L($0) }.joined(separator: "、")])
    }
}

private extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// 投稿の前に出す、「写っているもの」のひとこと候補
struct CaptionSuggestion: View {
    let image: UIImage?
    @Binding var caption: String
    @State private var names: [String] = []

    var body: some View {
        Group {
            if !names.isEmpty && caption.isEmpty {
                Button { caption = names.map { L($0) }.joined(separator: "・") } label: {
                    Label(names.map { L($0) }.joined(separator: "・"), systemImage: "sparkles")
                        .font(.subheadline.weight(.bold)).lineLimit(1)
                        .padding(.horizontal, 14).frame(height: 36)
                        .background(Capsule().fill(Hi.tile))
                        .foregroundStyle(Hi.neon)
                }
                .buttonStyle(.plain)
                .accessibilityHint(L("ひとことに入れる"))
            }
        }
        .task(id: image.map { ObjectIdentifier($0) }) {
            guard let image else { names = []; return }
            names = await PhotoDescriber.objects(in: image)
        }
    }
}

// MARK: - 翻訳（端末の中。文章は外へ出さない）

/// 文章の下に出す「翻訳」。自分の言語と同じ文章には出さない。iOS 18 以上
struct TranslateLine: View {
    let text: String
    var body: some View {
        if #available(iOS 18.0, *), Self.needsTranslation(text) {
            TranslateLine18(text: text)
        }
    }

    /// 自分の言語と違う言語で書かれているか
    static func needsTranslation(_ text: String) -> Bool {
        guard text.count >= 2 else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let lang = recognizer.dominantLanguage?.rawValue else { return false }
        let mine = AppLanguage.current.rawValue
        return !lang.hasPrefix(mine)
    }
}

@available(iOS 18.0, *)
private struct TranslateLine18: View {
    let text: String
    @State private var configuration: TranslationSession.Configuration?
    @State private var result: String?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let result {
                Text(result).font(.subheadline).foregroundStyle(Hi.neon)
                Button(L("原文を見る")) { self.result = nil }.font(.caption2.weight(.bold)).foregroundStyle(Hi.dim)
            } else {
                Button { start() } label: {
                    Label(failed ? L("翻訳できませんでした") : L("翻訳"), systemImage: "translate")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(failed ? Hi.dim : Hi.neon)
                .disabled(failed)
            }
        }
        .buttonStyle(.plain)
        .translationTask(configuration) { session in
            do {
                let response = try await session.translate(text)
                await MainActor.run { result = response.targetText }
            } catch {
                await MainActor.run { failed = true }
            }
        }
    }

    private func start() {
        let target = Locale.Language(identifier: AppLanguage.current == .zh ? "zh-Hans" : AppLanguage.current.rawValue)
        configuration = TranslationSession.Configuration(source: nil, target: target)
        configuration?.invalidate()
    }
}
