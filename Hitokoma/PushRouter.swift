import SwiftUI

/// 通知をタップしたとき、開く先（投稿・DM・通知一覧）
enum PushRoute: Equatable {
    case notices
    case post(id: String, name: String)
    case chat(CloudFriend)
}

/// 通知のタップを受け取って、画面に伝える。起動直後の通知も、画面ができたときに拾う
@MainActor
final class PushRouter: ObservableObject {
    static let shared = PushRouter()
    @Published var route: PushRoute?

    /// 通知の中身（投稿の番号・相手の名前など）から、開く先を決める。中身の文は使わない
    func open(type: String, postID: String, fromUID: String, fromName: String, fromCode: String) {
        switch type {
        case "message":
            if !fromUID.isEmpty {
                route = .chat(CloudFriend(uid: fromUID, name: fromName, code: fromCode))
            } else {
                route = .notices
            }
        case "comment", "like", "friendPost":
            route = postID.isEmpty ? .notices : .post(id: postID, name: fromName)
        default:
            route = .notices
        }
    }
}
