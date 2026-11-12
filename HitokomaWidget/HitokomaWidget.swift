import WidgetKit
import SwiftUI

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
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: zone) ?? .gmt
        formatter.dateFormat = "HH:mm"
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
                        time: entry.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)),
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

@main
struct HitokomaWidgets: WidgetBundle {
    var body: some Widget {
        StreakWidget()
        WorldWidget()
    }
}

// MARK: - ウィジェットの文言（アプリと同じ5言語。アプリで選んだ言語、なければ iPhone の言語、対応外は英語）

enum W {
    static func code(_ lang: String?) -> String {
        if let lang, ["en", "ja", "zh", "ko", "es"].contains(lang) { return lang }
        for c in Locale.preferredLanguages.map({ $0.lowercased() }) {
            for l in ["ja", "zh", "ko", "es", "en"] where c.hasPrefix(l) { return l }
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
        "今日のお題": ["en": "Today's prompt", "zh": "今日题目", "ko": "오늘의 주제", "es": "Tema de hoy"],
        "日連続": ["en": "day streak", "zh": "天连续", "ko": "일 연속", "es": "días seguidos"],
        "撮る": ["en": "Shoot", "zh": "拍摄", "ko": "찍기", "es": "Fotografiar"],
        "アプリを開くと、ここに今日のお題が出ます": ["en": "Open the app to see today's prompt here", "zh": "打开应用即可在此看到今日题目", "ko": "앱을 열면 오늘의 주제가 여기에 나와요", "es": "Abre la app para ver aquí el tema de hoy"],
        "通知は {n} ごろ": ["en": "Arrives around {n}", "zh": "约 {n} 送达", "ko": "{n}쯤 도착", "es": "Llega sobre las {n}"],
        "通知でお題が届きます": ["en": "The prompt arrives by notification", "zh": "题目会通过通知送达", "ko": "주제는 알림으로 도착해요", "es": "El tema llega por notificación"],
        "届いてから": ["en": "since it arrived", "zh": "送达后", "ko": "도착 후", "es": "desde que llegó"],
        "投稿済み {n}": ["en": "Posted {n}", "zh": "已发布 {n}", "ko": "게시함 {n}", "es": "Publicado {n}"],
        "あなた": ["en": "You", "zh": "你", "ko": "나", "es": "Tú"],
        "今日のお題と、届いてからの時間、連続日数を表示します。": ["en": "Shows today's prompt, time since it arrived, and your streak.", "zh": "显示今日题目、送达后的时间和连续天数。", "ko": "오늘의 주제, 도착 후 시간, 연속 일수를 보여줘요.", "es": "Muestra el tema de hoy, el tiempo desde que llegó y tu racha."],
        "あなたと世界の都市の、いまの時刻と空の色を表示します。タップで世界の地図へ。": ["en": "Shows the time and sky color for you and cities around the world. Tap to open the world map.", "zh": "显示你和世界各城市此刻的时间与天空颜色。点按打开世界地图。", "ko": "나와 세계 도시의 지금 시각과 하늘 색을 보여줘요. 탭하면 세계 지도로 이동해요.", "es": "Muestra la hora y el color del cielo para ti y ciudades del mundo. Toca para abrir el mapa."],
        "連続 {n} 日": ["en": "{n}-day streak", "zh": "连续 {n} 天", "ko": "{n}일 연속", "es": "Racha de {n} días"],
        "連続": ["en": "Streak", "zh": "连续", "ko": "연속", "es": "Racha"],
        "今日 {n}": ["en": "Today {n}", "zh": "今天 {n}", "ko": "오늘 {n}", "es": "Hoy {n}"],
        "アプリを開くと更新されます": ["en": "Open the app to update", "zh": "打开应用即可更新", "ko": "앱을 열면 업데이트돼요", "es": "Abre la app para actualizar"],
        "アプリを開くと更新": ["en": "Open app to update", "zh": "打开应用更新", "ko": "앱을 열어 업데이트", "es": "Abre la app"],
        "連続日数": ["en": "Streak", "zh": "连续天数", "ko": "연속 일수", "es": "Racha"],
        "Difframe の連続投稿日数と、今日の投稿数を表示します。": [
            "en": "Shows your Difframe posting streak and today's posts.",
            "zh": "显示你在 Difframe 的连续发布天数和今天的发布数。",
            "ko": "Difframe 연속 게시 일수와 오늘 게시 수를 보여줘요.",
            "es": "Muestra tu racha en Difframe y tus publicaciones de hoy."],
        "世界のいま": ["en": "World now", "zh": "此刻的世界", "ko": "지금 세계", "es": "El mundo ahora"],
        "サンプル": ["en": "Sample", "zh": "示例", "ko": "샘플", "es": "Ejemplo"],
        "世界の都市の、現地の時刻とあいさつを表示します。タップで世界のタイムラインへ。": [
            "en": "Shows local time and greetings in cities around the world. Tap to open the world timeline.",
            "zh": "显示世界各城市的当地时间和问候语。点按打开世界时间线。",
            "ko": "세계 도시의 현지 시각과 인사말을 보여줘요. 탭하면 세계 타임라인으로 이동해요.",
            "es": "Muestra la hora local y saludos de ciudades del mundo. Toca para abrir la línea de tiempo mundial."],
        "傘": ["en": "Umbrella", "zh": "伞", "ko": "우산", "es": "Paraguas"],
        "Tokyo": ["zh": "东京", "ko": "도쿄", "es": "Tokio"],
        "New York": ["zh": "纽约", "ko": "뉴욕", "es": "Nueva York"],
        "Paris": ["zh": "巴黎", "ko": "파리", "es": "París"],
        "Sydney": ["zh": "悉尼", "ko": "시드니", "es": "Sídney"],
        "Mexico City": ["zh": "墨西哥城", "ko": "멕시코시티", "es": "Ciudad de México"],
        "Cairo": ["zh": "开罗", "ko": "카이로", "es": "El Cairo"],
        "São Paulo": ["zh": "圣保罗", "ko": "상파울루", "es": "São Paulo"],
        "Mumbai": ["zh": "孟买", "ko": "뭄바이", "es": "Bombay"],
    ]
}
