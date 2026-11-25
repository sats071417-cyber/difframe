import WidgetKit
import SwiftUI
import ActivityKit

// MARK: - 色

private let neon = Color(red: 0.894, green: 1.0, blue: 0.102)
private let onNeon = Color(red: 0.118, green: 0.137, blue: 0.0)

/// その土地のいまの光（朝・昼・夕・夜）
private enum Light {
    case dawn, day, dusk, night

    init(hour: Int) {
        switch hour {
        case 5...7: self = .dawn
        case 8...16: self = .day
        case 17...20: self = .dusk
        default: self = .night
        }
    }

    var icon: String {
        switch self {
        case .dawn: return "sunrise.fill"
        case .day: return "sun.max.fill"
        case .dusk: return "sunset.fill"
        case .night: return "moon.stars.fill"
        }
    }

    var colors: [Color] {
        func c(_ hex: UInt32) -> Color {
            Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
        }
        switch self {
        case .dawn: return [c(0x7A2E6B), c(0xFF8F6B)]
        case .day: return [c(0x1A6BE0), c(0x6FD0FF)]
        case .dusk: return [c(0x5B16B8), c(0xFF7A3D)]
        case .night: return [c(0x0A0F3C), c(0x2B2F8F)]
        }
    }

    var text: Color { self == .night ? .white : Color.black.opacity(0.82) }
}

// MARK: - 世界の都市（アプリの世界タブと同じサンプル）

private struct City {
    let flag: String
    let name: String
    let zone: String
    let greeting: String

    func hour(at date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        return calendar.component(.hour, from: date)
    }

    func time(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: zone) ?? .gmt
        formatter.setLocalizedDateFormatFromTemplate("jm")   // iPhone の12/24時間の設定に合わせる
        return formatter.string(from: date)
    }
}

private let cities: [City] = [
    City(flag: "🇯🇵", name: "Tokyo", zone: "Asia/Tokyo", greeting: "こんにちは"),
    City(flag: "🇺🇸", name: "New York", zone: "America/New_York", greeting: "Hey"),
    City(flag: "🇫🇷", name: "Paris", zone: "Europe/Paris", greeting: "Salut"),
    City(flag: "🇦🇺", name: "Sydney", zone: "Australia/Sydney", greeting: "G'day"),
    City(flag: "🇲🇽", name: "Mexico City", zone: "America/Mexico_City", greeting: "Hola"),
    City(flag: "🇪🇬", name: "Cairo", zone: "Africa/Cairo", greeting: "مرحبا"),
    City(flag: "🇧🇷", name: "São Paulo", zone: "America/Sao_Paulo", greeting: "Oi"),
    City(flag: "🇮🇳", name: "Mumbai", zone: "Asia/Kolkata", greeting: "नमस्ते"),
]

// MARK: - 今日のお題のウィジェット

