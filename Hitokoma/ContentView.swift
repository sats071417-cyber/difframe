import SwiftUI

struct ContentView: View {
    @StateObject private var store = PostStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab = .today
    @State private var visited: Set<AppTab> = [.today]   // 開いた画面だけ作る（地図を最初から読み込まない）
    @State private var showCapture = false
    @State private var dragX: CGFloat = 0           // 横にスワイプしている量
    @State private var swiping = false              // いま、画面の切り替えをなぞっている
    @State private var swipeDecided = false         // このなぞりを、切り替えとして扱うか決めた
    @GestureState private var dragging = false      // 指が触れている間だけ true。途中で取り消されても、自動で false に戻る
    @ObservedObject private var router = PushRouter.shared
    @ObservedObject private var worldFocus = WorldFocus.shared
    @State private var showNotices = false
    @State private var showPickup = false
    @ObservedObject private var pickup = MorningPickup.shared
    @State private var pushPost: CommentTarget? = nil
    @State private var pushChat: CloudFriend? = nil
    @State private var showFull = false
    @State private var viewingCode: CodeTarget? = nil   // リンクやQRで開いた、友達コードの持ち主
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
                        .offset(x: tabOffset(tab))   // 指についてくる。隣の画面が、横から入ってくる
                        .allowsHitTesting(selection == tab && !swiping)
                        .accessibilityHidden(selection != tab)
                }
            }
        }
        .simultaneousGesture(tabSwipe)
        // なぞりがシステムに取り消されたとき（onEnded が呼ばれない）は、元の位置に戻して、触れるようにする
        .onChange(of: dragging) { _, now in
            guard !now, swipeDecided else { return }
            swipeDecided = false
            withAnimation(.easeOut(duration: 0.2)) { dragX = 0 }
            swiping = false
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
        .fullScreenCover(item: $viewingCode) { PersonProfileSheet(code: $0.id, canAdd: true) }
        .fullScreenCover(isPresented: $showNotices) { InboxSheet() }
        .fullScreenCover(isPresented: $showPickup) {
            MorningPickupSheet(pickup: pickup) { p in
                showPickup = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    pushPost = CommentTarget(id: p.id, owner: p.name.isEmpty ? "@" + p.handle : p.name,
                                             caption: p.caption, image: p.photo, front: p.front, cloudID: p.id)
                }
            }
            .task { await pickup.refresh(force: true) }
        }
        .fullScreenCover(item: $pushPost) { t in
            CommentSheet(postID: t.id, owner: t.owner, caption: t.caption, image: t.image, front: t.front,
                         prompt: t.prompt, cloudID: t.cloudID, ownRecordID: t.ownRecordID, focusID: t.focusID)
                .environmentObject(store)
        }
        .fullScreenCover(item: $pushChat) { ChatView(friend: $0) }
        .onChange(of: worldFocus.request?.id) { _, id in if id != nil { selection = .world } }
        .onChange(of: router.route) { _, _ in openPushRoute() }
        .onAppear { openPushRoute() }
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
            if phase == .background {
                // 閉じるときに今の通知を「見た」ことにし、次の確認を頼む
                BackgroundSync.markAllSeen()
                BackgroundSync.schedule()
            }
        }
    }

    private var tabOrder: [AppTab] { AppTab.allCases.map { $0 } }

    private func tabOffset(_ tab: AppTab) -> CGFloat {
        guard let i = tabOrder.firstIndex(of: tab), let s = tabOrder.firstIndex(of: selection) else { return 0 }
        return CGFloat(i - s) * UIScreen.main.bounds.width + dragX
    }

    /// 左右にスワイプして、今日・タイムライン・世界・自分を切り替える。指に画面がついてきて、隣の画面が横から入ってくる。
    /// 地図や写真の横スクロールとぶつからないように、画面の端から始めたときだけ効く画面がある。
    private var tabSwipe: some Gesture {
        DragGesture(minimumDistance: 15, coordinateSpace: .global)
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { value in
                let dx = value.translation.width, dy = value.translation.height
                if !swipeDecided {
                    swipeDecided = true
                    // 横にスクロールする列の上から始めたときは、切り替えない
                    let inRow = TabSwipeGate.blocked[selection]?.values.contains(where: { $0.contains(value.startLocation) }) == true
                    let width = UIScreen.main.bounds.width
                    let fromEdge = value.startLocation.x < 40 || value.startLocation.x > width - 40
                    // 全面で効くのは、「今日」（撮った写真が出ていないとき）・タイムライン・自分。地図と写真の横スクロールは、端から始めたときだけ
                    let hasPhotos = store.records(day: store.activeDayKey()).contains { $0.postedPhotoFile != nil }
                    let anywhere = (selection == .today && !hasPhotos) || selection == .friends || selection == .profile
                    swiping = !inRow && abs(dx) > abs(dy) * 1.5 && (anywhere || fromEdge)
                    if swiping, let i = tabOrder.firstIndex(of: selection) {
                        // 入ってくる隣の画面を、先に作っておく
                        if i > 0 { visited.insert(tabOrder[i - 1]) }
                        if i + 1 < tabOrder.count { visited.insert(tabOrder[i + 1]) }
                    }
                }
                guard swiping, let i = tabOrder.firstIndex(of: selection) else { return }
                // 端の画面では、ゴムのように、少しだけ動く
                let blocked = (dx > 0 && i == 0) || (dx < 0 && i == tabOrder.count - 1)
                dragX = blocked ? dx * 0.25 : dx
            }
            .onEnded { value in
                defer { swipeDecided = false }
                guard swiping, let i = tabOrder.firstIndex(of: selection) else { swiping = false; return }
                let dx = value.translation.width
                let predicted = value.predictedEndTranslation.width
                var next = i
                if dx < -80 || predicted < -200 { next = i + 1 } else if dx > 80 || predicted > 200 { next = i - 1 }
                if !tabOrder.indices.contains(next) { next = i }
                withAnimation(.easeOut(duration: 0.25)) {
                    selection = tabOrder[next]
                    dragX = 0
                }
                // 動きが終わってから、触れるようにする
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { swiping = false }
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
        if FirebaseBoot.canHandle(url) { return }   // 電話認証の途中の画面から戻ってきた
        guard url.scheme == "hitokoma" else { return }
        switch url.host {
        case "today": selection = .today
        case "capture": capture()   // ウィジェットの「撮る」から
        case "world": selection = .world
        case "add":
            // リンクやQRで開いたら、その人のプロフィールを見せる（追加は、そこから）
            guard let id = FriendCode.parse(url.absoluteString), id != FriendCode.myID else { return }
            viewingCode = CodeTarget(id: id)
        default: break
        }
    }

    private func refreshToday() {
        Task { await CloudSync.shared.refresh() }
        store.ensureToday()
        // ウィジェットの言語とお題の文字を、いまの言語に合わせ直す（言語を変えた直後も含む）
        WidgetBridge.push(store)
        for slot in PromptSlot.active { store.reveal(id: "\(todayKey)-\(slot.rawValue)") }
    }
}

#Preview {
    ContentView()
}

extension ContentView {
    /// 通知をタップされたときの、開く先（投稿・DM・通知一覧）
    @MainActor
    func openPushRoute() {
        guard let route = PushRouter.shared.route else { return }
        PushRouter.shared.route = nil
        switch route {
        case .notices:
            showNotices = true
        case .pickup:
            showPickup = true
        case .chat(let friend):
            pushChat = friend
        case .post(let postID, let name):
            let owner = postID.split(separator: "_").first.map(String.init) ?? ""
            let recordID = postID.split(separator: "_", maxSplits: 1).last.map(String.init) ?? ""
            if owner == CloudSync.shared.uid, let record = PostStore.shared.records.first(where: { $0.id == recordID }) {
                // 自分の投稿：写真・一言も、そのまま見られる
                let image = record.postedPhotoFile.flatMap { PostStore.shared.image(for: $0) }
                pushPost = CommentTarget(id: recordID, owner: L("あなた"), caption: record.caption, image: image,
                                         cloudID: postID, ownRecordID: recordID)
            } else {
                pushPost = CommentTarget(id: postID, owner: name, cloudID: postID)
            }
        }
    }
}
