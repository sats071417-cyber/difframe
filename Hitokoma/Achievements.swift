import SwiftUI

/// タイムアタック（自分の投稿のタイムの記録）
/// お題に合う写真と確認できた投稿（verified）だけを数える。
struct TimeAttackStats {
    /// 投稿したお題の、タイム（速い順）
    let times: [(dayKey: String, elapsed: TimeInterval)]

    init(records: [PromptRecord]) {
        times = records
            .compactMap { record -> (String, TimeInterval)? in
                guard record.postedPhotoFile != nil, record.verified == true, let elapsed = record.elapsed else { return nil }
                return (record.dayKey, elapsed)
            }
            .sorted { $0.1 < $1.1 }
    }

    var best: TimeInterval? { times.first?.elapsed }

    var average: TimeInterval? {
        guard !times.isEmpty else { return nil }
        return times.map(\.elapsed).reduce(0, +) / Double(times.count)
    }
}

/// トロフィー（実績）の一覧。条件は投稿の記録から計算する。
enum Trophy: CaseIterable, Identifiable {
    case firstPost
    case posts10
    case posts25
    case posts50
    case posts100
    case streak3
    case streak7
    case streak14
    case streak30
    case streak100
    case under60
    case under30
    case under10
    case under5
    case fast10
    case fast30x5
    case friends1
    case friends3
    case friends5
    case friends10
    case cities3
    case cities10
    case earlyBird
    case nightOwl
    case weekend
    case caption10
    case dual10
    case full3
    case full3x7
    case public10

    var id: Self { self }

    /// サーバーに置くときの名前（変えないこと）
    var key: String { String(describing: self) }

    init?(key: String) {
        guard let found = Trophy.allCases.first(where: { $0.key == key }) else { return nil }
        self = found
    }

    var title: String {
        switch self {
        case .firstPost: return L("はじめての一枚")
        case .posts10: return L("10枚投稿")
        case .posts25: return L("25枚投稿")
        case .posts50: return L("50枚投稿")
        case .posts100: return L("100枚投稿")
        case .streak3: return L("3日連続")
        case .streak7: return L("7日連続")
        case .streak14: return L("14日連続")
        case .streak30: return L("30日連続")
        case .streak100: return L("100日連続")
        case .under60: return L("1分以内")
        case .under30: return L("30秒以内")
        case .under10: return L("10秒以内")
        case .under5: return L("5秒以内")
        case .fast10: return L("はやうち名人")
        case .fast30x5: return L("神速5回")
        case .friends1: return L("はじめての友達")
        case .friends3: return L("友達3人")
        case .friends5: return L("友達5人")
        case .friends10: return L("友達10人")
        case .cities3: return L("3つの街")
        case .cities10: return L("世界旅行者")
        case .earlyBird: return L("早起きさん")
        case .nightOwl: return L("夜ふかしさん")
        case .weekend: return L("週末の一枚")
        case .caption10: return L("ひとこと名人")
        case .dual10: return L("2枚撮りマスター")
        case .full3: return L("1日3枚")
        case .full3x7: return L("3枚の達人")
        case .public10: return L("世界に10枚")
        }
    }

    var detail: String {
        switch self {
        case .firstPost: return L("初めて投稿した")
        case .posts10: return L("合計10枚投稿した")
        case .posts25: return L("合計25枚投稿した")
        case .posts50: return L("合計50枚投稿した")
        case .posts100: return L("合計100枚投稿した")
        case .streak3: return L("3日続けて投稿した")
        case .streak7: return L("7日続けて投稿した")
        case .streak14: return L("14日続けて投稿した")
        case .streak30: return L("30日続けて投稿した")
        case .streak100: return L("100日続けて投稿した")
        case .under60: return L("通知から1分以内に投稿した")
        case .under30: return L("通知から30秒以内に投稿した")
        case .under10: return L("通知から10秒以内に投稿した")
        case .under5: return L("通知から5秒以内に投稿した")
        case .fast10: return L("1分以内の投稿を10回した")
        case .fast30x5: return L("30秒以内の投稿を5回した")
        case .friends1: return L("友達を1人追加した")
        case .friends3: return L("友達を3人追加した")
        case .friends5: return L("友達を5人追加した")
        case .friends10: return L("友達を10人追加した")
        case .cities3: return L("3つの都市から投稿した")
        case .cities10: return L("10の都市から投稿した")
        case .earlyBird: return L("朝5時〜7時に投稿した")
        case .nightOwl: return L("夜11時〜朝4時に投稿した")
        case .weekend: return L("土日に4回投稿した")
        case .caption10: return L("ひとことを10回つけた")
        case .dual10: return L("2枚撮りで10回投稿した")
        case .full3: return L("1日に3枚とも投稿した")
        case .full3x7: return L("1日3枚の投稿を7日した")
        case .public10: return L("みんなに10枚投稿した")
        }
    }

