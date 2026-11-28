import SwiftUI

/// 友達を追加する画面：連絡先・QRコード・リンクやID。自分のコードも見せられる
struct AddFriendSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject private var cloud = CloudSync.shared
    @AppStorage("friendList") private var friendList: String = MyProfile.defaultFriends
    @AppStorage(Account.verifiedKey) private var phoneVerified = false
    @State private var newFriend = ""
    @State private var showScanner = false
    @State private var showContacts = false
    @State private var showInviteList = false
    @State private var message: String? = nil
    @State private var viewing: CodeTarget? = nil

    /// IDで探すか、電話番号で探すか
    private enum SearchMode: Hashable { case id, phone }
    @State private var mode: SearchMode = .id
    @State private var country = AddFriendSheet.defaultCountry()
    @State private var number = ""
    @State private var phoneResult: PhoneResult = .none
    private enum PhoneResult { case none, searching, found(CloudSync.ContactMatch), notFound, failed }

    private var friends: [String] {
        friendList.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// 自分の番号の国を、はじめから選んでおく
    private static func defaultCountry() -> Country {
        let own = UserDefaults.standard.string(forKey: Account.phoneKey) ?? ""
        let dial = PhoneNumbers.defaultCallingCode(own: own)
        let region = Locale.current.region?.identifier ?? ""
        return Country.all.first { $0.dial == dial && $0.region == region } ?? Country.all.first { $0.dial == dial } ?? Country.current
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    NewContactFriendsBanner()
                    searchCard
                    waysCard
                    myCodeCard
                    if cloud.isOn { friendsCard }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(L("友達を追加"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { isPresented = false } label: {
                        Image(systemName: "chevron.left").font(.system(size: 16, weight: .black)).foregroundStyle(.white)
                    }
                    .accessibilityLabel(L("戻る"))
                }
            }
            .fullScreenCover(isPresented: $showContacts) { ContactsOnboardingView(fromSettings: true) { showContacts = false } }
            .fullScreenCover(isPresented: $showInviteList) { ContactsView() }
            .fullScreenCover(isPresented: $showScanner) {
                ZStack(alignment: .topLeading) {
                    QRScannerView { value in
                        showScanner = false
                        open(from: value, delay: 0.5)
                    }
                    .ignoresSafeArea()
                    // 全画面で開くので、閉じるボタンが要る
                    Button { showScanner = false } label: {
                        Image(systemName: "chevron.left").font(.headline).foregroundStyle(.white)
                            .frame(width: 44, height: 44).background(Circle().fill(Color.black.opacity(0.55)))
                    }
                    .padding(16)
                    .accessibilityLabel(L("戻る"))
                }
            }
            .fullScreenCover(item: $viewing) { target in
                PersonProfileSheet(code: target.id, canAdd: true)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: 探す（IDか電話番号）

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("友達を探す")).font(.headline.weight(.black)).foregroundStyle(.white)
            HiSegment(options: [(value: SearchMode.id, title: L("ID")), (value: SearchMode.phone, title: L("電話番号"))], selection: $mode)
            if mode == .id {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text("@").font(.body.weight(.bold)).foregroundStyle(Hi.dim)
                        TextField(L("相手のIDを入力"), text: $newFriend)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit { open(from: newFriend) }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black))
                    searchButton(enabled: !newFriend.trimmingCharacters(in: .whitespaces).isEmpty) { open(from: newFriend) }
                }
                if let message {
                    Text(message).font(.caption).foregroundStyle(Hi.dim)
                }
            } else {
                HStack(spacing: 8) {
                    Menu {
                        Picker(L("国"), selection: $country) {
                            ForEach(Country.all) { c in Text("\(c.flag) \(c.name) +\(c.dial)").tag(c) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(country.flag)
                            Text("+\(country.dial)").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black))
                    }
                    .accessibilityLabel(LF("国番号 {c}", ["c": country.name]))
                    TextField(L("電話番号"), text: $number)
                        .keyboardType(.phonePad)
                        .padding(.horizontal, 14)
                        .frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black))
                        .onChange(of: number) { _, _ in phoneResult = .none }
                    searchButton(enabled: phoneVerified && number.filter(\.isNumber).count >= 6) { searchPhone() }
                }
                phoneResultView
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Hi.tile))
    }

    private func searchButton(enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(L("探す")).font(.subheadline.weight(.black))
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(enabled ? Hi.neon : Hi.dim.opacity(0.3)))
                .foregroundStyle(enabled ? Hi.onNeon : Hi.dim)
        }
        .disabled(!enabled)
    }

    @ViewBuilder private var phoneResultView: some View {
        if !phoneVerified {
            Text(L("電話番号で探すには、先に自分の電話番号を登録してください（設定 →「電話番号を登録」）。"))
                .font(.caption).foregroundStyle(Hi.dim)
        }
        switch phoneResult {
        case .none:
            Text(L("相手が「連絡先から見つけてもらう」をオンにしていると見つかります。番号は、元に戻せない形に変えてから照合します。"))
                .font(.caption).foregroundStyle(Hi.dim)
        case .searching:
            ProgressView().tint(.white).frame(maxWidth: .infinity)
        case .found(let m):
            HStack(spacing: 12) {
                Circle().fill(Hi.neon.opacity(0.25)).frame(width: 44, height: 44)
                    .overlay(Text(String((m.name.isEmpty ? m.handle : m.name).prefix(1))).font(.headline.weight(.bold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.name.isEmpty ? m.handle : m.name).font(.body.weight(.bold)).foregroundStyle(.white)
                    if !m.handle.isEmpty { Text("@" + m.handle).font(.caption).foregroundStyle(Hi.dim) }
                }
                Spacer()
                if cloud.friends.contains(where: { $0.uid == m.uid }) {
                    Text(L("友達")).font(.caption.weight(.bold)).foregroundStyle(Hi.dim)
                } else if cloud.sentRequests.contains(m.uid) {
                    Text(L("申請済み")).font(.caption.weight(.bold)).foregroundStyle(Hi.dim)
                } else {
                    Button(L("申請")) {
                        Task {
                            let profile = CloudProfile(uid: m.uid, code: m.code, name: m.name, handle: m.handle, rank: nil, streak: nil)
                            try? await cloud.sendRequest(to: profile)
                        }
                    }
                    .font(.caption.weight(.black))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Hi.neon))
                    .foregroundStyle(Hi.onNeon)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black))
        case .notFound:
            VStack(alignment: .leading, spacing: 8) {
                Text(L("見つかりませんでした。まだ使っていないか、見つけてもらう設定をオフにしているかもしれません。"))
                    .font(.caption).foregroundStyle(Hi.dim)
                ShareLink(item: FriendCode.shareURL, message: Text(L("Difframeで同じお題を撮ろう。このリンクから友達になれるよ。"))) {
                    Label(L("招待リンクを送る"), systemImage: "square.and.arrow.up").font(.caption.weight(.bold))
                }
                .foregroundStyle(Hi.neon)
            }
        case .failed:
            Text(L("探せませんでした。通信を確かめて、もう一度試してください。")).font(.caption).foregroundStyle(Hi.dim)
        }
    }

    private func searchPhone() {
        guard let e164 = PhoneNumbers.e164(number, defaultCode: country.dial) else { phoneResult = .notFound; return }
        phoneResult = .searching
        Task {
            guard let result = await cloud.matchContacts(hashes: [PhoneNumbers.hash(e164)]) else { phoneResult = .failed; return }
            if let m = result.first(where: { $0.uid != cloud.uid }) { phoneResult = .found(m) } else { phoneResult = .notFound }
        }
    }

    // MARK: そのほかの追加のしかた

    private var waysCard: some View {
        VStack(spacing: 0) {
            wayRow(L("連絡先から探す"), icon: "person.2.fill") { showContacts = true }
            divider
            wayRow(L("相手のQRコードを読み取る"), icon: "qrcode.viewfinder") { showScanner = true }
            divider
            wayRow(L("連絡先の人を招待"), icon: "envelope.fill") { showInviteList = true }
        }
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Hi.tile))
    }

    private var divider: some View { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.leading, 56) }

    private func wayRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.body.weight(.bold)).foregroundStyle(Hi.neon).frame(width: 26)
                Text(title).font(.body.weight(.bold)).foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Hi.dim)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 自分のコード

    private var myCodeCard: some View {
        VStack(spacing: 12) {
            Text(L("自分のコード（相手に見せる）")).font(.headline.weight(.black)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let qr = FriendCode.qrImage(for: FriendCode.shareURL) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 180, height: 180)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white))
            }
            Text(FriendCode.myID)
                .font(.system(.body, design: .monospaced).weight(.bold))
                .foregroundStyle(.white)
                .textSelection(.enabled)
            ShareLink(item: FriendCode.shareURL) {
                Label(L("リンクを送る（LINEなど）"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(NeonButtonStyle())
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Hi.tile))
    }

    // MARK: いまの友達

    private var friendsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LF("いまの友達（{n}人）", ["n": "\(cloud.friends.count)"])).font(.headline.weight(.black)).foregroundStyle(.white)
            if cloud.friends.isEmpty {
                Text(L("まだ友達がいません")).font(.subheadline).foregroundStyle(Hi.dim)
            }
            ForEach(cloud.friends) { friend in
                HStack(spacing: 12) {
                    Circle().fill(Color.white.opacity(0.12)).frame(width: 36, height: 36)
                        .overlay(Text(String((friend.name.isEmpty ? friend.code : friend.name).prefix(1))).font(.subheadline.weight(.bold)).foregroundStyle(.white))
                    Text(friend.name.isEmpty ? friend.code : friend.name).font(.body.weight(.bold)).foregroundStyle(.white)
                    Spacer()
                }
                .contextMenu {
                    Button(role: .destructive) {
                        Task { await cloud.removeFriend(uid: friend.uid) }
                    } label: { Label(L("友達から外す"), systemImage: "person.badge.minus") }
                }
            }
            if !cloud.friends.isEmpty {
                Text(L("長押しで、友達から外せます。")).font(.caption).foregroundStyle(Hi.dim)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Hi.tile))
    }

    /// 読み取った（貼った）コードの人のプロフィールを開く。追加は、そこから行う
    private func open(from text: String, delay: Double = 0) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // リンクでないなら、まずIDとして探す（@・大文字もOK）
        let looksLikeLink = trimmed.contains("/") || trimmed.contains(":")
        Task {
            var code: String? = nil
            if !looksLikeLink { code = await CloudSync.shared.resolveID(trimmed) }
            if code == nil { code = FriendCode.parse(trimmed) }
            guard let id = code else {
                message = L("IDかリンクが見つかりませんでした")
                return
            }
            message = nil
            newFriend = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { viewing = CodeTarget(id: id) }
        }
    }

    private func removeFriends(at offsets: IndexSet) {
        var list = friends
        list.remove(atOffsets: offsets)
        friendList = list.joined(separator: ",")
    }
}