/// 色のお題のときの色（アプリの「その色の日」と同じ考え方）
private func promptColors(_ name: String?) -> [Color]? {
    func c(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
    switch name {
    case "red": return [c(0xFF3B30), c(0x7A0A12)]
    case "orange": return [c(0xFF9500), c(0x7A3A00)]
    case "yellow": return [c(0xFFE14D), c(0x7A6100)]
    case "green": return [c(0x34C759), c(0x0B4A1E)]
    case "blue": return [c(0x0A84FF), c(0x062A66)]
    case "purple": return [c(0xAF52DE), c(0x3A0F5C)]
    case "pink": return [c(0xFF6FAE), c(0x6E1240)]
    case "brown": return [c(0xC08A55), c(0x3B2210)]
    case "white": return [c(0xF5F5F0), c(0x8A8A86)]
    case "black": return [c(0x3A3A3C), c(0x000000)]
    default: return nil
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: WidgetSnapshot(streak: 7, postedToday: 0, maxPerDay: 3, prompt: W.t("傘", nil),
                                                          updatedAt: Date(), startedAt: Date().addingTimeInterval(-74)))
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: Date(), snapshot: WidgetSnapshot.load() ?? (context.isPreview ? placeholder(in: context).snapshot : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let now = Date()
        var entries = [TodayEntry(date: now, snapshot: snapshot)]
        // お題が届く時刻に、表示を切り替える（「？」→ お題と時間）
        if let start = snapshot?.startedAt, start > now {
            var revealed = snapshot
            revealed?.hidden = false
            entries.append(TodayEntry(date: start, snapshot: revealed))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
    }
}

/// いまの状態
private enum TodayState {
    case unknown                 // アプリからの情報がない
    case waiting(Date?)          // お題はまだ秘密（通知の時刻）
    case live(Date)              // 届いた。まだ撮っていない（時間を数える）
    case posted                  // 撮った
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    private var s: WidgetSnapshot? { entry.snapshot }
    private var lang: String? { s?.lang }

    private var state: TodayState {
        guard let s else { return .unknown }
        if s.hidden == true, let start = s.startedAt, start > entry.date { return .waiting(start) }
        if s.hidden == true { return .waiting(nil) }
        if s.postedToday > 0 { return .posted }
        if let start = s.startedAt, start <= entry.date { return .live(start) }
        return .posted
    }

    private var glow: [Color] { promptColors(s?.colorName) ?? [neon, Color(red: 0.25, green: 0.3, blue: 0.0)] }
    private var promptText: String {
        if case .waiting = state { return "？" }
        return s?.prompt ?? "？"
    }
    private var link: URL? {
        if case .live = state { return URL(string: "hitokoma://capture") }
        return URL(string: "hitokoma://today")
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .systemMedium: medium
            default: small
            }
        }
        .widgetURL(link)
    }

    // ホーム画面（小）
    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            Spacer(minLength: 4)
            promptBlock
            Spacer(minLength: 4)
            statusLine
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // ホーム画面（中）：左にお題、右に連続日数と今日の枚数
    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                Spacer(minLength: 4)
                promptBlock
                Spacer(minLength: 4)
                statusLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 8) {
                VStack(spacing: 0) {
                    Text(s.map { "\($0.streak)" } ?? "–")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                    Label(W.t("日連続", lang), systemImage: "flame.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                }
                postDots
                if case .live = state {
                    Label(W.t("撮る", lang), systemImage: "camera.fill")
                        .font(.caption.weight(.black))
                        .foregroundStyle(onNeon)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(neon))
                }
            }
            .frame(width: 104)
            .padding(.vertical, 6)
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.08)))
        }
    }

    private var topBar: some View {
        HStack(spacing: 4) {
            Text("Difframe").font(.system(size: 11, weight: .black)).foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 0)
            if let s, family == .systemSmall {
                Image(systemName: "flame.fill").font(.system(size: 10)).foregroundStyle(.orange)
                Text("\(s.streak)").font(.system(size: 12, weight: .black, design: .rounded)).foregroundStyle(.white)
            }
        }
    }

    private var promptBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(W.t("今日のお題", lang)).font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.65))
            Text(promptText)
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.45)
                .shadow(color: .black.opacity(0.35), radius: 6)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch state {
        case .unknown:
            Text(W.t("アプリを開くと、ここに今日のお題が出ます", lang))
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
        case .waiting(let at):
            Label(at.map { W.f("通知は {n} ごろ", $0.formatted(date: .omitted, time: .shortened), lang) } ?? W.t("通知でお題が届きます", lang),
                  systemImage: "bell.fill")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(neon).lineLimit(1).minimumScaleFactor(0.7)
        case .live(let start):
            VStack(alignment: .leading, spacing: 0) {
                Text(start, style: .timer)
                    .font(.system(size: 22, weight: .black, design: .monospaced))
                    .foregroundStyle(neon)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(W.t("届いてから", lang)).font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.6))
            }
        case .posted:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(neon)
                Text(W.f("投稿済み {n}", "\(s?.postedToday ?? 0)/\(s?.maxPerDay ?? 3)", lang))
                if let t = s?.lastTime {
                    Text(timeString(t)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
                }
            }
            .font(.system(size: 11, weight: .black)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private var postDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<(s?.maxPerDay ?? 3), id: \.self) { i in
                Circle()
                    .fill(i < (s?.postedToday ?? 0) ? neon : Color.white.opacity(0.18))
                    .frame(width: 9, height: 9)
            }
        }
        .accessibilityLabel(W.f("投稿済み {n}", "\(s?.postedToday ?? 0)/\(s?.maxPerDay ?? 3)", lang))
    }

    // ロック画面
    private var inline: some View {
        Text("🔥\(s?.streak ?? 0) · \(promptText)")
    }

    private var circular: some View {
        Gauge(value: Double(s?.postedToday ?? 0), in: 0...Double(max(s?.maxPerDay ?? 3, 1))) {
            Image(systemName: "flame.fill")
        } currentValueLabel: {
            Text(s.map { "\($0.streak)" } ?? "–").font(.system(.title3, design: .rounded).weight(.black))
        }
        .gaugeStyle(.accessoryCircular)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Difframe · 🔥\(s?.streak ?? 0)").font(.caption2.weight(.bold))
            Text(promptText).font(.headline.weight(.black)).lineLimit(1)
            switch state {
            case .live(let start): Text(start, style: .timer).font(.caption.monospacedDigit())
            case .waiting(let at): Text(at.map { W.f("通知は {n} ごろ", $0.formatted(date: .omitted, time: .shortened), lang) } ?? W.t("通知でお題が届きます", lang)).font(.caption)
            case .posted: Text(W.f("投稿済み {n}", "\(s?.postedToday ?? 0)/\(s?.maxPerDay ?? 3)", lang)).font(.caption)
            case .unknown: Text(W.t("アプリを開くと更新", lang)).font(.caption)
            }
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let total = Int(t * 10)
        let m = total / 600, sec = (total / 10) % 60, tenth = total % 10
        return m >= 60 ? String(format: "%d:%02d:%02d", m / 60, m % 60, sec) : String(format: "%d:%02d.%d", m, sec, tenth)
    }
}

