import SwiftUI

/// 初回に1度だけ出す、3画面の説明：通知が来る → 撮る → 世界で比べる。
/// 最後の画面で「はじめる」を押すと、通知の許可を聞く。
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private struct Page {
        let step: String
        let title: String
        let detail: String
        let palette: GlowPalette
    }

    private let pages: [Page] = [
        Page(step: "1", title: L("お題が届く"),
             detail: L("毎日1回、通知でお題が届きます。\\n通知が届いた瞬間から、タイムが始まります。"),
             palette: .forPrompt(L("空"))),
        Page(step: "2", title: L("撮る"),
             detail: L("お題のものを、アプリのカメラで撮ります。\\n遅れてもOK。1日に3枚まで投稿できます。"),
             palette: .forPrompt(L("車"))),
        Page(step: "3", title: L("世界で比べる"),
             detail: L("同じお題を、世界の人はいつ、どう撮った？\\n地図とタイムラインで見て、時間帯ごとのタイムを競います。"),
             palette: .forPrompt(L("窓"))),
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GlowBackground(palette: pages[page].palette, focus: UnitPoint(x: 0.5, y: 0.34))
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: page)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if page < pages.count - 1 {
                        Button(L("スキップ")) { onFinish() }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.black.opacity(0.7))
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .background(Capsule().fill(Color.white.opacity(0.55)))
                    }
                }
                .padding(.horizontal, 20)
                .frame(height: 56)

                Spacer(minLength: 0)
                illustration
                    .frame(height: 220)
                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    EmptyView()
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color.black.opacity(0.6))
                    Text(pages[page].title)
                        .font(.system(size: 40, weight: .black))
                        .foregroundStyle(Color.black.opacity(0.85))
                    Text(pages[page].detail.replacingOccurrences(of: "\\n", with: "\n"))
                        .font(.body.weight(.bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.black.opacity(0.75))
                        .padding(.horizontal, 28)
                }
                .id(page)
                .transition(.opacity)

                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Color.black.opacity(0.85) : Color.black.opacity(0.25))
                            .frame(width: index == page ? 24 : 8, height: 8)
                    }
                }
                .padding(.top, 22)
                .accessibilityHidden(true)

                Button {
                    if page < pages.count - 1 {
                        withAnimation { page += 1 }
                    } else {
                        onFinish()
                    }
                } label: {
                    Text(page < pages.count - 1 ? L("次へ") : L("はじめる"))
                }
                .buttonStyle(NeonButtonStyle())
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -40, page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else if value.translation.width > 40, page > 0 {
                    withAnimation { page -= 1 }
                }
            }
        )
    }

    /// 画面ごとの絵
    @ViewBuilder
    private var illustration: some View {
        switch page {
        case 0:
            // 通知のカード
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Hi.neon)
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: "camera.fill").foregroundStyle(Hi.onNeon))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Difframe")).font(.subheadline.weight(.black))
                    Text(L("今日のお題が届きました。")).font(.footnote)
                }
                Spacer()
                Text(L("いま")).font(.caption).foregroundStyle(Hi.dim)
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(Color.black.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 28)
        case 1:
            // シャッターと、ドットのタイム
            VStack(spacing: 16) {
                DotText(text: "0:12.4", pitch: 6, color: Color.black.opacity(0.8))
                ZStack {
                    Circle().stroke(Hi.neon, lineWidth: 6).frame(width: 96, height: 96)
                    Circle().fill(.white).frame(width: 78, height: 78)
                }
                .background(Circle().fill(Color.black.opacity(0.85)).frame(width: 108, height: 108))
            }
        default:
            // 世界のあいさつ
            HStack(spacing: 10) {
                ForEach(["🇯🇵", "🇫🇷", "🇧🇷", "🇦🇺"], id: \.self) { flag in
                    VStack(spacing: 6) {
                        Text(flag).font(.system(size: 34))
                        Text([L("やあ"), "Salut", "Oi", "G'day"][["🇯🇵", "🇫🇷", "🇧🇷", "🇦🇺"].firstIndex(of: flag) ?? 0])
                            .font(.caption.weight(.black))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 70, height: 96)
                    .background(Color.black.opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
        }
    }
}
