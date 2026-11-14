import Foundation
import UIKit

// MARK: - 通知（友達リクエストなど）と、友達とのメッセージ（DM）
// 通知は、アプリを開いたとき・画面を引っぱったときに、サーバーから読む（iPhone の通知で自動では届かない）

/// 通知1件。type は friendRequest / friendAccepted / comment / message
struct CloudNotice: Identifiable, Equatable {
    let id: String
    let type: String
    let fromUID: String
    let fromName: String
    let fromCode: String
    let text: String
    let postID: String?
    let date: Date
    let read: Bool
}

/// DM の1件：文字・写真・ボイスのどれか。絵文字のリアクションは、相手と自分の分が入る
struct CloudMessage: Identifiable {
    let id: String
    let from: String
    let kind: String          // text / photo / voice
    let text: String
    let date: Date
    var photo: UIImage? = nil
    var front: UIImage? = nil     // 両方撮りのとき、内カメラの写真（小さい枠）
    var voice: Data? = nil
    var duration: Double = 0
    var reactions: [String: String] = [:]   // 送った人の uid → 絵文字
    var prompt: String? = nil               // 投稿を送ったときのお題
    var caption: String? = nil              // 投稿を送ったときの一言
    var sharedFrom: String? = nil           // 投稿を送った人の名前（投稿の共有のとき）
}

extension CloudSync {
    // MARK: 通知

    /// 相手の通知箱に1件入れる（失敗しても、投稿やコメント自体は止めない）
    func notify(to target: String, id: String, type: String, text: String = "", postID: String? = nil) async {
        guard let uid else { return }
        var fields: [String: FS] = [
            "type": .string(type), "fromUID": .string(uid), "fromName": .string(myName),
            "fromCode": .string(FriendCode.myID), "text": .string(String(text.prefix(120))),
            "date": .timestamp(Date()), "read": .bool(false),
        ]
        if let postID { fields["postID"] = .string(postID) }
        do { try await patch("notifications/\(target)/items/\(id)", fields: fields) } catch { report(error) }
    }

    /// リアクションをつけたら、投稿した人に知らせる（1人1投稿につき1件。外したら消す）
    func notifyReaction(postID: String, emoji: String) {
        guard let uid, postID.contains("_"), let owner = postID.split(separator: "_").first.map(String.init),
              owner != uid, PostStore.shared.reactions[postID] == emoji else { return }
        Task { await notify(to: owner, id: "react_\(uid)_\(postID)", type: "like", text: emoji, postID: postID) }
    }

    /// 自分の通知を読む
    func loadInbox() async {
        guard let uid else { return }
        do {
            let json = try await send("GET", url: URL(string: "https://firestore.googleapis.com/v1/projects/\(CloudConfig.projectID)/databases/(default)/documents/notifications/\(uid)/items?pageSize=100")!, json: nil)
            let docs = json["documents"] as? [[String: Any]] ?? []
            notices = docs.compactMap { doc -> CloudNotice? in
                guard let name = doc["name"] as? String, let f = doc["fields"] as? [String: Any],
                      let type = FS.string(f, "type") else { return nil }
                return CloudNotice(id: String(name.split(separator: "/").last ?? ""), type: type,
                                   fromUID: FS.string(f, "fromUID") ?? "", fromName: FS.string(f, "fromName") ?? "",
                                   fromCode: FS.string(f, "fromCode") ?? "", text: FS.string(f, "text") ?? "",
                                   postID: FS.string(f, "postID"), date: FS.date(f, "date") ?? Date(),
                                   read: FS.bool(f, "read") ?? false)
            }.sorted { $0.date > $1.date }.filter { !blocked.contains($0.fromUID) }
            // 友達になれたリクエストは、送信済みの印を外す
            let friendIDs = Set(friends.map(\.uid))
            if !sentRequests.isDisjoint(with: friendIDs) {
                sentRequests.subtract(friendIDs)
                saveSent()
            }
        } catch {
            report(error)
        }
    }

    /// 見た通知を、既読にする
    func markAllRead() async {
        guard let uid else { return }
        let unread = notices.filter { !$0.read && $0.type != "message" }
        guard !unread.isEmpty else { return }
        notices = notices.map { n in
            n.type == "message" ? n :
            CloudNotice(id: n.id, type: n.type, fromUID: n.fromUID, fromName: n.fromName, fromCode: n.fromCode,
                        text: n.text, postID: n.postID, date: n.date, read: true)
        }
        for n in unread {
            try? await patch("notifications/\(uid)/items/\(n.id)", fields: ["read": .bool(true)], mask: ["read"])
        }
    }

    // MARK: 友達リクエスト

