import Foundation
import SwiftUI

/// 電話番号の確認（SMS）を行う窓口。
/// 本物のSMS認証にはサーバー（Firebase Authなど）が必要なので、いまは DemoPhoneAuth だけを使う。
/// あとで本物に差し替えるときは、このプロトコルに合わせて作ればよい。
protocol PhoneAuthProvider {
    /// 確認コードを送る。デモでは送らずに、画面に出すコードを返す。
    func sendCode(to e164: String) async throws -> String?
    /// 入力されたコードが正しいか
    func verify(code: String, for e164: String) async -> Bool
    /// 本物のSMSか（falseならデモ）
    var isReal: Bool { get }
}

/// デモ用：SMSは送らない。コードを画面に表示する。電話番号の持ち主かどうかは確認できない。
final class DemoPhoneAuth: PhoneAuthProvider {
    private var codes: [String: String] = [:]
    var isReal: Bool { false }

    func sendCode(to e164: String) async throws -> String? {
        try await Task.sleep(nanoseconds: 400_000_000)
        let code = String(format: "%06d", Int.random(in: 0...999_999))
        codes[e164] = code
        return code
    }

    func verify(code: String, for e164: String) async -> Bool {
        codes[e164] == code
    }
}

/// 国番号の候補
struct Country: Identifiable, Hashable {
    let region: String
    let name: String
    let dial: String
    var id: String { region }

    var flag: String {
        region.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }
            .map { String($0) }.joined()
    }

    static let all: [Country] = [
        Country(region: "JP", name: L("日本"), dial: "81"),
        Country(region: "US", name: L("アメリカ"), dial: "1"),
        Country(region: "CA", name: L("カナダ"), dial: "1"),
        Country(region: "GB", name: L("イギリス"), dial: "44"),
        Country(region: "FR", name: L("フランス"), dial: "33"),
        Country(region: "DE", name: L("ドイツ"), dial: "49"),
        Country(region: "KR", name: L("韓国"), dial: "82"),
        Country(region: "CN", name: L("中国"), dial: "86"),
        Country(region: "TW", name: L("台湾"), dial: "886"),
        Country(region: "SG", name: L("シンガポール"), dial: "65"),
        Country(region: "AU", name: L("オーストラリア"), dial: "61"),
        Country(region: "IN", name: L("インド"), dial: "91"),
        Country(region: "BR", name: L("ブラジル"), dial: "55"),
        Country(region: "MX", name: L("メキシコ"), dial: "52"),
        Country(region: "KE", name: L("ケニア"), dial: "254"),
    ]

    /// 端末の地域に合う国（なければ日本）
    static var current: Country {
        let code = Locale.current.region?.identifier ?? "JP"
        return all.first { $0.region == code } ?? all[0]
    }
}

/// アカウント（電話番号）。電話番号はこの端末の中にだけ保存する。サーバーへは送らない。
enum Account {
    static let phoneKey = "accountPhone"          // E.164形式（例：+819012345678）
    static let verifiedKey = "accountVerified"    // 本物のSMSで確認できたか
    static let doneKey = "signUpDone"             // 登録の画面を終えたか（「あとで」も含む）

    /// 入力を E.164 形式にする。数字が足りなければ nil。
    static func e164(country: Country, input: String) -> String? {
        var digits = input.filter { $0.isASCII && $0.isNumber }
        if input.contains(where: { $0.isNumber && !$0.isASCII }) {
            // 全角数字も受け付ける
            digits = input.compactMap { $0.wholeNumberValue.map(String.init) }.joined()
        }
        while digits.hasPrefix("0") { digits.removeFirst() }
        guard digits.count >= 6, digits.count <= 12 else { return nil }
        return "+" + country.dial + digits
    }

    /// 表示用に、後ろ4桁だけ見せる（例：+81 ••• 5678）
    static func masked(_ e164: String) -> String {
        guard e164.count > 6 else { return e164 }
        return "••••• " + e164.suffix(4)
    }
}
