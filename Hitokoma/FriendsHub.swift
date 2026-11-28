import SwiftUI
import Contacts
import MessageUI

/// 連絡先の1人（端末の中だけで使う。サーバーには送らない）
struct LocalContact: Identifiable {
    let id: String
    let name: String
    let phone: String
    let thumbnail: Data?
}

/// 「友達追加・承認」に出す、連絡先の友達。
/// ・Difframe を使っている人（番号の SHA-256 で照合）→ そのまま友達申請
/// ・使っていない人 → メッセージで招待
@MainActor
final class ContactsDirectory: ObservableObject {
    static let shared = ContactsDirectory()

    enum State { case idle, needsAccess, denied, loading, ready }
    @Published var state: State = .idle
    @Published var onApp: [ContactFriend] = []
    @Published var invitable: [LocalContact] = []
    @Published var thumbnails: [String: Data] = [:]   // 使っている人の uid → 連絡先の写真
    @Published private(set) var hidden: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "contacts.hidden") ?? [])
    private var loadedAt: Date = .distantPast

    var verified: Bool { UserDefaults.standard.bool(forKey: Account.verifiedKey) }

    /// 「×」で、Difframe を使っている人の一覧から外す（この端末で覚える）
    func hide(_ uid: String) {
        hidden.insert(uid)
        UserDefaults.standard.set(Array(hidden), forKey: "contacts.hidden")
        onApp.removeAll { $0.uid == uid }
        ContactsMatcher.dismiss(uid)
    }

    /// 読み込む（10分以内なら読み直さない）
    func load(force: Bool = false) async {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .authorized || status.rawValue == 4 else {
            state = status == .notDetermined ? .needsAccess : .denied
            return
        }
        if !force, state == .ready, Date().timeIntervalSince(loadedAt) < 600 { return }
        if state != .ready { state = .loading }

        let contacts: [LocalContact] = await Task.detached(priority: .userInitiated) {
            let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey,
                        CNContactThumbnailImageDataKey] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.sortOrder = .userDefault
            var out: [LocalContact] = []
            try? CNContactStore().enumerateContacts(with: request) { c, _ in
                guard let phone = c.phoneNumbers.first?.value.stringValue else { return }
                let name = [c.familyName, c.givenName].filter { !$0.isEmpty }.joined(separator: " ")
                out.append(LocalContact(id: c.identifier, name: name.isEmpty ? phone : name, phone: phone, thumbnail: c.thumbnailImageData))
            }
            return out
        }.value

        // 使っている人を探す（電話番号を確認した人だけ）。名前は送らない
        let own = UserDefaults.standard.string(forKey: Account.phoneKey) ?? ""
        let cc = PhoneNumbers.defaultCallingCode(own: own)
        var byHash: [String: LocalContact] = [:]
        for c in contacts {
            if let e164 = PhoneNumbers.e164(c.phone, defaultCode: cc), e164 != own { byHash[PhoneNumbers.hash(e164)] = c }
        }
        var matchedContactIDs = Set<String>()
        var found: [ContactFriend] = []
        var thumbs: [String: Data] = [:]
        let cloud = CloudSync.shared
        if verified, cloud.isOn, !byHash.isEmpty, let result = await cloud.matchContacts(hashes: Array(byHash.keys)) {
            var seen = Set<String>()
            for m in result {
                guard let c = byHash[m.hash] else { continue }
                matchedContactIDs.insert(c.id)
                guard m.uid != cloud.uid, seen.insert(m.uid).inserted else { continue }
                found.append(ContactFriend(uid: m.uid, code: m.code, name: m.name, handle: m.handle, contactName: c.name))
                if let t = c.thumbnail { thumbs[m.uid] = t }
            }
            ContactsMatcher.remember(found)
        }
        onApp = found
            .filter { f in !hidden.contains(f.uid) && !cloud.friends.contains(where: { $0.uid == f.uid }) }
            .sorted { $0.contactName.localizedStandardCompare($1.contactName) == .orderedAscending }
        thumbnails = thumbs
        // 招待：使っていない人（写真のある人を先に）
        invitable = contacts.filter { !matchedContactIDs.contains($0.id) }
            .sorted { ($0.thumbnail != nil ? 0 : 1, $0.name) < ($1.thumbnail != nil ? 0 : 1, $1.name) }
        loadedAt = Date()
        state = .ready
    }

    func requestAccess() {
        CNContactStore().requestAccess(for: .contacts) { _, _ in
            Task { @MainActor in await self.load(force: true) }
        }
    }
}