struct TodayBackground: View {
    let colors: [Color]
    var body: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [colors[0].opacity(0.85), colors[1].opacity(0.35), .clear],
                           center: .bottomTrailing, startRadius: 4, endRadius: 220)
        }
    }
}

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        // 前の版の「連続日数」と同じ種類名にして、置いてあるウィジェットはそのまま新しい形になる
        StaticConfiguration(kind: "HitokomaStreak", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    TodayBackground(colors: promptColors(entry.snapshot?.colorName) ?? [neon, Color(red: 0.25, green: 0.3, blue: 0.0)])
                }
        }
        .configurationDisplayName(W.t("今日のお題", nil))
        .description(W.t("今日のお題と、届いてからの時間、連続日数を表示します。", nil))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - 世界のいまのウィジェット

struct WorldEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct WorldProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorldEntry { WorldEntry(date: Date(), snapshot: nil) }

    func getSnapshot(in context: Context, completion: @escaping (WorldEntry) -> Void) {
        completion(WorldEntry(date: Date(), snapshot: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WorldEntry>) -> Void) {
        // 現地の時刻がずれないよう、1分ごとに1時間分を用意する
        let snapshot = WidgetSnapshot.load()
        let start = Calendar.current.dateInterval(of: .minute, for: Date())?.start ?? Date()
        let entries = (0..<60).map { WorldEntry(date: start.addingTimeInterval(Double($0) * 60), snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct WorldWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WorldEntry
    private var lang: String? { entry.snapshot?.lang }

    /// 見せる都市：自分の時刻と、時差の大きい順に散らした都市
    private var rows: [City] {
        let count = family == .systemLarge ? 5 : 2
        // 1時間ごとに、見せる都市を入れかえる
        let shift = Int(entry.date.timeIntervalSince1970 / 3600) % cities.count
        return (0..<count).map { cities[(shift + $0 * 3) % cities.count] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "globe.asia.australia.fill").foregroundStyle(neon)
                Text(W.t("世界のいま", lang)).font(.system(size: 13, weight: .black)).foregroundStyle(.white)
                Spacer(minLength: 0)
                if let prompt = entry.snapshot?.prompt, !prompt.isEmpty {
                    Text(prompt)
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(onNeon)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(neon))
                        .lineLimit(1)
                }
            }
            if family == .systemLarge {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    youTile
                    ForEach(rows, id: \.name) { tile($0, large: true) }
                }
                .frame(maxHeight: .infinity)
            } else {
                HStack(spacing: 8) {
                    youTile
                    ForEach(rows, id: \.name) { tile($0, large: false) }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .widgetURL(URL(string: "hitokoma://world"))
    }

    /// 自分のいまの時刻（いまの光で）
    private var youTile: some View {
        let hour = Calendar.current.component(.hour, from: entry.date)
        let light = Light(hour: hour)
        return tileBody(light: light, flag: "📍", name: W.t("あなた", lang),
                        time: entry.date.formatted(.dateTime.hour().minute()),
                        greeting: nil, highlight: true)
    }

    private func tile(_ city: City, large: Bool) -> some View {
        tileBody(light: Light(hour: city.hour(at: entry.date)), flag: city.flag, name: W.t(city.name, lang),
                 time: city.time(at: entry.date), greeting: large ? city.greeting : nil, highlight: false)
    }

    private func tileBody(light: Light, flag: String, name: String, time: String, greeting: String?, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(flag).font(.system(size: 15))
                Spacer(minLength: 0)
                Image(systemName: light.icon).font(.system(size: 11, weight: .bold))
            }
            Spacer(minLength: 0)
            Text(time)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(name).font(.system(size: 10, weight: .black)).lineLimit(1).minimumScaleFactor(0.7)
            if let greeting {
                Text("「\(greeting)」").font(.system(size: 10, weight: .semibold)).opacity(0.85).lineLimit(1)
            }
        }
        .foregroundStyle(light.text)
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(LinearGradient(colors: light.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(highlight ? neon : .clear, lineWidth: 2))
    }
}

struct WorldWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HitokomaWorld", provider: WorldProvider()) { entry in
            WorldWidgetView(entry: entry)
                .containerBackground(Color.black, for: .widget)
        }
        .configurationDisplayName(W.t("世界のいま", nil))
        .description(W.t("あなたと世界の都市の、いまの時刻と空の色を表示します。タップで世界の地図へ。", nil))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - ダイナミックアイランド・ロック画面（Live Activity）

/// 表示に使う値をまとめる
private struct PromptActivityModel {
    let context: ActivityViewContext<PromptActivityAttributes>
    var state: PromptActivityAttributes.ContentState { context.state }
    /// お題が届いたか。届く時刻を過ぎると、システムが「古い表示（stale）」として描き直すので、その時に切り替わる
    var revealed: Bool { state.revealed || context.isStale || state.fireAt <= Date() }
    var lang: String? { state.lang }
    var prompt: String { revealed ? state.prompt : "？" }
    var glow: Color { promptColors(state.colorName)?.first ?? neon }
    var icon: String { revealed ? "camera.fill" : "hourglass" }
    var label: String { revealed ? W.t("今日のお題", lang) : W.t("今日のお題まで", lang) }
    var link: URL? { URL(string: revealed ? "hitokoma://capture" : "hitokoma://today") }
}

