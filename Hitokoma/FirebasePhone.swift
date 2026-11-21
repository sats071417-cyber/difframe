import Foundation
import FirebaseCore
import FirebaseAuth

/// Firebase の設定ファイル（GoogleService-Info.plist）が入っているビルドだけ、本物のSMS認証を使う
enum FirebaseBoot {
    static var available: Bool { Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil }

    static func configure() {
        guard available, FirebaseApp.app() == nil else { return }
        FirebaseApp.configure()
    }

    /// 認証の途中で開いた画面（reCAPTCHA）から戻ってきたリンクか
    static func canHandle(_ url: URL) -> Bool {
        available && Auth.auth().canHandle(url)
    }
}

/// 本物のSMS：コードを送るところは Firebase Auth（アプリの確認や reCAPTCHA もここで行う）。
/// コードの確認と、いまのアカウントへの結びつけは、アカウント本体（Cloud.swift）が行う。
final class FirebasePhoneAuth: Hitokoma.PhoneAuthProvider {
    static let shared = FirebasePhoneAuth()
    private var sessions: [String: String] = [:]   // 電話番号 → SMS の確認ID
    var isReal: Bool { true }

    func sendCode(to e164: String) async throws -> String? {
        Auth.auth().useAppLanguage()
        let id = try await FirebaseAuth.PhoneAuthProvider.provider().verifyPhoneNumber(e164, uiDelegate: nil)
        sessions[e164] = id
        return nil
    }

    func verify(code: String, for e164: String) async -> Bool {
        guard let session = sessions[e164] else { return false }
        do {
            try await CloudSync.shared.completePhoneSignIn(sessionInfo: session, code: code, phone: e164)
            return true
        } catch {
            NSLog("phone verify failed: \(error)")
            return false
        }
    }
}
