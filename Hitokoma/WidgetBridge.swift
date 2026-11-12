import Foundation
import WidgetKit

/// アプリの状況を、ウィジェットに知らせる
enum WidgetBridge {
    static func push(_ store: PostStore) {
        let today = store.activeDayKey()
        let records = store.records(day: today)
        let hidden = store.isPromptHidden()
        let key = store.activePrompt()
        let last = records.filter { $0.postedAt != nil }.max { ($0.postedAt ?? .distantPast) < ($1.postedAt ?? .distantPast) }
        let snapshot = WidgetSnapshot(streak: store.currentStreak(),
                                      postedToday: store.postedCount(day: today),
                                      maxPerDay: PromptSlot.maxPerDay,
                                      prompt: key.map { L($0) } ?? "？",
                                      updatedAt: Date(),
                                      lang: AppLanguage.current.rawValue,
                                      startedAt: records.compactMap(\.startedAt).min(),
                                      hidden: hidden,
                                      colorName: key.flatMap { PromptCatalog.colors[$0] }.map { "\($0)" },
                                      lastTime: last?.elapsed)
        if snapshot.save() {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
