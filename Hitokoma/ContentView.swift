import SwiftUI

struct ContentView: View {
    @StateObject private var store = PostStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab = .today
    @State private var visited: Set<AppTab> = [.today]   // 開いた画面だけ作る（地図を最初から読み込まない）
    @State private var showCapture = false
    @State private var showFull = false
    @AppStorage(AppLanguage.storageKey) private var languageRaw = ""   // 空 = iPhone の言語に合わせる   // 言語を変えると、画面全体を作り直す
    @AppStorage("onboarded") private var onboarded = false   // 初回の説明を見たか
    @AppStorage(Account.doneKey) private var signUpDone = false   // 電話番号の登録画面を終えたか（「あとで」も含む）

    private var todayKey: String { PostStore.dayKey(for: Date()) }
    @State private var showHidden = false          // お題が秘密のときに撮ろうとした
    @State private var lastDayState = ""           // いま見せる日が変わったら、画面を作り直す

    /// いま見せる日に、あと1枚以上撮れるか（1日3枚まで）
    private var canPostMore: Bool {
        store.nextOpenRecord(day: store.activeDayKey()) != nil
    }

    var body: some View {
        ZStack {
            ForEach(AppTab.allCases) { tab in
                if visited.contains(tab) {
                    screen(for: tab)
                        .opacity(selection == tab ? 1 : 0)
                        .allowsHitTesting(selection == tab)
                        .accessibilityHidden(selection != tab)
                }
            }
        }
        .id(languageRaw)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HiTabBar(selection: $selection, onCapture: capture)
        }
        .background(Color.black.ignoresSafeArea())
        .fullScreenCover(isPresented: $showCapture) {
            CaptureFlow()
                .environmentObject(store)
        }
        .fullScreenCover(isPresented: Binding(get: { !onboarded || !signUpDone }, set: { _ in })) {
            if !onboarded {
                OnboardingView { onboarded = true }
            } else {
                SignUpView {
                    signUpDone = true
                    NotificationScheduler.requestAndSchedule()
                }
            }
        }
        .alert(L("今日のお題は、通知で届きます"), isPresented: $showHidden) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(L("届くまで、お題はヒミツです。届いた瞬間から、タイムが始まります。"))
        }
        // 通知の時刻を過ぎたら、前日の表示から今日の表示へ切り替える
        .onReceive(Timer.publish(every: 20, on: .main, in: .common).autoconnect()) { _ in
            let state = store.activeDayKey() + (store.isPromptHidden() ? "-hidden" : "")
            if state != lastDayState {
                lastDayState = state
                store.objectWillChange.send()
            }
        }
        .alert(L("今日は3枚とも投稿しました"), isPresented: $showFull) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(L("次のお題は、明日届きます。"))
        }
        .environmentObject(store)
        .preferredColorScheme(.dark)
        .tint(.white)
        .onAppear(perform: refreshToday)
        .onOpenURL(perform: handle)
        .onChange(of: selection) { _, tab in
            visited.insert(tab)
            refreshToday()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshToday() }
        }
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .today: TodayView(onCapture: capture, isActive: selection == .today && !showCapture)
        case .friends: TimelineScreen(onCapture: capture)
        case .world: WorldView(isActive: selection == .world && !showCapture)
        case .profile: ProfileView()
        }
    }

    /// 真ん中のボタン：今日の画面へ戻り、まだ投稿していなければすぐ撮影に進む
    private func capture() {
        selection = .today
        if store.isPromptHidden() { showHidden = true }
        else if canPostMore { showCapture = true } else { showFull = true }
    }

    /// リンクやウィジェットから開いたとき（hitokoma://today、world、add?id=…）
    private func handle(_ url: URL) {
        guard url.scheme == "hitokoma" else { return }
        switch url.host {
        case "today": selection = .today
        case "capture": capture()   // ウィジェットの「撮る」から
        case "world": selection = .world
        case "add":
            guard let id = FriendCode.parse(url.absoluteString), id != FriendCode.myID else { return }
            var list = (UserDefaults.standard.string(forKey: "friendList") ?? MyProfile.defaultFriends)
                .split(separator: ",").map(String.init)
            if !list.contains(id) {
                list.append(id)
                UserDefaults.standard.set(list.joined(separator: ","), forKey: "friendList")
            }
            selection = .friends
        default: break
        }
    }

    private func refreshToday() {
        store.ensureToday()
        for slot in PromptSlot.active { store.reveal(id: "\(todayKey)-\(slot.rawValue)") }
    }
}

#Preview {
    ContentView()
}
