import SwiftUI

@main
struct HitokomaApp: App {
    init() {
        // 起動直後に通知をタップされても受け取れるように、起動時に設定する
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        UIWindow.appearance().backgroundColor = .black   // 起動直後に白くならないように
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // 初回の説明を見たあとに、通知の許可を聞く（2回目以降は、起動のたびに予約し直す）
                    if UserDefaults.standard.bool(forKey: "onboarded") {
                        NotificationScheduler.requestAndSchedule()
                    }
                }
        }
    }
}
