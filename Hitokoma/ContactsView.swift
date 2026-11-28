import SwiftUI
import Contacts
import CryptoKit

/// 連絡先から友達を探す・招待する画面。
/// 連絡先は、この画面を開いている間だけ読み込む。名前は端末の外へ送らない。
/// 電話番号は、+81… の形にそろえてから SHA-256 にした値だけをサーバーに送り、Difframe を使っている人を探す（サーバーは保存しない）。
struct ContactsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject private var cloud = CloudSync.shared
    @AppStorage(Account.verifiedKey) private var phoneVerified = false

    private struct Person: Identifiable {
        let id: String
        let name: String
        let phone: String
        let phones: [String]
    }

    /// 連絡先の中で、Difframe を使っている人
    private struct Found: Identifiable {
        var id: String { match.uid }
        let contactName: String
        let match: CloudSync.ContactMatch
    }

    @State private var found: [Found] = []
    @State private var matching = false
    @State private var matchFailed = false
    @State private var requested: Set<String> = []

    @State private var status = CNContactStore.authorizationStatus(for: .contacts)
    @State private var people: [Person] = []
    @State private var query = ""
    @State private var loading = false

    /// 全部または一部の連絡先を共有してもらえたか（iOS 18 の「一部だけ共有」は rawValue 4）
    private var hasAccess: Bool { status == .authorized || status.rawValue == 4 }

    private var filtered: [Person] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return people }
        return people.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.phone.contains(q) }
    }

    private var inviteText: Text {
        Text(L("Difframeで同じお題を撮ろう。このリンクから友達になれるよ。"))
    }

    var body: some View {
        NavigationStack {
            Group {
                if hasAccess {
                    list
                } else if status == .notDetermined {
                    ask
                } else {
                    denied
                }
            }
            .navigationTitle(L("連絡先の人を招待"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 16, weight: .black)).foregroundStyle(.white)
                    }
                    .accessibilityLabel(L("戻る"))
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(Hi.neon)
        .task {
            if hasAccess { await load() }
        }
    }

    // 許可を聞く前の説明
    private var ask: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 56))
            Text(L("連絡先から友達を探す"))
                .font(.title3.weight(.black))
            Text(L("連絡先の中から、Difframe を使っている友達を探します。電話番号は読めない形に変えてから照合し、名前は送りません。サーバーには保存しません。使っていない人には、招待リンクを送れます。"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L("連絡先へのアクセスを許可")) { request() }
                .buttonStyle(NeonButtonStyle())
                .padding(.horizontal, 20)
        }
        .padding(28)
    }

    private var denied: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill").font(.system(size: 44))
            Text(L("連絡先が許可されていません"))
                .font(.title3.weight(.black))
            Text(L("連絡先を使わなくても、QRコードやリンクで友達を追加できます。使いたい場合は、設定で許可してください。"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L("設定を開く")) {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(NeonButtonStyle())
                .padding(.horizontal, 20)
        }
        .padding(28)
    }

    private var list: some View {
        List {
            foundSection
            Section(L("招待する")) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if people.isEmpty {
                    Text(L("電話番号のある連絡先が見つかりませんでした"))
                        .foregroundStyle(.secondary)
                } else if filtered.isEmpty {
                    Text(LF("「{q}」に合う連絡先がありません", ["q": query]))
                        .foregroundStyle(.secondary)
                }
                ForEach(filtered) { person in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 40, height: 40)
                            .overlay(Text(String(person.name.prefix(1))).font(.headline.weight(.bold)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(person.name).font(.body.weight(.bold))
                            Text(person.phone).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        ShareLink(item: FriendCode.shareURL, message: inviteText) {
                            Text(L("招待"))
                                .font(.subheadline.weight(.bold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Hi.neon))
                                .foregroundStyle(Hi.onNeon)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: L("名前や番号で探す"))
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    /// Difframe を使っている友達（いちばん上）
    @ViewBuilder private var foundSection: some View {
        if !phoneVerified {
            Section {
                note(L("電話番号を登録すると、連絡先の中から Difframe を使っている友達を探せます。設定 →「電話番号を登録」から登録できます。"))
            }
        } else if matching {
            Section(L("Difframe を使っている友達")) { ProgressView().frame(maxWidth: .infinity) }
        } else if matchFailed {
            Section(L("Difframe を使っている友達")) { note(L("探せませんでした。通信を確かめて、開き直してください。")) }
        } else if found.isEmpty {
            Section(L("Difframe を使っている友達")) { note(L("連絡先の中に、まだ見つかりませんでした。招待してみましょう。")) }
        } else {
            Section(L("Difframe を使っている友達")) {
                ForEach(found) { item in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Hi.neon.opacity(0.25))
                            .frame(width: 40, height: 40)
                            .overlay(Text(String(item.contactName.prefix(1))).font(.headline.weight(.bold)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.contactName).font(.body.weight(.bold))
                            Text(item.match.handle.isEmpty ? item.match.name : "@" + item.match.handle)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        addButton(item.match)
                    }
                }
            }
        }
    }

    @ViewBuilder private func addButton(_ m: CloudSync.ContactMatch) -> some View {
        if cloud.friends.contains(where: { $0.uid == m.uid }) {
            Text(L("友達")).font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
        } else if requested.contains(m.uid) || cloud.sentRequests.contains(m.uid) {
            Text(L("申請済み")).font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
        } else {
            Button {
                requested.insert(m.uid)
                Task {
                    let profile = CloudProfile(uid: m.uid, code: m.code, name: m.name, handle: m.handle, rank: nil, streak: nil)
                    do { try await cloud.sendRequest(to: profile) } catch { requested.remove(m.uid) }
                }
            } label: {
                Text(L("追加"))
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Hi.neon))
                    .foregroundStyle(Hi.onNeon)
            }
            .buttonStyle(.plain)
        }
    }

    private func note(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(.secondary)
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
    }

    /// 連絡先の番号を照合して、使っている人を探す
    private func findFriends() async {
        guard phoneVerified, cloud.isOn, !people.isEmpty else { return }
        matching = true
        matchFailed = false
        let own = UserDefaults.standard.string(forKey: Account.phoneKey) ?? ""
        let cc = PhoneNumbers.defaultCallingCode(own: own)
        var names: [String: String] = [:]   // ハッシュ → 連絡先の名前
        for person in people {
            for raw in person.phones {
                guard let e164 = PhoneNumbers.e164(raw, defaultCode: cc), e164 != own else { continue }
                names[PhoneNumbers.hash(e164)] = person.name
            }
        }
        let result = await cloud.matchContacts(hashes: Array(names.keys))
        matching = false
        guard let result else { matchFailed = true; return }
        var seen = Set<String>()
        found = result.compactMap { m in
            guard m.uid != cloud.uid, seen.insert(m.uid).inserted else { return nil }
            return Found(contactName: names[m.hash] ?? m.name, match: m)
        }.sorted { $0.contactName < $1.contactName }
    }

    private func request() {
        CNContactStore().requestAccess(for: .contacts) { _, _ in
            DispatchQueue.main.async {
                status = CNContactStore.authorizationStatus(for: .contacts)
                if hasAccess { Task { await load() } }
            }
        }
    }

    private func load() async {
        loading = true
        let result: [Person] = await Task.detached(priority: .userInitiated) {
            let keys = [CNContactGivenNameKey, CNContactFamilyNameKey,
                        CNContactPhoneNumbersKey] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.sortOrder = .givenName
            var out: [Person] = []
            try? CNContactStore().enumerateContacts(with: request) { contact, _ in
                let numbers = contact.phoneNumbers.map { $0.value.stringValue }
                guard let number = numbers.first else { return }
                let name = [contact.familyName, contact.givenName].filter { !$0.isEmpty }.joined(separator: " ")
                out.append(Person(id: contact.identifier, name: name.isEmpty ? number : name, phone: number, phones: numbers))
            }
            return out
        }.value
        people = result
        loading = false
        await findFriends()
    }
}

