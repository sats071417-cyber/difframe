import SwiftUI

/// アプリ全体の色
enum Hi {
    static let neon = Color(red: 0.894, green: 1.0, blue: 0.102)
    static let onNeon = Color(red: 0.118, green: 0.137, blue: 0.0)
    static let tile = Color(red: 0.09, green: 0.09, blue: 0.11)
    static let dim = Color(red: 0.66, green: 0.65, blue: 0.71)
}

private func rgb(_ hex: UInt32) -> Color {
    Color(red: Double((hex >> 16) & 0xFF) / 255,
          green: Double((hex >> 8) & 0xFF) / 255,
          blue: Double(hex & 0xFF) / 255)
}

/// 光るカードの色の組み合わせ
struct GlowPalette {
    let top: Color
    let bottom: Color
    let left: Color
    let right: Color
    let halo: Color
    let core: Color

    private static let promptPalettes: [GlowPalette] = [
        GlowPalette(top: rgb(0xB3124F), bottom: rgb(0xF0506E), left: rgb(0x8A3DFF), right: rgb(0x19D3C5), halo: rgb(0xFFC27A), core: rgb(0xFFF6DC)),
        GlowPalette(top: rgb(0x1A2BC4), bottom: rgb(0x3D7BFF), left: rgb(0xD63DFF), right: rgb(0x19E0B0), halo: rgb(0xA9D8FF), core: rgb(0xF2FBFF)),
        GlowPalette(top: rgb(0x0B6B55), bottom: rgb(0x22C08A), left: rgb(0x1E6BFF), right: rgb(0xE4FF1A), halo: rgb(0xC9FFB0), core: rgb(0xF8FFE6)),
        GlowPalette(top: rgb(0x5B16B8), bottom: rgb(0xB14BFF), left: rgb(0xFF3D8B), right: rgb(0x3DA5FF), halo: rgb(0xFFB8F0), core: rgb(0xFFF0FB)),
        GlowPalette(top: rgb(0xB83A00), bottom: rgb(0xFF8A1F), left: rgb(0xFF2D6B), right: rgb(0xFFD400), halo: rgb(0xFFD98A), core: rgb(0xFFF8E0)),
        GlowPalette(top: rgb(0x8C0F2E), bottom: rgb(0xE0264F), left: rgb(0xFF8A1F), right: rgb(0x6A3DFF), halo: rgb(0xFFB0A8), core: rgb(0xFFF1EC)),
    ]

    /// お題ごとに決まる色（同じお題なら、誰の画面でも同じ色）
    static func forPrompt(_ prompt: String) -> GlowPalette {
        if let color = PromptCatalog.colors[prompt] { return forColor(color) }
        let hash = prompt.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        return promptPalettes[abs(hash % promptPalettes.count)]
    }