    var icon: String {
        switch self {
        case .firstPost: return "camera.fill"
        case .posts10: return "photo.stack.fill"
        case .posts25: return "photo.on.rectangle.angled"
        case .posts50: return "square.stack.3d.up.fill"
        case .posts100: return "trophy.fill"
        case .streak3: return "flame.fill"
        case .streak7: return "flame.fill"
        case .streak14: return "flame.circle.fill"
        case .streak30: return "flame.fill"
        case .streak100: return "crown.fill"
        case .under60: return "stopwatch.fill"
        case .under30: return "hare.fill"
        case .under10: return "bolt.fill"
        case .under5: return "bolt.circle.fill"
        case .fast10: return "timer"
        case .fast30x5: return "sparkles"
        case .friends1: return "person.crop.circle.badge.plus"
        case .friends3: return "person.3.fill"
        case .friends5: return "person.2.fill"
        case .friends10: return "person.3.sequence.fill"
        case .cities3: return "map.fill"
        case .cities10: return "globe.europe.africa.fill"
        case .earlyBird: return "sunrise.fill"
        case .nightOwl: return "moon.stars.fill"
        case .weekend: return "calendar"
        case .caption10: return "text.bubble.fill"
        case .dual10: return "camera.on.rectangle.fill"
        case .full3: return "3.square.fill"
        case .full3x7: return "medal.fill"
        case .public10: return "megaphone.fill"
        }
    }

    /// 他の人に見せるときの優先度（大きいほど珍しい）
    var priority: Int {
        switch self {
        case .firstPost: return 1
        case .posts10: return 5
        case .posts25: return 10
        case .posts50: return 13
        case .posts100: return 19
        case .streak3: return 3
        case .streak7: return 7
        case .streak14: return 12
        case .streak30: return 9
        case .streak100: return 20
        case .under60: return 4
        case .under30: return 6
        case .under10: return 8
        case .under5: return 17
        case .fast10: return 11
        case .fast30x5: return 15
        case .friends1: return 1
        case .friends3: return 2
        case .friends5: return 5
        case .friends10: return 12
        case .cities3: return 6
        case .cities10: return 16
        case .earlyBird: return 4
        case .nightOwl: return 4
        case .weekend: return 5
        case .caption10: return 6
        case .dual10: return 7
        case .full3: return 6
        case .full3x7: return 14
        case .public10: return 8
        }
    }

    /// 他の人に見せる、珍しいトロフィー（優先度の高い順）。同じ系統は、いちばん上の段階だけ
    static func showcase(_ trophies: [Trophy], limit: Int = 3) -> [Trophy] {
        let earned = Set(trophies)
        let top = TrophyFamily.all.compactMap { $0.current(earned) }
        return Array(top.sorted { $0.priority > $1.priority }.prefix(limit))
    }

