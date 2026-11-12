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
