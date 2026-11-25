import Foundation
import UIKit
import WidgetKit

/// アプリの状況を、ウィジェットに知らせる
enum WidgetBridge {
    static func push(_ store: PostStore) {
        // ダイナミックアイランド・ロック画面のお題も、同じタイミングで整える
        LiveActivityBridge.sync(store)
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
        Task { @MainActor in pushFeed(store) }
    }

    // MARK: - カレンダー・自分の投稿・友達の投稿のウィジェット

    /// 投稿した日、自分の写真、友達の写真を、ウィジェット用に書き出す
    @MainActor
    static func pushFeed(_ store: PostStore) {
        guard let dir = WidgetFeed.imageDir else { return }
        let now = Date()
        let activeDay = store.activeDayKey()
        var keep = Set<String>()

        // 自分の投稿（新しい順に4枚）
        let posted = store.records.filter { $0.postedPhotoFile != nil }
            .sorted { ($0.postedAt ?? .distantPast) > ($1.postedAt ?? .distantPast) }
        var mine: [WidgetFeed.Mine] = []
        for record in posted.prefix(4) {
            let name = "mine_\(record.id).jpg"
            if writeThumb(named: name, in: dir, image: { record.postedPhotoFile.flatMap { store.image(for: $0) } }) {
                keep.insert(name)
                mine.append(.init(file: name, prompt: L(record.prompt), dayKey: record.dayKey, elapsed: record.elapsed))
            }
        }

        // 友達の投稿（いまのお題の日の分。新しい順に4枚）。見せるかどうかは、ウィジェットが決める
        var friends: [WidgetFeed.Friend] = []
        for post in CloudSync.shared.friendPosts.prefix(4) {
            let name = "friend_\(post.id).jpg"
            if writeThumb(named: name, in: dir, image: { post.photo }) {
                keep.insert(name)
                friends.append(.init(id: post.id, file: name, name: post.name.isEmpty ? "@" + post.handle : post.name,
                                     prompt: L(post.prompt), city: post.city, postedAt: post.postedAt))
            }
        }

        // 次のお題が届く時刻（そこからは、また投稿するまで友達の投稿を隠す）
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        let lockAt = [NotificationScheduler.fireTime(for: now), NotificationScheduler.fireTime(for: tomorrow)]
            .filter { $0 > now }.min()

        let days = Array(Set(posted.map(\.dayKey))).sorted(by: >).prefix(62)
        let feed = WidgetFeed(postedDays: Array(days), streak: store.currentStreak(), mine: mine, friends: friends,
                              friendsUnlocked: store.hasPosted(day: activeDay), lockAt: lockAt,
                              lang: AppLanguage.current.rawValue, updatedAt: now)

        // もう使わない写真は消す
        if let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for f in files where !keep.contains(f) { try? FileManager.default.removeItem(at: dir.appendingPathComponent(f)) }
        }
        if feed.save() {
            for kind in ["HitokomaCalendar", "HitokomaMine", "HitokomaFriends"] { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
        }
    }

    /// 写真を小さく（長い辺 600px）して保存する。すでにあれば何もしない
    private static func writeThumb(named name: String, in dir: URL, image: () -> UIImage?) -> Bool {
        let url = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { return true }
        guard let img = image() else { return false }
        let side: CGFloat = 600
        let scale = min(1, side / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = small.jpegData(compressionQuality: 0.75) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