/// 届く前は届くまでのカウントダウン、届いたあとは届いてからの時間（1時間を超えたら 時:分:秒）
private struct ActivityTimer: View {
    let model: PromptActivityModel

    var body: some View {
        if model.revealed {
            Text(model.state.fireAt, style: .timer)
        } else {
            Text(timerInterval: Date()...max(model.state.fireAt, Date().addingTimeInterval(1)), countsDown: true)
        }
    }
}

/// 黄緑の丸に、いまの状態のアイコン
private struct ActivityBadge: View {
    let model: PromptActivityModel
    var size: CGFloat

    var body: some View {
        Image(systemName: model.icon)
            .font(.system(size: size * 0.48, weight: .black))
            .foregroundStyle(onNeon)
            .frame(width: size, height: size)
            .background(Circle().fill(neon))
    }
}

/// 「撮る」の黄緑のボタン
private struct ShootCapsule: View {
    let lang: String?

    var body: some View {
        Label(W.t("撮る", lang), systemImage: "camera.fill")
            .font(.caption.weight(.black))
            .foregroundStyle(onNeon)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(neon))
    }
}

/// ロック画面とバナー
private struct PromptActivityLockView: View {
    let model: PromptActivityModel

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("Difframe").font(.system(size: 12, weight: .black)).foregroundStyle(.white.opacity(0.7))
                    if model.state.streak > 0 {
                        Image(systemName: "flame.fill").font(.system(size: 10)).foregroundStyle(.orange)
                        Text("\(model.state.streak)")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                Text(model.label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.65))
                Text(model.prompt)
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                ActivityTimer(model: model)
                    .font(.system(size: 26, weight: .black, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(neon)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140, alignment: .trailing)
                if model.revealed {
                    ShootCapsule(lang: model.lang)
                } else {
                    Text(W.t("通知と同時にここに出ます", model.lang))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(16)
        .background(
            RadialGradient(colors: [model.glow.opacity(0.55), .clear],
                           center: .bottomTrailing, startRadius: 4, endRadius: 260)
        )
    }
}

struct PromptLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PromptActivityAttributes.self) { context in
            let model = PromptActivityModel(context: context)
            PromptActivityLockView(model: model)
                .activityBackgroundTint(Color.black.opacity(0.92))
                .activitySystemActionForegroundColor(neon)
                .widgetURL(model.link)
        } dynamicIsland: { context in
            let model = PromptActivityModel(context: context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        ActivityBadge(model: model, size: 28)
                        Text("Difframe")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityTimer(model: model)
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(neon)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .bottom, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.label)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.6))
                            Text(model.prompt)
                                .font(.system(size: 28, weight: .black))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                        Spacer(minLength: 0)
                        if model.revealed {
                            ShootCapsule(lang: model.lang)
                        } else if model.state.streak > 0 {
                            Label("\(model.state.streak)", systemImage: "flame.fill")
                                .font(.caption.weight(.black))
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                ActivityBadge(model: model, size: 22)
            } compactTrailing: {
                ActivityTimer(model: model)
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(neon)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 58)
            } minimal: {
                Image(systemName: model.icon)
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(neon)
            }
            .widgetURL(model.link)
            .keylineTint(neon)
        }
    }
}


// MARK: - カレンダー・自分の投稿・友達の投稿（WidgetFeed を読む）

struct FeedEntry: TimelineEntry {
    let date: Date
    let feed: WidgetFeed?
}

struct FeedProvider: TimelineProvider {
    func placeholder(in context: Context) -> FeedEntry { FeedEntry(date: Date(), feed: nil) }

