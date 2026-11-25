import Foundation

/// アプリがウィジェットに渡す、いまの状況（連続日数など）。
/// App Group が使えるときだけ共有される。使えないときは nil になり、ウィジェットは仮の表示になる。
struct WidgetSnapshot: Codable, Equatable {
    var streak: Int
    var postedToday: Int
    var maxPerDay: Int
    var prompt: String
    var updatedAt: Date
    var lang: String? = nil      // アプリで選んでいる言語（en/ja/zh/ko/es）
    var startedAt: Date? = nil   // いま見せる日のお題が届いた時刻（タイムの開始。ウィジェットで時間を数える）
    var hidden: Bool? = nil      // お題がまだ届いていない（秘密）
    var colorName: String? = nil // 色のお題なら、その色（red / blue など）
    var lastTime: TimeInterval? = nil  // いちばん新しい投稿のタイム

    private static let key = "widgetSnapshot"

    private static var defaults: UserDefaults? {
        guard let id = AppGroup.id else { return nil }
        return UserDefaults(suiteName: id)
    }

    static func load() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// 保存する。変わったときだけ true を返す
    @discardableResult
    func save() -> Bool {
        guard let defaults = Self.defaults else { return false }
        if let old = Self.load(), old.streak == streak, old.postedToday == postedToday, old.prompt == prompt, old.lang == lang,
           old.startedAt == startedAt, old.hidden == hidden, old.lastTime == lastTime { return false }
        guard let data = try? JSONEncoder().encode(self) else { return false }
        defaults.set(data, forKey: Self.key)
        return true
    }
}

/// カレンダー・自分の投稿・友達の投稿のウィジェットに渡すデータ。
/// 写真は App Group の中の「WidgetImages」に小さくして置き、ここにはファイル名だけを入れる。
struct WidgetFeed: Codable, Equatable {
    struct Mine: Codable, Equatable {
        var file: String          // WidgetImages の中のファイル名
        var prompt: String        // 表示用（翻訳済み）
        var dayKey: String
        var elapsed: Double?      // タイム（秒）
    }
    struct Friend: Codable, Equatable {
        var id: String
        var file: String
        var name: String
        var prompt: String
        var city: String?
        var postedAt: Date
    }

    var postedDays: [String]      // 投稿した日（yyyy-MM-dd）
    var streak: Int
    var mine: [Mine]              // 新しい順
    var friends: [Friend]         // 新しい順
    var friendsUnlocked: Bool     // いまのお題に、自分が投稿したか（したときだけ友達の投稿を見せる）
    var lockAt: Date?             // 次のお題が届く時刻。過ぎたら、また投稿するまで隠す
    var lang: String?
    var updatedAt: Date

    private static let key = "widgetFeed"
    private static var defaults: UserDefaults? { AppGroup.id.flatMap { UserDefaults(suiteName: $0) } }

    /// 写真を置く場所（App Group が使えないときは nil）
    static var imageDir: URL? {
        guard let id = AppGroup.id,
              let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else { return nil }
        let dir = base.appendingPathComponent("WidgetImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func load() -> WidgetFeed? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetFeed.self, from: data)
    }

    /// 保存する。中身が変わったときだけ true（updatedAt は比べない）
    @discardableResult
    func save() -> Bool {
        guard let defaults = Self.defaults else { return false }
        if var old = Self.load() {
            old.updatedAt = updatedAt
            if old == self { return false }
        }
        guard let data = try? JSONEncoder().encode(self) else { return false }
        defaults.set(data, forKey: Self.key)
        return true
    }

    /// 友達の投稿を、いま見せてよいか
    func friendsVisible(at now: Date) -> Bool {
        guard friendsUnlocked else { return false }
        if let lockAt, now >= lockAt { return false }
        return true
    }
}
