import UIKit
import Foundation
import UserNotifications

/// 通知の予約と、通知をタップしたときの処理
///
/// - お題の通知：その日の時刻を、地域（タイムゾーン）と日付から決める（地域の時間で 10:00〜19:59 のどこか）。
///   同じ地域の全員が同じ計算をするので、サーバーなしで同時に届く。通知を開いた時点から2分
enum NotificationScheduler {
    static func requestAndSchedule() {
        let center = UNUserNotificationCenter.current()
        center.delegate = NotificationDelegate.shared
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            schedule(center: center)
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    /// 通知の時刻を決める地域（設定で選ぶ）
    static let zoneKey = "notifyZone"

    /// 選べる4つの地域の代表の時間帯（東アジア・南アジア・ヨーロッパ・アメリカ）
    static let representativeZones = ["Asia/Tokyo", "Asia/Kolkata", "Europe/Paris", "America/New_York"]

    /// 通知の時刻に使う時間帯。未選択（初期値）や古い版の時間帯は、いまの端末の地域の代表に寄せる。
    /// こうすると、同じ地域の人は必ず同じ代表の時間帯で計算し、同じ時刻に届く。
    static var zone: TimeZone {
        let stored = UserDefaults.standard.string(forKey: zoneKey) ?? ""
        if representativeZones.contains(stored), let zone = TimeZone(identifier: stored) { return zone }
        let base = TimeZone(identifier: stored) ?? .current
        let region = PostStore.regionIndex(forOffset: base.secondsFromGMT())
        return TimeZone(identifier: representativeZones[region]) ?? .current
    }

    /// 地域を変えたら、通知を決め直す
    static func changeZone(to identifier: String) {
        UserDefaults.standard.set(identifier, forKey: zoneKey)
        requestAndSchedule()
    }

    /// その日の通知時刻。地域の名前と日付だけで決まる（端末ごとの乱数は使わない）ので、同じ地域の全員が同じ時刻になる。
    static func fireTime(for day: Date) -> Date {
        let tz = zone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        guard let year = parts.year, let month = parts.month, let dayOfMonth = parts.day else { return day }
        let dayString = String(format: "%04d-%02d-%02d", year, month, dayOfMonth)
        let hour = 10 + Int(stableHash("hour|\(tz.identifier)|\(dayString)") % 10)
        let minute = Int(stableHash("minute|\(tz.identifier)|\(dayString)") % 60)

        var when = DateComponents()
        when.year = year
        when.month = month
        when.day = dayOfMonth
        when.hour = hour
        when.minute = minute
        return calendar.date(from: when) ?? day
    }

    /// 端末をまたいでも同じ値になるハッシュ（FNV-1a）。Swift の hashValue は起動ごとに変わるので使わない
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }

    private static func schedule(center: UNUserNotificationCenter) {
        center.removeAllPendingNotificationRequests()

        // 今日から7日分。絶対時刻で予約するので、端末の時間設定が変わっても、地域の時刻はずれない
        for offset in 0..<7 {
            guard let day = Calendar.current.date(byAdding: .day, value: offset, to: Date()) else { continue }
            let wait = fireTime(for: day).timeIntervalSinceNow
            // もう過ぎた時刻の通知は出さない（同じ地域の人と、ずらさないため）
            guard wait > 1 else { continue }

            let content = UNMutableNotificationContent()
            content.title = L("Difframe")
            content.body = L("今日のお題が届きました。")
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false)
            center.add(UNNotificationRequest(identifier: "morning-\(offset)", content: content, trigger: trigger))
        }
    }
}

/// 朝の通知が届いた時刻を記録する（今日のタイムの開始）
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    private func recordArrival(_ notification: UNNotification) {
        guard notification.request.identifier.hasPrefix("morning") else { return }
        let store = PostStore.shared
        store.ensureToday()
        store.markNotified(day: PostStore.dayKey(for: notification.date), arrivedAt: notification.date)
    }

    // アプリを開いたまま通知が届いたとき：バナーを出して、届いた時刻を記録
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        recordArrival(notification)
        completionHandler([.banner, .sound])
    }

    // 通知をタップしたとき：届いた時刻を記録（まだなら）
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        recordArrival(response.notification)
        // サーバーからの通知なら、開く先を伝える（文字は取り出して渡す）
        let info = response.notification.request.content.userInfo
        let type = info["type"] as? String ?? ""
        let postID = info["postID"] as? String ?? ""
        let fromUID = info["fromUID"] as? String ?? ""
        let fromName = info["fromName"] as? String ?? ""
        let fromCode = info["fromCode"] as? String ?? ""
        if !type.isEmpty {
            Task { @MainActor in
                PushRouter.shared.open(type: type, postID: postID, fromUID: fromUID, fromName: fromName, fromCode: fromCode)
            }
        }
        completionHandler()
    }
}
