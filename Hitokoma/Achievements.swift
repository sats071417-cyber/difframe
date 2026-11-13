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
    case streak3, streak7, streak30
    case under60, under30, under10
    case posts10
    case friends3

    var id: Self { self }

    var title: String {
        switch self {
        case .firstPost: return L("はじめての一枚")
        case .streak3: return L("3日連続")
        case .streak7: return L("7日連続")
        case .streak30: return L("30日連続")
        case .under60: return L("1分以内")
        case .under30: return L("30秒以内")
        case .under10: return L("10秒以内")
        case .posts10: return L("10枚投稿")
        case .friends3: return L("友達3人")
        }
    }

    var detail: String {
        switch self {
        case .firstPost: return L("初めて投稿した")
        case .streak3: return L("3日続けて投稿した")
        case .streak7: return L("7日続けて投稿した")
        case .streak30: return L("30日続けて投稿した")
        case .under60: return L("通知から1分以内に投稿した")
        case .under30: return L("通知から30秒以内に投稿した")
        case .under10: return L("通知から10秒以内に投稿した")
        case .posts10: return L("合計10枚投稿した")
        case .friends3: return L("友達を3人追加した")
        }
    }

    var icon: String {
        switch self {
        case .firstPost: return "camera.fill"
        case .streak3, .streak7, .streak30: return "flame.fill"
        case .under60: return "stopwatch.fill"
        case .under30: return "hare.fill"
        case .under10: return "bolt.fill"
        case .posts10: return "photo.stack.fill"
        case .friends3: return "person.3.fill"
        }
    }

    /// 他の人に見せるときの優先度（大きいほど珍しい）
    var priority: Int {
        switch self {
        case .streak30: return 9
        case .under10: return 8
        case .streak7: return 7
        case .under30: return 6
        case .posts10: return 5
        case .under60: return 4
        case .streak3: return 3
        case .friends3: return 2
        case .firstPost: return 1
        }
    }

    /// 他の人に見せる、珍しいトロフィー（優先度の高い順）
    static func showcase(_ trophies: [Trophy], limit: Int = 3) -> [Trophy] {
        Array(trophies.sorted { $0.priority > $1.priority }.prefix(limit))
    }

    /// 達成しているかどうか
    func isUnlocked(_ s: AchievementInput) -> Bool {
        switch self {
        case .firstPost: return s.postCount >= 1
        case .streak3: return s.longestStreak >= 3
        case .streak7: return s.longestStreak >= 7
        case .streak30: return s.longestStreak >= 30
        case .under60: return (s.bestTime ?? .infinity) <= 60
        case .under30: return (s.bestTime ?? .infinity) <= 30
        case .under10: return (s.bestTime ?? .infinity) <= 10
        case .posts10: return s.postCount >= 10
        case .friends3: return s.friendCount >= 3
        }
    }
}

/// トロフィー判定に使う、集計済みの数字
struct AchievementInput {
    let postCount: Int
    let longestStreak: Int
    let bestTime: TimeInterval?
    let friendCount: Int

    init(records: [PromptRecord], friendCount: Int) {
        let posted = records.filter { $0.postedPhotoFile != nil }
        postCount = posted.count
        bestTime = TimeAttackStats(records: records).best
        self.friendCount = friendCount
        longestStreak = AchievementInput.longestStreak(of: Set(posted.map(\.dayKey)))
    }

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

/// 世界ランキングの1人分（サンプル。サーバーがないため、サンプルの人と自分の記録を並べる）
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

/// タイムアタックのランキング。世界を4つの地域に分ける（東アジア・オセアニア／南アジア・中東／ヨーロッパ・アフリカ／アメリカ）。
/// サーバーがないので、他の人はサンプル。地域ごとに、同じ顔ぶれが出る。
enum WorldRanking {
    static let regions = [0, 1, 2, 3]

    static func regionName(_ region: Int) -> String { L(PostStore.regionShortNames[region]) }

