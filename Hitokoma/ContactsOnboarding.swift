import SwiftUI
import Contacts
import UserNotifications

/// 電話番号を登録した直後に、1回だけ出す画面：連絡先の中から Difframe を使っている人を見つけ、選んだ人に友達申請を送る。
/// 連絡先の名前は送らない。番号は端末の中で SHA-256 にしてから照合する（ContactsView と同じ仕組み）。
struct ContactsOnboardingView: View {
    /// 設定などから開いたとき（「あとで」ではなく「閉じる」を出す）
    var fromSettings = false
    let onFinish: () -> Void

    @ObservedObject private var cloud = CloudSync.shared

    private struct Candidate: Identifiable {
        var id: String { match.uid }
        let contactName: String
        let match: CloudSync.ContactMatch
    }

    private enum Phase { case ask, searching, results, denied, failed }

    @State private var phase: Phase = .ask
    @State private var candidates: [Candidate] = []
    @State private var selected: Set<String> = []
    @State private var sending = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(fromSettings ? L("閉じる") : L("あとで")) { onFinish() }
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Capsule().fill(Hi.tile))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 10) {
                Text(L("連絡先の友達とつながろう"))
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(.white)
                Text(L("連絡先の中で Difframe を使っている人を探します。申請を送る相手は、あなたが選べます。"))
                    .font(.subheadline)
                    .foregroundStyle(Hi.dim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task {
            let status = CNContactStore.authorizationStatus(for: .contacts)
            if status == .authorized || status.rawValue == 4 { await search() }
            else if status == .denied || status == .restricted { phase = .denied }
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .ask:
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "person.2.crop.square.stack.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Hi.neon)
                Text(L("連絡先の名前は送りません。電話番号は、元に戻せない形に変えてから照合します。"))
                    .font(.footnote)
                    .foregroundStyle(Hi.dim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
                Button(L("連絡先から探す")) { requestAccess() }
                    .buttonStyle(NeonButtonStyle())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        case .searching:
            VStack(spacing: 14) {
                Spacer()
                ProgressView().tint(.white)
                Text(L("探しています…")).font(.subheadline).foregroundStyle(Hi.dim)
                Spacer()
            }
        case .denied:
            message(L("連絡先が許可されていません。設定で許可するか、IDやQRコードで友達を追加できます。"), button: L("次へ"))
        case .failed:
            message(L("探せませんでした。あとで、友達を追加の画面から探せます。"), button: L("次へ"))
        case .results:
            if candidates.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Text(L("連絡先の中に、まだ Difframe を使っている人はいませんでした。"))
                        .font(.subheadline)
                        .foregroundStyle(Hi.dim)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    ShareLink(item: FriendCode.shareURL, message: Text(L("Difframeで同じお題を撮ろう。このリンクから友達になれるよ。"))) {
                        Label(L("友達を招待"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(TileButtonStyle())
                    Spacer()
                    Button(L("次へ")) { onFinish() }
                        .buttonStyle(NeonButtonStyle())
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
            } else {
                resultsList
            }
        }
    }

    private var resultsList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(LF("{n}人が Difframe を使っています", ["n": "\(candidates.count)"]))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Hi.dim)
                Spacer()
                Button(selected.count == candidates.count ? L("選ぶのをやめる") : L("全員を選ぶ")) {
                    selected = selected.count == candidates.count ? [] : Set(candidates.map(\.id))
                }
                .font(.footnote.weight(.bold))
                .foregroundStyle(Hi.neon)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(candidates) { c in
                        row(c)
                    }
                }
                .padding(.horizontal, 20)
            }

            Button {
                send()
            } label: {
                if sending { ProgressView().tint(.black) }
                else { Text(selected.isEmpty ? L("申請しないで次へ") : LF("{n}人に申請を送る", ["n": "\(selected.count)"])) }
            }
            .buttonStyle(NeonButtonStyle())
            .disabled(sending)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    private func row(_ c: Candidate) -> some View {
        let on = selected.contains(c.id)
        return Button {
            if on { selected.remove(c.id) } else { selected.insert(c.id) }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Hi.neon.opacity(0.25))
                    .frame(width: 44, height: 44)
                    .overlay(Text(String(c.contactName.prefix(1))).font(.headline.weight(.bold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.contactName).font(.body.weight(.bold)).foregroundStyle(.white)
                    Text(c.match.handle.isEmpty ? c.match.name : "@" + c.match.handle)
                        .font(.caption).foregroundStyle(Hi.dim)
                }
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(on ? Hi.neon : Hi.dim)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Hi.tile))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func message(_ text: String, button: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Hi.dim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button(button) { onFinish() }
                .buttonStyle(NeonButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }

    private func requestAccess() {
        CNContactStore().requestAccess(for: .contacts) { _, _ in
            DispatchQueue.main.async {
                let status = CNContactStore.authorizationStatus(for: .contacts)
                if status == .authorized || status.rawValue == 4 { Task { await search() } } else { phase = .denied }
            }
        }
    }

    /// 連絡先を照合して、一覧にする
    private func search() async {
        phase = .searching
        guard let found = await ContactsMatcher.find() else { phase = .failed; return }
        ContactsMatcher.remember(found)
        candidates = found.map { Candidate(contactName: $0.contactName, match: CloudSync.ContactMatch(hash: "", uid: $0.uid, code: $0.code, name: $0.name, handle: $0.handle)) }
        phase = .results
    }

    /// 選んだ人に友達申請を送って、次へ
    private func send() {
        let targets = candidates.filter { selected.contains($0.id) }
        guard !targets.isEmpty else { onFinish(); return }
        sending = true
        Task {
            for c in targets {
                let profile = CloudProfile(uid: c.match.uid, code: c.match.code, name: c.match.name, handle: c.match.handle, rank: nil, streak: nil)
                if (try? await cloud.sendRequest(to: profile)) != nil { ContactsMatcher.dismiss(c.match.uid) }
            }
            sending = false
            onFinish()
        }
    }
}


/// 連絡先の中で、Difframe を使っている人（端末の中にだけ覚える。連絡先の名前は、サーバーに送らない）
struct ContactFriend: Identifiable, Codable, Equatable {
    var id: String { uid }
    let uid: String
    let code: String
    let name: String
    let handle: String
    let contactName: String
}

/// 連絡先の照合と、「新しく始めた連絡先の友達」を見つける仕組み
@MainActor
enum ContactsMatcher {
    static let newJoinersKey = "contacts.newJoiners"   // 新しく始めた人（JSON）。画面は @AppStorage で読む
    private static let knownKey = "contacts.knownUIDs"   // これまでに見つけた人（新しいかどうかの判定に使う）
    private static let checkedKey = "contacts.checkedAt"
    private static let baselineKey = "contacts.baselineDone"   // 1回でも照合したか（0人でも）

    static var hasAccess: Bool {
        let s = CNContactStore.authorizationStatus(for: .contacts)
        return s == .authorized || s.rawValue == 4
    }

    /// 連絡先を読み、番号を SHA-256 にして照合する。自分・もう友達の人は除く。照合できなかったら nil
    static func find() async -> [ContactFriend]? {
        let contacts: [(name: String, phones: [String])] = await Task.detached(priority: .userInitiated) {
            let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
            var out: [(String, [String])] = []
            try? CNContactStore().enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, _ in
                let numbers = contact.phoneNumbers.map { $0.value.stringValue }
                guard !numbers.isEmpty else { return }
                let name = [contact.familyName, contact.givenName].filter { !$0.isEmpty }.joined(separator: " ")
                out.append((name.isEmpty ? numbers[0] : name, numbers))
            }
            return out
        }.value
        let own = UserDefaults.standard.string(forKey: Account.phoneKey) ?? ""
        let cc = PhoneNumbers.defaultCallingCode(own: own)
        var names: [String: String] = [:]
        for person in contacts {
            for raw in person.phones {
                guard let e164 = PhoneNumbers.e164(raw, defaultCode: cc), e164 != own else { continue }
                names[PhoneNumbers.hash(e164)] = person.name
            }
        }
        guard !names.isEmpty else { return [] }
        let cloud = CloudSync.shared
        guard let result = await cloud.matchContacts(hashes: Array(names.keys)) else { return nil }
        var seen = Set<String>()
        return result.compactMap { m in
            guard m.uid != cloud.uid, !cloud.friends.contains(where: { $0.uid == m.uid }), seen.insert(m.uid).inserted else { return nil }
            return ContactFriend(uid: m.uid, code: m.code, name: m.name, handle: m.handle, contactName: names[m.hash] ?? m.name)
        }
        .sorted { $0.contactName.localizedStandardCompare($1.contactName) == .orderedAscending }
    }

    /// 見つけた人を「もう知っている人」として覚える（次から「新しく始めた」に出さない）
    static func remember(_ list: [ContactFriend]) {
        var known = Set(UserDefaults.standard.stringArray(forKey: knownKey) ?? [])
        known.formUnion(list.map(\.uid))
        UserDefaults.standard.set(Array(known), forKey: knownKey)
        UserDefaults.standard.set(true, forKey: baselineKey)
    }

    static var newJoiners: [ContactFriend] {
        get {
            guard let data = (UserDefaults.standard.string(forKey: newJoinersKey) ?? "").data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([ContactFriend].self, from: data)) ?? []
        }
        set {
            let text = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            UserDefaults.standard.set(text, forKey: newJoinersKey)
        }
    }

    /// 申請した・閉じた人を、「新しく始めた」から外す
    static func dismiss(_ uid: String) {
        newJoiners.removeAll { $0.uid == uid }
    }

    /// アプリを開いたとき・iOS がアプリを起こしたときに呼ぶ（12時間に1回まで）。
    /// 前に見つけていなかった人が増えていたら、「新しく始めた」に足して、その人たちを返す
    @discardableResult
    static func checkForNewJoiners() async -> [ContactFriend] {
        let defaults = UserDefaults.standard
        guard CloudSync.shared.isOn, defaults.bool(forKey: Account.verifiedKey), hasAccess else { return [] }
        let last = defaults.double(forKey: checkedKey)
        guard Date().timeIntervalSince1970 - last > 12 * 3600 else { return [] }
        guard let found = await find() else { return [] }
        var fresh: [ContactFriend] = []
        defaults.set(Date().timeIntervalSince1970, forKey: checkedKey)
        let known = Set(defaults.stringArray(forKey: knownKey) ?? [])
        let sent = CloudSync.shared.sentRequests
        if defaults.bool(forKey: baselineKey) {
            fresh = found.filter { !known.contains($0.uid) && !sent.contains($0.uid) }
            if !fresh.isEmpty {
                var list = newJoiners
                for f in fresh where !list.contains(where: { $0.uid == f.uid }) { list.append(f) }
                newJoiners = list
            }
        }
        remember(found)   // はじめての照合では、見つけた人を「知っている人」にするだけ（全員が「新しく始めた」にならないように）
        return fresh
    }

    // MARK: 通知（連絡先の友達が始めたとき）

    nonisolated static let notificationCategory = "contactJoined"
    nonisolated static let addAction = "ADD_FRIEND"

    /// 通知の「友達申請を送る」ボタンを、iOS に登録する（起動時に1回）
    nonisolated static func registerNotificationActions() {
        let add = UNNotificationAction(identifier: addAction, title: L("友達申請を送る"), options: [])
        let category = UNNotificationCategory(identifier: notificationCategory, actions: [add], intentIdentifiers: [], options: [])
        let center = UNUserNotificationCenter.current()
        center.getNotificationCategories { existing in
            center.setNotificationCategories(existing.filter { $0.identifier != notificationCategory }.union([category]))
        }
    }

    /// 新しく始めた人を、端末の通知で知らせる。1人なら、通知から友達申請を送れる
    static func notify(_ fresh: [ContactFriend]) async {
        guard !fresh.isEmpty, !NotifySettings.isMuted("contactJoined") else { return }
        let content = UNMutableNotificationContent()
        content.title = "Difframe"
        content.sound = .default
        content.userInfo = ["contactJoined": true]
        if fresh.count == 1, let f = fresh.first {
            content.body = LF("連絡先の{name}さんが Difframe を始めました", ["name": f.contactName])
            content.categoryIdentifier = notificationCategory
            content.userInfo = ["contactJoined": true, "uid": f.uid, "code": f.code, "name": f.name, "handle": f.handle]
        } else {
            content.body = LF("連絡先の友達{n}人が Difframe を始めました", ["n": "\(fresh.count)"])
        }
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "contactJoined-" + UUID().uuidString, content: content, trigger: nil))
    }
}