    func getSnapshot(in context: Context, completion: @escaping (FeedEntry) -> Void) {
        completion(FeedEntry(date: Date(), feed: WidgetFeed.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FeedEntry>) -> Void) {
        let feed = WidgetFeed.load()
        let now = Date()
        var entries = [FeedEntry(date: now, feed: feed)]
        // 次のお題が届いたら、友達の投稿を隠す（日付が変わったらカレンダーも描き直す）
        if let lockAt = feed?.lockAt, lockAt > now { entries.append(FeedEntry(date: lockAt, feed: feed)) }
        if let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime),
           entries.allSatisfy({ $0.date != midnight }) {
            entries.append(FeedEntry(date: midnight, feed: feed))
        }
        entries.sort { $0.date < $1.date }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

/// タイム（例：3:12.5、1時間を超えたら 1:03:12）
private func feedTime(_ t: TimeInterval) -> String {
    let total = Int(t * 10)
    let m = total / 600, sec = (total / 10) % 60, tenth = total % 10
    return m >= 60 ? String(format: "%d:%02d:%02d", m / 60, m % 60, sec) : String(format: "%d:%02d.%d", m, sec, tenth)
}

/// App Group に置いた、小さくした写真
private func feedImage(_ file: String) -> UIImage? {
    guard let url = WidgetFeed.imageDir?.appendingPathComponent(file) else { return nil }
    return UIImage(contentsOfFile: url.path)
}

private let feedDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

/// 写真を、同じ大きさで横に並べる（枚数が少なくても、引き伸ばさず、左から並べる。アプリのプロフィールの並びと同じ感じ）
private struct TileRow<Item, Content: View>: View {
    let items: [Item]
    var count = 3
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        GeometryReader { g in
            let spacing: CGFloat = 8, pad: CGFloat = 10
            let side = (g.size.width - pad * 2 - spacing * CGFloat(count - 1)) / CGFloat(count)
            let height = min(side * 1.25, g.size.height - pad * 2)
            HStack(spacing: spacing) {
                ForEach(Array(items.prefix(count).enumerated()), id: \.offset) { _, item in
                    content(item).frame(width: side, height: height)
                }
                Spacer(minLength: 0)
            }
            .padding(pad)
            .frame(width: g.size.width, height: g.size.height, alignment: .center)
        }
    }
}

/// 写真を枠いっぱいに出し、下に文字を重ねる
private struct PhotoTile<Overlay: View>: View {
    let image: UIImage?
    var corner: CGFloat = 16
    @ViewBuilder var overlay: Overlay

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.white.opacity(0.08)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            overlay.padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

// MARK: ストリークのカレンダー

struct CalendarWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FeedEntry
    private var lang: String? { entry.feed?.lang }
    private var posted: Set<String> { Set(entry.feed?.postedDays ?? []) }

    /// 今月のマス（月曜はじまりではなく、日曜はじまり。前の月の分は nil）
    private var cells: [Date?] {
        let cal = Calendar(identifier: .gregorian)
        guard let interval = cal.dateInterval(of: .month, for: entry.date) else { return [] }
        let first = interval.start
        let lead = cal.component(.weekday, from: first) - 1
        let count = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        return Array(repeating: nil, count: lead) + (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: first) }
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: W.code(lang))
        f.setLocalizedDateFormatFromTemplate("MMMM")
        return f.string(from: entry.date)
    }

    var body: some View {
        Group {
            if family == .systemMedium {
                HStack(spacing: 14) {
                    streakBlock.frame(width: 96)
                    grid
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(monthTitle).font(.system(size: 12, weight: .black)).foregroundStyle(.white)
                        Spacer(minLength: 0)
                        Image(systemName: "flame.fill").font(.system(size: 10)).foregroundStyle(.orange)
                        Text("\(entry.feed?.streak ?? 0)").font(.system(size: 12, weight: .black, design: .rounded)).foregroundStyle(.white)
                    }
                    grid
                }
            }
        }
        .widgetURL(URL(string: "hitokoma://me"))
    }

    private var streakBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(monthTitle).font(.system(size: 12, weight: .black)).foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 0)
            Image(systemName: "flame.fill").font(.system(size: 22)).foregroundStyle(.orange)
            Text("\(entry.feed?.streak ?? 0)")
                .font(.system(size: 44, weight: .black, design: .rounded)).foregroundStyle(.white)
                .minimumScaleFactor(0.5).lineLimit(1)
            Text(W.t("日連続", lang)).font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 0)
            Text(W.f("今月 {n} 日", "\(cells.compactMap { $0 }.filter { posted.contains(feedDayFormatter.string(from: $0)) }.count)", lang))
                .font(.system(size: 10, weight: .bold)).foregroundStyle(neon)
        }
        .frame(maxHeight: .infinity, alignment: .leading)
    }

    private var grid: some View {
        let todayKey = feedDayFormatter.string(from: entry.date)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)
        return LazyVGrid(columns: columns, spacing: 3) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                if let day {
                    let key = feedDayFormatter.string(from: day)
                    let on = posted.contains(key)
                    let isToday = key == todayKey
                    Text("\(Calendar.current.component(.day, from: day))")
                        .font(.system(size: family == .systemMedium ? 10 : 8, weight: on ? .black : .semibold, design: .rounded))
                        .foregroundStyle(on ? onNeon : (key > todayKey ? .white.opacity(0.25) : .white.opacity(0.7)))
                        .frame(maxWidth: .infinity, minHeight: family == .systemMedium ? 17 : 14)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(on ? neon : Color.white.opacity(0.07)))
                        .overlay {
                            if isToday {
                                RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(Color.white, lineWidth: 1.2)
                            }
                        }
                } else {
                    Color.clear.frame(minHeight: family == .systemMedium ? 17 : 14)
                }
            }
        }
    }
}

struct CalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HitokomaCalendar", provider: FeedProvider()) { entry in
            CalendarWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.black }
        }
        .configurationDisplayName(W.t("投稿カレンダー", nil))
        .description(W.t("投稿した日が光るカレンダーと、連続日数を表示します。", nil))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: 自分の投稿

