import Foundation
import UIKit
import Combine

// MARK: - サーバー（Firebase の REST API。SDK は使わない）
// ・ログイン：匿名ログイン（Identity Toolkit）
// ・データ：Firestore。写真も Firestore に入れる（Storage は使わない）
// ・端末の投稿（PostStore）が正。サーバーに送れなくても、投稿は消えない

/// サーバーにある、他の人（または自分）の投稿
struct CloudPost: Identifiable {
    let id: String            // "uid_2026-11-12-morning"
    let owner: String         // 投稿した人の uid
    let name: String
    let handle: String
    let code: String          // 投稿した人の友達コード（名前から、プロフィールを開くため）
    let dayKey: String
    let prompt: String
    let caption: String?
    let city: String?
    let toPublic: Bool
    let toFriends: Bool
    let commentsOff: Bool
    let postedAt: Date
    let elapsed: Double?
    let tzOffset: Int         // 投稿した場所の、世界標準時との差（秒）
    let photo: UIImage?
    let front: UIImage?

    /// 投稿した場所の、投稿したときの時刻（例：14:05）
    var localTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = TimeZone(secondsFromGMT: tzOffset)
        return f.string(from: postedAt)
    }
}

/// サーバーにあるコメント
struct CloudComment: Identifiable, Equatable {
    let id: String
    let uid: String
    let name: String
    let text: String
    let date: Date
    var replyTo: String? = nil      // 返信先のコメントの id
    var replyName: String? = nil    // 返信先の名前（返信の下に、引用として出す）
    var replyText: String? = nil    // 返信先の文
}

/// 友達コードから見つけた、その人のプロフィール（追加する前に見せる）
struct CloudProfile: Equatable {
    let uid: String
    let code: String
    let name: String
    let handle: String
    let rank: Int?
    let streak: Int?
}

/// サーバーでつながった友達
struct CloudFriend: Codable, Identifiable, Equatable, Hashable {
    let uid: String
    var name: String
    var code: String
    var id: String { uid }
}

enum CloudError: LocalizedError {
    case disabled, notFound, server(String)
    var errorDescription: String? {
        switch self {
        case .disabled: return "Cloud is off"
        case .notFound: return "Not found"
        case .server(let message): return message
        }
    }
}

@MainActor
final class CloudSync: ObservableObject {
    static let shared = CloudSync()