    /// 達成しているかどうか
    func isUnlocked(_ s: AchievementInput) -> Bool {
        switch self {
        case .firstPost: return s.postCount >= 1
        case .posts10: return s.postCount >= 10
        case .posts25: return s.postCount >= 25
        case .posts50: return s.postCount >= 50
        case .posts100: return s.postCount >= 100
        case .streak3: return s.longestStreak >= 3
        case .streak7: return s.longestStreak >= 7
        case .streak14: return s.longestStreak >= 14
        case .streak30: return s.longestStreak >= 30
        case .streak100: return s.longestStreak >= 100
        case .under60: return (s.bestTime ?? .infinity) <= 60
        case .under30: return (s.bestTime ?? .infinity) <= 30
        case .under10: return (s.bestTime ?? .infinity) <= 10
        case .under5: return (s.bestTime ?? .infinity) <= 5
        case .fast10: return s.fastCount(60) >= 10
        case .fast30x5: return s.fastCount(30) >= 5
        case .friends1: return s.friendCount >= 1
        case .friends3: return s.friendCount >= 3
        case .friends5: return s.friendCount >= 5
        case .friends10: return s.friendCount >= 10
        case .cities3: return s.cityCount >= 3
        case .cities10: return s.cityCount >= 10
        case .earlyBird: return s.earlyBird
        case .nightOwl: return s.nightOwl
        case .weekend: return s.weekendPosts >= 4
        case .caption10: return s.captionCount >= 10
        case .dual10: return s.dualCount >= 10
        case .full3: return s.fullDays >= 1
        case .full3x7: return s.fullDays >= 7
        case .public10: return s.publicCount >= 10
        }
    }
}

/// 同じ系統のトロフィー（表示のためだけの分け方。サーバーには、これまでどおり個別の名前で置く）
struct TrophyFamily: Identifiable {
    let tiers: [Trophy]   // 低い段階から順に
    var id: String { tiers[0].key }

    static let all: [TrophyFamily] = [
        TrophyFamily(tiers: [.firstPost, .posts10, .posts25, .posts50, .posts100]),
        TrophyFamily(tiers: [.streak3, .streak7, .streak14, .streak30, .streak100]),
        TrophyFamily(tiers: [.under60, .under30, .under10, .under5]),
        TrophyFamily(tiers: [.friends1, .friends3, .friends5, .friends10]),
        TrophyFamily(tiers: [.cities3, .cities10]),
        TrophyFamily(tiers: [.full3, .full3x7]),
        TrophyFamily(tiers: [.fast10]), TrophyFamily(tiers: [.fast30x5]),
        TrophyFamily(tiers: [.earlyBird]), TrophyFamily(tiers: [.nightOwl]), TrophyFamily(tiers: [.weekend]),
        TrophyFamily(tiers: [.caption10]), TrophyFamily(tiers: [.dual10]), TrophyFamily(tiers: [.public10]),
    ]

    /// いま獲得している、いちばん上の段階
    func current(_ earned: Set<Trophy>) -> Trophy? { tiers.last { earned.contains($0) } }
    /// 次に目指す段階（全部取っていれば nil）
    func next(_ earned: Set<Trophy>) -> Trophy? { tiers.first { !earned.contains($0) } }
    func earnedCount(_ earned: Set<Trophy>) -> Int { tiers.filter { earned.contains($0) }.count }
}

/// 1つの系統を1マスで見せる：いまの段階の名前と、段階の点。次の目標を、下に小さく
struct TrophyFamilyCell: View {
    let family: TrophyFamily
    let earned: Set<Trophy>
    var showNext = true

    var body: some View {
        let current = family.current(earned)
        let shown = current ?? family.tiers[0]
        let on = current != nil
        let next = family.next(earned)
        VStack(spacing: 6) {
            Image(systemName: shown.icon).font(.title2)
                .foregroundStyle(on ? Hi.neon : Hi.dim.opacity(0.35)).frame(height: 30)
            Text(shown.title).font(.caption.weight(.black))
                .foregroundStyle(on ? .white : Hi.dim)
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            if family.tiers.count > 1 {
                HStack(spacing: 4) {
                    ForEach(Array(family.tiers.enumerated()), id: \.offset) { i, tier in
                        Circle().fill(earned.contains(tier) ? Hi.neon : Hi.dim.opacity(0.3)).frame(width: 6, height: 6)
                    }
                }
            }
            if showNext {
                Text(!on ? shown.detail : (next.map { LF("次：{t}", ["t": $0.title]) } ?? L("すべて達成")))
                    .font(.system(size: 11)).foregroundStyle(Hi.dim)
                    .multilineTextAlignment(.center).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: showNext ? 118 : 70, alignment: .top)
        .padding(.vertical, 10).padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(family.earnedCount(earned)) / \(family.tiers.count)")
    }
}

/// トロフィー判定に使う、集計済みの数字
struct AchievementInput {
    let postCount: Int
    let longestStreak: Int
    let bestTime: TimeInterval?
    let friendCount: Int
    let cityCount: Int
    let captionCount: Int
    let dualCount: Int
    let publicCount: Int
    let weekendPosts: Int
    let fullDays: Int
    let earlyBird: Bool
    let nightOwl: Bool
    private let times: [TimeInterval]

