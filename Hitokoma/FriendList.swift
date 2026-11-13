import SwiftUI

/// 友達を追加する画面：連絡先・QRコード・リンクやID。自分のコードも見せられる
struct AddFriendSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject private var cloud = CloudSync.shared
    @AppStorage("friendList") private var friendList: String = MyProfile.defaultFriends
    @State private var newFriend = ""
    @State private var showScanner = false
    @State private var showContacts = false
    @State private var message: String? = nil
    @State private var viewing: CodeTarget? = nil

    private var friends: [String] {
        friendList.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                Section(L("友達を追加")) {
                    Button {
                        showScanner = true
                    } label: {
                        Label(L("相手のQRコードを読み取る"), systemImage: "qrcode.viewfinder")
                    }
                    Text(L("友達追加は、相手のQRコードか、相手から受け取ったリンクからできます。"))
                        .font(.caption).foregroundStyle(.secondary)
                    if let message {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section(L("自分のコード（相手に見せる）")) {
                    VStack(spacing: 12) {
                        if let qr = FriendCode.qrImage(for: FriendCode.shareURL) {
                            Image(uiImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 180, height: 180)
                        }
                        Text(FriendCode.myID)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        ShareLink(item: FriendCode.shareURL) {
                            Label(L("リンクを送る（LINEなど）"), systemImage: "square.and.arrow.up")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }

                if cloud.isOn {
                    Section(L("いまの友達")) {
                        if cloud.friends.isEmpty {
                            Text(L("まだ友達がいません")).foregroundStyle(.secondary)
                        }
                        ForEach(cloud.friends) { friend in
                            Text(friend.name.isEmpty ? friend.code : friend.name)
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { cloud.friends[$0].uid }
                            Task { for id in ids { await cloud.removeFriend(uid: id) } }
                        }
                    }
                } else {
                Section(L("いまの友達（サンプルを含む）")) {
                    if friends.isEmpty {
                        Text(L("まだ友達がいません")).foregroundStyle(.secondary)
                    }
                    ForEach(friends, id: \.self) { name in
                        Text(name)
                    }
                    .onDelete(perform: removeFriends)
                }
                }
            }
            .navigationTitle(L("友達を追加"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("閉じる")) { isPresented = false }
                }
            }
            .sheet(isPresented: $showScanner) {
                QRScannerView { value in
                    showScanner = false
                    open(from: value, delay: 0.5)
                }
                .ignoresSafeArea()
            }
            .sheet(item: $viewing) { target in
                PersonProfileSheet(code: target.id, canAdd: true)
            }
        }
    }


    /// 読み取った（貼った）コードの人のプロフィールを開く。追加は、そこから行う
    private func open(from text: String, delay: Double = 0) {
        guard let id = FriendCode.parse(text) else {
            message = L("リンクかIDを読み取れませんでした")
            return
        }
        message = nil
        newFriend = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { viewing = CodeTarget(id: id) }
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

    var body: some View {
        NavigationStack {
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
                ToolbarItem(placement: .confirmationAction) { Button(L("閉じる")) { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.black)
        .preferredColorScheme(.dark)
        .task { await load() }
        .sheet(item: $chatFriend) { ChatView(friend: $0) }
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

    private func card(_ p: CloudProfile) -> some View {
        VStack(spacing: 10) {
            Circle()
                .fill(Hi.neon)
                .frame(width: 104, height: 104)
                .overlay(Text(String(p.name.prefix(1)))
                    .font(.system(size: 44, weight: .black, design: .rounded)).foregroundStyle(Hi.onNeon))
            Text(p.name).font(.title2.weight(.black))
            HStack(spacing: 6) {
                Text("@" + p.handle).font(.subheadline).foregroundStyle(Hi.dim)
                if let rank = p.rank.flatMap(Rank.init(rawValue:)) { RankBadge(rank: rank) }
            }
            if let streak = p.streak, streak > 0 {
                Label(LF("{n}日連続", ["n": "\(streak)"]), systemImage: "flame.fill")
                    .font(.caption.weight(.bold)).foregroundStyle(.orange)
            }
            Text(p.code).font(.system(.caption, design: .monospaced)).foregroundStyle(Hi.dim)

            Spacer(minLength: 16)
            if isMe {
                Text(L("これは自分のコードです")).font(.subheadline.weight(.bold)).foregroundStyle(Hi.dim)
            } else if isFriend(p) {
                Label(L("友達です"), systemImage: "checkmark.circle.fill")
                    .font(.headline.weight(.black)).foregroundStyle(Hi.neon)
                if cloud.isOn {
                    Button {
                        chatFriend = CloudFriend(uid: p.uid, name: p.name, code: p.code)
                    } label: {
                        Label(L("メッセージ"), systemImage: "bubble.left.and.bubble.right.fill")
                    }
                    .buttonStyle(NeonButtonStyle())
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
            phase = .found(try await cloud.lookup(code: code))
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

    var body: some View {
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
                ToolbarItem(placement: .confirmationAction) { Button(L("閉じる")) { dismiss() } }
            }
            .sheet(isPresented: $showAdd) { AddFriendSheet(isPresented: $showAdd) }
            .sheet(item: $viewing) { PersonProfileSheet(code: $0.id) }
            .sheet(item: $chat) { ChatView(friend: $0) }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }
}