    @Published private(set) var uid: String? = UserDefaults.standard.string(forKey: "cloud.uid")
    @Published var friendPosts: [CloudPost] = []
    @Published var publicPosts: [CloudPost] = []
    @Published private(set) var comments: [String: [CloudComment]] = [:]
    @Published var friends: [CloudFriend] = CloudSync.loadFriends()
    @Published private(set) var lastError: String? = nil
    @Published private(set) var lastSync: Date? = nil
    @Published var avatars: [String: UIImage] = [:]                  // 相手のアイコン（DM・通知で使う）
    var avatarTried: Set<String> = []
    @Published var blocked: Set<String> = []                          // ブロックした人の uid（表示しない）
    @Published var myReadAt: [String: Date] = [:]                     // 自分が会話を読んだ時刻（未読数に使う）
    @Published var friendTypingAt: [String: Date] = [:]               // 友達が入力していた時刻
    @Published var friendReadAt: [String: Date] = [:]                // 友達が既読にした時刻（DM の既読）
    @Published var notices: [CloudNotice] = []                       // 通知（友達リクエストなど）
    @Published var messages: [String: [CloudMessage]] = [:]          // 友達ごとのメッセージ（キーは友達の uid）
    @Published var sentRequests: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "cloud.sent") ?? [])

    /// まだ見ていない通知の数
    /// 通知タブの未読（メッセージは DM 側で数える）
    var unreadCount: Int { notices.filter { !$0.read && $0.type != "message" && !NotifySettings.isMuted($0.type) }.count }
    /// DM の未読（会話ごと）
    var unreadMessages: Int { NotifySettings.isMuted("message") ? 0 : notices.filter { !$0.read && $0.type == "message" }.count }

    var isOn: Bool { CloudConfig.isEnabled }
    var isSignedIn: Bool { isOn && uid != nil }

    private var idToken: String?
    private var tokenExpiry = Date.distantPast
    private var refreshToken: String? = UserDefaults.standard.string(forKey: "cloud.refresh")
    private var signingIn: Task<Void, Error>?

    private var base: String {
        "https://firestore.googleapis.com/v1/projects/\(CloudConfig.projectID)/databases/(default)/documents"
    }

    /// 自分の投稿の、サーバーでの名前
    func cloudID(for recordID: String) -> String? {
        guard isOn, let uid else { return nil }
        return "\(uid)_\(recordID)"
    }

    // MARK: ログイン

    /// 匿名でログインする（初回だけ、アカウントを作る）
    func ensureSignedIn() async throws {
        guard isOn else { throw CloudError.disabled }
        if idToken != nil, Date() < tokenExpiry { return }
        if let running = signingIn { return try await running.value }
        let task = Task { @MainActor in
            defer { signingIn = nil }
            if let refreshToken {
                do { try await refresh(refreshToken); return } catch { /* 作り直す */ }
            }
            try await signUp()
        }
        signingIn = task
        try await task.value
    }

    private func signUp() async throws {
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=\(CloudConfig.apiKey)")!
        let json = try await send("POST", url: url, json: ["returnSecureToken": true], auth: false)
        guard let token = json["idToken"] as? String, let refresh = json["refreshToken"] as? String,
              let uid = json["localId"] as? String else { throw CloudError.server("sign-up failed") }
        store(token: token, refresh: refresh, uid: uid, expiresIn: json["expiresIn"])
    }

    private func refresh(_ token: String) async throws {
        let url = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(CloudConfig.apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=refresh_token&refresh_token=\(token)".data(using: .utf8)
        let json = try await perform(request)
        guard let id = json["id_token"] as? String, let refresh = json["refresh_token"] as? String,
              let uid = json["user_id"] as? String else { throw CloudError.server("refresh failed") }
        store(token: id, refresh: refresh, uid: uid, expiresIn: json["expires_in"])
    }

    private func store(token: String, refresh: String, uid: String, expiresIn: Any?) {
        idToken = token
        refreshToken = refresh
        let seconds = Double("\(expiresIn ?? "3600")") ?? 3600
        tokenExpiry = Date().addingTimeInterval(seconds - 120)
        if self.uid != uid { self.uid = uid }
        UserDefaults.standard.set(uid, forKey: "cloud.uid")
        UserDefaults.standard.set(refresh, forKey: "cloud.refresh")
    }

    // MARK: 自分の名前と友達コード

    var myName: String {
        let name = UserDefaults.standard.string(forKey: "myName") ?? ""
        return (name.isEmpty || name == "あなた") ? MyProfile.handle(myHandle) : name
    }
    var myHandle: String { UserDefaults.standard.string(forKey: "myHandle") ?? "" }

    /// 友達コード → 自分、の対応をサーバーに置く（相手がコードで自分を見つけられるように）
    private func publishProfile() async throws {
        guard let uid else { return }
        let store = PostStore.shared
        let month = MonthlyPoints(records: store.records, month: MonthlyPoints.monthKey(for: Date()))
        try await patch("codes/\(FriendCode.myID)", fields: [
            "uid": .string(uid), "name": .string(myName), "handle": .string(MyProfile.handle(myHandle)),
            "rank": .int(month.rank.rawValue), "streak": .int(store.currentStreak()),
        ])
    }

    /// 自分のアイコンを、相手にも見せられるように置く（変わったときだけ送る）
    func publishAvatar() async {
        guard let uid, let image = Avatar.load() else { return }
        let data = image.scaled(maxSide: 256).jpegData(compressionQuality: 0.7) ?? Data()
        let stamp = "\(data.count):\(data.suffix(16).base64EncodedString())"
        guard UserDefaults.standard.string(forKey: "cloud.avatarStamp") != stamp else { return }
        do {
            try await ensureSignedIn()
            try await patch("profiles/\(uid)", fields: ["avatar": .bytes(data), "name": .string(myName)], mask: ["avatar", "name"])
            UserDefaults.standard.set(stamp, forKey: "cloud.avatarStamp")
        } catch {
            report(error)
        }
    }

    /// 相手のアイコンを読む（一度だけ。アイコンがない人は、名前の頭文字で出す）
    func loadAvatar(_ otherUID: String) async {
        guard let uid, otherUID != uid, avatars[otherUID] == nil, !avatarTried.contains(otherUID) else { return }
        avatarTried.insert(otherUID)
        do {
            try await ensureSignedIn()
            let json = try await get("profiles/\(otherUID)")
            if let f = json["fields"] as? [String: Any], let data = FS.bytes(f, "avatar"), let image = UIImage(data: data) {
                avatars[otherUID] = image
            }
        } catch {}
    }

    /// 友達コードから、その人のプロフィールを読む（見つからなければ notFound）
    func lookup(code: String) async throws -> CloudProfile {
        try await ensureSignedIn()
        let doc = try await get("codes/\(code)")
        let f = doc["fields"] as? [String: Any] ?? [:]
        guard let uid = FS.string(f, "uid") else { throw CloudError.notFound }
        return CloudProfile(uid: uid, code: code, name: FS.string(f, "name") ?? code,
                            handle: FS.string(f, "handle") ?? code,
                            rank: FS.double(f, "rank").map(Int.init), streak: FS.double(f, "streak").map(Int.init))
    }

    // MARK: 友達

    /// 友達コードで友達になる（相手の一覧にも、自分が入る）
    func addFriend(code: String) async throws -> CloudFriend {
        try await ensureSignedIn()
        guard let uid else { throw CloudError.disabled }
        let doc = try await get("codes/\(code)")
        let fields = doc["fields"] as? [String: Any] ?? [:]
        guard let friendUID = FS.string(fields, "uid") else { throw CloudError.notFound }
        let friend = CloudFriend(uid: friendUID, name: FS.string(fields, "name") ?? code, code: code)
        try await patch("friends/\(uid)/list/\(friendUID)", fields: [
            "uid": .string(friendUID), "name": .string(friend.name), "code": .string(code),
        ])
        try await patch("friends/\(friendUID)/list/\(uid)", fields: [
            "uid": .string(uid), "name": .string(myName), "code": .string(FriendCode.myID),
        ])
        if !friends.contains(where: { $0.uid == friendUID }) { friends.append(friend) }
        saveFriends()
        await updateAudience()
        return friend
    }

    func removeFriend(uid friendUID: String) async {
        friends.removeAll { $0.uid == friendUID }
        saveFriends()
        guard let uid else { return }
        try? await delete("friends/\(uid)/list/\(friendUID)")
        try? await delete("friends/\(friendUID)/list/\(uid)")
        await updateAudience()
    }

    /// サーバーの友達一覧を読む（相手が自分を追加したときも、ここで増える）
    private func loadFriendList() async throws {
        guard let uid else { return }
        let json = try await send("GET", url: URL(string: "\(base)/friends/\(uid)/list?pageSize=300")!, json: nil)
        let docs = json["documents"] as? [[String: Any]] ?? []
        let list = docs.compactMap { doc -> CloudFriend? in
            let f = doc["fields"] as? [String: Any] ?? [:]
            guard let id = FS.string(f, "uid") else { return nil }
            return CloudFriend(uid: id, name: FS.string(f, "name") ?? "", code: FS.string(f, "code") ?? "")
        }
        let changed = Set(list.map(\.uid)) != Set(friends.map(\.uid))
        friends = list
        saveFriends()
        if changed { await updateAudience() }
    }

    var audience: [FS] {
        ([uid].compactMap { $0 } + friends.map(\.uid)).map { .string($0) }
    }

    // MARK: 自分の投稿を送る

    /// 端末の投稿を、サーバーに送る（同じ投稿なら上書き）。投稿がなければ、サーバーからも消す
    func upload(recordID: String) {
        guard isOn else { return }
        Task { @MainActor in
            do {
                try await ensureSignedIn()
                let store = PostStore.shared
                guard let record = store.records.first(where: { $0.id == recordID }),
                      let file = record.postedPhotoFile, let photo = store.image(for: file),
                      let id = cloudID(for: recordID) else {
                    if let id = cloudID(for: recordID) { try? await delete("posts/\(id)") }
                    return
                }
                let firstTime = !isUploaded(record)   // 最初に送るときだけ、友達に知らせる（編集では知らせない）
                let front = record.frontPhotoFile.flatMap { store.image(for: $0) }
                let (main, small) = Self.encode(photo, front)
                var fields: [String: FS] = [
                    "owner": .string(uid ?? ""), "name": .string(myName), "handle": .string(MyProfile.handle(myHandle)),
                    "code": .string(FriendCode.myID),
                    "dayKey": .string(record.dayKey), "prompt": .string(record.prompt),
                    "toPublic": .bool(record.isForPublic), "toFriends": .bool(record.isForFriends),
                    "commentsOff": .bool(record.publicCommentsOff == true),
                    "postedAt": .timestamp(record.postedAt ?? Date()),
                    "tzOffset": .int(TimeZone.current.secondsFromGMT()),
                    "verified": .bool(record.verified == true),
                    "audience": .array(record.isForFriends ? audience : [.string(uid ?? "")]),
                    "photo": .bytes(main),
                ]
                if let small { fields["front"] = .bytes(small) }
                if let caption = record.caption { fields["caption"] = .string(caption) }
                if let city = record.city { fields["city"] = .string(city) }
                if let elapsed = record.elapsed { fields["elapsed"] = .double(elapsed) }
                try await patch("posts/\(id)", fields: fields)
                markUploaded(record)
                if firstTime && record.isForFriends {
                    for friend in friends {
                        await notify(to: friend.uid, id: "post_\(id)", type: "friendPost", text: record.prompt)
                    }
                }
                lastError = nil
                await refresh(force: true)
            } catch {
                report(error)
            }
        }
    }

    /// 友達が変わったら、今日の自分の投稿を見られる人も変える
    func updateAudience() async {
        let store = PostStore.shared
        for record in store.records(day: store.activeDayKey()) where record.postedPhotoFile != nil && record.isForFriends {
            guard let id = cloudID(for: record.id) else { continue }
            try? await patch("posts/\(id)", fields: ["audience": .array(audience)], mask: ["audience"])
        }
    }

    /// 写真を小さくする（Firestore の1件は 1MB まで。2枚あわせて 700KB 以下に）
    private static func encode(_ main: UIImage, _ front: UIImage?) -> (Data, Data?) {
        var side: CGFloat = 1280
        var quality: CGFloat = 0.62
        while true {
            let a = main.scaled(maxSide: side).jpegData(compressionQuality: quality) ?? Data()
            let b = front.map { $0.scaled(maxSide: side * 0.45).jpegData(compressionQuality: quality) ?? Data() }
            if a.count + (b?.count ?? 0) < 700_000 || side < 500 { return (a, b) }
            side *= 0.85
            quality = max(0.4, quality - 0.06)
        }
    }

    /// 送った投稿（投稿した時刻で、送り直しが要るかを見分ける）
    private func uploadKey(_ record: PromptRecord) -> String {
        "\(uid ?? "")_\(record.id)_\(record.postedAt?.timeIntervalSince1970 ?? 0)"
    }
    private func isUploaded(_ record: PromptRecord) -> Bool {
        (UserDefaults.standard.stringArray(forKey: "cloud.uploaded") ?? []).contains(uploadKey(record))
    }
    private func markUploaded(_ record: PromptRecord) {
        var list = UserDefaults.standard.stringArray(forKey: "cloud.uploaded") ?? []
        list.append(uploadKey(record))
        UserDefaults.standard.set(Array(list.suffix(200)), forKey: "cloud.uploaded")
    }

    // MARK: 投稿を読む

    /// 友達の投稿と、みんなの投稿を読み直す
    func refresh(force: Bool = false) async {
        guard isOn else { return }
        // 画面を切り替えるたびに読み直さない（8秒以内なら、そのまま）
        if !force, let lastSync, Date().timeIntervalSince(lastSync) < 8 { return }
        do {
            try await ensureSignedIn()
            try await publishProfile()
            await publishAvatar()
            try await loadFriendList()
            await loadBlocks()
            await loadInbox()
            let day = PostStore.shared.activeDayKey()
            guard let uid else { return }
            // まだ送れていない今日の投稿（つながる前に投稿したもの）を送る
            for record in PostStore.shared.records(day: day)
            where record.postedPhotoFile != nil && !isUploaded(record) {
                upload(recordID: record.id)
            }
            async let friendDocs = query([
                FS.filter("audience", "ARRAY_CONTAINS", .string(uid)),
                FS.filter("dayKey", "EQUAL", .string(day)),
            ])
            async let publicDocs = query([
                FS.filter("toPublic", "EQUAL", .bool(true)),
                FS.filter("dayKey", "EQUAL", .string(day)),
            ])
            let (f, p) = try await (friendDocs, publicDocs)
            friendPosts = f.filter { $0.owner != uid && $0.toFriends && !blocked.contains($0.owner) }.sorted { $0.postedAt > $1.postedAt }
            publicPosts = p.filter { $0.owner != uid && !blocked.contains($0.owner) }.sorted { $0.postedAt > $1.postedAt }
            lastSync = Date()
            lastError = nil
        } catch {
            report(error)
        }
    }

    private func query(_ filters: [[String: Any]]) async throws -> [CloudPost] {
        let body: [String: Any] = ["structuredQuery": [
            "from": [["collectionId": "posts"]],
            "where": ["compositeFilter": ["op": "AND", "filters": filters]],
            "limit": 40,
        ]]
        let url = URL(string: "\(base):runQuery")!
        let rows = try await sendArray("POST", url: url, json: body)
        return rows.compactMap { row in
            guard let doc = row["document"] as? [String: Any] else { return nil }
            return Self.post(from: doc)
        }
    }

    private static func post(from doc: [String: Any]) -> CloudPost? {
        guard let name = doc["name"] as? String, let f = doc["fields"] as? [String: Any],
              let owner = FS.string(f, "owner") else { return nil }
        return CloudPost(
            id: String(name.split(separator: "/").last ?? ""),
            owner: owner,
            name: FS.string(f, "name") ?? "",
            handle: FS.string(f, "handle") ?? "",
            code: FS.string(f, "code") ?? "",
            dayKey: FS.string(f, "dayKey") ?? "",
            prompt: FS.string(f, "prompt") ?? "",
            caption: FS.string(f, "caption"),
            city: FS.string(f, "city"),
            toPublic: FS.bool(f, "toPublic") ?? false,
            toFriends: FS.bool(f, "toFriends") ?? true,
            commentsOff: FS.bool(f, "commentsOff") ?? false,
            postedAt: FS.date(f, "postedAt") ?? Date(),
            elapsed: FS.double(f, "elapsed"),
            tzOffset: Int(FS.double(f, "tzOffset") ?? 0),
            photo: FS.bytes(f, "photo").flatMap(UIImage.init(data:)),
            front: FS.bytes(f, "front").flatMap(UIImage.init(data:)))
    }

    // MARK: コメント

    func loadComments(postID: String) async {
        guard isOn else { return }
        do {
            try await ensureSignedIn()
            let url = URL(string: "\(base)/posts/\(postID)/comments?pageSize=200")!
            let json = try await send("GET", url: url, json: nil)
            let docs = json["documents"] as? [[String: Any]] ?? []
            comments[postID] = docs.compactMap { doc in
                guard let name = doc["name"] as? String, let f = doc["fields"] as? [String: Any],
                      let text = FS.string(f, "text") else { return nil }
                return CloudComment(id: String(name.split(separator: "/").last ?? ""), uid: FS.string(f, "uid") ?? "",
                                    name: FS.string(f, "name") ?? "", text: text, date: FS.date(f, "date") ?? Date(),
                                    replyTo: FS.string(f, "replyTo"), replyName: FS.string(f, "replyName"),
                                    replyText: FS.string(f, "replyText"))
            }.sorted { $0.date < $1.date }
        } catch {
            report(error)
        }
    }

    func addComment(postID: String, text: String, replyTo target: CloudComment? = nil) async {
        guard let uid else { return }
        let comment = CloudComment(id: UUID().uuidString, uid: uid, name: myName, text: text, date: Date(),
                                   replyTo: target?.id, replyName: target?.name, replyText: target?.text)
        comments[postID, default: []].append(comment)   // 先に画面に出す
        var fields: [String: FS] = [
            "uid": .string(uid), "name": .string(comment.name), "text": .string(text), "date": .timestamp(comment.date),
        ]
        if let target {
            fields["replyTo"] = .string(target.id)
            fields["replyName"] = .string(target.name)
            fields["replyText"] = .string(String(target.text.prefix(120)))
        }
        do {
            try await ensureSignedIn()
            try await patch("posts/\(postID)/comments/\(comment.id)", fields: fields)
            // 投稿した人に知らせる（自分の投稿へのコメントは、知らせない）
            if let owner = postID.split(separator: "_").first.map(String.init), owner != uid {
                await notify(to: owner, id: "comment_\(comment.id)", type: "comment", text: text, postID: postID)
            }
        } catch {
            comments[postID]?.removeAll { $0.id == comment.id }
            report(error)
        }
    }

    func deleteComment(postID: String, commentID: String) async {
        comments[postID]?.removeAll { $0.id == commentID }
        try? await delete("posts/\(postID)/comments/\(commentID)")
    }

    // MARK: 通信の下まわり

    func get(_ path: String) async throws -> [String: Any] {
        try await send("GET", url: URL(string: "\(base)/\(path)")!, json: nil)
    }

    func patch(_ path: String, fields: [String: FS], mask: [String]? = nil) async throws {
        var text = "\(base)/\(path)"
        if let mask { text += "?" + mask.map { "updateMask.fieldPaths=\($0)" }.joined(separator: "&") }
        _ = try await send("PATCH", url: URL(string: text)!, json: ["fields": fields.mapValues(\.json)])
    }

    func delete(_ path: String) async throws {
        _ = try await send("DELETE", url: URL(string: "\(base)/\(path)")!, json: nil)
    }

    func send(_ method: String, url: URL, json: Any?, auth: Bool = true) async throws -> [String: Any] {
        let any = try await sendAny(method, url: url, json: json, auth: auth)
        return any as? [String: Any] ?? [:]
    }

    func sendArray(_ method: String, url: URL, json: Any?) async throws -> [[String: Any]] {
        let any = try await sendAny(method, url: url, json: json, auth: true)
        return any as? [[String: Any]] ?? []
    }

    private func sendAny(_ method: String, url: URL, json: Any?, auth: Bool) async throws -> Any {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        if auth, let idToken { request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if auth, status == 401 {   // 期限切れ：入り直して、1回だけやり直す
            tokenExpiry = .distantPast
            idToken = nil
            try await ensureSignedIn()
            if let idToken { request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization") }
            let (retry, again) = try await URLSession.shared.data(for: request)
            return try Self.parse(retry, status: (again as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try Self.parse(data, status: status)
    }

    private func perform(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        return try Self.parse(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0) as? [String: Any] ?? [:]
    }

    private static func parse(_ data: Data, status: Int) throws -> Any {
        let json = data.isEmpty ? [String: Any]() : (try? JSONSerialization.jsonObject(with: data)) ?? [String: Any]()
        if status == 404 { throw CloudError.notFound }
        guard (200..<300).contains(status) else {
            let error = (json as? [String: Any])?["error"] as? [String: Any]
            let message = error?["message"] as? String ?? String(data: data, encoding: .utf8) ?? "HTTP \(status)"
            throw CloudError.server("HTTP \(status): \(message)")
        }
        // runQuery はエラーを配列の中に入れて返すことがある
        if let rows = json as? [[String: Any]], let error = rows.first?["error"] as? [String: Any] {
            throw CloudError.server(error["message"] as? String ?? "query failed")
        }
        return json
    }

    func report(_ error: Error) {
        let text = error.localizedDescription
        lastError = text
        print("☁️ Cloud error:", text)   // 索引（index）が要るときは、作るためのリンクがここに出る
    }

    // MARK: 端末に覚えておく友達

    private static func loadFriends() -> [CloudFriend] {
        guard let data = UserDefaults.standard.data(forKey: "cloud.friends"),
              let list = try? JSONDecoder().decode([CloudFriend].self, from: data) else { return [] }
        return list
    }

    func saveFriends() {
        if let data = try? JSONEncoder().encode(friends) { UserDefaults.standard.set(data, forKey: "cloud.friends") }
    }
}

// MARK: - Firestore の値

enum FS {
    case string(String), bool(Bool), int(Int), double(Double), timestamp(Date), bytes(Data), array([FS]), map([String: FS])

    var json: [String: Any] {
        switch self {
        case .string(let v): return ["stringValue": v]
        case .bool(let v): return ["booleanValue": v]
        case .int(let v): return ["integerValue": String(v)]
        case .double(let v): return ["doubleValue": v]
        case .timestamp(let v): return ["timestampValue": FS.iso.string(from: v)]
        case .bytes(let v): return ["bytesValue": v.base64EncodedString()]
        case .map(let v):
            var fields: [String: Any] = [:]
            for (k, x) in v { fields[k] = x.json }
            return ["mapValue": ["fields": fields]]
        case .array(let v):
            var inner: [String: Any] = [:]
            if !v.isEmpty { inner["values"] = v.map { $0.json } }
            return ["arrayValue": inner]
        }
    }

    static func filter(_ field: String, _ op: String, _ value: FS) -> [String: Any] {
        ["fieldFilter": ["field": ["fieldPath": field], "op": op, "value": value.json]]
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    private static func value(_ fields: [String: Any], _ key: String) -> [String: Any]? { fields[key] as? [String: Any] }

    static func string(_ f: [String: Any], _ key: String) -> String? { value(f, key)?["stringValue"] as? String }
    static func bool(_ f: [String: Any], _ key: String) -> Bool? { value(f, key)?["booleanValue"] as? Bool }
    static func double(_ f: [String: Any], _ key: String) -> Double? {
        guard let v = value(f, key) else { return nil }
        if let d = v["doubleValue"] as? Double { return d }
        if let i = v["integerValue"] as? String { return Double(i) }
        return nil
    }
    /// 文字の入った map（リアクションの一覧など）。空の値は除く
    static func strings(_ f: [String: Any], _ key: String) -> [String: String] {
        guard let m = value(f, key)?["mapValue"] as? [String: Any],
              let fields = m["fields"] as? [String: [String: Any]] else { return [:] }
        var out: [String: String] = [:]
        for (k, v) in fields {
            if let text = v["stringValue"] as? String, !text.isEmpty { out[k] = text }
        }
        return out
    }
    static func bytes(_ f: [String: Any], _ key: String) -> Data? {
        (value(f, key)?["bytesValue"] as? String).flatMap { Data(base64Encoded: $0) }
    }
    static func date(_ f: [String: Any], _ key: String) -> Date? {
        guard let text = value(f, key)?["timestampValue"] as? String else { return nil }
        if let d = iso.date(from: text) { return d }
        // 小数点以下が6桁のときなど：小数点以下を落として読む
        let plain = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return isoPlain.date(from: plain)
    }
}

extension UIImage {
    /// 長い辺を maxSide にした画像（もとより大きくはしない）
    func scaled(maxSide: CGFloat) -> UIImage {
        let long = max(size.width, size.height)
        guard long > maxSide else { return self }
        let ratio = maxSide / long
        let target = CGSize(width: (size.width * ratio).rounded(), height: (size.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}