    /// 色のお題の日の色（そのお題の色で、カードと画面を染める）
    static func forColor(_ color: ColorName) -> GlowPalette {
        switch color {
        case .red:    return GlowPalette(top: rgb(0x7A0010), bottom: rgb(0xE0262F), left: rgb(0xB3124F), right: rgb(0xFF5A3D), halo: rgb(0xFFB0A8), core: rgb(0xFFF1EC))
        case .orange: return GlowPalette(top: rgb(0x8A3A00), bottom: rgb(0xFF8A1F), left: rgb(0xFF5A1F), right: rgb(0xFFC400), halo: rgb(0xFFD98A), core: rgb(0xFFF8E0))
        case .yellow: return GlowPalette(top: rgb(0x8A6A00), bottom: rgb(0xF2C200), left: rgb(0xE8A800), right: rgb(0xFFF04A), halo: rgb(0xFFF3A0), core: rgb(0xFFFDE8))
        case .green:  return GlowPalette(top: rgb(0x0B5A2A), bottom: rgb(0x22B04A), left: rgb(0x0F8A3A), right: rgb(0x8AE03D), halo: rgb(0xC9FFB0), core: rgb(0xF4FFE8))
        case .blue:   return GlowPalette(top: rgb(0x0A2A9A), bottom: rgb(0x2F6BFF), left: rgb(0x1A3DD6), right: rgb(0x3DB8FF), halo: rgb(0xA9D8FF), core: rgb(0xF0F8FF))
        case .purple: return GlowPalette(top: rgb(0x3A0E8A), bottom: rgb(0x8A4DFF), left: rgb(0x5B16B8), right: rgb(0xC47AFF), halo: rgb(0xE0C8FF), core: rgb(0xF8F0FF))
        case .pink:   return GlowPalette(top: rgb(0x9A1050), bottom: rgb(0xFF4D8F), left: rgb(0xE0266F), right: rgb(0xFF9AC4), halo: rgb(0xFFC8E0), core: rgb(0xFFF0F6))
        case .white:  return GlowPalette(top: rgb(0x7C8391), bottom: rgb(0xE8EAEE), left: rgb(0xB8BDC6), right: rgb(0xFFFFFF), halo: rgb(0xFFFFFF), core: rgb(0xFFFFFF))
        case .black:  return GlowPalette(top: rgb(0x050506), bottom: rgb(0x2A2C33), left: rgb(0x101114), right: rgb(0x3A3D46), halo: rgb(0x6A6E78), core: rgb(0xA8ACB6))
        case .brown:  return GlowPalette(top: rgb(0x3A1E0A), bottom: rgb(0x8A5A2F), left: rgb(0x5C3317), right: rgb(0xB07A45), halo: rgb(0xE0B88A), core: rgb(0xFFF0DC))
        }
    }

    static func forRank(_ rank: Rank) -> GlowPalette {
        switch rank {
        case .bronze:
            return GlowPalette(top: rgb(0x4A2412), bottom: rgb(0xA8602F), left: rgb(0x6B2E12), right: rgb(0xC77A3A), halo: rgb(0xF0B98A), core: rgb(0xFFEBD8))
        case .silver:
            return GlowPalette(top: rgb(0x2A3040), bottom: rgb(0x7F8AA3), left: rgb(0x46506A), right: rgb(0x9AA8C4), halo: rgb(0xCFD8EA), core: rgb(0xF4F7FF))
        case .gold:
            return GlowPalette(top: rgb(0x7A3B00), bottom: rgb(0xD88A00), left: rgb(0x9A4A00), right: rgb(0xE8A800), halo: rgb(0xFFCF5A), core: rgb(0xFFF3C0))
        case .platinum:
            return GlowPalette(top: rgb(0x06505E), bottom: rgb(0x18B5C4), left: rgb(0x1E6BFF), right: rgb(0x3DF0D0), halo: rgb(0xA8F2F2), core: rgb(0xEFFFFF))
        case .diamond:
            return GlowPalette(top: rgb(0x10157A), bottom: rgb(0x4A52FF), left: rgb(0xB03DFF), right: rgb(0x3DB8FF), halo: rgb(0xC0C8FF), core: rgb(0xF4F5FF))
        }
    }
}

extension Rank {
    /// ランキングのカードの色
    var cardColors: [Color] {
        switch self {
        case .bronze: return [rgb(0x7B4A2E), rgb(0x33190C)]
        case .silver: return [rgb(0x5B6478), rgb(0x20242E)]
        case .gold: return [rgb(0xC98A00), rgb(0x4A2A00)]
        case .platinum: return [rgb(0x0E8C9B), rgb(0x06323A)]
        case .diamond: return [rgb(0x2B3BFF), rgb(0x0A1570)]
        }
    }
}

/// 光る背景。ぼかしを使わず、放射状の色を重ねて軽く描く。
struct GlowBackground: View {
    let palette: GlowPalette
    var focus: UnitPoint = UnitPoint(x: 0.5, y: 0.72)

    var body: some View {
        GeometryReader { geo in
            let r = max(geo.size.width, geo.size.height)
            ZStack {
                LinearGradient(colors: [palette.top, palette.bottom], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [palette.left, palette.left.opacity(0)],
                               center: .bottomLeading, startRadius: 0, endRadius: r * 0.62)
                RadialGradient(colors: [palette.right, palette.right.opacity(0)],
                               center: .bottomTrailing, startRadius: 0, endRadius: r * 0.5)
                RadialGradient(colors: [palette.core, palette.halo, palette.halo.opacity(0)],
                               center: focus, startRadius: 0, endRadius: r * 0.42)
            }
        }
    }
}

