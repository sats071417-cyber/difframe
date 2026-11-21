import SwiftUI

/// 毎朝の「今日の10枚」：世界の公開投稿から、ランダムに10枚（同じ日は、同じ10枚）。
/// 今日の投稿が10枚に足りない朝は、昨日の公開投稿で埋める。
@MainActor
final class MorningPickup: ObservableObject {
    static let shared = MorningPickup()

    @Published private(set) var posts: [CloudPost] = []
    @Published var show = false
    private var loadedAt: Date?

    func refresh(force: Bool = false) async {
        if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < 600, !posts.isEmpty { return }
        let now = Date()
        let today = PostStore.dayKey(for: now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now).map(PostStore.dayKey(for:))
        var picks = Self.pick(from: await CloudSync.shared.pickupPool(day: today), seed: today)
        if picks.count < 10, let yesterday {
            let ids = Set(picks.map(\.id))
            let more = Self.pick(from: await CloudSync.shared.pickupPool(day: yesterday), seed: yesterday).filter { !ids.contains($0.id) }
            picks += more.prefix(10 - picks.count)
        }
        posts = picks
        loadedAt = now
    }

    private static func pick(from pool: [CloudPost], seed day: String) -> [CloudPost] {
        // 日付の文字から乱数の種を作る（起動のたびに変わる hashValue は使わない）
        var seed: UInt64 = 1469598103934665603
        for b in day.utf8 { seed = (seed ^ UInt64(b)) &* 1099511628211 }
        var rng = SeededGenerator(state: seed)
        let ordered = pool.filter { $0.photo != nil }.sorted { $0.id < $1.id }
        return Array(ordered.shuffled(using: &rng).prefix(10))
    }
}

/// 「今日の10枚」の画面。写真を押すと、その投稿を開く
struct MorningPickupSheet: View {
    @ObservedObject var pickup: MorningPickup
    let onOpen: (CloudPost) -> Void
    @Environment(\.dismiss) private var dismiss

    /// 上のタイルの色：その日のお題の色（あざやかなもの）に、写真の色を少し混ぜる
    private var heroColors: [Color] {
        let palette = GlowPalette.forPrompt(pickup.posts.first?.prompt ?? "")
        let photo = pickup.posts.first?.photo.map { DominantColor.of($0, key: $0.description) }
        return [palette.top, palette.left, photo ?? palette.right]
    }

    var body: some View { bodyContent.edgeSwipeBack() }

    private var bodyContent: some View {
        GeometryReader { geo in
            let top = geo.safeAreaInsets.top
            ZStack(alignment: .topLeading) {
                ScrollView {
                    VStack(spacing: 14) {
                        // 画面の上から始まる、長いタイル：お題の色が、やわらかく混ざって光る
                        ZStack(alignment: .bottomLeading) {
                            SoftGradient(colors: heroColors, corner: 0, rim: false)
                            // 状態バーの文字が、明るい色でも読めるように
                            LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                                .frame(height: top + 90).frame(maxHeight: .infinity, alignment: .top)
                            HStack(alignment: .bottom) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(L("今日の10枚")).font(.system(size: 40, weight: .black)).foregroundStyle(.white)
                                    Text(L("世界の公開投稿から、ランダムに選びました"))
                                        .font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
                                }
                                Spacer(minLength: 8)
                                if !pickup.posts.isEmpty {
                                    Text("\(pickup.posts.count)/10").font(.footnote.weight(.black).monospacedDigit()).foregroundStyle(.white)
                                        .padding(.horizontal, 12).frame(height: 30)
                                        .background(Capsule().fill(Color.black.opacity(0.28)))
                                }
                            }
                            .padding(.horizontal, 22).padding(.bottom, 26)
                        }
                        .frame(height: top + 300)
                        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 44, bottomTrailingRadius: 44, style: .continuous))
                        .overlay(alignment: .bottom) {
                            // 下の丸い縁だけ、白く光る
                            UnevenRoundedRectangle(bottomLeadingRadius: 44, bottomTrailingRadius: 44, style: .continuous)
                                .stroke(LinearGradient(colors: [.clear, .white.opacity(0.55)], startPoint: .center, endPoint: .bottom), lineWidth: 1.6)
                        }

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(pickup.posts) { post in
                                tile(post)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onOpen(post) }   // 小さい写真の上は、入れ替え。それ以外は、投稿を開く
                                    .accessibilityAddTraits(.isButton)
                                    .riseIn()
                            }
                        }
                        .padding(.horizontal, 16).padding(.bottom, 30)
                    }
                }
                .ignoresSafeArea(edges: .top)
                // 戻るボタンは、スクロールしても、いつも左上に
                Button { pickup.show = false; dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .black)).foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.black.opacity(0.35)))
                        .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("戻る"))
                .padding(.leading, 16).padding(.top, 6)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func tile(_ post: CloudPost) -> some View {
        let tint = post.photo.map { DominantColor.of($0, key: $0.description) } ?? .purple
        return ZStack(alignment: .bottomLeading) {
            // 投稿と同じ2枚の写真：小さい写真を押すと、大きい写真と入れ替わる
            if let photo = post.photo { DualPhotoView(main: photo, inset: post.front) } else { Hi.tile }
            VStack(alignment: .leading, spacing: 1) {
                Text(post.city?.isEmpty == false ? post.city! : "@" + post.handle)
                    .font(.caption.weight(.black)).foregroundStyle(.white).lineLimit(1)
                Text(L(post.prompt)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1.2))
        .shadow(color: tint.opacity(0.45), radius: 14, y: 6)
    }
}