/// 「友達追加・承認」タブの、リクエストの下に出す部分
struct FriendSuggestionsSection: View {
    @ObservedObject private var dir = ContactsDirectory.shared
    @ObservedObject private var cloud = CloudSync.shared
    @State private var onAppLimit = 5
    @State private var inviteLimit = 5
    @State private var inviting: LocalContact? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch dir.state {
            case .needsAccess:
                accessCard
            case .denied:
                note(L("連絡先が許可されていません。iPhoneの設定で許可すると、連絡先の友達が見つかります。"))
            case .idle, .loading:
                ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 20)
            case .ready:
                onAppSection
                inviteSection
            }
        }
        .task { await dir.load() }
        .sheet(item: $inviting) { contact in
            InviteComposer(contact: contact) { inviting = nil }
                .ignoresSafeArea()
        }
    }

    // MARK: Difframe を使っている連絡先

    @ViewBuilder private var onAppSection: some View {
        title(L("Difframe を使っている連絡先"), count: dir.onApp.count)
        if !dir.verified {
            note(L("電話番号を登録すると、連絡先の中で Difframe を使っている友達が見つかります。"))
        } else if dir.onApp.isEmpty {
            note(L("連絡先の中に、まだ Difframe を使っている人はいませんでした。下から招待できます。"))
        } else {
            VStack(spacing: 4) {
                ForEach(dir.onApp.prefix(onAppLimit)) { f in onAppRow(f) }
            }
            if dir.onApp.count > onAppLimit {
                moreButton { onAppLimit += 10 }
            }
        }
    }

    private func onAppRow(_ f: ContactFriend) -> some View {
        HStack(spacing: 12) {
            ContactAvatar(name: f.contactName, data: dir.thumbnails[f.uid], badge: false)
            VStack(alignment: .leading, spacing: 2) {
                Text(f.contactName).font(.body.weight(.black)).foregroundStyle(.white).lineLimit(1)
                Text(f.handle.isEmpty ? f.name : "@" + f.handle).font(.subheadline).foregroundStyle(Hi.dim).lineLimit(1)
            }
            Spacer(minLength: 8)
            if cloud.sentRequests.contains(f.uid) {
                pill(L("申請済み"), filled: false) {}
                    .disabled(true)
            } else {
                pill(L("追加"), filled: true) {
                    Task {
                        let profile = CloudProfile(uid: f.uid, code: f.code, name: f.name, handle: f.handle, rank: nil, streak: nil)
                        if (try? await cloud.sendRequest(to: profile)) != nil { ContactsMatcher.dismiss(f.uid) }
                    }
                }
            }
            Button { withAnimation { dir.hide(f.uid) } } label: {
                Image(systemName: "xmark").font(.body.weight(.bold)).foregroundStyle(Hi.dim).frame(width: 30, height: 44)
            }
            .accessibilityLabel(L("一覧から外す"))
        }
        .padding(.vertical, 6)
    }

    // MARK: 連絡先を招待

    @ViewBuilder private var inviteSection: some View {
        if !dir.invitable.isEmpty {
            title(L("連絡先を招待"), count: nil)
                .padding(.top, 10)
            VStack(spacing: 4) {
                ForEach(dir.invitable.prefix(inviteLimit)) { c in
                    HStack(spacing: 12) {
                        ContactAvatar(name: c.name, data: c.thumbnail, badge: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name).font(.body.weight(.black)).foregroundStyle(.white).lineLimit(1)
                            Text(L("まだ Difframe を使っていません")).font(.subheadline).foregroundStyle(Hi.dim).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        pill(L("招待"), filled: false) { inviting = c }
                    }
                    .padding(.vertical, 6)
                }
            }
            if dir.invitable.count > inviteLimit {
                moreButton { inviteLimit += 10 }
            }
        }
    }

    // MARK: 部品

    private var accessCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.fill").font(.system(size: 34)).foregroundStyle(Hi.neon)
            Text(L("連絡先から友達を探す")).font(.headline.weight(.black)).foregroundStyle(.white)
            Text(L("連絡先の中で Difframe を使っている人を見つけたり、まだの人を招待したりできます。連絡先の名前は送りません。"))
                .font(.footnote).foregroundStyle(Hi.dim).multilineTextAlignment(.center)
            Button(L("連絡先へのアクセスを許可")) { dir.requestAccess() }
                .buttonStyle(NeonButtonStyle())
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Hi.tile))
    }

    private func title(_ text: String, count: Int?) -> some View {
        HStack(spacing: 6) {
            Text(text).font(.footnote.weight(.black)).foregroundStyle(Hi.dim)
            if let count, count > 0 { Text("\(count)").font(.footnote.weight(.black)).foregroundStyle(Hi.neon) }
        }
        .padding(.top, 6)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(Hi.dim)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Hi.tile))
    }

    private func pill(_ text: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline.weight(.black))
                .padding(.horizontal, 18)
                .frame(height: 40)
                .background(Capsule().fill(filled ? Hi.neon : Color.white.opacity(0.12)))
                .foregroundStyle(filled ? Hi.onNeon : .white)
        }
        .buttonStyle(.plain)
    }

    private func moreButton(_ action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation { action() } }) {
            Text(L("もっと見る"))
                .font(.subheadline.weight(.black))
                .padding(.horizontal, 22)
                .frame(height: 44)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

/// 連絡先の写真（なければ頭文字）。招待の人には、メッセージの印をつける
struct ContactAvatar: View {
    let name: String
    let data: Data?
    var badge = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let data, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Circle().fill(Color.white.opacity(0.12))
                        .overlay(Text(String(name.prefix(1))).font(.title3.weight(.black)).foregroundStyle(.white))
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            if badge {
                Image(systemName: "message.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color(red: 0.2, green: 0.78, blue: 0.35)))
                    .overlay(Circle().stroke(Color.black, lineWidth: 2))
                    .offset(x: 2, y: 2)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 招待のメッセージ（宛先と文は入れておく。送るのは、本人がメッセージの画面で押す）
struct InviteComposer: UIViewControllerRepresentable {
    let contact: LocalContact
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> UIViewController {
        let text = L("Difframeで同じお題を撮ろう。このリンクから友達になれるよ。") + "\n" + FriendCode.shareURL.absoluteString
        if MFMessageComposeViewController.canSendText() {
            let vc = MFMessageComposeViewController()
            vc.recipients = [contact.phone]
            vc.body = text
            vc.messageComposeDelegate = context.coordinator
            return vc
        }
        // メッセージが使えない端末（シミュレーターなど）は、共有シート
        let share = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        share.completionWithItemsHandler = { _, _, _, _ in onDone() }
        return share
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            onDone()
        }
    }
}
