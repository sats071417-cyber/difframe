import SwiftUI
import UIKit

// MARK: - やわらかく光るグラデーション（ぼかした色を重ねた、縁が光るタイル）

struct SoftGradient: View {
    let colors: [Color]
    var corner: CGFloat = 26
    var rim = true      // 縁の白い光（上の大きなタイルでは、自分で付けるので、false）

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let m = min(w, h)
            let c = colors.isEmpty ? [Color.purple] : colors
            ZStack {
                c[0].opacity(0.9)
                Circle().fill(c[min(1, c.count - 1)]).frame(width: m * 0.9, height: m * 0.9)
                    .offset(x: -w * 0.28, y: h * 0.22).blur(radius: m * 0.22)
                Circle().fill(c[min(2, c.count - 1)]).frame(width: m * 0.8, height: m * 0.8)
                    .offset(x: w * 0.3, y: -h * 0.2).blur(radius: m * 0.22)
                Ellipse().fill(Color.black.opacity(0.65)).frame(width: w * 0.7, height: h * 0.36)
                    .offset(y: -h * 0.3).blur(radius: m * 0.2)
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay {
                // 縁だけ、白く光る
                if rim { RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.08), .white.opacity(0.4)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.6)
                    .blur(radius: 0.6) }
            }
        }
    }
}

// MARK: - 写真の代表の色

enum DominantColor {
    private static let cache = NSCache<NSString, UIColor>()

    /// 写真の平均の色を、少し鮮やかに・明るくしたもの
    static func of(_ image: UIImage, key: String? = nil) -> Color {
        let cacheKey = (key ?? "\(ObjectIdentifier(image).hashValue)") as NSString
        if let hit = cache.object(forKey: cacheKey) { return Color(hit) }
        var pixel = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let color: UIColor
        if let cg = image.cgImage,
           let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
                .getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            color = UIColor(hue: h, saturation: min(1, s * 1.25 + 0.1), brightness: max(0.6, min(1, b * 1.3)), alpha: 1)
        } else {
            color = UIColor.systemPurple
        }
        cache.setObject(color, forKey: cacheKey)
        return Color(color)
    }
}

// MARK: - スクロールに合わせた動き（Apple の製品ページのように）

/// スクロール量を、上の画面へ伝える（タイムラインの見出しを縮めるのに使う）
struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// スクロールの中身の先頭に置く目印。どれだけ動いたかを、tag で伝える
    func reportScroll(tag: Int, space: String = "feedScroll") -> some View {
        background(alignment: .top) {
            GeometryReader { geo in
                Color.clear.preference(key: ScrollOffsetKey.self, value: [tag: geo.frame(in: .named(space)).minY])
            }
            .frame(height: 0)
        }
    }

    /// 下から上がってくるように、ふわっと現れる（画面の下から入るとき）
    func riseIn() -> some View {
        scrollTransition(.animated(.easeOut(duration: 0.4)).threshold(.visible(0.1))) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0)
                .offset(y: phase == .bottomTrailing ? 44 : 0)
                .scaleEffect(phase.isIdentity ? 1 : 0.96)
        }
    }

    /// 画面に入るとき、少し暗く・小さく・ぼかしてから、ふわっと現れる（出ていくときも同じ）
    func scrollFade() -> some View {
        scrollTransition(.animated(.easeOut(duration: 0.35)).threshold(.visible(0.15))) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.2)
                .scaleEffect(phase.isIdentity ? 1 : 0.95)
                .blur(radius: phase.isIdentity ? 0 : 4)
        }
    }
}

/// 横に並ぶカードの下の、細長い現在位置の表示（いまの点だけが長くなる）
struct PillIndicator: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Color.white : Color.white.opacity(0.3))
                    .frame(width: i == index ? 22 : 6, height: 6)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Capsule().fill(Color.white.opacity(0.1)))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: index)
    }
}


// MARK: - スクロールで、大きな見出しが小さくなる

struct SheetScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

extension View {
    /// スクロールの量を測る（ScrollView の中身につける。ScrollView には `.coordinateSpace(name: "sheetScroll")`）
    func trackSheetScroll(_ offset: Binding<CGFloat>) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: SheetScrollOffsetKey.self, value: -g.frame(in: .named("sheetScroll")).minY)
        })
        .onPreferenceChange(SheetScrollOffsetKey.self) { offset.wrappedValue = $0 }
    }
}
