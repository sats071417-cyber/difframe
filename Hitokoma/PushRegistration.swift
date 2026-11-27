import SwiftUI
import UIKit
import UserNotifications
import FirebaseAuth
import FirebaseCore

/// アプリを閉じていても届くプッシュ通知（APNs）のための、端末の登録。
/// 端末のトークンを Firestore（devices/{uid}）に預けておくと、サーバー（Cloud Functions）が
/// 友達リクエスト・コメント・リアクション・友達の投稿・DM が来たときに、その端末へ通知を送る。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Firebase は、アプリ本体（UIApplication）ができたあとに設定する。早すぎると、電話認証の部品が作られない
        FirebaseBoot.configure()
        // 電話番号のSMS認証は、Apple の無音の通知で端末を確かめる。無音の通知は、通知の許可がなくても受け取れるので、
        // 許可を聞く前（はじめの登録画面）でも、通知の宛先をもらっておく
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // 電話番号のSMS認証：Firebase に、この端末の宛先を渡す（SwiftUI のアプリでは、自動では渡らない）
        FirebaseBoot.apnsToken = deviceToken
        FirebaseBoot.handOffAPNS(delay: 2)
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        // サーバーからの通知（友達の投稿など）の宛先は、通知の許可があるときだけ預ける
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                // 通知をオフにした端末：サーバーに預けた宛先を消す（アプリの中の通知に戻す）
                Task { @MainActor in await PushRegistration.shared.unregister() }
                return
            }
            Task { @MainActor in PushRegistration.shared.didReceive(token: token) }
        }
    }

    /// 電話番号のSMS認証では、Firebase が「この端末は本物か」を確かめる無音の通知を送ってくる。それを Firebase に渡す
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if FirebaseBoot.available, FirebaseApp.app() != nil { _ = Auth.auth().canHandleNotification(userInfo) }
        completionHandler(.noData)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // 登録できなかった端末は、これまでどおり「アプリを開いたとき・iOSが起こしたとき」に確かめる
        UserDefaults.standard.set(false, forKey: PushRegistration.registeredKey)
    }
}

@MainActor
final class PushRegistration {
    static let shared = PushRegistration()

    /// サーバーに登録済みか（登録済みなら、アプリ側で同じ通知をもう一度出さない）
    nonisolated static let registeredKey = "push.registered"
    private let tokenKey = "push.token"
    private let uploadedKey = "push.uploaded"

    /// 通知の許可がある端末で、プッシュの登録を頼む
    func register() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    /// 通知の許可がなくなったとき：サーバーの宛先を消して、端末の通知に戻す
    func unregister() async {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: uploadedKey) != nil || defaults.bool(forKey: Self.registeredKey) else { return }
        if let uid = CloudSync.shared.uid { try? await CloudSync.shared.delete("devices/\(uid)") }
        defaults.removeObject(forKey: uploadedKey)
        defaults.removeObject(forKey: uploadedKey + ".at")
        defaults.set(false, forKey: Self.registeredKey)
    }

    func didReceive(token: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
        Task { await upload(force: true) }
    }

    /// トークン・言語・ミュート中の種類を、サーバーに預ける（変わったときと、半日ごと）
    func upload(force: Bool = false) async {
        let defaults = UserDefaults.standard
        guard let token = defaults.string(forKey: tokenKey), CloudSync.shared.isOn else { return }
        let muted = CloudSync.pushTypes.filter { NotifySettings.isMuted($0) }
        let signature = [token, AppLanguage.current.rawValue, muted.joined(separator: ",")].joined(separator: "|")
        let last = defaults.string(forKey: uploadedKey) ?? ""
        let lastAt = defaults.double(forKey: uploadedKey + ".at")
        if !force, last == signature, Date().timeIntervalSince1970 - lastAt < 12 * 3600 { return }
        if await CloudSync.shared.registerDevice(token: token, env: Self.environment, lang: AppLanguage.current.rawValue, muted: muted) {
            defaults.set(signature, forKey: uploadedKey)
            defaults.set(Date().timeIntervalSince1970, forKey: uploadedKey + ".at")
            defaults.set(true, forKey: Self.registeredKey)
        }
    }

    /// この端末向けのプッシュを送る先（開発用ビルドは "sandbox"、ストア・TestFlight は "production"）
    static var environment: String {
        #if targetEnvironment(simulator)
        return "sandbox"
        #else
        // 開発用ビルドには、署名の情報（embedded.mobileprovision）が入っている。ストア配布のものには入っていない
        guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
              let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .isoLatin1),
              let range = text.range(of: "<key>aps-environment</key>") else { return "production" }
        let rest = text[range.upperBound...].prefix(80)
        return rest.contains("development") ? "sandbox" : "production"
        #endif
    }
}

extension CloudSync {
    /// プッシュ通知の種類（アプリの通知設定で、ミュートできるもの）
    static let pushTypes = ["friendRequest", "friendAccepted", "comment", "like", "message", "friendPost", "rankUp"]

    /// 自分の端末の情報を、サーバーに預ける（自分だけが読み書きできる）。成功したら true
    func registerDevice(token: String, env: String, lang: String, muted: [String]) async -> Bool {
        // 起動直後は、まだサインインが済んでいないことがある。先に済ませてから書く
        do { try await ensureSignedIn() } catch { NSLog("push: sign-in failed: \(error)"); return false }
        guard let uid else { NSLog("push: registerDevice skipped, no uid"); return false }
        let fields: [String: FS] = [
            "token": .string(token), "env": .string(env), "lang": .string(lang),
            "muted": .array(muted.map { .string($0) }), "updatedAt": .timestamp(Date()),
        ]
        do {
            try await patch("devices/\(uid)", fields: fields)
            return true
        } catch {
            NSLog("push: registerDevice failed: \(error)")
            return false
        }
    }

    /// サインアウトや退会のとき：この端末にはもう通知を送らない
    func unregisterDevice() async {
        guard let uid else { return }
        try? await delete("devices/\(uid)")
        UserDefaults.standard.set(false, forKey: PushRegistration.registeredKey)
        UserDefaults.standard.removeObject(forKey: "push.uploaded")
    }
}
