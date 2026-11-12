import UIKit
@preconcurrency import Vision

/// 写真がお題に合っているかを、iPhoneの画像認識で確かめる。
/// 画像認識の結果（iPhoneが持つ約1300種の言葉）の中に、お題に対応する言葉が入っていれば「合っている」とする。
/// 言葉は完全に一致したものだけを数える（「key」が「keyboard」に当たるような部分一致はしない）。
/// 画像認識の言葉にないお題（切手、手、色、形など）は、確かめられないので「不明」にする。
enum PromptVerifier {
    enum Result {
        case matched        // お題に合っている
        case notMatched     // お題と違うかもしれない
        case unknown        // このお題は確かめられない
    }

    /// お題ごとに、画像認識の結果に入っていれば合っているとみなす言葉（iPhoneの認識リストにある名前そのまま）
    /// お題ごとに、画像認識の結果に入っていれば合っているとみなす言葉（iPhoneの認識リストにある名前そのまま）
    private static let keywords: [String: [String]] = PromptCatalog.labels

    /// このお題は自動で確かめられるか（ランキングの対象になれるか）
    static func canVerify(_ prompt: String) -> Bool {
        keywords[prompt] != nil || PromptCatalog.colors[prompt] != nil
    }

    /// 写真を画像認識して、お題に合うかを返す
    static func verify(_ image: UIImage, prompt: String) async -> Result {
        // 色のお題は、画像認識ではなく、写真の色の割合で確かめる
        if let color = PromptCatalog.colors[prompt] {
            guard let cgImage = image.cgImage else { return .unknown }
            return await Task.detached(priority: .userInitiated) {
                ColorMatcher.matches(cgImage, color: color) ? Result.matched : Result.notMatched
            }.value
        }
        guard let words = keywords[prompt], let cgImage = image.cgImage else { return .unknown }
        let wordSet = Set(words)
        return await withCheckedContinuation { continuation in
            let request = VNClassifyImageRequest { request, _ in
                let observations = (request.results as? [VNClassificationObservation]) ?? []
                let found = observations.prefix(15).contains { observation in
                    observation.confidence >= 0.05 && wordSet.contains(observation.identifier.lowercased())
                }
                continuation.resume(returning: found ? .matched : .notMatched)
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgOrientation(image.imageOrientation))
            // 画像認識は重いので、画面を止めないよう、別のスレッドで行う
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: .unknown)
                }
            }
        }
    }

    private static func cgOrientation(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}


/// 写真の色を数えて、色のお題に合うかを確かめる。
/// 写真を小さくして、画素ごとに色相・彩度・明るさを調べ、お題の色の画素が一定の割合以上あれば「合っている」とする。
/// 画像認識（Vision）ではなく、色の計算。背景に同じ色が広がっていても合格になる。
enum ColorMatcher {
    static func matches(_ image: CGImage, color: ColorName) -> Bool {
        let size = 48
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let context = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        var hits = 0
        for i in 0..<(size * size) {
            let r = Double(pixels[i * 4]) / 255, g = Double(pixels[i * 4 + 1]) / 255, b = Double(pixels[i * 4 + 2]) / 255
            if classify(r, g, b) == color { hits += 1 }
        }
        let share = Double(hits) / Double(size * size)
        let needed: Double = (color == .white || color == .black) ? 0.3 : 0.2
        return share >= needed
    }

    /// 1つの画素がどの色か（どれでもなければ nil）
    static func classify(_ r: Double, _ g: Double, _ b: Double) -> ColorName? {
        let maxV = max(r, g, b), minV = min(r, g, b)
        let delta = maxV - minV
        let v = maxV
        let s = maxV == 0 ? 0 : delta / maxV
        if v < 0.15 { return .black }
        if s < 0.12 { return v > 0.85 ? .white : nil }
        var h: Double
        if delta == 0 { h = 0 }
        else if maxV == r { h = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
        else if maxV == g { h = 60 * ((b - r) / delta + 2) }
        else { h = 60 * ((r - g) / delta + 4) }
        if h < 0 { h += 360 }
        // 薄い赤〜赤紫はピンク
        if s >= 0.15 && s < 0.55 && v >= 0.75 && (h >= 315 || h < 15) { return .pink }
        if s < 0.3 { return nil }
        // 暗いオレンジ〜黄は茶色
        if h >= 10 && h < 45 && v < 0.6 { return .brown }
        if v < 0.25 { return nil }
        switch h {
        case 0..<15, 345..<360: return .red
        case 15..<40: return .orange
        case 40..<70: return .yellow
        case 70..<170: return .green
        case 170..<260: return .blue
        case 260..<300: return .purple
        case 300..<345: return .pink
        default: return nil
        }
    }
}
