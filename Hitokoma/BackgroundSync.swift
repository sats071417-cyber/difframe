import Foundation
import BackgroundTasks
import UserNotifications

/// 電源を切っている間も、iOS が時々アプリを起こして新しい通知を確かめ、端末の通知として出す。
/// 無料で使える方法。いつ起きるかは iOS が決めるので、届く時刻は保証されない（有料のプッシュ通知の代わりではない）。
enum BackgroundSync {
    static let taskID = "com.example.hitokoma.refresh"
    private static let seenKey = "seen.notices"

    /// アプリの起動時に一度だけ呼ぶ
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            handle(task)
        }
    }

    /// 次の確認を頼む（早くても15分後。実際は iOS が決める）
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// アプリを閉じるときに呼ぶ：今ある通知は「見た」ことにして、次の確認で新しい分だけ出す
    @MainActor
    static func markAllSeen() {
        let seen = UserDefaults.standard.stringArray(forKey: seenKey) ?? []
        let ids = CloudSync.shared.notices.map(\.id)
        UserDefaults.standard.set(Array((seen + ids).suffix(400)), forKey: seenKey)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()
        let work = Task { @MainActor in
            for notice in await checkForNew() {
                let content = UNMutableNotificationContent()
                content.title = "Difframe"
                content.body = notice.summary
                content.sound = .default
                try? await UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: "bg-" + notice.id, content: content, trigger: nil))
            }
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    /// 前回見てから増えた通知（ミュート中の種類と、既読のものは除く）
    @MainActor
    static func checkForNew() async -> [CloudNotice] {
        let cloud = CloudSync.shared
        guard cloud.isOn else { return [] }
        await cloud.refresh(force: true)
        let seen = Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? [])
        if seen.isEmpty {
            markAllSeen()          // 初めての確認は、いっせいに出さない
            return []
        }
        let fresh = cloud.notices.filter { !seen.contains($0.id) && !$0.read && !NotifySettings.isMuted($0.type) }
        markAllSeen()
        return fresh
    }
}