/// 電話番号を、国番号つきの形（+819012345678）にそろえる。照合のために、SHA-256 にする
enum PhoneNumbers {
    /// 地域 → 国番号（よく使われる国だけ。ほかは、自分の番号の国番号を使う）
    static let callingCodes: [String: String] = [
        "US": "1", "CA": "1", "JP": "81", "KR": "82", "CN": "86", "TW": "886", "HK": "852", "MO": "853",
        "GB": "44", "IE": "353", "FR": "33", "DE": "49", "ES": "34", "PT": "351", "IT": "39", "NL": "31",
        "BE": "32", "CH": "41", "AT": "43", "SE": "46", "NO": "47", "DK": "45", "FI": "358", "PL": "48",
        "RU": "7", "TR": "90", "IL": "972", "AE": "971", "SA": "966", "EG": "20", "ZA": "27", "NG": "234",
        "KE": "254", "IN": "91", "PK": "92", "BD": "880", "LK": "94", "NP": "977", "TH": "66", "VN": "84",
        "PH": "63", "MY": "60", "SG": "65", "ID": "62", "KH": "855", "MM": "95", "MN": "976", "AU": "61",
        "NZ": "64", "MX": "52", "BR": "55", "AR": "54", "CL": "56", "CO": "57", "PE": "51",
    ]
    private static let codes = Set(callingCodes.values)

