import SwiftUI

@main
struct HitokomaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // 起動直後に通知をタップされても受け取れるように、起動時に設定する
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        BackgroundSync.register()
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
                    // 起動のたびに、プッシュの宛先を確かめて預け直す（変わっていなければ何もしない）
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        await PushRegistration.shared.upload()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    // アプリを開いたとき・閉じるときに、プッシュの宛先（トークン・言語・ミュート）を預け直す
                    if phase == .active || phase == .background {
                        Task { await PushRegistration.shared.upload() }
                    }
                    if phase == .active { PushRegistration.shared.register() }
                }
        }
    }
}