struct MineWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FeedEntry
    private var lang: String? { entry.feed?.lang }
    private var mine: [WidgetFeed.Mine] { entry.feed?.mine ?? [] }

    var body: some View {
        Group {
            if mine.isEmpty {
                empty(icon: "camera.fill", text: W.t("撮った写真が、ここに並びます", lang))
            } else if family == .systemMedium {
                TileRow(items: mine) { m in tile(m, small: true) }
            } else {
                tile(mine[0], small: false)
            }
        }
        .widgetURL(URL(string: "hitokoma://me"))
    }

    private func tile(_ m: WidgetFeed.Mine, small: Bool) -> some View {
        PhotoTile(image: feedImage(m.file), corner: small ? 14 : 18) {
            VStack(alignment: .leading, spacing: 0) {
                Text(m.prompt).font(.system(size: small ? 11 : 15, weight: .black)).foregroundStyle(.white).lineLimit(1)
                if let t = m.elapsed {
                    Text(feedTime(t)).font(.system(size: small ? 10 : 12, weight: .bold, design: .monospaced)).foregroundStyle(neon)
                }
            }
        }
    }
}

struct MineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HitokomaMine", provider: FeedProvider()) { entry in
            MineWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.black }
        }
        .configurationDisplayName(W.t("自分の投稿", nil))
        .description(W.t("最近撮った写真と、お題、タイムを表示します。", nil))
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

// MARK: 友達の投稿（自分がいまのお題に投稿するまで見えない）

struct FriendsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FeedEntry
    private var lang: String? { entry.feed?.lang }
    private var visible: Bool { entry.feed?.friendsVisible(at: entry.date) ?? false }
    private var friends: [WidgetFeed.Friend] { entry.feed?.friends ?? [] }

    var body: some View {
        Group {
            if !visible {
                locked
            } else if friends.isEmpty {
                empty(icon: "person.2.fill", text: W.t("友達の投稿は、まだありません", lang))
            } else if family == .systemMedium {
                TileRow(items: friends) { f in tile(f, small: true) }
            } else {
                tile(friends[0], small: false)
            }
        }
        .widgetURL(URL(string: visible ? "hitokoma://timeline" : "hitokoma://capture"))
    }

    private var locked: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.fill").font(.system(size: family == .systemMedium ? 26 : 22, weight: .bold)).foregroundStyle(neon)
            Text(W.t("今日のお題を投稿すると、友達の投稿が見られます", lang))
                .font(.system(size: 12, weight: .black)).foregroundStyle(.white)
                .multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.7)
            if family == .systemMedium {
                Label(W.t("撮る", lang), systemImage: "camera.fill")
                    .font(.caption.weight(.black)).foregroundStyle(onNeon)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(neon))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tile(_ f: WidgetFeed.Friend, small: Bool) -> some View {
        PhotoTile(image: feedImage(f.file), corner: small ? 14 : 18) {
            VStack(alignment: .leading, spacing: 0) {
                Text(f.name).font(.system(size: small ? 11 : 14, weight: .black)).foregroundStyle(.white).lineLimit(1)
                Text([f.prompt, f.city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: small ? 9 : 11, weight: .bold)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
            }
        }
    }
}

struct FriendsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HitokomaFriends", provider: FeedProvider()) { entry in
            FriendsWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.black }
        }
        .configurationDisplayName(W.t("友達の投稿", nil))
        .description(W.t("友達の最新の写真を表示します。今日のお題を投稿するまでは見えません。", nil))
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

/// 写真がまだないときの表示
private func empty(icon: String, text: String) -> some View {
    VStack(spacing: 8) {
        Image(systemName: icon).font(.system(size: 22, weight: .bold)).foregroundStyle(neon)
        Text(text).font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.8))
            .multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.7)
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

@main
struct HitokomaWidgets: WidgetBundle {
    var body: some Widget {
        StreakWidget()
        CalendarWidget()
        MineWidget()
        FriendsWidget()
        WorldWidget()
        PromptLiveActivity()
    }
}

// MARK: - ウィジェットの文言（アプリと同じ5言語。アプリで選んだ言語、なければ iPhone の言語、対応外は英語）

enum W {
    static func code(_ lang: String?) -> String {
        if let lang, ["en", "ja", "zh", "ko", "es", "fr"].contains(lang) { return lang }
        for c in Locale.preferredLanguages.map({ $0.lowercased() }) {
            for l in ["ja", "zh", "ko", "es", "fr", "en"] where c.hasPrefix(l) { return l }
        }
        return "en"
    }

    static func t(_ key: String, _ lang: String?) -> String {
        let l = code(lang)
        if l == "ja" { return jaCity[key] ?? key }
        return table[key]?[l] ?? key
    }

    static func f(_ key: String, _ n: String, _ lang: String?) -> String {
        t(key, lang).replacingOccurrences(of: "{n}", with: n)
    }

    private static let jaCity: [String: String] = [
        "Tokyo": "東京", "New York": "ニューヨーク", "Paris": "パリ", "Sydney": "シドニー",
        "Mexico City": "メキシコシティ", "Cairo": "カイロ", "São Paulo": "サンパウロ", "Mumbai": "ムンバイ",
    ]

