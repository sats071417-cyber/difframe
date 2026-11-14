import Foundation
import Combine
import UIKit
import ImageIO

/// 1日の投稿の枠。同じお題で、1日に最大3枚まで投稿できる（遅れてもOK）
enum PromptSlot: String, Codable, CaseIterable {
    case morning   // 1枚目
    case second    // 2枚目
    case third     // 3枚目
    case random    // 以前の名残（今は使わない）

    /// 今使う枠
    static let active: [PromptSlot] = [.morning, .second, .third]

    /// 1日に投稿できる枚数
    static let maxPerDay = 3

    var title: String {
        switch self {
        case .morning: return ("1枚目")
        case .second: return ("2枚目")
        case .third: return ("3枚目")
        case .random: return ("ランダムのお題")
        }
    }

    /// 撮影できる時間（nil は一日中）
    var window: TimeInterval? {
        switch self {
        case .morning, .second, .third: return nil
        case .random: return 120
        }
    }
}

/// 1つのお題の記録（1日2件まで）
struct PromptRecord: Codable, Identifiable, Equatable {
    var id: String { "\(dayKey)-\(slot.rawValue)" }
    let dayKey: String            // "2026-11-09"
    let slot: PromptSlot
    var prompt: String
    var revealedAt: Date?         // 表示した時刻（ランダムの2分の開始）
    var postedPhotoFile: String?  // 投稿した写真のファイル名
    var caption: String?
    var notifiedAt: Date? = nil   // 通知が届いた時刻（タイムの開始）
    var postedAt: Date? = nil     // 投稿した時刻（タイムの終了）
    var verified: Bool? = nil     // 画像認識で、お題に合うと確認できた（ランキングに数える）
    var scheduledAt: Date? = nil  // 今日の通知が届く予定の時刻（アプリを開いた時刻ではなく、これがタイムの開始）
    var frontPhotoFile: String? = nil   // 2枚撮りのときの、内カメラの写真（小さい方に出す）
    var publicCommentsOff: Bool? = nil  // みんな（公開）の投稿で、コメントを受け付けない（友達からは、いつでも受け付ける）
    var toFriends: Bool? = nil          // 友達に送ったか（nil = 送った。前の版の投稿は、両方に出す）
    var toPublic: Bool? = nil           // みんなに送ったか（nil = 送った）
    var city: String? = nil             // つけた場所（都市の名前だけ。正確な位置は残さない）

    var isForFriends: Bool { toFriends != false }
    var isForPublic: Bool { toPublic != false }

    /// タイムの開始：通知が届いた時刻。無ければ通知の予定時刻。古い記録は、お題を表示した時刻
    var startedAt: Date? { notifiedAt ?? scheduledAt ?? revealedAt }

    /// 通知が届く前か（まだタイムが始まっていない）
    func isWaiting(at now: Date = Date()) -> Bool {
        guard let start = startedAt else { return false }
        return now < start
    }

    /// 今日のタイム（通知から投稿まで）。通知より前に投稿した場合は、タイムなし（ランキングにも入らない）
    var elapsed: TimeInterval? {
        guard let start = startedAt, let end = postedAt, end >= start else { return nil }
        return end.timeIntervalSince(start)
    }
}

/// 投稿へのコメント（端末の中に保存）
struct Comment: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    let text: String
    let date: Date
}

/// お題・投稿・リアクション・コメントを端末内に保存する
final class PostStore: ObservableObject {
    @Published private(set) var records: [PromptRecord] = []
    @Published private(set) var reactions: [String: String] = [:]
    @Published private(set) var comments: [String: [Comment]] = [:]

    private let fileURL: URL
    private let reactionURL: URL
    private let commentURL: URL
    private let photoDir: URL

    /// お題の一覧。すべて、iPhoneの画像認識（Vision）が見分けられる言葉だけ（PromptCatalog）
    static let morningPrompts: [String] = PromptCatalog.prompts
    static let randomPrompts: [String] = []

    /// 朝・ランダムそれぞれのお題の一覧
    static func prompts(for slot: PromptSlot) -> [String] {
        switch slot {
        case .morning, .second, .third:
            // 1日1個なので、両方のリストをまとめて使う（重複は除く）
            var all: [String] = []
            for x in morningPrompts + randomPrompts where !all.contains(x) { all.append(x) }
            return all
        case .random: return randomPrompts
        }
    }

    /// 世界を時差で4つのグループに分ける（端末の時差から自動で決まる）
    static let regionNames = [("東アジア・東南アジア・オセアニア"), ("南アジア・中東・東ヨーロッパ"), ("ヨーロッパ・アフリカ"), ("南北アメリカ")]