    /// 国番号のない番号に使う国番号：自分の番号の国番号。なければ、端末の地域
    static func defaultCallingCode(own: String) -> String {
        if own.hasPrefix("+") {
            let digits = own.dropFirst()
            for length in [3, 2, 1] where codes.contains(String(digits.prefix(length))) { return String(digits.prefix(length)) }
        }
        return callingCodes[Locale.current.region?.identifier ?? ""] ?? "1"
    }

    /// 連絡先の番号を +国番号… の形に。そろえられないときは nil
    static func e164(_ raw: String, defaultCode cc: String) -> String? {
        let text = (raw.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? raw).trimmingCharacters(in: .whitespaces)
        var digits = String(text.unicodeScalars.filter { $0.isASCII && CharacterSet.decimalDigits.contains($0) }.map(Character.init))
        guard digits.count >= 6, digits.count <= 15 else { return nil }
        if text.hasPrefix("+") { return "+" + digits }
        if digits.hasPrefix("00") { return "+" + digits.dropFirst(2) }
        if cc == "1" {   // アメリカ・カナダ
            if digits.hasPrefix("011") { return "+" + digits.dropFirst(3) }
            if digits.count == 10 { return "+1" + digits }
            if digits.count == 11, digits.hasPrefix("1") { return "+" + digits }
            return nil
        }
        if digits.hasPrefix("0") && cc != "39" { digits.removeFirst() }   // 国内の「0」（イタリアは残す）
        return "+" + cc + digits
    }

    static func hash(_ e164: String) -> String {
        SHA256.hash(data: Data(e164.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension CloudSync {
    /// 「連絡先から見つけてもらう」（初期値はオン）
    static let discoverableKey = "phoneDiscoverable"
    static var phoneDiscoverable: Bool { UserDefaults.standard.object(forKey: discoverableKey) as? Bool ?? true }

    /// 連絡先で見つかった人
    struct ContactMatch {
        let hash: String
        let uid: String
        let code: String
        let name: String
        let handle: String
    }

    /// サーバーの関数（Cloud Functions の onCall）を呼ぶ
    func callFunction(_ name: String, _ data: [String: Any]) async throws -> [String: Any] {
        try await ensureSignedIn()
        let url = URL(string: "https://us-central1-\(CloudConfig.projectID).cloudfunctions.net/\(name)")!
        let json = try await send("POST", url: url, json: ["data": data])
        return json["result"] as? [String: Any] ?? [:]
    }

    /// 「見つけてもらう」の設定を、サーバーの索引に反映する（SMS で確認した番号のアカウントだけ）。同じ内容は1日1回
    func syncPhoneDiscovery(force: Bool = false) async {
        guard isOn, UserDefaults.standard.bool(forKey: Account.verifiedKey) else { return }
        let on = Self.phoneDiscoverable
        let stampKey = "phoneDiscovery.stamp"
        let stamp = "\(uid ?? "")|\(on)|\(PostStore.dayKey(for: Date()))"
        if !force, UserDefaults.standard.string(forKey: stampKey) == stamp { return }
        do {
            _ = try await callFunction("setPhoneDiscoverable", ["enabled": on])
            UserDefaults.standard.set("\(uid ?? "")|\(on)|\(PostStore.dayKey(for: Date()))", forKey: stampKey)
        } catch {
            NSLog("phone discovery sync failed: \(error.localizedDescription)")
        }
    }

    /// 連絡先の番号（SHA-256）を照合する。失敗したら nil
    func matchContacts(hashes: [String]) async -> [ContactMatch]? {
        var out: [ContactMatch] = []
        let chunks = stride(from: 0, to: min(hashes.count, 5000), by: 1000).map { Array(hashes[$0..<min($0 + 1000, hashes.count)]) }
        for chunk in chunks {
            guard let result = try? await callFunction("matchContacts", ["hashes": chunk]) else { return out.isEmpty ? nil : out }
            for m in result["matches"] as? [[String: Any]] ?? [] {
                guard let hash = m["hash"] as? String, let uid = m["uid"] as? String else { continue }
                out.append(ContactMatch(hash: hash, uid: uid, code: m["code"] as? String ?? "",
                                        name: m["name"] as? String ?? "", handle: m["handle"] as? String ?? ""))
            }
        }
        return out
    }
}