/// タイムラインの上に出す：「連絡先の友達が Difframe を始めました」。申請・閉じるができる
struct NewContactFriendsBanner: View {
    @AppStorage(ContactsMatcher.newJoinersKey) private var json: String = ""
    @ObservedObject private var cloud = CloudSync.shared
    @State private var showAll = false

    private var list: [ContactFriend] {
        guard let data = json.data(using: .utf8) else { return [] }
        return ((try? JSONDecoder().decode([ContactFriend].self, from: data)) ?? [])
            .filter { m in !cloud.friends.contains(where: { $0.uid == m.uid }) }
    }

    var body: some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "sparkles").foregroundStyle(Hi.neon)
                    Text(L("連絡先の友達が Difframe を始めました"))
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(.white)
                    Spacer()
                }
                ForEach(list.prefix(3)) { f in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Hi.neon.opacity(0.25))
                            .frame(width: 36, height: 36)
                            .overlay(Text(String(f.contactName.prefix(1))).font(.subheadline.weight(.bold)).foregroundStyle(.white))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(f.contactName).font(.subheadline.weight(.bold)).foregroundStyle(.white).lineLimit(1)
                            Text(f.handle.isEmpty ? f.name : "@" + f.handle).font(.caption).foregroundStyle(Hi.dim).lineLimit(1)
                        }
                        Spacer()
                        if cloud.sentRequests.contains(f.uid) {
                            Text(L("申請済み")).font(.caption.weight(.bold)).foregroundStyle(Hi.dim)
                        } else {
                            Button(L("申請")) {
                                Task {
                                    let profile = CloudProfile(uid: f.uid, code: f.code, name: f.name, handle: f.handle, rank: nil, streak: nil)
                                    if (try? await cloud.sendRequest(to: profile)) != nil { ContactsMatcher.dismiss(f.uid) }
                                }
                            }
                            .font(.caption.weight(.black))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Capsule().fill(Hi.neon))
                            .foregroundStyle(Hi.onNeon)
                        }
                        Button {
                            ContactsMatcher.dismiss(f.uid)
                        } label: {
                            Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(Hi.dim)
                        }
                        .accessibilityLabel(L("閉じる"))
                    }
                }
                if list.count > 3 {
                    Button(LF("ほか{n}人を見る", ["n": "\(list.count - 3)"])) { showAll = true }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Hi.neon)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Hi.tile))
            .fullScreenCover(isPresented: $showAll) {
                ContactsOnboardingView(fromSettings: true) { showAll = false }
            }
        }
    }
}
