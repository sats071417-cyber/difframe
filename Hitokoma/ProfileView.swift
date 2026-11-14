import SwiftUI
import PhotosUI

/// プロフィール：名前、ランク、トロフィー、自分の投稿、友達コード。
struct ProfileView: View {
    @EnvironmentObject private var store: PostStore
    @AppStorage("myName") private var myName: String = L("あなた")
    @AppStorage("friendList") private var friendList: String = MyProfile.defaultFriends
    @AppStorage("myHandle") private var myHandle: String = ""
    @AppStorage("onboarded") private var onboarded = true
    @AppStorage(Account.phoneKey) private var phone: String = ""
    @AppStorage(Account.verifiedKey) private var phoneVerified = false
    @AppStorage(Account.doneKey) private var signUpDone = true
    @State private var section: ProfileSection = .rank
    @State private var scrollTarget: String? = nil
    @State private var showSettings = false
    @State private var showRanks = false
    @State private var showAllPosts = false
    @State private var showInvite = false
    @State private var showFriends = false
    @ObservedObject private var cloud = CloudSync.shared
    @State private var editingHandle = false
    @State private var editingName = false
    @State private var draftName = ""
    @State private var viewerID: String? = nil     // 全画面で見ている写真
    @State private var pickerItem: PhotosPickerItem? = nil   // アイコンに選んだ写真
    @State private var cropSource: UIImage? = nil            // 切り抜く前の写真
    @AppStorage("avatarStamp") private var avatarStamp: Double = 0   // アイコンを変えた時刻（表示を新しくする）

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    private var currentHandle: String { MyProfile.handle(myHandle) }

    /// 今月のポイントとランク
    private var monthly: MonthlyPoints {
        MonthlyPoints(records: store.records, month: MonthlyPoints.monthKey(for: Date()))
    }

    /// 先月の最終ランク
    private var lastMonthly: MonthlyPoints {
        let last = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        return MonthlyPoints(records: store.records, month: MonthlyPoints.monthKey(for: last))
    }

    private var achievementInput: AchievementInput {
        AchievementInput(records: store.records, friendCount: MyProfile.friendCount(friendList))
    }

    private var unlockedTrophies: [Trophy] {
        let input = achievementInput
        return Trophy.allCases.filter { $0.isUnlocked(input) }
    }