/// 友達コード（QR・リンク・ID）から開く相手
struct CodeTarget: Identifiable {
    let id: String
}

/// 友達コードの持ち主のプロフィール。ここから友達に追加する（QR・リンク・IDを読み取ると、まずここに来る）
struct CalendarTarget: Identifiable { let id: String; let name: String }

struct PersonProfileSheet: View {
    let code: String
    /// 追加できるのは、QRコードかリンクから開いたときだけ（ユーザー名から開いたときは追加しない）
    var canAdd = false
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var cloud = CloudSync.shared
    @AppStorage("friendList") private var friendList: String = MyProfile.defaultFriends

    private enum Phase: Equatable { case loading, found(CloudProfile), notFound, failed }
    @State private var phase: Phase = .loading
    @State private var working = false
    @State private var chatFriend: CloudFriend? = nil
    @State private var calendarTarget: CalendarTarget? = nil
    @State private var showReport = false
    @State private var reported = false

    private var isMe: Bool { code == FriendCode.myID }

    private var foundProfile: CloudProfile? {
        if case .found(let p) = phase { return p }
        return nil
    }

    private func isFriend(_ profile: CloudProfile?) -> Bool {
        if cloud.isOn { return cloud.friends.contains { $0.code == code || $0.uid == profile?.uid } }
        return friendList.split(separator: ",").map(String.init).contains(code)
    }