    /// 画面で使う短い名前
    static let regionShortNames = [("東アジア・オセアニア"), ("南アジア・中東"), ("ヨーロッパ・アフリカ"), ("南北アメリカ")]

    /// 所属するグループ（0〜3）。UTCからの時差（秒）で決める
    static func regionIndex(forOffset seconds: Int) -> Int {
        let hours = seconds / 3600
        switch hours {
        case 7...: return 0          // UTC+7 以上：東アジア・東南アジア・オセアニア
        case 3...6: return 1         // UTC+3〜+6：南アジア・中東・東ヨーロッパ
        case -1...2: return 2        // UTC-1〜+2：ヨーロッパ・アフリカ
        default: return 3            // UTC-2 以下：アメリカ
        }
    }

    static var regionIndex: Int { regionIndex(forOffset: TimeZone.current.secondsFromGMT()) }

    static var regionName: String { L(regionNames[regionIndex]) }

    /// その日のお題。日付ごとに1つで、世界のどこでも、同じ日付なら同じお題になる（現地の日付で切り替わる）。
    /// 日本が先に日付が変わるので、同じ瞬間には、国によってお題が違うことがある。
    static func worldwidePrompt(for date: Date = Date(), region: Int = regionIndex) -> String {
        let pool = prompts(for: .morning)
        guard !pool.isEmpty else { return L("服") }
        _ = region
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let reference = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? Date(timeIntervalSince1970: 0)
        let days = calendar.dateComponents([.day], from: reference, to: calendar.startOfDay(for: date)).day ?? 0
        let day = max(0, days)
        let cycle = day / pool.count
        return promptOrder(cycle: cycle, pool: pool)[day % pool.count]
    }

    /// 同じお題が、この日数の間には出ない（7日の間に重ならない）
    static let noRepeatDays = 7

    /// cycle 回目（pool の数ごとに1周）のお題の並び。
    /// 周ごとに、日付だけで決まる順番にシャッフルする（同じ周は、世界のどこでも同じ並び）。
    /// 周の境目でも、前の周の最後の6日と同じお題が、次の周の最初の6日に来ないように入れ替える。
    static func promptOrder(cycle: Int, pool: [String]) -> [String] {
        var previous: [String] = []
        var order = pool
        for c in 0...max(0, cycle) {
            var generator = SeededGenerator(state: UInt64(2026 + c) &* 0x9E37_79B9_7F4A_7C15)
            order = pool.shuffled(using: &generator)
            let gap = noRepeatDays - 1
            if c > 0, pool.count > gap * 2 {
                let tail = Set(previous.suffix(gap))
                var spare = gap
                for i in 0..<gap where tail.contains(order[i]) {
                    while spare < order.count, tail.contains(order[spare]) { spare += 1 }
                    if spare < order.count { order.swapAt(i, spare); spare += 1 }
                }
            }
            previous = order
        }
        return order
    }

    /// 同じスロットのお題が30日以内に出ないように、使えるお題を選ぶ
    private func availablePrompts(for dayKey: String, slot: PromptSlot) -> [String] {
        let all = PostStore.prompts(for: slot)
        let cutoff = PostStore.dayKey(for: Date().addingTimeInterval(-30 * 24 * 60 * 60))
        let recent = Set(records.filter { $0.dayKey >= cutoff && $0.slot == slot }.map(\.prompt))
        let pool = all.filter { !recent.contains($0) }
        // 30日以内に全部使い切った場合は、今日の同じスロットの重複だけ避ける
        return pool.isEmpty ? all : pool
    }

    /// アプリ全体で1つだけ使う保存先（通知をタップしたときにも同じ保存先を使うため）
    static let shared = PostStore()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("records.json")
        reactionURL = docs.appendingPathComponent("reactions.json")
        commentURL = docs.appendingPathComponent("comments.json")
        photoDir = docs.appendingPathComponent("photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: photoDir, withIntermediateDirectories: true)
        load()
    }

    static func dayKey(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    func record(day: String, slot: PromptSlot) -> PromptRecord? {
        records.first { $0.dayKey == day && $0.slot == slot }
    }

    /// その日の枠（1枚目〜3枚目の順）
    func records(day: String) -> [PromptRecord] {
        PromptSlot.active.compactMap { record(day: day, slot: $0) }
    }

    /// その日に投稿した枚数
    // MARK: - いま見せる日（今日のお題は、通知が届くまで秘密）

    /// いま見せる日。今日の通知が届く前は、前日のまま（前日のお題・写真・残りの枠）。
    /// 前日の記録がない（はじめての日）ときは今日。そのときは、通知までお題を伏せる。
    func activeDayKey(now: Date = Date()) -> String {
        let today = PostStore.dayKey(for: now)
        if let start = records(day: today).compactMap(\.startedAt).min(), start <= now { return today }
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) {
            let key = PostStore.dayKey(for: yesterday)
            if !records(day: key).isEmpty { return key }
        }
        return today
    }

