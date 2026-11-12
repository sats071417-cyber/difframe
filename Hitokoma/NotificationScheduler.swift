import Foundation
import UserNotifications

/// 通知の予約と、通知をタップしたときの処理
///
/// - 朝：毎朝8時（端末の時間）に1件。その日一日いつでも撮れる
/// - ランダム：世界中で同じ時刻（UTC）に届く。日付ごとに同じ時刻を決めるので、
///   サーバーなしで全員の時刻が一致する。通知を開いた時点から2分
enum NotificationScheduler {
    static func requestAndSchedule() {
        let center = UNUserNotificationCenter.current()
        center.delegate = NotificationDelegate.shared
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            schedule(center: center)
        }
    }

    /// 日付（UTC）ごとの「世界共通のランダム時刻」を決める。全員が同じ計算をするので時刻が揃う。
    /// 範囲：UTC 12:00〜22:00（どの地域でも極端な深夜になりにくい時間帯）
    static func worldwideRandomDate(utcDayKey: String) -> Date? {
        let parts = utcDayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        // 日付から決まる擬似乱数（全員で同じ値になる）
        var seed = UInt64(parts[0]) &* 10_000 &+ UInt64(parts[1]) &* 100 &+ UInt64(parts[2])
        seed = seed &* 2_654_435_761 &+ 12_345
        let minutesFrom12 = Int(seed % UInt64(10 * 60))   // 12:00〜22:00 の分

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        comps.hour = 12 + minutesFrom12 / 60
        comps.minute = minutesFrom12 % 60
        return utc.date(from: comps)
    }

    static func utcDayKey(for date: Date) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let c = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static let fireTimesKey = "fireTimes"
    /// 通知の時刻を決める地域（設定で選ぶ。空なら、いまの端末の時間）
    static let zoneKey = "notifyZone"

    static var zone: TimeZone {
        let id = UserDefaults.standard.string(forKey: zoneKey) ?? ""
        return TimeZone(identifier: id) ?? .current
    }

    /// 地域を変えたら、明日以降の通知時刻を決め直す（今日の分は、もう届いているかもしれないので変えない）
    static func changeZone(to identifier: String) {
        UserDefaults.standard.set(identifier, forKey: zoneKey)
        let tomorrow = PostStore.dayKey(for: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        var stored = (UserDefaults.standard.dictionary(forKey: fireTimesKey) as? [String: Double]) ?? [:]
        stored = stored.filter { $0.key < tomorrow }
        UserDefaults.standard.set(stored, forKey: fireTimesKey)
        requestAndSchedule()
    }

    /// その日の通知時刻（朝10時〜夜8時の間のランダム）。最初に決めたら、アプリを開き直しても変えない。
    /// その日の最初の決定が、すでに過ぎた時刻になったときは「いま」にする（通知が来なかった日を、早く始めたことにしない）。
    static func fireTime(for day: Date) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = zone
        let key = PostStore.dayKey(for: day)
        var stored = (UserDefaults.standard.dictionary(forKey: fireTimesKey) as? [String: Double]) ?? [:]
        if let seconds = stored[key] { return Date(timeIntervalSince1970: seconds) }

        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = Int.random(in: 10...19)
        parts.minute = Int.random(in: 0...59)
        var fire = calendar.date(from: parts) ?? day
        if calendar.isDateInToday(day), fire < Date() { fire = Date() }

        stored[key] = fire.timeIntervalSince1970
        // 古い日付は消す（30日より前）
        let limit = Date().addingTimeInterval(-30 * 86_400).timeIntervalSince1970
        stored = stored.filter { $0.value > limit }
        UserDefaults.standard.set(stored, forKey: fireTimesKey)
        return fire
    }

    private static func schedule(center: UNUserNotificationCenter) {
        center.removeAllPendingNotificationRequests()
        let calendar = Calendar.current

        // 今日から7日分：毎日1件、決めた時刻に通知する（端末の時間）
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: Date()) else { continue }
            let fire = fireTime(for: day)
            guard fire > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = L("Difframe")
            content.body = L("今日のお題が届きました。")
            let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents(
                [.year, .month, .day, .hour, .minute], from: fire), repeats: false)
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
        completionHandler()
    }
}