    var body: some View { bodyContent.edgeSwipeBack() }

    private var bodyContent: some View {
        NavigationStack {
            ScrollView {
            VStack(spacing: 14) {
                Spacer(minLength: 20)
                switch phase {
                case .loading:
                    ProgressView()
                    Text(L("さがしています…")).foregroundStyle(Hi.dim)
                case .notFound:
                    Image(systemName: "person.fill.questionmark").font(.system(size: 44)).foregroundStyle(Hi.dim)
                    Text(L("そのIDの人は見つかりませんでした")).font(.headline.weight(.black))
                    Text(code).font(.system(.caption, design: .monospaced)).foregroundStyle(Hi.dim)
                case .failed:
                    Image(systemName: "wifi.exclamationmark").font(.system(size: 44)).foregroundStyle(Hi.dim)
                    Text(L("つながりませんでした。あとでもう一度お試しください")).multilineTextAlignment(.center)
                    Button(L("もう一度")) { Task { await load() } }.buttonStyle(TileButtonStyle())
                case .found(let profile):
                    card(profile)
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(L("プロフィール"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if cloud.isOn, !isMe, let p = foundProfile {
                        Menu {
                            if cloud.blocked.contains(p.uid) {
                                Button(L("ブロックを解除")) { Task { await cloud.unblock(p.uid) } }
                            } else {
                                Button(L("通報")) { showReport = true }
                                Button(L("ブロック"), role: .destructive) {
                                    Task { await cloud.block(p.uid); dismiss() }
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle").font(.title3)
                        }
                        .accessibilityLabel(L("その他"))
                    }
                }
                ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold)) }.accessibilityLabel(L("戻る")) }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.black)
        .preferredColorScheme(.dark)
        .task { await load() }
        .fullScreenCover(item: $chatFriend) { ChatView(friend: $0) }
        .fullScreenCover(item: $calendarTarget) { FriendCalendarSheet(uid: $0.id, name: $0.name).environmentObject(PostStore.shared) }
        .alert(L("通報を受け付けました。ありがとうございます。"), isPresented: $reported) {
            Button("OK", role: .cancel) {}
        }
        .confirmationDialog(L("通報の理由"), isPresented: $showReport, titleVisibility: .visible) {
            if let p = foundProfile {
                Button(L("嫌がらせ・不快")) { reported = true; Task { await cloud.sendReport(against: p.uid, reason: L("嫌がらせ・不快")) } }
                Button(L("不適切な内容")) { reported = true; Task { await cloud.sendReport(against: p.uid, reason: L("不適切な内容")) } }
                Button(L("その他")) { reported = true; Task { await cloud.sendReport(against: p.uid, reason: L("その他")) } }
            }
            Button(L("キャンセル"), role: .cancel) {}
        }
    }

    // MARK: 相手の数字（ランク・連続・投稿・自己ベスト・地域・トロフィー）

    private func statsSection(_ p: CloudProfile) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                statTile(L("連続"), p.streak.map { LF("{n}日", ["n": "\($0)"]) } ?? "--")
                postsTile(p)
                statTile(L("自己ベスト"), p.best.map { TimeFormat.string($0) } ?? "--")
            }
            trophyCard(Set(p.trophies.compactMap(Trophy.init(key:))))
        }
    }

    /// 「投稿」の数字：いまの友達なら、押すと、その人のカレンダーが開く
    @ViewBuilder
    private func postsTile(_ p: CloudProfile) -> some View {
        let value = p.posts.map { LF("{n}枚", ["n": "\($0)"]) } ?? "--"
        if cloud.isOn, !isMe, isFriend(p), !cloud.blocked.contains(p.uid) {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                calendarTarget = CalendarTarget(id: p.uid, name: p.name)
            } label: {
                statTile(L("投稿"), value)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "calendar").font(.caption2.weight(.bold)).foregroundStyle(Hi.dim).padding(10)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(L("カレンダーを見る"))
        } else {
            statTile(L("投稿"), value)
        }
    }

    private func statTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Hi.dim).lineLimit(1).minimumScaleFactor(0.7)
            Text(value).font(.subheadline.weight(.black)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .hiTile(cornerRadius: 18)
    }

    private func rankCard(_ rank: Rank, points: Int?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: rank.icon).font(.title2).foregroundStyle(rank.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("今月のランク")).font(.caption).foregroundStyle(Hi.dim)
                Text(rank.name).font(.title3.weight(.black)).foregroundStyle(rank.color)
            }
            Spacer()
            if let points {
                Text("\(points) pt").font(.headline.monospacedDigit().weight(.black)).foregroundStyle(.white)
            }
        }
        .accessibilityElement(children: .combine)
        .hiTile(cornerRadius: 22)
    }

    private func trophyCard(_ earned: Set<Trophy>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("トロフィー")).font(.headline.weight(.black))
                Spacer()
                Text("\(earned.count) / \(Trophy.allCases.count)")
                    .font(.subheadline.weight(.bold)).foregroundStyle(Hi.dim)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(TrophyFamily.all) { family in
                    TrophyFamilyCell(family: family, earned: earned, showNext: false)
                }
            }
        }
        .hiTile(cornerRadius: 22)
    }

    /// 上の大きなカード：ランクの色に染まった背景に、アイコン・名前・ランク・次のランクまで
    private func hero(_ p: CloudProfile) -> some View {
        let rank = p.rank.flatMap(Rank.init(rawValue:)) ?? .bronze
        let colors = rank.cardColors
        let points = p.points ?? rank.threshold
        let progress: Double = {
            guard let next = rank.next else { return 1 }
            let span = Double(next.threshold - rank.threshold)
            return min(1, max(0, Double(points - rank.threshold) / span))
        }()
        return VStack(spacing: 10) {
            Group {
                if let image = (isMe ? Avatar.load() : cloud.avatars[p.uid]) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Hi.neon)
                        .overlay(Text(String(p.name.prefix(1)))
                            .font(.system(size: 48, weight: .black, design: .rounded)).foregroundStyle(Hi.onNeon))
                }
            }
            .frame(width: 112, height: 112)
            .clipShape(Circle())
            .overlay(Circle().stroke(rank.color, lineWidth: 4))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: rank.icon).font(.subheadline.weight(.black)).foregroundStyle(rank.color)
                    .padding(8).background(Circle().fill(Color.black.opacity(0.75)))
            }
            Text(p.name).font(.title.weight(.black)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 6) {
                Text("@" + p.handle).font(.subheadline.weight(.bold)).foregroundStyle(.white.opacity(0.75))
                if p.rank != nil { RankBadge(rank: rank) }
            }
            Text(p.code).font(.system(.caption, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
            if p.points != nil {
                VStack(spacing: 5) {
                    ProgressView(value: progress).tint(rank.color)
                    Text(rank.next.map { LF("{r}まで {n} pt", ["r": $0.name, "n": "\(max(0, $0.threshold - points))"]) } ?? L("最高ランク"))
                        .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.75))
                }
                .padding(.top, 6).padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 22).padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [rank.color.opacity(0.45), .clear], center: .top, startRadius: 0, endRadius: 260)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func card(_ p: CloudProfile) -> some View {
        VStack(spacing: 10) {
            hero(p)
            // 友達なら、上のすぐ見えるところから、メッセージを開ける
            if cloud.isOn, !isMe, isFriend(p), !cloud.blocked.contains(p.uid) {
                Button {
                    chatFriend = CloudFriend(uid: p.uid, name: p.name, code: p.code)
                } label: {
                    Label(L("メッセージ"), systemImage: "bubble.left.and.bubble.right.fill")
                }
                .buttonStyle(NeonButtonStyle())
            }
            statsSection(p).padding(.top, 4)

            Spacer(minLength: 16)
            if isMe {
                Text(L("これは自分のコードです")).font(.subheadline.weight(.bold)).foregroundStyle(Hi.dim)
            } else if isFriend(p) {
                Label(L("友達です"), systemImage: "checkmark.circle.fill")
                    .font(.headline.weight(.black)).foregroundStyle(Hi.neon)
                if cloud.isOn {
                    if !cloud.blocked.contains(p.uid) {
                        Button {
                            calendarTarget = CalendarTarget(id: p.uid, name: p.name)
                        } label: {
                            Label(L("カレンダーを見る"), systemImage: "calendar")
                        }
                        .buttonStyle(TileButtonStyle())
                    }
                }
                Button(role: .destructive) {
                    Task { await cloud.removeFriend(uid: p.uid); dismiss() }
                } label: { Text(L("友達をやめる")) }
                    .font(.subheadline)
            } else if cloud.blocked.contains(p.uid) {
                Text(L("ブロック中です")).font(.subheadline.weight(.bold)).foregroundStyle(Hi.dim)
            } else if !canAdd {
                Text(L("友達追加はリンクかQRコードから")).font(.caption).foregroundStyle(Hi.dim).multilineTextAlignment(.center)
            } else if let incoming = cloud.notices.first(where: { $0.type == "friendRequest" && $0.fromUID == p.uid }) {
                // 相手から、すでにリクエストが来ているとき
                Text(LF("{n} さんから友達リクエストが届きました", ["n": p.name])).font(.subheadline.weight(.bold))
                Button {
                    Task {
                        working = true
                        try? await cloud.accept(incoming)
                        working = false
                    }
                } label: {
                    Label(L("承認"), systemImage: "checkmark")
                }
                .buttonStyle(NeonButtonStyle())
                .disabled(working)
            } else if cloud.sentRequests.contains(p.uid) {
                Label(L("リクエスト送信済み"), systemImage: "paperplane.fill")
                    .font(.headline.weight(.black)).foregroundStyle(Hi.dim)
            } else {
                Button {
                    Task {
                        working = true
                        if cloud.isOn {
                            try? await cloud.sendRequest(to: p)
                        } else {
                            var list = friendList.split(separator: ",").map(String.init)
                            if !list.contains(code) { list.append(code) }
                            friendList = list.joined(separator: ",")
                        }
                        working = false
                    }
                } label: {
                    Label(cloud.isOn ? L("友達リクエストを送る") : L("友達に追加"), systemImage: "person.badge.plus")
                }
                .buttonStyle(NeonButtonStyle())
                .disabled(working)
            }
        }
    }

    private func load() async {
        if isMe, !cloud.isOn {
            phase = .notFound
            return
        }
        guard cloud.isOn else {
            // サーバーを使わないときは、名前を知らないので、コードだけで追加する
            phase = .found(CloudProfile(uid: code, code: code, name: code, handle: code, rank: nil, streak: nil))
            return
        }
        phase = .loading
        do {
            let profile = try await cloud.lookup(code: code)
            phase = .found(profile)
            Task { await cloud.loadAvatar(profile.uid) }
        } catch CloudError.notFound {
            phase = .notFound
        } catch {
            phase = .failed
        }
    }
}