    private func saveSent() {
        UserDefaults.standard.set(Array(sentRequests), forKey: "cloud.sent")
    }

    /// 友達リクエストを送る（相手が承認すると、友達になる）
    func sendRequest(to profile: CloudProfile) async throws {
        try await ensureSignedIn()
        guard let uid else { throw CloudError.disabled }
        let fields: [String: FS] = [
            "type": .string("friendRequest"), "fromUID": .string(uid), "fromName": .string(myName),
            "fromCode": .string(FriendCode.myID), "text": .string(""),
            "date": .timestamp(Date()), "read": .bool(false),
        ]
        try await patch("notifications/\(profile.uid)/items/request_\(uid)", fields: fields)
        sentRequests.insert(profile.uid)
        saveSent()
    }

    /// 来ているリクエストを承認する（お互いの友達一覧に入れる）
    func accept(_ notice: CloudNotice) async throws {
        try await ensureSignedIn()
        guard let uid else { throw CloudError.disabled }
        let other = notice.fromUID
        // 先に自分の一覧、次に相手の一覧（相手の一覧に書けるのは、リクエストが残っているあいだだけ）
        try await patch("friends/\(uid)/list/\(other)", fields: [
            "uid": .string(other), "name": .string(notice.fromName), "code": .string(notice.fromCode),
        ])
        try await patch("friends/\(other)/list/\(uid)", fields: [
            "uid": .string(uid), "name": .string(myName), "code": .string(FriendCode.myID),
        ])
        try await delete("notifications/\(uid)/items/\(notice.id)")
        notices.removeAll { $0.id == notice.id }
        if !friends.contains(where: { $0.uid == other }) {
            friends.append(CloudFriend(uid: other, name: notice.fromName, code: notice.fromCode))
            saveFriends()
        }
        await notify(to: other, id: "accepted_\(uid)", type: "friendAccepted")
        await updateAudience()
    }

    /// リクエストを断る（通知を消すだけ。相手には知らせない）
    func decline(_ notice: CloudNotice) async {
        guard let uid else { return }
        notices.removeAll { $0.id == notice.id }
        try? await delete("notifications/\(uid)/items/\(notice.id)")
    }

    // MARK: メッセージ（友達とだけ）

    /// 2人の会話の名前（2人の uid を並べたもの）
    func chatID(with friendUID: String) -> String? {
        guard let uid else { return nil }
        return [uid, friendUID].sorted().joined(separator: "_")
    }

    private func chatPath(with friendUID: String) -> String? {
        chatID(with: friendUID).map { "chats/\($0)/messages" }
    }

    func loadMessages(with friendUID: String) async {
        guard let path = chatPath(with: friendUID) else { return }
        do {
            try await ensureSignedIn()
            let json = try await send("GET", url: URL(string: "https://firestore.googleapis.com/v1/projects/\(CloudConfig.projectID)/databases/(default)/documents/\(path)?pageSize=300")!, json: nil)
            let docs = json["documents"] as? [[String: Any]] ?? []
            let list = docs.compactMap { doc -> CloudMessage? in
                guard let name = doc["name"] as? String, let f = doc["fields"] as? [String: Any] else { return nil }
                let kind = FS.string(f, "kind") ?? "text"
                return CloudMessage(id: String(name.split(separator: "/").last ?? ""),
                                    from: FS.string(f, "from") ?? "", kind: kind,
                                    text: FS.string(f, "text") ?? "", date: FS.date(f, "date") ?? Date(),
                                    photo: kind == "photo" ? FS.bytes(f, "photo").flatMap(UIImage.init(data:)) : nil,
                                    front: kind == "photo" ? FS.bytes(f, "front").flatMap(UIImage.init(data:)) : nil,
                                    voice: kind == "voice" ? FS.bytes(f, "voice") : nil,
                                    duration: FS.double(f, "duration") ?? 0,
                                    reactions: FS.strings(f, "reactions"),
                                    prompt: FS.string(f, "prompt"), caption: FS.string(f, "caption"),
                                    sharedFrom: FS.string(f, "sharedFrom"))
            }.sorted { $0.date < $1.date }
            messages[friendUID] = list
        } catch {
            report(error)
        }
    }

    /// 書き込みの共通部分（文字・写真・ボイス）
    private func write(_ friendUID: String, id: String, date: Date, extra: [String: FS]) async throws {
        guard let uid, let path = chatPath(with: friendUID) else { throw CloudError.disabled }
        var fields: [String: FS] = ["from": .string(uid), "date": .timestamp(date)]
        for (k, v) in extra { fields[k] = v }
        try await ensureSignedIn()
        try await patch("\(path)/\(id)", fields: fields)
    }

