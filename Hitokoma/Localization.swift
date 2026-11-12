import Foundation

/// アプリの表示言語。標準は英語。日本語などは、プロフィールの設定で選んだときだけ。
enum AppLanguage: String, CaseIterable, Identifiable {
    case en, ja, zh, ko, es

    var id: String { rawValue }

    /// 設定画面に出す名前（その言語で書く）
    var label: String {
        switch self {
        case .en: return "English"
        case .ja: return "日本語"
        case .zh: return "中文（简体）"
        case .ko: return "한국어"
        case .es: return "Español"
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

    /// iPhone の言語（対応していなければ英語）
    static var device: AppLanguage {
        for code in Locale.preferredLanguages {
            let c = code.lowercased()
            if c.hasPrefix("ja") { return .ja }
            if c.hasPrefix("zh") { return .zh }      // 繁体字も、いまは簡体字で出す
            if c.hasPrefix("ko") { return .ko }
            if c.hasPrefix("es") { return .es }
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