    /// 自分の投稿（新しい順）
    private var myPosts: [PromptRecord] {
        store.records
            .filter { $0.postedPhotoFile != nil }
            .sorted { $0.dayKey > $1.dayKey }
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 14) {
                ScreenHeader(title: L("プロフィール")) {
                    HStack(spacing: 10) {
                    NotificationBell()
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Hi.tile))
                    }
                    .accessibilityLabel(L("設定"))
                    }
                }
                identity
                statTiles
                rankAndTrophies
                    .id("sections")
                postsGrid
                friendCodeCard
                helpButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .onChange(of: scrollTarget) { _, target in
            guard let target else { return }
            withAnimation { proxy.scrollTo(target, anchor: .top) }
            scrollTarget = nil
        }
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $editingHandle) {
            HandleEditSheet(current: currentHandle) { newHandle in
                myHandle = newHandle
            }
        }
        .alert(L("名前を変更"), isPresented: $editingName) {
            TextField(L("名前"), text: $draftName)
            Button(L("保存")) {
                let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { myName = trimmed }
            }
            Button(L("キャンセル"), role: .cancel) {}
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                // アイコン：押すと写真ライブラリから選んで、丸く切り抜ける
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    avatarCircle
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Hi.onNeon)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Hi.neon))
                                .overlay(Circle().stroke(Color.black, lineWidth: 2))
                        }
                }
                .accessibilityLabel(L("アイコンを変える"))
                .contextMenu {
                    if Avatar.load() != nil {
                        Button(role: .destructive) {
                            Avatar.remove(); avatarStamp = Date().timeIntervalSince1970
                        } label: { Label(L("アイコンを外す"), systemImage: "trash") }
                    }
                }
                .onChange(of: pickerItem) { _, item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                            cropSource = Avatar.downscaled(image)
                        }
                        pickerItem = nil
                    }
                }
                .fullScreenCover(isPresented: Binding(get: { cropSource != nil }, set: { if !$0 { cropSource = nil } })) {
                    if let cropSource {
                        AvatarCropper(image: cropSource) { cropped in
                            Avatar.save(cropped)
                            avatarStamp = Date().timeIntervalSince1970
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(myName)
                        .font(.title2.weight(.black))
                        .foregroundStyle(.white)
                    HStack(spacing: 6) {
                        Text("@" + currentHandle)
                            .font(.subheadline)
                            .foregroundStyle(Hi.dim)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        RankBadge(rank: monthly.rank)
                    }
                    if !unlockedTrophies.isEmpty {
                        TrophyBadges(trophies: unlockedTrophies, limit: 4)
                    }
                    // 電話番号（後ろ4桁だけ表示）。登録前なら、登録画面を開くボタン
                    if phone.isEmpty {
                        Button {
                            signUpDone = false
                        } label: {
                            Label(L("電話番号を登録"), systemImage: "phone.badge.plus")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(Hi.neon)
                    } else {
                        Label(Account.masked(phone) + (phoneVerified ? "" : L("（デモ・未確認）")), systemImage: "phone.fill")
                            .font(.caption)
                            .foregroundStyle(Hi.dim)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button(L("名前を変える")) {
                    draftName = myName
                    editingName = true
                }
                .buttonStyle(TileButtonStyle())
                Button(L("ハンドル名を設定")) {
                    editingHandle = true
                }
                .buttonStyle(TileButtonStyle())
            }
            // 友達（Instagram のように、人数を見せて、押すと一覧と追加）。右の QR は、自分のQRコードをすぐ出す
            HStack(spacing: 10) {
                Button {
                    showFriends = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.2.fill").foregroundStyle(Hi.neon)
                        Text(LF("友達 {n}人", ["n": "\(friendTotal)"])).font(.subheadline.weight(.black))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Hi.dim)
                    }
                    .foregroundStyle(.white)
                    .contentShape(Rectangle())
                    .hiTile(cornerRadius: 22)
                }
                .buttonStyle(.plain)
                Button {
                    showInvite = true
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Hi.neon)
                        .frame(width: 24)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .hiTile(cornerRadius: 22)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("友達追加カード"))
            }
            .fixedSize(horizontal: false, vertical: true)
            .sheet(isPresented: $showFriends) { FriendListSheet() }
            .sheet(isPresented: $showInvite) { FriendInviteSheet() }
        }
    }

    /// 友達の人数（サーバーにつながっているときは、本当の友達だけ）
    private var friendTotal: Int {
        cloud.isOn ? cloud.friends.count : MyProfile.friendCount(friendList)
    }

    private enum ProfileSection: Hashable { case rank, trophies, calendar }

    /// ランクとトロフィーを、1つの場所にまとめる（切り替えで見る）
    private var rankAndTrophies: some View {
        VStack(spacing: 12) {
            HiSegment(options: [(value: ProfileSection.rank, title: L("ランク")),
                                (value: ProfileSection.trophies, title: L("トロフィー")),
                                (value: ProfileSection.calendar, title: L("カレンダー"))],
                      selection: $section)
            switch section {
            case .rank:
                rankCard
                pointTiles
            case .trophies:
                trophiesCard
            case .calendar:
                CalendarView(embedded: true)
            }
        }
    }

    /// ランク：今月のポイントで決まる。月が変わるとリセットされる
    private var rankCard: some View {
        let m = monthly
        return ZStack {
            GlowBackground(palette: .forRank(m.rank), focus: UnitPoint(x: 0.5, y: 0.5))
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text(m.rank.name).font(.title3.weight(.black))
                    Image(systemName: "chevron.right.circle.fill").font(.subheadline).opacity(0.8)
                    Spacer()
                    Text(monthTitle(m.month)).font(.caption.weight(.bold))
                }
                .foregroundStyle(.white)
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.5),
                                style: StrokeStyle(lineWidth: 10, dash: [2, 6]))
                    Circle()
                        .trim(from: 0, to: m.progress)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 10))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 4) {
                        DotText(text: "\(m.total)", pitch: 6, color: Color.black.opacity(0.82))
                        Text("pt").font(.caption.weight(.black)).foregroundStyle(Color.black.opacity(0.75))
                    }
                }
                .frame(width: 190, height: 190)
                .accessibilityElement()
                .accessibilityLabel(LF("今月 {n} ポイント", ["n": "\(m.total)"]))
                Text(remainingText(m))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                // ポイントのルール（一行ずつ）
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("投稿：1枚 10pt（お題に合う写真も、確認できないお題の写真も）。違うと言われた写真は 3pt"))
                    Text(L("早さ：届いてから5分以内 10pt、30分以内 6pt、90分以内 3pt（1日1回）"))
                    Text(L("連続：続けた日数に応じて、1日 最大10pt"))
                    Text(L("ランキングに入るのは、お題に合うと確認できた写真だけです"))
                }
                .font(.caption2)
                .foregroundStyle(Color.black.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture { showRanks = true }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(L("ランク一覧"))
        .sheet(isPresented: $showRanks) {
            RankListSheet(points: m.total)
        }
    }

    private func monthTitle(_ month: String) -> String {
        let parts = month.split(separator: "-")
        guard parts.count == 2, let number = Int(parts[1]) else { return month }
        return LF("{n}月", ["n": "\(number)"])
    }

    private func remainingText(_ m: MonthlyPoints) -> String {
        if let next = m.rank.next, let remain = m.pointsToNext {
            return LF("{r}まで {n} pt", ["r": next.name, "n": "\(remain)"])
        }
        return L("最高ランクです")
    }

    private var pointTiles: some View {
        let m = monthly
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                pointTile(L("投稿"), m.postPoints, colors: [Color(red: 0.17, green: 0.42, blue: 0.31), Color(red: 0.07, green: 0.2, blue: 0.15)])
                pointTile(L("早さ"), m.speedPoints, colors: [Color(red: 0.48, green: 0.12, blue: 0.36), Color(red: 0.17, green: 0.05, blue: 0.15)])
                pointTile(L("連続"), m.streakPoints, colors: [Color(red: 0.15, green: 0.25, blue: 0.6), Color(red: 0.06, green: 0.1, blue: 0.26)])
            }
            HStack(spacing: 6) {
                Text(L("先月")).font(.caption).foregroundStyle(Hi.dim)
                RankBadge(rank: lastMonthly.rank)
                Text("\(lastMonthly.total) pt").font(.caption.monospacedDigit()).foregroundStyle(Hi.dim)
                Spacer()
            }
            Text(L("ランクは毎月リセットされます。投稿1回 +10、早さと連続でボーナスが付きます。"))
                .font(.caption)
                .foregroundStyle(Hi.dim)
        }
    }

    private func pointTile(_ title: String, _ points: Int, colors: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.75))
            Text("+\(points)").font(.headline.weight(.black)).foregroundStyle(.white)
        }
        .accessibilityElement(children: .combine)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var statTiles: some View {
        let best = TimeAttackStats(records: store.records).best
        let position = WorldRanking.position(myBest: best)
        return HStack(spacing: 8) {
            statTile(L("連続"), LF("{n}日", ["n": "\(store.currentStreak())"]))
            // 投稿を押すと、カレンダーに飛ぶ（投稿した日を見られる）
            Button {
                withAnimation { section = .calendar }
                scrollTarget = "sections"
            } label: {
                statTile(L("投稿"), LF("{n}枚", ["n": "\(myPosts.count)"]))
            }
            .buttonStyle(.plain)
            statTile(L("自己ベスト"), best.map { TimeFormat.string($0) } ?? "--")
            statTile(L("地域"), position.map { LF("{n}位", ["n": "\($0)"]) } ?? "--")
        }
    }

    private func statTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Hi.dim).lineLimit(1).minimumScaleFactor(0.7)
            Text(value).font(.subheadline.weight(.black)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
        .hiTile(cornerRadius: 18)
    }

    /// トロフィー：獲得済みは光らせ、未獲得は暗く
    private var trophiesCard: some View {
        let input = achievementInput
        let unlocked = Trophy.allCases.filter { $0.isUnlocked(input) }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("トロフィー")).font(.title3.weight(.black)).foregroundStyle(.white)
                Spacer()
                Text("\(unlocked) / \(Trophy.allCases.count)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Hi.dim)
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Trophy.allCases) { trophy in
                    trophyCell(trophy, unlocked: trophy.isUnlocked(input))
                }
            }
        }
    }

    private func trophyCell(_ trophy: Trophy, unlocked: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: trophy.icon)
                .font(.title2)
                .foregroundStyle(unlocked ? Hi.neon : Hi.dim.opacity(0.35))
                .frame(height: 30)
            Text(trophy.title)
                .font(.caption.weight(.black))
                .foregroundStyle(unlocked ? .white : Hi.dim)
                .multilineTextAlignment(.center)
            Text(trophy.detail)
                .font(.system(size: 11))
                .foregroundStyle(Hi.dim)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .top)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(Hi.tile)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue(unlocked ? L("獲得済み") : L("未獲得"))
    }

    /// 自分の投稿：一列で、左右にスワイプして過去に戻れる。「広げる」で全部を一覧に
    private var postsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("自分の投稿")).font(.title3.weight(.black)).foregroundStyle(.white)
                Spacer()
                if !myPosts.isEmpty {
                    Button { showAllPosts = true } label: {
                        Label(L("広げる"), systemImage: "square.grid.2x2")
                    }
                    .buttonStyle(TileButtonStyle())
                    .accessibilityLabel(L("投稿をすべて広げて見る"))
                }
            }
            if myPosts.isEmpty {
                Text(L("今日のお題を撮ると、ここに並びます"))
                    .font(.subheadline)
                    .foregroundStyle(Hi.dim)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(myPosts) { record in
                            postCell(record)
                                .frame(width: 150, height: 150)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fullScreenCover(isPresented: Binding(get: { viewerID != nil }, set: { if !$0 { viewerID = nil } })) {
            PhotoViewer(startID: viewerID ?? "")
                .environmentObject(store)
        }
        .sheet(isPresented: $showAllPosts) {
            AllPostsSheet().environmentObject(store)
        }
    }

    @ViewBuilder
    private func postCell(_ record: PromptRecord) -> some View {
        if let file = record.postedPhotoFile, let image = store.image(for: file) {
            Button {
                viewerID = record.id
            } label: {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(Image(uiImage: image).resizable().scaledToFill())
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(record.dayKey) \(L(record.prompt))")
        }
    }

    /// 友達コード：場所を取らない1行にする
    private var friendCodeCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("友達コード")).font(.caption).foregroundStyle(Hi.dim)
                Text(FriendCode.myID)
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
            }
            Spacer()
            ShareLink(item: FriendCode.shareURL) {
                Label(L("送る"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(TileButtonStyle())
        }
        .hiTile(cornerRadius: 22)
    }

    /// 表示言語の選択。変えると、アプリ全体がその言語で表示し直される（標準は英語）
    /// 自分のアイコン。写真があればそれ、なければランクの色と名前の1文字
    private var avatarCircle: some View {
        ZStack {
            if let image = Avatar.load() {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                GlowBackground(palette: .forRank(monthly.rank), focus: .center)
                Text(String(myName.prefix(1)))
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(Color.black.opacity(0.8))
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(Circle())
        .id(avatarStamp)
    }

    /// 初回の説明をもう一度見る
    private var helpButton: some View {
        Button(L("使い方を見る")) { onboarded = false }
            .buttonStyle(TileButtonStyle())
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
    }
}

/// 自分のプロフィールの共通の計算
enum MyProfile {
    static let defaultFriends = "Kanta,motohiro,Alex,Sam,Mina,Lucas"

    /// ハンドル名（未設定のときは、友達コードから作った仮の名前）
    static func handle(_ stored: String) -> String {
        stored.isEmpty ? "user_" + FriendCode.myID.lowercased() : stored
    }

    static func friendCount(_ list: String) -> Int {
        list.split(separator: ",").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }
}

/// ハンドル名（@名前）の設定画面。使える文字を確認してから保存する。
struct HandleEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let current: String
    let onSave: (String) -> Void
    @State private var text = ""

    private var normalized: String { HandleRule.normalize(text) }
    private var errorMessage: String? { HandleRule.error(for: normalized) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 2) {
                        Text("@").foregroundStyle(.gray)
                        TextField("handle", text: $text)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                    }
                } footer: {
                    if !text.isEmpty, let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    } else {
                        Text(L("英小文字・数字・ピリオド(.)・アンダースコア(_)で、3〜20文字。"))
                    }
                }
            }
            .navigationTitle(L("ハンドル名"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("キャンセル")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("保存")) {
                        onSave(normalized)
                        dismiss()
                    }
                    .disabled(errorMessage != nil)
                }
            }
            .onAppear { text = current }
        }
        .presentationDetents([.medium])
    }
}