    init(records: [PromptRecord], friendCount: Int) {
        let posted = records.filter { $0.postedPhotoFile != nil }
        postCount = posted.count
        bestTime = TimeAttackStats(records: records).best
        self.friendCount = friendCount
        longestStreak = AchievementInput.longestStreak(of: Set(posted.map(\.dayKey)))
        times = TimeAttackStats(records: records).times.map(\.elapsed)
        cityCount = Set(posted.compactMap { $0.city?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }).count
        captionCount = posted.filter { !($0.caption ?? "").trimmingCharacters(in: .whitespaces).isEmpty }.count
        dualCount = posted.filter { $0.frontPhotoFile != nil }.count
        publicCount = posted.filter(\.isForPublic).count
        let calendar = Calendar.current
        let dates = posted.compactMap(\.postedAt)
        weekendPosts = dates.filter { calendar.isDateInWeekend($0) }.count
        earlyBird = dates.contains { (5..<7).contains(calendar.component(.hour, from: $0)) }
        nightOwl = dates.contains { let h = calendar.component(.hour, from: $0); return h >= 23 || h < 4 }
        let perDay = Dictionary(grouping: posted, by: \.dayKey).mapValues(\.count)
        fullDays = perDay.values.filter { $0 >= 3 }.count
    }

    /// 通知から seconds 秒以内に投稿した回数
    func fastCount(_ seconds: TimeInterval) -> Int { times.filter { $0 <= seconds }.count }

    /// 投稿した日（yyyy-MM-dd）の、最長の連続日数
    private static func longestStreak(of keys: Set<String>) -> Int {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current
        let dates = keys.compactMap { formatter.date(from: $0) }.sorted()
        var best = 0
        var run = 0
        var previous: Date?
        for date in dates {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == date {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = date
        }
        return best
    }
}

/// タイムの表示（例：1:23.4）は TodayView.swift の TimeFormat を使う

/// 世界ランキングの1人分
struct WorldRankEntry: Identifiable {
    let id = UUID()
    let name: String
    let countryCode: String
    let city: String
    let time: TimeInterval
    let isYou: Bool
    var trophies: [Trophy] = []
    var rank: Rank = .bronze

    /// 国コード（例："JP"）から国旗の絵文字
    var flag: String {
        if countryCode.isEmpty { return "🌐" }
        return countryCode.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(127397 + $0.value) }
            .map { String($0) }
            .joined()
    }
}

/// タイムアタックのランキング。世界を4つの地域（東アジア・オセアニア／南アジア・中東／ヨーロッパ・アフリカ／アメリカ）に分け、
/// 「世界」で全員をまとめて見られる。今日の公開投稿のタイムを、速い順に並べる。
enum WorldRanking {
    static let regions = [0, 1, 2, 3]
    static let world = 4          // 全員

    static func regionName(_ region: Int) -> String {
        region == world ? L("世界") : L(PostStore.regionShortNames[region])
    }

    /// 今日のランキング（速い順）。region が world なら全員
    static func board(region: Int, others: [WorldTime], myBest: TimeInterval?, myName: String,
                      myTrophies: [Trophy] = [], myRank: Rank = .bronze) -> [WorldRankEntry] {
        var list = others
            .filter { region == world || PostStore.regionIndex(forOffset: $0.tzOffset) == region }
            .map { WorldRankEntry(name: "@" + $0.handle, countryCode: "", city: $0.city, time: $0.elapsed, isYou: false) }
        if let myBest, region == world || region == PostStore.regionIndex {
            list.append(WorldRankEntry(name: myName, countryCode: "", city: L("あなた"), time: myBest,
                                       isYou: true, trophies: myTrophies, rank: myRank))
        }
        return Array(list.sorted { $0.time < $1.time }.prefix(50))
    }
}

/// 同じ入力から、いつも同じ並びを出すための乱数
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

/// 名前のそばに出す、小さなトロフィーのアイコン（他の人からも見える）
struct TrophyBadges: View {
    let trophies: [Trophy]
    var limit: Int = 3
    var color: Color = Hi.neon