    /// ランキングに出す人数
    private static let boardSize = 10

    /// 地域に住む、サンプルの人たち（その地域に都市があれば、その人たちを先に入れる）。足りない分は、地域ごとに決まった顔ぶれで補う
    private static func entries(region: Int, at date: Date = Date()) -> [WorldRankEntry] {
        var result = WorldSamples.all
            .filter { PostStore.regionIndex(forOffset: $0.timeZone.secondsFromGMT(for: date)) == region }
            .map { WorldRankEntry(name: "@" + $0.handle, countryCode: $0.code, city: $0.city, time: $0.time,
                                  isYou: false, trophies: $0.trophies, rank: $0.rank) }

        let handles = ["mika.k", "alex_r", "noor.h", "tomas.v", "yui.s", "dara_o", "sam.lee", "ines_p", "kofi.a",
                       "lila.m", "ravi_n", "hana.t", "omar.z", "eva_k", "zoe.b", "ken.u", "ana_c", "ben.w",
                       "lars.j", "maya_d", "joon.p", "sana.r", "theo_f", "nina.q"]
        var seed = UInt64(region + 1) &* 2_654_435_761 &+ 97
        func next() -> UInt64 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return seed >> 33
        }
        var generator = SeededGenerator(state: seed)
        var pool = handles.shuffled(using: &generator)
        pool.removeAll { name in result.contains { $0.name == "@" + name } }
        while result.count < boardSize, let name = pool.popLast() {
            let time = 9 + Double(next() % 1400) / 10   // 9.0〜148.9秒
            let rank: Rank = time < 15 ? .platinum : time < 35 ? .gold : time < 70 ? .silver : .bronze
            let trophies: [Trophy] = time < 12 ? [.under10, .streak7, .firstPost]
                : time < 32 ? [.under30, .firstPost]
                : time < 62 ? [.under60, .firstPost] : [.firstPost]
            result.append(WorldRankEntry(name: "@" + name, countryCode: "", city: "", time: (time * 10).rounded() / 10,
                                         isYou: false, trophies: trophies, rank: rank))
        }
        return result
    }

    /// その地域のランキング（速い順）。自分の地域なら、自己ベストを入れる
    static func board(region: Int, myBest: TimeInterval?, myName: String, myTrophies: [Trophy] = [],
                      myRank: Rank = .bronze) -> [WorldRankEntry] {
        var all = entries(region: region)
        if region == PostStore.regionIndex, let myBest {
            all.append(WorldRankEntry(name: myName, countryCode: "", city: L("あなた"), time: myBest,
                                      isYou: true, trophies: myTrophies, rank: myRank))
        }
        return all.sorted { $0.time < $1.time }
    }

    /// 自分の地域での順位（記録がなければ nil）
    static func position(myBest: TimeInterval?) -> Int? {
        guard let myBest else { return nil }
        return entries(region: PostStore.regionIndex).filter { $0.time < myBest }.count + 1
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
    case bronze, silver, gold, platinum, diamond

    static func < (a: Rank, b: Rank) -> Bool { a.rawValue < b.rawValue }

    var name: String {
        switch self {
        case .bronze: return L("ブロンズ")
        case .silver: return L("シルバー")
        case .gold: return L("ゴールド")
        case .platinum: return L("プラチナ")
        case .diamond: return L("ダイヤ")
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
        }
    }

    var color: Color {
        switch self {
        case .bronze: return Color(red: 0.80, green: 0.50, blue: 0.20)
        case .silver: return Color(red: 0.78, green: 0.80, blue: 0.85)
        case .gold: return .yellow
        case .platinum: return .cyan
        case .diamond: return Color(red: 0.55, green: 0.60, blue: 1.0)
        }
    }

    var icon: String {
        switch self {
        case .bronze, .silver, .gold: return "medal.fill"
        case .platinum: return "crown.fill"
        case .diamond: return "diamond.fill"
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
