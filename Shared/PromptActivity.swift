import Foundation
import ActivityKit

/// ダイナミックアイランドとロック画面に出す「今日のお題」（アプリとウィジェットで共有）
struct PromptActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var prompt: String        // お題（届くまでは画面に出さない）
        var fireAt: Date          // お題が届く（届いた）時刻。地域ごとに全員同じ
        var revealed: Bool        // アプリが「もう届いた」と知っている
        var colorName: String?    // 色のお題なら、その色（red / blue など）
        var lang: String?         // アプリで選んでいる言語
        var streak: Int           // 連続日数
    }

    var dayKey: String
}