    /// 今日のお題が、まだ秘密か（通知の前で、前日の表示もないとき）
    func isPromptHidden(now: Date = Date()) -> Bool {
        let today = PostStore.dayKey(for: now)
        guard activeDayKey(now: now) == today,
              let start = records(day: today).compactMap(\.startedAt).min() else { return false }
        return now < start
    }

    /// いま見せるお題（秘密なら nil）
    func activePrompt(now: Date = Date()) -> String? {
        if isPromptHidden(now: now) { return nil }
        return records(day: activeDayKey(now: now)).first?.prompt ?? PostStore.worldwidePrompt(for: now)
    }

    func postedCount(day: String) -> Int {
        records(day: day).filter { $0.postedPhotoFile != nil }.count
    }

    func hasPosted(day: String) -> Bool { postedCount(day: day) > 0 }

    /// 次に撮れる枠（3枚すべて投稿済みなら nil）
    func nextOpenRecord(day: String) -> PromptRecord? {
        records(day: day).first { $0.postedPhotoFile == nil }
    }

    /// その日の最新の投稿
    func latestPosted(day: String) -> PromptRecord? {
        records(day: day).filter { $0.postedPhotoFile != nil }
            .max { ($0.postedAt ?? .distantPast) < ($1.postedAt ?? .distantPast) }
    }

    /// 今日の2件を用意する（無ければ作る）。お題は朝とランダムで別のものにする
    func ensureToday() {
        let key = PostStore.dayKey(for: Date())
        var changed = false
        // 古い版で保存された、今日の未投稿のお題を、今の一覧から選び直す
        for index in records.indices where records[index].dayKey == key
            && records[index].postedPhotoFile == nil
            && records[index].prompt != PostStore.worldwidePrompt(for: Date()) {
            let fresh = PostStore.worldwidePrompt(for: Date())
            records[index].prompt = fresh
            changed = true
        }
        for slot in PromptSlot.active where record(day: key, slot: slot) == nil {
            let prompt = PostStore.worldwidePrompt(for: Date())
            records.append(PromptRecord(dayKey: key, slot: slot, prompt: prompt,
                                        revealedAt: nil, postedPhotoFile: nil, caption: nil))
            changed = true
        }
        // 今日の通知の予定時刻を、記録に入れる（タイムは、ここから数える）
        for index in records.indices where records[index].dayKey == key
            && records[index].postedPhotoFile == nil
            && records[index].scheduledAt == nil {
            // 通知の時刻がもう過ぎていたら、いまから数える（知らないうちに早く始めたことにしない）
            records[index].scheduledAt = max(NotificationScheduler.fireTime(for: Date()), Date())
            changed = true
        }
        if changed { save() }
    }

    /// お題を表示した時刻を記録する（ランダムは、ここから2分）
    func reveal(id: String) {
        guard let index = records.firstIndex(where: { $0.id == id }),
              records[index].revealedAt == nil else { return }
        records[index].revealedAt = Date()
        save()
    }

    /// 撮れる状態かどうか（朝は一日中、ランダムは表示から2分）
    func canCapture(_ record: PromptRecord, at now: Date = Date()) -> Bool {
        // 制限時間はなし。お題を表示したら撮れる
        return record.revealedAt != nil
    }

    /// 通知が届いた時刻を記録する（タイムの開始）。最初の1回だけ。その日の3枠すべてに入れる
    func markNotified(day: String, arrivedAt: Date = Date()) {
        var changed = false
        for index in records.indices where records[index].dayKey == day && records[index].notifiedAt == nil {
            records[index].notifiedAt = arrivedAt
            changed = true
        }
        if changed { save() }
    }