    private static let table: [String: [String: String]] = [
        "今日のお題": ["en": "Today's prompt", "zh": "今日题目", "ko": "오늘의 주제", "es": "Tema de hoy", "fr": "Thème du jour"],
        "日連続": ["en": "day streak", "zh": "天连续", "ko": "일 연속", "es": "días seguidos", "fr": "jours d'affilée"],
        "撮る": ["en": "Shoot", "zh": "拍摄", "ko": "찍기", "es": "Fotografiar", "fr": "Photographier"],
        "アプリを開くと、ここに今日のお題が出ます": ["en": "Open the app to see today's prompt here", "zh": "打开应用即可在此看到今日题目", "ko": "앱을 열면 오늘의 주제가 여기에 나와요", "es": "Abre la app para ver aquí el tema de hoy", "fr": "Ouvre l'app pour voir ici le thème du jour"],
        "通知は {n} ごろ": ["en": "Arrives around {n}", "zh": "约 {n} 送达", "ko": "{n}쯤 도착", "es": "Llega sobre las {n}", "fr": "Notification vers {n}"],
        "通知でお題が届きます": ["en": "The prompt arrives by notification", "zh": "题目会通过通知送达", "ko": "주제는 알림으로 도착해요", "es": "El tema llega por notificación", "fr": "Le thème arrive par notification"],
        "届いてから": ["en": "since it arrived", "zh": "送达后", "ko": "도착 후", "es": "desde que llegó", "fr": "depuis son arrivée"],
        "投稿カレンダー": ["en": "Post calendar", "zh": "投稿日历", "ko": "게시 캘린더", "es": "Calendario de fotos", "fr": "Calendrier des photos"],
        "投稿した日が光るカレンダーと、連続日数を表示します。": ["en": "A calendar that lights up the days you posted, with your streak.", "zh": "点亮你投稿过的日子，并显示连续天数。", "ko": "게시한 날이 빛나는 캘린더와 연속 일수를 보여줘요.", "es": "Un calendario que ilumina los días que publicaste, con tu racha.", "fr": "Un calendrier qui illumine les jours où tu as publié, avec ta série."],
        "今月 {n} 日": ["en": "{n} days this month", "zh": "本月 {n} 天", "ko": "이번 달 {n}일", "es": "{n} días este mes", "fr": "{n} jours ce mois-ci"],
        "自分の投稿": ["en": "My photos", "zh": "我的投稿", "ko": "내 게시물", "es": "Mis fotos", "fr": "Mes photos"],
        "最近撮った写真と、お題、タイムを表示します。": ["en": "Your latest photos with the prompt and your time.", "zh": "显示你最近拍的照片、题目和用时。", "ko": "최근 찍은 사진과 주제, 시간을 보여줘요.", "es": "Tus fotos recientes con el tema y tu tiempo.", "fr": "Tes dernières photos avec le thème et ton temps."],
        "撮った写真が、ここに並びます": ["en": "Your photos will appear here", "zh": "拍的照片会显示在这里", "ko": "찍은 사진이 여기에 나와요", "es": "Tus fotos aparecerán aquí", "fr": "Tes photos apparaîtront ici"],
        "友達の投稿": ["en": "Friends' photos", "zh": "朋友的投稿", "ko": "친구 게시물", "es": "Fotos de amigos", "fr": "Photos d'amis"],
        "友達の最新の写真を表示します。今日のお題を投稿するまでは見えません。": ["en": "Your friends' latest photos. Hidden until you post today's prompt.", "zh": "显示朋友的最新照片。投稿今日题目前看不到。", "ko": "친구의 최신 사진을 보여줘요. 오늘의 주제를 올리기 전에는 보이지 않아요.", "es": "Las últimas fotos de tus amigos. Ocultas hasta que publiques el tema de hoy.", "fr": "Les dernières photos de tes amis. Masquées jusqu'à ce que tu publies le thème du jour."],
        "今日のお題を投稿すると、友達の投稿が見られます": ["en": "Post today's prompt to see your friends' photos", "zh": "投稿今日题目后，就能看到朋友的投稿", "ko": "오늘의 주제를 올리면 친구 게시물을 볼 수 있어요", "es": "Publica el tema de hoy para ver las fotos de tus amigos", "fr": "Publie le thème du jour pour voir les photos de tes amis"],
        "友達の投稿は、まだありません": ["en": "No photos from friends yet", "zh": "朋友还没有投稿", "ko": "아직 친구 게시물이 없어요", "es": "Aún no hay fotos de amigos", "fr": "Pas encore de photos d'amis"],
        "今日のお題まで": ["en": "Next prompt in", "zh": "距今日题目还有", "ko": "오늘의 주제까지", "es": "Próximo tema en", "fr": "Prochain thème dans"],
        "通知と同時にここに出ます": ["en": "Appears here the moment it's sent", "zh": "送达的同时出现在这里", "ko": "도착하는 순간 여기에 나와요", "es": "Aparece aquí en cuanto llega", "fr": "Apparaît ici dès l'envoi"],
        "投稿済み {n}": ["en": "Posted {n}", "zh": "已发布 {n}", "ko": "게시함 {n}", "es": "Publicado {n}", "fr": "Publié {n}"],
        "あなた": ["en": "You", "zh": "你", "ko": "나", "es": "Tú", "fr": "Toi"],
        "今日のお題と、届いてからの時間、連続日数を表示します。": ["en": "Shows today's prompt, time since it arrived, and your streak.", "zh": "显示今日题目、送达后的时间和连续天数。", "ko": "오늘의 주제, 도착 후 시간, 연속 일수를 보여줘요.", "es": "Muestra el tema de hoy, el tiempo desde que llegó y tu racha.", "fr": "Affiche le thème du jour, le temps écoulé depuis son arrivée et ta série."],
        "あなたと世界の都市の、いまの時刻と空の色を表示します。タップで世界の地図へ。": ["en": "Shows the time and sky color for you and cities around the world. Tap to open the world map.", "zh": "显示你和世界各城市此刻的时间与天空颜色。点按打开世界地图。", "ko": "나와 세계 도시의 지금 시각과 하늘 색을 보여줘요. 탭하면 세계 지도로 이동해요.", "es": "Muestra la hora y el color del cielo para ti y ciudades del mundo. Toca para abrir el mapa.", "fr": "Affiche l'heure et la couleur du ciel pour toi et des villes du monde. Touche pour ouvrir la carte du monde."],
        "連続 {n} 日": ["en": "{n}-day streak", "zh": "连续 {n} 天", "ko": "{n}일 연속", "es": "Racha de {n} días", "fr": "Série de {n} jours"],
        "連続": ["en": "Streak", "zh": "连续", "ko": "연속", "es": "Racha", "fr": "Série"],
        "今日 {n}": ["en": "Today {n}", "zh": "今天 {n}", "ko": "오늘 {n}", "es": "Hoy {n}", "fr": "Aujourd'hui {n}"],
        "アプリを開くと更新されます": ["en": "Open the app to update", "zh": "打开应用即可更新", "ko": "앱을 열면 업데이트돼요", "es": "Abre la app para actualizar", "fr": "Ouvre l'app pour actualiser"],
        "アプリを開くと更新": ["en": "Open app to update", "zh": "打开应用更新", "ko": "앱을 열어 업데이트", "es": "Abre la app", "fr": "Ouvre l'app"],
        "連続日数": ["en": "Streak", "zh": "连续天数", "ko": "연속 일수", "es": "Racha", "fr": "Série"],
        "Difframe の連続投稿日数と、今日の投稿数を表示します。": [
            "en": "Shows your Difframe posting streak and today's posts.",
            "zh": "显示你在 Difframe 的连续发布天数和今天的发布数。",
            "ko": "Difframe 연속 게시 일수와 오늘 게시 수를 보여줘요.",
            "es": "Muestra tu racha en Difframe y tus publicaciones de hoy.",
            "fr": "Affiche ta série de publications Difframe et tes publications du jour."],
        "世界のいま": ["en": "World now", "zh": "此刻的世界", "ko": "지금 세계", "es": "El mundo ahora", "fr": "Le monde maintenant"],
        "サンプル": ["en": "Sample", "zh": "示例", "ko": "샘플", "es": "Ejemplo", "fr": "Exemple"],
        "世界の都市の、現地の時刻とあいさつを表示します。タップで世界のタイムラインへ。": [
            "en": "Shows local time and greetings in cities around the world. Tap to open the world timeline.",
            "zh": "显示世界各城市的当地时间和问候语。点按打开世界时间线。",
            "ko": "세계 도시의 현지 시각과 인사말을 보여줘요. 탭하면 세계 타임라인으로 이동해요.",
            "es": "Muestra la hora local y saludos de ciudades del mundo. Toca para abrir la línea de tiempo mundial.",
            "fr": "Affiche l'heure locale et les salutations de villes du monde. Touche pour ouvrir la chronologie mondiale."],
        "傘": ["en": "Umbrella", "zh": "伞", "ko": "우산", "es": "Paraguas", "fr": "Parapluie"],
        "Tokyo": ["zh": "东京", "ko": "도쿄", "es": "Tokio", "fr": "Tokyo"],
        "New York": ["zh": "纽约", "ko": "뉴욕", "es": "Nueva York", "fr": "New York"],
        "Paris": ["zh": "巴黎", "ko": "파리", "es": "París", "fr": "Paris"],
        "Sydney": ["zh": "悉尼", "ko": "시드니", "es": "Sídney", "fr": "Sydney"],
        "Mexico City": ["zh": "墨西哥城", "ko": "멕시코시티", "es": "Ciudad de México", "fr": "Mexico"],
        "Cairo": ["zh": "开罗", "ko": "카이로", "es": "El Cairo", "fr": "Le Caire"],
        "São Paulo": ["zh": "圣保罗", "ko": "상파울루", "es": "São Paulo", "fr": "São Paulo"],
        "Mumbai": ["zh": "孟买", "ko": "뭄바이", "es": "Bombay", "fr": "Mumbai"],
    ]
}