/// ドットで描く数字（ストップウォッチやポイント）
struct DotText: View {
    let text: String
    var pitch: CGFloat = 8
    var color: Color = .white

    private static let glyphs: [Character: [String]] = [
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
        ":": ["0", "0", "1", "0", "1", "0", "0"],
        ".": ["0", "0", "0", "0", "0", "0", "1"],
        "-": ["000", "000", "000", "111", "000", "000", "000"],
    ]

    private var glyphRows: [[String]] { text.compactMap { Self.glyphs[$0] } }

    private var columns: Int {
        let rows = glyphRows
        return rows.reduce(0) { $0 + ($1.first?.count ?? 0) } + max(0, rows.count - 1)
    }

    var body: some View {
        Canvas { context, _ in
            let size = pitch * 0.82
            var x = 0
            for glyph in glyphRows {
                for (row, line) in glyph.enumerated() {
                    for (column, cell) in line.enumerated() where cell == "1" {
                        let rect = CGRect(x: CGFloat(x + column) * pitch, y: CGFloat(row) * pitch,
                                          width: size, height: size)
                        context.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                }
                x += (glyph.first?.count ?? 0) + 1
            }
        }
        .frame(width: CGFloat(columns) * pitch, height: 7 * pitch)
        .accessibilityElement()
        .accessibilityLabel(Text(text))
    }
}

/// 幅に収まる大きさで表示するドット数字（タイムが長くなっても、はみ出さない）
struct FitDotText: View {
    let text: String
    var color: Color = .white

    var body: some View {
        ViewThatFits(in: .horizontal) {
            DotText(text: text, pitch: 9, color: color)
            DotText(text: text, pitch: 7, color: color)
            DotText(text: text, pitch: 5, color: color)
            DotText(text: text, pitch: 3.5, color: color)
        }
    }
}

/// 画面の上の見出し
struct ScreenHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(.white)
            Spacer()
            trailing
        }
        .frame(minHeight: 44)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}

/// 黄緑の大きなボタン
struct NeonButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline).weight(.black))
            .foregroundStyle(Hi.onNeon)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Capsule().fill(Hi.neon))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// 暗い色の小さなボタン
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.footnote).weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(Capsule().fill(Hi.tile))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

extension View {
    /// 暗いタイルの見た目
    func hiTile(cornerRadius: CGFloat = 20) -> some View {
        self
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Hi.tile)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// 切り替えのボタン
struct HiSegment<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                let isOn = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.system(.subheadline).weight(.bold))
                        .foregroundStyle(isOn ? .black : Hi.dim)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(Capsule().fill(isOn ? Color.white : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Hi.tile))
    }
}

enum AppTab: Hashable, CaseIterable, Identifiable {
    case today, friends, world, profile
    var id: Self { self }
}

/// 下のバー。左右に名前つきのタブが2つずつ、真ん中の黄緑のボタンで撮影に進む。
struct HiTabBar: View {
    @Binding var selection: AppTab
    let onCapture: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            item(.today, icon: "house.fill", label: L("今日"))
            item(.friends, icon: "text.bubble.fill", label: L("タイムライン"))
            Button(action: onCapture) {
                Image(systemName: "camera.fill")
                    .font(.title3)
                    .foregroundStyle(Hi.onNeon)
                    .frame(width: 76, height: 46)
                    .background(Capsule().fill(Hi.neon))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("撮る"))
            .frame(maxWidth: .infinity)
            item(.world, icon: "globe", label: L("世界"))
            item(.profile, icon: "person.crop.circle.fill", label: L("自分"))
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background(Color.black.ignoresSafeArea(edges: .bottom))
    }

    private func item(_ tab: AppTab, icon: String, label: String) -> some View {
        let isOn = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 20))
                Text(label).font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(isOn ? Color.white : Hi.dim.opacity(0.7))
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