/// プロフィールから開く、友達の一覧（Instagram のように、人数と一覧を見て、追加もできる）
struct FriendListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var cloud = CloudSync.shared
    @AppStorage("friendList") private var friendList: String = MyProfile.defaultFriends
    @State private var showAdd = false
    @State private var viewing: CodeTarget? = nil
    @State private var chat: CloudFriend? = nil

    private struct Row: Identifiable {
        let id: String
        let name: String
        let sub: String
        let cloudUID: String?
        var code: String? = nil
    }

    private var rows: [Row] {
        if cloud.isOn {
            return cloud.friends.map { Row(id: $0.uid, name: $0.name.isEmpty ? $0.code : $0.name, sub: "@" + $0.code, cloudUID: $0.uid, code: $0.code) }
        }
        return friendList.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { Row(id: $0, name: $0, sub: "@" + $0.lowercased(), cloudUID: nil) }
    }

    var body: some View { bodyContent.edgeSwipeBack() }

    private var bodyContent: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showAdd = true
                    } label: {
                        Label(L("友達を追加する"), systemImage: "person.badge.plus")
                            .font(.headline.weight(.bold))
                    }
                }
                Section {
                    if rows.isEmpty {
                        VStack(spacing: 6) {
                            Text(L("友達がいません")).font(.subheadline.weight(.bold))
                            Text(L("友達コードかQRコードで追加できます"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    ForEach(rows) { row in
                        Button {
                            if let code = row.code { viewing = CodeTarget(id: code) }
                        } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 44, height: 44)
                                .overlay(Text(String(row.name.prefix(1)))
                                    .font(.system(.headline, design: .rounded).bold()))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.name).font(.subheadline.weight(.black)).lineLimit(1)
                                Text(row.sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if row.code != nil {
                                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading) {
                            if let uid = row.cloudUID {
                                Button {
                                    chat = CloudFriend(uid: uid, name: row.name, code: row.code ?? "")
                                } label: { Label(L("メッセージ"), systemImage: "bubble.left.fill") }
                                .tint(Hi.neon)
                            }
                        }
                    }
                    .onDelete { offsets in
                        let targets = offsets.map { rows[$0] }
                        if cloud.isOn {
                            Task { for t in targets { if let uid = t.cloudUID { await cloud.removeFriend(uid: uid) } } }
                        } else {
                            let remove = Set(targets.map(\.id))
                            friendList = rows.map(\.id).filter { !remove.contains($0) }.joined(separator: ",")
                        }
                    }
                } header: {
                    Text(LF("友達 {n}人", ["n": "\(rows.count)"]))
                }
            }
            .navigationTitle(L("友達"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold)) }.accessibilityLabel(L("戻る")) }
            }
            .fullScreenCover(isPresented: $showAdd) { AddFriendSheet(isPresented: $showAdd) }
            .fullScreenCover(item: $viewing) { PersonProfileSheet(code: $0.id) }
            .fullScreenCover(item: $chat) { ChatView(friend: $0) }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }
}
