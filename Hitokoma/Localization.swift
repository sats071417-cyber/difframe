import Foundation

/// アプリの表示言語。標準は英語。日本語などは、プロフィールの設定で選んだときだけ。
enum AppLanguage: String, CaseIterable, Identifiable {
    case en, ja, zh, ko, es, fr

    var id: String { rawValue }

    /// 設定画面に出す名前（その言語で書く）
    var label: String {
        switch self {
        case .en: return "English"
        case .ja: return "日本語"
        case .zh: return "中文（简体）"
        case .ko: return "한국어"
        case .es: return "Español"
        case .fr: return "Français"
        }
    }

    static let storageKey = "appLanguage"

    /// 表示する言語。プロフィールで選んだものがあれば、それを使う。
    /// 選んでいなければ iPhone の言語に合わせ、対応していない言語なら英語にする。
    static var current: AppLanguage {
        if let chosen = UserDefaults.standard.string(forKey: storageKey), let lang = AppLanguage(rawValue: chosen) {
            return lang
        }
        return device
    }

    /// アプリの言語を、iPhone の「このアプリの言語」にも伝える。
    /// こうすると、次にアプリを開いたときから、地図の「法律に基づく情報」など、Apple の画面も、アプリの言語で出る。
    /// 言語を選んでいない（iPhone に合わせる）ときは、上書きをやめる
    static func syncSystemLanguage() {
        let defaults = UserDefaults.standard
        guard let chosen = defaults.string(forKey: storageKey), let lang = AppLanguage(rawValue: chosen) else {
            if defaults.object(forKey: "AppleLanguages") != nil { defaults.removeObject(forKey: "AppleLanguages") }
            return
        }
        let code = lang == .zh ? "zh-Hans" : lang.rawValue
        if (defaults.array(forKey: "AppleLanguages") as? [String])?.first != code {
            defaults.set([code], forKey: "AppleLanguages")
        }
    }

    /// iPhone の言語（対応していなければ英語）
    static var device: AppLanguage {
        for code in Locale.preferredLanguages {
            let c = code.lowercased()
            if c.hasPrefix("ja") { return .ja }
            if c.hasPrefix("zh") { return .zh }      // 繁体字も、いまは簡体字で出す
            if c.hasPrefix("ko") { return .ko }
            if c.hasPrefix("es") { return .es }
            if c.hasPrefix("fr") { return .fr }
            if c.hasPrefix("en") { return .en }
        }
        return .en
    }
}

/// 文字列の表。キーは、もとの日本語の文字そのもの。日本語は表を使わずそのまま出す。
enum L10n {
    static func text(_ key: String) -> String {
        switch AppLanguage.current {
        case .ja: return key
        case .en: return en[key] ?? key
        case .zh: return zh[key] ?? en[key] ?? key
        case .ko: return ko[key] ?? en[key] ?? key
        case .es: return es[key] ?? en[key] ?? key
        case .fr: return fr[key] ?? en[key] ?? key
        }
    }

    /// 2つの表の、同じキーは先のものを使う（キーの重複で止まらないように）
    static func table(_ pairs: [(String, String)]) -> [String: String] {
        Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }
}

/// 表示する文字列
func L(_ key: String) -> String { L10n.text(key) }

/// 差し込みのある文字列。{名前} の部分を、args の値に置き換える。
func LF(_ key: String, _ args: [String: String]) -> String {
    var s = L(key)
    for (name, value) in args { s = s.replacingOccurrences(of: "{\(name)}", with: value) }
    return s
}

/// 時刻の書き方：12時間か24時間かは、iPhone の設定に合わせる（言語はアプリの言語）
enum Clock {
    /// iPhone が24時間表示か（設定 → 一般 → 日付と時刻）
    static var uses24h: Bool {
        let f = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Locale.current) ?? ""
        return !f.contains("a")
    }

    static func string(_ date: Date, zone: TimeZone? = nil) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: AppLanguage.current.rawValue)
        if let zone { f.timeZone = zone }
        f.setLocalizedDateFormatFromTemplate(uses24h ? "Hm" : "hm")
        return f.string(from: date)
    }
}

extension Date {
    /// 日付・時刻の書き方を、端末の言語ではなく、アプリの言語で作る（時刻の12/24時間は、iPhone の設定）
    func appFormatted(date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> String {
        let locale = Locale(identifier: AppLanguage.current.rawValue)
        if time == .omitted { return formatted(Date.FormatStyle(date: date, time: .omitted).locale(locale)) }
        let clock = Clock.string(self)
        if date == .omitted { return clock }
        return formatted(Date.FormatStyle(date: date, time: .omitted).locale(locale)) + " " + clock
    }
}
