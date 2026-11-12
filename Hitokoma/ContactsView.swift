import SwiftUI
import Contacts

/// 連絡先から友達を招待する画面。
/// 連絡先はこの画面を開いている間だけメモリに読み込み、保存も送信もしない。
/// 「すでに使っている友達」を探すにはサーバーが必要なので、いまは招待リンクを送る形。
struct ContactsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private struct Person: Identifiable {
        let id: String
        let name: String
        let phone: String
    }

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
            .navigationTitle(L("連絡先から招待"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("閉じる")) { dismiss() }
                }
            }
        }
        .task {
            if hasAccess { await load() }
        }
    }

    // 許可を聞く前の説明
    private var ask: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 56))
            Text(L("連絡先から友達を招待"))
                .font(.title3.weight(.black))
            Text(L("連絡先を読み取り、招待リンクを送る相手を選べるようにします。連絡先はこの端末の外へ送りません。保存もしません。"))
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
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill").foregroundStyle(.secondary)
                    Text(L("デモ版では、Difframeをすでに使っている友達の自動表示はできません（サーバーが必要です）。招待リンクを送ってください。"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
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
                guard let number = contact.phoneNumbers.first?.value.stringValue else { return }
                let name = [contact.familyName, contact.givenName].filter { !$0.isEmpty }.joined(separator: " ")
                out.append(Person(id: contact.identifier, name: name.isEmpty ? number : name, phone: number))
            }
            return out
        }.value
        people = result
        loading = false
    }
}