    func sendMessage(to friendUID: String, text: String) async {
        guard let uid else { return }
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
        guard !trimmed.isEmpty else { return }
        let id = UUID().uuidString, date = Date()
        messages[friendUID, default: []].append(CloudMessage(id: id, from: uid, kind: "text", text: trimmed, date: date))
        do {
            try await write(friendUID, id: id, date: date, extra: ["kind": .string("text"), "text": .string(trimmed)])
            await notify(to: friendUID, id: "msg_\(uid)", type: "message", text: trimmed)
        } catch {
            messages[friendUID]?.removeAll { $0.id == id }
            report(error)
        }
    }

    /// 友達の投稿を、DM に送る（写真・お題・一言・誰の投稿かを一緒に）
    func sharePost(to friendUID: String, post: CloudPost) async throws {
        guard let photo = post.photo, let uid else { throw CloudError.server("no photo") }
        let data = ChatPhoto.encode(photo)
        guard data.count < 900_000 else { throw CloudError.server("photo too large") }
        var extra: [String: FS] = ["kind": .string("photo"), "photo": .bytes(data),
                                   "prompt": .string(post.prompt),
                                   "sharedFrom": .string(post.name.isEmpty ? post.handle : post.name)]
        if let caption = post.caption, !caption.isEmpty { extra["caption"] = .string(caption) }
        try await write(friendUID, id: UUID().uuidString, date: Date(), extra: extra)
        await notify(to: friendUID, id: "msg_\(uid)", type: "message", text: "📷")
        await loadMessages(with: friendUID)
    }

    /// 写真を送る（小さくしてから、メッセージの中に入れる）
    func sendPhoto(to friendUID: String, image: UIImage, front: UIImage? = nil) async throws {
        // 1メッセージは 1MB まで。外カメラを 600KB、内カメラの枠を 180KB 以内に収める
        let data = ChatPhoto.encode(image, budget: 600_000)
        guard data.count < 900_000 else { throw CloudError.server("photo too large") }
        var extra: [String: FS] = ["kind": .string("photo"), "photo": .bytes(data)]
        if let front {
            extra["front"] = .bytes(ChatPhoto.encode(front, startSide: 600, budget: 180_000))
        }
        try await write(friendUID, id: UUID().uuidString, date: Date(), extra: extra)
        await notify(to: friendUID, id: "msg_\(uid ?? "")", type: "message", text: "📷")
        await loadMessages(with: friendUID)
    }

    /// ボイスを送る（録音データ。最長60秒）
    func sendVoice(to friendUID: String, data: Data, duration: Double) async throws {
        guard data.count < 400_000 else { throw CloudError.server("voice too large") }
        try await write(friendUID, id: UUID().uuidString, date: Date(),
                        extra: ["kind": .string("voice"), "voice": .bytes(data), "duration": .double(duration)])
        await notify(to: friendUID, id: "msg_\(uid ?? "")", type: "message", text: "🎤")
        await loadMessages(with: friendUID)
    }

    /// 絵文字のリアクション（自分の分だけを書き換える。nil で外す）
    func react(messageID: String, friendUID: String, emoji: String?) async {
        guard let uid, let path = chatPath(with: friendUID) else { return }
        if let index = messages[friendUID]?.firstIndex(where: { $0.id == messageID }) {
            messages[friendUID]?[index].reactions[uid] = emoji
        }
        do {
            try await ensureSignedIn()
            try await patch("\(path)/\(messageID)", fields: ["reactions": .map([uid: .string(emoji ?? "")])],
                            mask: ["reactions.\(uid)"])
        } catch {
            report(error)
        }
    }

    /// 相手の会話を、ここまで読んだと知らせる（既読）
    func markRead(friendUID: String) async {
        guard uid != nil, let chat = chatID(with: friendUID) else { return }
        do {
            try await ensureSignedIn()
            myReadAt[friendUID] = Date()
            try await patch("chats/\(chat)/state/\(uid ?? "")", fields: ["lastReadAt": .timestamp(Date())], mask: ["lastReadAt"])
        } catch {}
    }

    /// 相手の既読・入力中、自分の既読の時刻を読む
    func refreshReadAt(_ friendUID: String) async {
        guard uid != nil, let chat = chatID(with: friendUID) else { return }
        do {
            try await ensureSignedIn()
            let theirs = try await get("chats/\(chat)/state/\(friendUID)")
            if let f = theirs["fields"] as? [String: Any] {
                if let d = FS.date(f, "lastReadAt") { friendReadAt[friendUID] = d }
                if let t = FS.date(f, "typingAt") { friendTypingAt[friendUID] = t }
            }
            let mine = try await get("chats/\(chat)/state/\(uid ?? "")")
            if let f = mine["fields"] as? [String: Any], let d = FS.date(f, "lastReadAt") { myReadAt[friendUID] = d }
        } catch {}
    }

