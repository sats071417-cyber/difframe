import Foundation
import ActivityKit

/// 今日のお題を、ダイナミックアイランドとロック画面に出す（Live Activity）
/// - 届く前：お題が届く時刻までのカウントダウン。届く時刻を「古くなる時刻（staleDate）」にしておくので、
///   その瞬間にシステムが描き直して「お題＋届いてからの時間」に変わる（アプリを開かなくても、通知と同時に切り替わる）
/// - 撮って投稿したら消す
/// Live Activity はアプリを開いているときしか始められないので、アプリを開くたび・記録が変わるたびに整える
enum LiveActivityBridge {
    /// お題が届く30分前から出す（届く前のカウントダウン）
    private static let lead: TimeInterval = 30 * 60
    /// その日にもう出したか（自分で消した人に、また出さないため）
    private static let startedDayKey = "liveActivityDay"

    static func sync(_ store: PostStore) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let now = Date()
        let today = PostStore.dayKey(for: now)
        let records = store.records(day: today)
        let posted = store.postedCount(day: today) > 0
        let fireAt = records.compactMap(\.startedAt).min() ?? NotificationScheduler.fireTime(for: now)
        let tooEarly = fireAt.timeIntervalSince(now) > lead
        let tooLate = now.timeIntervalSince(fireAt) > 8 * 3600
        let activities = Activity<PromptActivityAttributes>.activities

        // 投稿した日・別の日・時間切れのものは消す
        for activity in activities where posted || tooLate || activity.attributes.dayKey != today {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        guard !posted, !tooEarly, !tooLate else { return }

        let key = records.first?.prompt ?? PostStore.worldwidePrompt(for: now)
        // お題の文字は、届いてからだけ入れる（届く前に、通知の内容を先に見られないように）
        let state = PromptActivityAttributes.ContentState(
            prompt: fireAt <= now ? L(key) : "", fireAt: fireAt, revealed: fireAt <= now,
            colorName: PromptCatalog.colors[key].map { "\($0)" },
            lang: AppLanguage.current.rawValue, streak: store.currentStreak())
        let content = ActivityContent(state: state, staleDate: fireAt > now ? fireAt : nil)

        if let current = activities.first(where: { $0.attributes.dayKey == today && $0.activityState == .active }) {
            if current.content.state != state { Task { await current.update(content) } }
        } else if UserDefaults.standard.string(forKey: startedDayKey) != today {
            if (try? Activity.request(attributes: PromptActivityAttributes(dayKey: today), content: content, pushType: nil)) != nil {
                UserDefaults.standard.set(today, forKey: startedDayKey)
            }
        }
    }
}