    /// 連続して投稿した日数（今日まだでも、昨日までの連続は数える）
    func currentStreak(today: Date = Date()) -> Int {
        let calendar = Calendar.current
        let posted = Set(records.filter { $0.postedPhotoFile != nil }.map(\.dayKey))
        var day = today
        if !posted.contains(PostStore.dayKey(for: day)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while posted.contains(PostStore.dayKey(for: day)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    func savePost(id: String, photo: UIImage, front: UIImage? = nil, caption: String, verified: Bool = false) {
        let fileName = "\(id)-\(UUID().uuidString).jpg"
        if let data = photo.jpegData(compressionQuality: 0.8) {
            try? data.write(to: photoDir.appendingPathComponent(fileName))
        }
        // 2枚撮りの内カメラは、別のファイルにする（あとで大小を入れ替えられるように）
        var frontName: String? = nil
        if let front, let data = front.jpegData(compressionQuality: 0.8) {
            let name = "\(id)-front-\(UUID().uuidString).jpg"
            try? data.write(to: photoDir.appendingPathComponent(name))
            frontName = name
        }
        if let index = records.firstIndex(where: { $0.id == id }) {
            records[index].frontPhotoFile = frontName
            records[index].postedPhotoFile = fileName
            records[index].caption = caption
            records[index].postedAt = Date()
            records[index].verified = verified
        }
        save()
    }

    /// 読み込んだ写真を覚えておく（同じ写真を何度も読み直さない）
    private let imageCache = NSCache<NSString, UIImage>()

    func image(for fileName: String) -> UIImage? {
        if let cached = imageCache.object(forKey: fileName as NSString) { return cached }
        let url = photoDir.appendingPathComponent(fileName) as CFURL
        // 大きすぎる写真でも、画面に必要な大きさ（1600px）で読み込む
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceShouldCacheImmediately: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 1600]
        guard let source = CGImageSourceCreateWithURL(url, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg)
        imageCache.setObject(image, forKey: fileName as NSString)
        return image
    }

    /// 自分の投稿を消す。写真のファイルも消し、その枠はもう一度撮れるようになる。
    func deletePost(id: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        for file in [records[index].postedPhotoFile, records[index].frontPhotoFile].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: photoDir.appendingPathComponent(file))
            imageCache.removeObject(forKey: file as NSString)
        }
        records[index].postedPhotoFile = nil
        records[index].frontPhotoFile = nil
        records[index].postedAt = nil
        records[index].caption = nil
        records[index].verified = nil
        records[index].publicCommentsOff = nil
        records[index].toFriends = nil
        records[index].toPublic = nil
        records[index].city = nil
        reactions[id] = nil
        comments[id] = nil
        saveReactions()
        saveComments()
        save()
        Task { @MainActor in CloudSync.shared.upload(recordID: id) }
    }

    func toggleReaction(postID: String, emoji: String) {
        reactions[postID] = (reactions[postID] == emoji) ? nil : emoji
        saveReactions()
    }

    /// 投稿へコメントを追加する
    func addComment(postID: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        comments[postID, default: []].append(Comment(text: trimmed, date: Date()))
        saveComments()
    }

    /// コメントを消す（自分のコメント）
    func deleteComment(postID: String, commentID: String) {
        comments[postID]?.removeAll { $0.id == commentID }
        saveComments()
    }

    /// リアクションをつける（ダブルタップのいいね用。すでに同じなら、そのまま）
    func setReaction(postID: String, emoji: String) {
        guard reactions[postID] != emoji else { return }
        reactions[postID] = emoji
        saveReactions()
    }

    /// どこに送るか（友達・みんな）、みんなでコメントを受け付けるか、場所（都市の名前）
    func setShareOptions(id: String, friends: Bool, everyone: Bool, comments: Bool, city: String?) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].toFriends = friends
        records[index].toPublic = everyone
        records[index].publicCommentsOff = comments ? nil : true
        records[index].city = city
        save()
        Task { @MainActor in CloudSync.shared.upload(recordID: id) }
    }

    /// 投稿の一言を、あとから書き換える（空にしたら、一言なし）
    func updateCaption(id: String, caption: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        records[index].caption = trimmed.isEmpty ? nil : trimmed
        save()
        Task { @MainActor in CloudSync.shared.upload(recordID: id) }
    }

    /// みんな（公開）の投稿で、コメントを受け付けるか
    func setPublicComments(id: String, on: Bool) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].publicCommentsOff = on ? nil : true
        save()
        Task { @MainActor in CloudSync.shared.upload(recordID: id) }
    }

    func comments(for postID: String) -> [Comment] {
        comments[postID] ?? []
    }

    private func saveComments() {
        if let data = try? JSONEncoder().encode(comments) {
            try? data.write(to: commentURL)
        }
    }

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([PromptRecord].self, from: data) {
            records = decoded
        }
        if let data = try? Data(contentsOf: reactionURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            reactions = decoded
        }
        if let data = try? Data(contentsOf: commentURL),
           let decoded = try? JSONDecoder().decode([String: [Comment]].self, from: data) {
            comments = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: fileURL)
        }
        WidgetBridge.push(self)
    }

    private func saveReactions() {
        if let data = try? JSONEncoder().encode(reactions) {
            try? data.write(to: reactionURL)
        }
    }
}