    /// 入力中であることを知らせる（会話の状態に書く）
    func setTyping(_ friendUID: String) async {
        guard uid != nil, let chat = chatID(with: friendUID) else { return }
        do {
            try await ensureSignedIn()
            try await patch("chats/\(chat)/state/\(uid ?? "")", fields: ["typingAt": .timestamp(Date())], mask: ["typingAt"])
        } catch {}
    }

    /// その友達から届いた、いちばん新しいメッセージの知らせを既読にする
    func markMessagesRead(from friendUID: String) async {
        guard let uid, let n = notices.first(where: { $0.id == "msg_\(friendUID)" }), !n.read else { return }
        notices = notices.map { $0.id == n.id ? CloudNotice(id: $0.id, type: $0.type, fromUID: $0.fromUID, fromName: $0.fromName,
                                                            fromCode: $0.fromCode, text: $0.text, postID: $0.postID, date: $0.date, read: true) : $0 }
        try? await patch("notifications/\(uid)/items/\(n.id)", fields: ["read": .bool(true)], mask: ["read"])
    }
}

// MARK: - 通知のオン・オフ

/// 通知の種類ごとのミュート（オフにした種類は、一覧にも未読の数にも出ない）。端末に保存する
enum NotifySettings {
    static func key(_ type: String) -> String { "mute." + type }
    static func isMuted(_ type: String) -> Bool { UserDefaults.standard.bool(forKey: key(type)) }
}

// MARK: - 通報・ブロック

extension CloudSync {
    /// ブロックした人の一覧を読む
    func loadBlocks() async {
        guard let uid else { return }
        do {
            let json = try await send("GET", url: URL(string: "https://firestore.googleapis.com/v1/projects/\(CloudConfig.projectID)/databases/(default)/documents/blocks/\(uid)/list?pageSize=300")!, json: nil)
            let docs = json["documents"] as? [[String: Any]] ?? []
            blocked = Set(docs.compactMap { $0["name"] as? String }.map { String($0.split(separator: "/").last ?? "") })
        } catch {
            report(error)
        }
    }

    /// ブロック：その人の投稿・コメント・通知を見えなくして、友達も外す（DM もできなくなる）
    func block(_ otherUID: String) async {
        guard let uid else { return }
        blocked.insert(otherUID)
        notices = notices.filter { $0.fromUID != otherUID }
        publicPosts = publicPosts.filter { $0.owner != otherUID }
        friendPosts = friendPosts.filter { $0.owner != otherUID }
        do {
            try await ensureSignedIn()
            try await patch("blocks/\(uid)/list/\(otherUID)", fields: ["uid": .string(otherUID)])
        } catch {
            report(error)
        }
        await removeFriend(uid: otherUID)
    }

    /// ブロックを解除する（友達には戻らない。もう一度、友達リクエストから）
    func unblock(_ otherUID: String) async {
        guard let uid else { return }
        blocked.remove(otherUID)
        do {
            try await ensureSignedIn()
            try await delete("blocks/\(uid)/list/\(otherUID)")
        } catch {
            report(error)
        }
    }

    /// 通報：運営が確認できるように、記録だけ残す（送った人には、読める内容を出さない）
    func sendReport(against target: String, postID: String? = nil, commentID: String? = nil, reason: String) async {
        guard let uid else { return }
        var fields: [String: FS] = ["reporter": .string(uid), "target": .string(target),
                                    "reason": .string(reason), "date": .timestamp(Date())]
        if let postID { fields["postID"] = .string(postID) }
        if let commentID { fields["commentID"] = .string(commentID) }
        do {
            try await ensureSignedIn()
            try await patch("reports/\(UUID().uuidString)", fields: fields)
        } catch {
            report(error)
        }
    }
}

extension CloudNotice {
    /// 通知の一行（端末の通知にも使う）
    var summary: String {
        let who = fromName.isEmpty ? fromCode : fromName
        switch type {
        case "friendRequest": return LF("{n} さんから友達リクエストが届きました", ["n": who])
        case "friendAccepted": return LF("{n} さんと友達になりました", ["n": who])
        case "comment": return LF("{n} さんがコメントしました", ["n": who])
        case "friendPost": return LF("{n} さんが投稿しました", ["n": who])
        case "like": return LF("{n} さんがリアクションしました", ["n": who])
        default: return LF("{n} さんからメッセージ", ["n": who])
        }
    }
}
