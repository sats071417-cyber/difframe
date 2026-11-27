import SwiftUI

/// アカウントの削除（Apple の審査の必須項目）。サーバーの自分のデータをすべて消し、認証のアカウントを消し、端末の記録も消す。
/// 消すのは自分のデータだけ。他の人の投稿につけたコメントは、サーバー側の仕組みが無いと探せないため、削除の依頼があれば窓口で消す。
enum DeleteResult { case done, needsRecentLogin, failed }

extension CloudSync {
    private var docsBase: String {
        "https://firestore.googleapis.com/v1/projects/\(CloudConfig.projectID)/databases/(default)/documents"
    }

    private func listDocs(_ path: String) async -> [[String: Any]] {
        var all: [[String: Any]] = []
        var token: String? = nil
        repeat {
            var text = "\(docsBase)/\(path)?pageSize=300"
            if let token { text += "&pageToken=" + (token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token) }
            guard let url = URL(string: text), let json = try? await send("GET", url: url, json: nil) else { break }
            all += json["documents"] as? [[String: Any]] ?? []
            token = json["nextPageToken"] as? String
        } while token != nil
        return all
    }

    private func docID(_ doc: [String: Any]) -> String? {
        (doc["name"] as? String)?.split(separator: "/").last.map(String.init)
    }

    /// 自分の投稿の名前（端末の記録から作る。サーバーのリスト検索は、ルールで断られるため使わない）
    private func ownPostIDs(_ uid: String) async -> [String] {
        PostStore.shared.records.filter { $0.postedPhotoFile != nil }.compactMap { cloudID(for: $0.id) }
    }

    /// サーバーの自分のデータをすべて消してから、認証のアカウントを消す
    func deleteAccount() async -> DeleteResult {
        guard isOn else { return .failed }
        do { try await ensureSignedIn() } catch { return .failed }
        guard let uid else { return .failed }

        // 自分の投稿（とそのコメント）
        for id in await ownPostIDs(uid) {
            for comment in await listDocs("posts/\(id)/comments") {
                if let cid = docID(comment) { try? await delete("posts/\(id)/comments/\(cid)") }
            }
            try? await delete("posts/\(id)")
        }

        // 友達との会話（自分のメッセージ）と、友達の関係。関係は、いちばん最後に消す（会話を消す権限に必要）
        for friend in await listDocs("friends/\(uid)/list") {
            guard let fid = docID(friend) else { continue }
            let chat = [uid, fid].sorted().joined(separator: "_")
            for message in await listDocs("chats/\(chat)/messages") {
                let fields = message["fields"] as? [String: Any] ?? [:]
                if FS.string(fields, "from") == uid, let mid = docID(message) { try? await delete("chats/\(chat)/messages/\(mid)") }
            }
            try? await delete("chats/\(chat)/state/\(uid)")
            try? await delete("friends/\(fid)/list/\(uid)")
            try? await delete("friends/\(uid)/list/\(fid)")
        }

        for item in await listDocs("notifications/\(uid)/items") {
            if let id = docID(item) { try? await delete("notifications/\(uid)/items/\(id)") }
        }
        for other in await listDocs("blocks/\(uid)/list") {
            if let id = docID(other) { try? await delete("blocks/\(uid)/list/\(id)") }
        }
        try? await delete("devices/\(uid)")
        try? await delete("profiles/\(uid)")
        try? await delete("codes/\(FriendCode.myID)")

        // IDも手放す（次に使う人が使えるように）
        if let h = UserDefaults.standard.string(forKey: "myHandle"), !h.isEmpty { await releaseID(CloudSync.normalizeID(h)) }

        // 連絡先から見つけてもらう索引からも外す（サーバー側でも、アカウントが消えたときに外す）
        _ = try? await callFunction("setPhoneDiscoverable", ["enabled": false])

        // 認証のアカウント（電話番号もここで消える）
        do {
            try await deleteAuthAccount()
        } catch {
            return "\(error)".contains("CREDENTIAL_TOO_OLD") ? .needsRecentLogin : .failed
        }
        return .done
    }

    /// ログアウト：サーバーのアカウントとデータは残して、この端末からだけ外す。
    /// 電話番号で確認したアカウントなら、あとで同じ番号でログインすると戻れる
    func signOut() async {
        await markOffline()
        if let uid { try? await delete("devices/\(uid)") }   // この端末に、通知が届かないようにする
        wipeLocalData(keepPreferences: true, keepRecords: true)
    }

    /// ログアウトしても残す、この端末の好み（アカウントのデータではないもの）
    private static let devicePreferenceKeys: Set<String> = [
        AppLanguage.storageKey, NotificationScheduler.zoneKey, "presenceShare", "dualCamera",
        "sharePublic", "shareFriends", "shareLocation", "publicCommentsDefault", "pickupOptOut",
    ]

    /// 削除が終わったあと：この端末の記録・設定・写真もすべて消して、最初の状態に戻す
    func wipeLocalData(keepPreferences: Bool = false, keepRecords: Bool = false) {
        resetLocalIdentity()
        if !keepRecords { PostStore.shared.wipeAll() }   // ログアウトでは、この端末の写真と記録を残す
        // 1つずつ消す（まとめて消すと、画面の @AppStorage に伝わらず、削除したあとも前の画面のままになる）
        let defaults = UserDefaults.standard
        if let id = Bundle.main.bundleIdentifier {
            for key in (defaults.persistentDomain(forName: id) ?? [:]).keys {
                if keepPreferences && (Self.devicePreferenceKeys.contains(key) || key.hasPrefix("mute.")) { continue }
                defaults.removeObject(forKey: key)
            }
        }
        // 最初の説明と、電話番号の登録画面から、やり直す
        defaults.set(false, forKey: "onboarded")
        defaults.set(false, forKey: Account.doneKey)
        if let group = UserDefaults(suiteName: AppGroup.id) {
            for key in group.dictionaryRepresentation().keys { group.removeObject(forKey: key) }
        }
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