    var body: some View {
        let shown = Trophy.showcase(trophies, limit: limit)
        HStack(spacing: 3) {
            ForEach(shown) { trophy in
                Image(systemName: trophy.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(color)
            }
            if trophies.count > shown.count {
                Text(LF("他{n}個", ["n": "\(trophies.count - shown.count)"]))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(color.opacity(0.7))
                    .fixedSize()
            }
        }
    }
}

/// ハンドル名（Instagramのような @名前）のルール
enum HandleRule {
    static let minLength = 3
    static let maxLength = 20

    /// 問題があれば、その説明を返す（問題なければ nil）
    static func error(for handle: String) -> String? {
        if handle.count < minLength { return LF("{n}文字以上にしてください", ["n": "\(minLength)"]) }
        if handle.count > maxLength { return LF("{n}文字以内にしてください", ["n": "\(maxLength)"]) }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789._")
        if handle.contains(where: { !allowed.contains($0) }) {
            return L("使えるのは、英小文字・数字・ピリオド(.)・アンダースコア(_)だけです")
        }
        if handle.hasPrefix(".") || handle.hasSuffix(".") { return L("ピリオドを最初や最後には使えません") }
        if handle.contains("..") { return L("ピリオドを続けて使えません") }
        return nil
    }

    /// 入力を整える（前後の空白を消し、小文字にする。先頭の @ は取る）
    static func normalize(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.hasPrefix("@") { t.removeFirst() }
        return t
    }
}

// MARK: - ランク（月ごとのポイントで決まる）

/// ランク。トロフィーとは別に、その月に貯めたポイントで決まり、月が変わるとリセットされる。
enum Rank: Int, CaseIterable, Comparable {
    case bronze, silver, gold, platinum, diamond, master, grandmaster, legend

    static func < (a: Rank, b: Rank) -> Bool { a.rawValue < b.rawValue }

    var name: String {
        switch self {
        case .bronze: return L("ブロンズ")
        case .silver: return L("シルバー")
        case .gold: return L("ゴールド")
        case .platinum: return L("プラチナ")
        case .diamond: return L("ダイヤ")
        case .master: return L("マスター")
        case .grandmaster: return L("グランドマスター")
        case .legend: return L("レジェンド")
        }
    }

    /// このランクになるのに必要な、その月のポイント
    var threshold: Int {
        switch self {
        case .bronze: return 0
        case .silver: return 60
        case .gold: return 150
        case .platinum: return 280
        case .diamond: return 450
        case .master: return 650
        case .grandmaster: return 900
        case .legend: return 1200
        }
    }

    var color: Color {
        switch self {
        case .bronze: return Color(red: 0.80, green: 0.50, blue: 0.20)
        case .silver: return Color(red: 0.78, green: 0.80, blue: 0.85)
        case .gold: return .yellow
        case .platinum: return .cyan
        case .diamond: return Color(red: 0.55, green: 0.60, blue: 1.0)
        case .master: return Color(red: 0.78, green: 0.45, blue: 1.0)
        case .grandmaster: return Color(red: 1.0, green: 0.42, blue: 0.38)
        case .legend: return Color(red: 1.0, green: 0.45, blue: 0.80)
        }
    }

    var icon: String {
        switch self {
        case .bronze, .silver, .gold: return "medal.fill"
        case .platinum: return "crown.fill"
        case .diamond: return "diamond.fill"
        case .master: return "star.circle.fill"
        case .grandmaster: return "flame.fill"
        case .legend: return "sparkles"
        }
    }

    var next: Rank? { Rank(rawValue: rawValue + 1) }

    static func rank(forPoints points: Int) -> Rank {
        allCases.last { points >= $0.threshold } ?? .bronze
    }
}

/// 月ごとのポイント計算
///
/// - お題に合う写真と確認できた投稿：1回 +10
/// - 確認できなかった投稿：1回 +3
/// - 早さボーナス（1日1回）：通知から5分以内 +10、30分以内 +6、90分以内 +3
/// - 連続ボーナス：連続2日目から、1日ごとに +1（最大 +5）
struct MonthlyPoints {
    let month: String          // "2026-11"
    let total: Int
    let postPoints: Int
    let speedPoints: Int
    let streakPoints: Int