/// 自分の写真を全画面で見る。左右にめくると、ほかの日の写真に移る。
struct PhotoViewer: View {
    @EnvironmentObject private var store: PostStore
    @Environment(\.dismiss) private var dismiss
    let startID: String
    @State private var page = ""

    /// 自分の投稿（プロフィールと同じ、新しい順）。消すと、すぐにここからも消える
    private var records: [PromptRecord] {
        store.records.filter { $0.postedPhotoFile != nil }.sorted { $0.dayKey > $1.dayKey }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $page) {
                ForEach(records) { record in
                    page(for: record).tag(record.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.15)))
            }
            .accessibilityLabel(L("閉じる"))
            .padding(16)
        }
        .overlay(alignment: .topLeading) {
            if !page.isEmpty {
                DeletePostMenu(recordID: page) {
                    // 消したあと：残りがあれば次の写真へ、なければ閉じる
                    if let next = records.first { page = next.id } else { dismiss() }
                }
                .padding(16)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { page = startID }
    }

    @ViewBuilder
    private func page(for record: PromptRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer(minLength: 0)
            if let file = record.postedPhotoFile, let image = store.image(for: file) {
                DualPhotoView(main: image, inset: record.frontPhotoFile.flatMap { store.image(for: $0) })
                    .aspectRatio(PhotoShape.ratio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            HStack(alignment: .firstTextBaseline) {
                Text(L(record.prompt)).font(.title2.weight(.black))
                if record.verified == true {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Hi.neon)
                }
                Spacer()
                if let elapsed = record.elapsed {
                    DotText(text: TimeFormat.string(elapsed), pitch: 3.5, color: Hi.neon)
                }
            }
            Text(record.postedAt.map { $0.appFormatted(date: .long, time: .shortened) } ?? record.dayKey)
                .font(.subheadline).foregroundStyle(Hi.dim)
            if let caption = record.caption, !caption.isEmpty {
                Text(caption).font(.body)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
    }
}


/// 自分のアイコンの写真（この端末の中だけに保存する）
enum Avatar {
    static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("avatar.jpg")
    }
    static func load() -> UIImage? { UIImage(contentsOfFile: url.path) }
    static func save(_ image: UIImage) {
        if let data = image.jpegData(compressionQuality: 0.85) { try? data.write(to: url) }
    }
    static func remove() { try? FileManager.default.removeItem(at: url) }

    /// 大きすぎる写真を、切り抜きやすい大きさ（長い辺 2000px）に縮める
    static func downscaled(_ image: UIImage, maxSide: CGFloat = 2000) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide else { return image }
        let k = maxSide / longest
        let size = CGSize(width: image.size.width * k, height: image.size.height * k)
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

/// アイコンの切り抜き。指で動かす・つまんで拡大して、丸の中に入る部分をアイコンにする。
struct AvatarCropper: View {
    let image: UIImage
    let onDone: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width - 48, 340)
            VStack(spacing: 18) {
                HStack(spacing: 10) {
                    // どの言語でも押しやすいように、押す範囲を大きく取る（高さ44pt以上）
                    Button { dismiss() } label: {
                        Text(L("キャンセル"))
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(minWidth: 84, minHeight: 44)
                            .background(Capsule().fill(Hi.tile))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    Text(L("アイコンを切り抜く"))
                        .font(.headline.weight(.black))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                    Button {
                        onDone(crop(side: side))
                        dismiss()
                    } label: {
                        Text(L("決定"))
                            .font(.subheadline.weight(.black))
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .foregroundStyle(Hi.onNeon)
                            .padding(.horizontal, 18)
                            .frame(minWidth: 84, minHeight: 44)
                            .background(Capsule().fill(Hi.neon))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                // アプリの中で言語を切り替えたあとは、この画面の上の余白(安全な範囲)が 0 になることがある。
                // そのままだと、ボタンが時計やカメラの位置に重なって押せないので、端末の画面から直接、余白を取る
                .padding(.top, 8 + max(0, Self.windowTopInset - geo.safeAreaInsets.top))
                .zIndex(2)

                Spacer(minLength: 0)
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: side, height: side)
                        .scaleEffect(scale)
                        .offset(offset)
                    // 丸の外を暗くする
                    Rectangle()
                        .fill(Color.black.opacity(0.62))
                        .overlay(Circle().frame(width: side, height: side).blendMode(.destinationOut))
                        .compositingGroup()
                        .allowsHitTesting(false)
                    Circle().stroke(Color.white, lineWidth: 2)
                        .frame(width: side, height: side)
                        .allowsHitTesting(false)
                }
                .frame(width: geo.size.width, height: side + 120)
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    SimultaneousGesture(
                        MagnifyGesture()
                            .onChanged { v in
                                scale = max(1, min(baseScale * v.magnification, 6))
                                offset = clamped(offset, side: side)
                            }
                            .onEnded { _ in baseScale = scale; baseOffset = offset },
                        DragGesture()
                            .onChanged { v in
                                offset = clamped(CGSize(width: baseOffset.width + v.translation.width,
                                                        height: baseOffset.height + v.translation.height), side: side)
                            }
                            .onEnded { _ in baseOffset = offset }
                    )
                )
                Text(L("指で動かしたり、つまんで大きさを変えたりできます"))
                    .font(.footnote)
                    .foregroundStyle(Hi.dim)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    /// いまの画面の上の余白（時計・ダイナミックアイランドの分）
    private static var windowTopInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.safeAreaInsets.top ?? 0
    }

    /// 写真が丸の外に出て、すき間ができないようにする
    private func clamped(_ o: CGSize, side: CGFloat) -> CGSize {
        let w = image.size.width, h = image.size.height
        let k = side / min(w, h) * scale              // 画面上の 1pt あたりの写真の大きさ
        let maxX = max(0, (w * k - side) / 2), maxY = max(0, (h * k - side) / 2)
        return CGSize(width: min(max(o.width, -maxX), maxX), height: min(max(o.height, -maxY), maxY))
    }

    /// 丸の中に見えている部分を、600×600 の正方形にする
    private func crop(side: CGFloat) -> UIImage {
        let w = image.size.width, h = image.size.height
        let f = side / min(w, h) * scale
        let cropSide = side / f
        let cx = w / 2 - offset.width / f, cy = h / 2 - offset.height / f
        let out: CGFloat = 600
        let s = out / cropSide
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: format).image { _ in
            image.draw(in: CGRect(x: -(cx - cropSide / 2) * s, y: -(cy - cropSide / 2) * s, width: w * s, height: h * s))
        }
    }
}


/// 自分の投稿を、全部広げて見る一覧
struct AllPostsSheet: View {
    @EnvironmentObject private var store: PostStore
    @Environment(\.dismiss) private var dismiss
    @State private var viewerID: String? = nil
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    private var posts: [PromptRecord] {
        store.records.filter { $0.postedPhotoFile != nil }.sorted { $0.dayKey > $1.dayKey }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(posts) { record in
                        if let file = record.postedPhotoFile, let image = store.image(for: file) {
                            Button { viewerID = record.id } label: {
                                Color.clear
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay(Image(uiImage: image).resizable().scaledToFill())
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(L("自分の投稿"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("閉じる")) { dismiss() } }
            }
        }
        .presentationBackground(.black)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: Binding(get: { viewerID != nil }, set: { if !$0 { viewerID = nil } })) {
            PhotoViewer(startID: viewerID ?? "").environmentObject(store)
        }
    }
}
