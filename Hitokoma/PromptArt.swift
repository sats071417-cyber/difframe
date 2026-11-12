import SwiftUI

/// お題に合わせたアイコンと色（サンプル投稿の「写真」の代わりに表示する絵）
enum PromptArt {
    private static let symbols: [String: String] = [
        L("硬貨"): "dollarsign.circle.fill", L("お札"): "banknote.fill", L("財布"): "wallet.pass.fill",
        L("時計"): "clock.fill", L("鍵"): "key.fill", L("傘"): "umbrella.fill", L("鞄"): "bag.fill",
        L("リュック"): "backpack.fill", L("本"): "book.fill", L("ペン"): "pencil", L("手紙"): "envelope.fill",
        L("写真"): "photo.fill", L("カード"): "creditcard.fill", L("バス"): "bus.fill", L("車"): "car.fill",
        L("自転車"): "bicycle", L("地図"): "map.fill", L("郵便ポスト"): "envelope.badge.fill",
        L("信号機"): "light.beacon.max.fill", L("新聞"): "newspaper.fill", L("眼鏡"): "eyeglasses",
        L("イヤホン"): "earbuds", L("スマホ"): "iphone", L("充電器"): "battery.100.bolt",
        L("ゴミ箱"): "trash.fill", L("絆創膏"): "bandage.fill", L("ボタン"): "circle.grid.2x2.fill",
        L("電池"): "battery.100", L("ノート"): "note.text", L("消しゴム"): "eraser.fill",
        L("花"): "leaf.fill", L("葉っぱ"): "leaf.fill", L("雲"): "cloud.fill", L("光"): "sun.max.fill",
        L("影"): "moon.fill", L("雪"): "snowflake", L("火"): "flame.fill", L("水"): "drop.fill",
        L("電球"): "lightbulb.fill", L("家"): "house.fill", L("ギフト"): "gift.fill", L("箱"): "shippingbox.fill",
        L("ケーキ"): "birthday.cake.fill", L("コーヒー"): "cup.and.saucer.fill", L("ジュース"): "takeoutbag.and.cup.and.straw.fill",
        L("道路"): "road.lanes", L("看板"): "signpost.right.fill", L("切手"): "tag.fill", L("ハサミ"): "scissors",
        L("定規"): "ruler.fill", L("絵筆"): "paintbrush.fill", L("靴"): "figure.walk", L("帽子"): "crown.fill",
        L("マスク"): "lungs.fill", L("手袋"): "hand.raised.fill", L("Tシャツ"): "tshirt.fill", L("ハンガー"): "hanger",
    ]

    /// お題に合うアイコン（無ければカメラ）
    static func symbol(for prompt: String) -> String {
        symbols[prompt] ?? "camera.fill"
    }
}

/// 写真の代わりに表示する、お題のアイコンの絵
struct PromptArtView: View {
    let prompt: String
    var iconScale: CGFloat = 0.42

    var body: some View {
        GeometryReader { geo in
            ZStack {
                GlowBackground(palette: .forPrompt(prompt), focus: .center)
                Image(systemName: PromptArt.symbol(for: prompt))
                    .font(.system(size: min(geo.size.width, geo.size.height) * iconScale, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.8))
            }
        }
    }
}