    var rank: Rank { Rank.rank(forPoints: total) }

    /// 次のランクまでのポイント（最高ランクなら nil）
    var pointsToNext: Int? {
        guard let next = rank.next else { return nil }
        return max(0, next.threshold - total)
    }

    /// 次のランクに向かう進み具合（0〜1）
    var progress: Double {
        guard let next = rank.next else { return 1 }
        let span = Double(next.threshold - rank.threshold)
        return min(1, max(0, Double(total - rank.threshold) / span))
    }

    static func monthKey(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f.string(from: date)
    }

    init(records: [PromptRecord], month: String) {
        self.month = month
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current

        let posted = records.filter { $0.postedPhotoFile != nil }
        // 連続の何日目か（月をまたいだ連続も数える）
        let days = Set(posted.map(\.dayKey))
            .compactMap { formatter.date(from: $0).map { (key: formatter.string(from: $0), date: $0) } }
            .sorted { $0.date < $1.date }
        var runPosition: [String: Int] = [:]
        var run = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day.date {
                run += 1
            } else {
                run = 1
            }
            runPosition[day.key] = run
            previous = day.date
        }

        // 点の決め方（お題が確かめられるかどうかで、同じ点になるように）
        //  ・お題に合うと確認できた写真：10点。確認できないお題の写真も、期限内なら10点（ランキングには入らない）
        //  ・お題と違うかもしれないと言われた写真：3点
        //  ・早さのボーナスは、1日1回。確認できないお題にも同じく付く
        //  ・連続のボーナスは、続けた日数に応じて1日最大10点
        var post = 0, speed = 0, streak = 0
        let postedInMonth = posted.filter { $0.dayKey.hasPrefix(month) }
        func counts(_ r: PromptRecord) -> Bool {
            r.verified == true || !PromptVerifier.canVerify(r.prompt)
        }
        for record in postedInMonth {
            post += counts(record) ? 10 : 3
        }
        for (dayKey, dayRecords) in Dictionary(grouping: postedInMonth, by: \.dayKey) {
            if let best = dayRecords.filter(counts).compactMap(\.elapsed).min() {
                if best <= 5 * 60 { speed += 10 } else if best <= 30 * 60 { speed += 6 } else if best <= 90 * 60 { speed += 3 }
            }
            streak += min(10, max(0, (runPosition[dayKey] ?? 1) - 1))
        }
        postPoints = post
        speedPoints = speed
        streakPoints = streak
        total = post + speed + streak
    }
}

/// 名前のそばに出す、ランクの小さなバッジ（他の人からも見える）
struct RankBadge: View {
    let rank: Rank

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: rank.icon)
                .font(.system(size: 10))
            Text(rank.name)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .fixedSize()
        }
        .fixedSize()
        .foregroundStyle(rank.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(rank.color.opacity(0.18)))
    }
}

/// ランクの一覧：必要なポイントと、いまのランク
struct RankListSheet: View {
    let points: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    let current = Rank.rank(forPoints: points)
                    ForEach(Array(Rank.allCases.reversed()), id: \.self) { rank in
                        let reached = points >= rank.threshold
                        HStack(spacing: 14) {
                            Image(systemName: rank.icon)
                                .font(.title2)
                                .foregroundStyle(rank.color)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(rank.color.opacity(0.18)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rank.name).font(.headline.weight(.black))
                                Text(LF("{n} pt〜", ["n": "\(rank.threshold)"]))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(Hi.dim)
                            }
                            Spacer()
                            if rank == current {
                                Text(L("いまのランク"))
                                    .font(.caption.weight(.black))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Capsule().fill(Hi.neon))
                                    .foregroundStyle(Hi.onNeon)
                            } else if reached {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Hi.dim)
                            }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(rank == current ? rank.color.opacity(0.22) : Hi.tile))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(rank == current ? rank.color : .clear, lineWidth: 2))
                        .opacity(reached ? 1 : 0.65)
                    }
                    Text(LF("今月 {n} ポイント", ["n": "\(points)"]))
                        .font(.caption).foregroundStyle(Hi.dim)
                        .padding(.top, 6)
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(L("ランク一覧"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("閉じる")) { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.black)
        .preferredColorScheme(.dark)
    }
}
