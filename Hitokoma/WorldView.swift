import SwiftUI

/// 世界の画面：同じお題を、世界のどこで・いつ撮ったかを見せる。地図が主役。
/// 「地図」「タイムライン」「タイムアタック」を切り替える。
struct WorldView: View {
    private enum Mode: Hashable { case now, ranking }

    /// true のときは、世界の投稿の一覧だけを出す（タイムラインの「みんな」）
    var feedOnly = false
    /// 見えていないときは地図を描かない（裏で地図が動くと、カメラが重くなるため）
    var isActive = true

    @EnvironmentObject private var store: PostStore
    @AppStorage("myHandle") private var myHandle: String = ""
    @AppStorage("friendList") private var friendList: String = MyProfile.defaultFriends
    @State private var mode: Mode = .now
    @State private var selectedID: String? = nil
    @State private var base = Date()       // サンプルの「何分前」の基準
    @State private var regionSelection = PostStore.regionIndex   // タイムアタックで見ている地域
    @State private var commentTarget: CommentTarget? = nil

    private let samples = WorldSamples.all

    /// いま見せるお題（今日の通知の前は前日。はじめての日は伏せる）
    private var prompt: String { store.activePrompt() ?? "？" }
    private var stats: TimeAttackStats { TimeAttackStats(records: store.records) }

    private var board: [WorldRankEntry] {
        let input = AchievementInput(records: store.records, friendCount: MyProfile.friendCount(friendList))
        let monthly = MonthlyPoints(records: store.records, month: MonthlyPoints.monthKey(for: Date()))
        return WorldRanking.board(region: regionSelection, myBest: stats.best,
                                  myName: "@" + MyProfile.handle(myHandle),
                                  myTrophies: Trophy.allCases.filter { $0.isUnlocked(input) },
                                  myRank: monthly.rank)
    }

    var body: some View {
        if feedOnly {
            timeline
                .sheet(item: $commentTarget) { target in
                    CommentSheet(postID: target.id, owner: target.owner, caption: target.caption,
                                 image: target.image, prompt: target.prompt)
                        .environmentObject(store)
                }
        } else {
            worldBody
        }
    }

    private var worldBody: some View {
        VStack(spacing: 10) {
            ScreenHeader(title: L("世界")) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(L("今日のお題")).font(.caption2).foregroundStyle(Hi.dim)
                    Text(L(prompt)).font(.headline.weight(.black)).foregroundStyle(Hi.neon)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, 16)

            HiSegment(options: [(value: Mode.now, title: L("地図")), (value: Mode.ranking, title: L("ランキング"))],
                      selection: $mode)
                .padding(.horizontal, 16)

            ZStack {
                // 地図を大きく。投稿の一覧は、タイムラインの「みんな」にある
                VStack(spacing: 10) {
                    Group {
                        if isActive {
                            WorldMapView(samples: samples, base: base, selectedID: $selectedID)
                        } else {
                            Color.black
                        }
                    }
                        .frame(maxHeight: .infinity)
                        .overlay(alignment: .bottom) {
                            // 地図の下の Apple のロゴと「法律に基づく情報」は隠さない（上に余白を取る）
                            mapBottom.padding(.horizontal, 10).padding(.bottom, 40)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
                .opacity(mode == .now ? 1 : 0)
                .allowsHitTesting(mode == .now)

                ranking
                    .opacity(mode == .ranking ? 1 : 0)
                    .allowsHitTesting(mode == .ranking)
            }
        }
        .background(Color.black.ignoresSafeArea())
    }

    // MARK: - 地図の下：選んだ都市のカード、または都市の一覧

    @ViewBuilder
    private var mapBottom: some View {
        if let sample = samples.first(where: { $0.id == selectedID }) {
            cityCard(sample)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(samples.sorted { $0.minutesAgo < $1.minutesAgo }) { sample in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selectedID = sample.id }
                        } label: {
                            HStack(spacing: 6) {
                                Text(sample.flag)
                                Text(sample.city).font(.subheadline.weight(.bold)).lineLimit(1)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .background(Capsule().fill(Color.black.opacity(0.65)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// 都市のカード：その土地のいまの光、現地時刻、あいさつ、タイム
    private func cityCard(_ sample: WorldSample) -> some View {
        let light = sample.light(base: base)
        return HStack(spacing: 12) {
            ZStack {
                if let photo = sample.photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else {
                    GlowBackground(palette: light.palette, focus: .center)
                }
                Text(sample.flag).font(.system(size: 30))
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(sample.city).font(.headline.weight(.black))
                Text(LF("現地 {t}", ["t": sample.localTime(base: base)]) + "・" + light.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Hi.dim)
                Text("「\(sample.greeting)」").font(.subheadline.weight(.bold)).lineLimit(1)
                Text("@\(sample.handle)・\(TimeFormat.string(sample.time))")
                    .font(.caption)
                    .foregroundStyle(Hi.neon)
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selectedID = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("閉じる"))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.8)))
    }

    // MARK: - タイムライン（Xのように、世界の投稿を1列で）

    private struct Pickup: Identifiable {
        let id: String
        let title: String
        let icon: String
        let sample: WorldSample
        let detail: String
    }

    /// 世界からのピックアップ：最速、いま夜の場所、あなたと時差がいちばん大きい場所
    private var pickups: [Pickup] {
        var result: [Pickup] = []
        if let fastest = samples.min(by: { $0.time < $1.time }) {
            result.append(Pickup(id: "fastest", title: L("最速"), icon: "bolt.fill", sample: fastest,
                                 detail: TimeFormat.string(fastest.time)))
        }
        if let night = samples.filter({ $0.light(base: base) == .night }).min(by: { $0.minutesAgo < $1.minutesAgo }) {
            result.append(Pickup(id: "night", title: L("いま夜"), icon: "moon.stars.fill", sample: night,
                                 detail: LF("現地 {t}", ["t": night.localTime(base: base)])))
        }
        let mine = TimeZone.current.secondsFromGMT(for: base)
        if let farthest = samples.max(by: {
            abs($0.timeZone.secondsFromGMT(for: base) - mine) < abs($1.timeZone.secondsFromGMT(for: base) - mine)
        }) {
            let hours = Int((Double(abs(farthest.timeZone.secondsFromGMT(for: base) - mine)) / 3600).rounded())
            result.append(Pickup(id: "far", title: L("時差が最大"), icon: "clock.arrow.2.circlepath", sample: farthest,
                                 detail: LF("{n}時間ちがい", ["n": "\(hours)"])))
        }
        return result
    }

    private var timeline: some View {
        let sorted = samples.sorted { $0.minutesAgo < $1.minutesAgo }
        return ScrollView {
            LazyVStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L("世界からのピックアップ"))
                            .font(.subheadline.weight(.black))
                        Spacer()
                        Text(L("サンプル")).font(.caption.weight(.bold)).foregroundStyle(Hi.dim)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(pickups) { pickup in
                                pickupCard(pickup)
                            }
                        }
                    }
                }
                // 自分の投稿（みんなにも出る。コメントを受け付けるかは、自分で選べる）
                ForEach(myPublicPosts, id: \.record.id) { item in
                    myPublicCard(item.record, image: item.image)
                }
                ForEach(sorted) { sample in
                    feedCard(sample)
                }
                Text(L("他の人の投稿はサンプルです。写真の代わりに、その土地のいまの光で表しています。"))
                    .font(.caption)
                    .foregroundStyle(Hi.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 16)
        }
    }

    private func pickupCard(_ pickup: Pickup) -> some View {
        let light = pickup.sample.light(base: base)
        return Button {
            if !feedOnly { withAnimation { selectedID = pickup.sample.id } }
        } label: {
            ZStack(alignment: .topLeading) {
                GlowBackground(palette: light.palette)
                VStack(alignment: .leading, spacing: 0) {
                    Label(pickup.title, systemImage: pickup.icon)
                        .font(.caption.weight(.black))
                    Spacer()
                    Text("\(pickup.sample.flag) \(pickup.sample.city)")
                        .font(.subheadline.weight(.black))
                    Text(pickup.detail)
                        .font(.caption.weight(.bold).monospacedDigit())
                }
                .foregroundStyle(light.textColor)
                .padding(12)
            }
            .frame(width: 150, height: 116)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LF("{a} {b} {c}。地図で見る", ["a": pickup.title, "b": pickup.sample.city, "c": pickup.detail]))
    }

    /// 1件の投稿：アイコン、@名前、都市・現地の時刻、正方形の写真（あいさつと時刻つき）、反応
    private func feedCard(_ sample: WorldSample) -> some View {
        let light = sample.light(base: base)
        let reactionID = "world-\(sample.id)"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    GlowBackground(palette: light.palette, focus: .center)
                    Text(sample.flag).font(.title3)
                }
                .frame(width: 42, height: 42)
                .clipShape(Circle())
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("@" + sample.handle).font(.subheadline.weight(.black))
                        RankBadge(rank: sample.rank)
                    }
                    Text("\(sample.city)・\(agoText(sample.minutesAgo))")
                        .font(.caption)
                        .foregroundStyle(Hi.dim)
                }
                Spacer(minLength: 0)
                TrophyBadges(trophies: sample.trophies, limit: 2)
            }
            ZStack {
                    if let photo = sample.photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else {
                        GlowBackground(palette: light.palette)
                    }
                    VStack {
                        HStack {
                            Label(light.name, systemImage: light.icon)
                                .font(.caption.weight(.bold))
                            Spacer()
                            DotText(text: sample.localTime(base: base), pitch: 4, color: light.textColor)
                        }
                        Spacer()
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("「\(sample.greeting)」").font(.title.weight(.black))
                                Text(sample.language).font(.caption.weight(.bold))
                            }
                            Spacer()
                        }
                    }
                    .foregroundStyle(light.textColor)
                    .padding(16)
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .contentShape(Rectangle())
                .socialPhoto(postID: reactionID, allowComments: !sample.commentsOff) {
                    commentTarget = CommentTarget(id: reactionID, owner: "@" + sample.handle, caption: "「\(sample.greeting)」",
                                                  image: sample.photo)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(LF("{a} 現地{b} {c}。地図で見る", ["a": sample.city, "b": sample.localTime(base: base), "c": light.name]))

            // 公開の投稿：コメントを受け付けるかは、投稿した人が決める
            CommentLine(postID: reactionID, allowComments: !sample.commentsOff) {
                commentTarget = CommentTarget(id: reactionID, owner: "@" + sample.handle, caption: "「\(sample.greeting)」",
                                              image: sample.photo)
            }
        }
    }

    /// みんなに出す、自分の投稿（いま見せる日のもの）
    private var myPublicPosts: [(record: PromptRecord, image: UIImage)] {
        store.records(day: store.activeDayKey())
            .filter { $0.postedPhotoFile != nil && $0.isForPublic }
            .sorted { ($0.postedAt ?? .distantPast) > ($1.postedAt ?? .distantPast) }
            .compactMap { r in r.postedPhotoFile.flatMap { store.image(for: $0) }.map { (r, $0) } }
    }

    private func myPublicCard(_ record: PromptRecord, image: UIImage) -> some View {
        let commentsOn = record.publicCommentsOff != true
        let open = {
            commentTarget = CommentTarget(id: record.id, owner: L("あなた"), caption: record.caption, image: image)
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Group {
                    if let avatar = Avatar.load() {
                        Image(uiImage: avatar).resizable().scaledToFill()
                    } else {
                        Hi.neon.overlay(Image(systemName: "person.fill").foregroundStyle(Hi.onNeon))
                    }
                }
                .frame(width: 42, height: 42)
                .clipShape(Circle())
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("@" + MyProfile.handle(myHandle)).font(.subheadline.weight(.black))
                        Text(L("自分")).font(.caption2.weight(.black))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Hi.neon)).foregroundStyle(Hi.onNeon)
                    }
                    HStack(spacing: 4) {
                        Text(L(record.prompt))
                        if let city = record.city {
                            Text("・")
                            Label(city, systemImage: "mappin")
                        }
                    }
                    .font(.caption).foregroundStyle(Hi.dim).lineLimit(1)
                }
                Spacer(minLength: 0)
                DeletePostMenu(recordID: record.id)
            }
            DualPhotoView(main: image, inset: record.frontPhotoFile.flatMap { store.image(for: $0) })
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .socialPhoto(postID: record.id, canReact: false, allowComments: commentsOn, onComment: open)
            if let caption = record.caption, !caption.isEmpty {
                Text(caption).font(.subheadline)
            }
            CommentLine(postID: record.id, allowComments: commentsOn, onComment: open)
        }
    }

    private func agoText(_ minutes: Int) -> String {
        if minutes < 60 { return LF("{n}分前", ["n": "\(minutes)"]) }
        return LF("{n}時間前", ["n": "\(minutes / 60)"])
    }

    // MARK: - タイムアタック

    private var ranking: some View {
        let mine = PostStore.regionIndex
        return ScrollView {
            VStack(spacing: 14) {
                // 4つの地域から選ぶ（初期は、自分の地域）
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(WorldRanking.regions, id: \.self) { region in
                        let isOn = region == regionSelection
                        Button {
                            regionSelection = region
                        } label: {
                            VStack(spacing: 1) {
                                Text(WorldRanking.regionName(region))
                                    .font(.footnote.weight(.black))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                if region == mine { Text(L("あなたの地域")).font(.system(size: 10, weight: .bold)) }
                            }
                            .foregroundStyle(isOn ? Hi.onNeon : .white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(isOn ? Hi.neon : Hi.tile))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }

                VStack(spacing: -16) {
                    ForEach(Array(board.enumerated()), id: \.element.id) { index, entry in
                        rankCard(position: index + 1, entry: entry)
                    }
                }

                Text(regionNote)
                    .font(.caption)
                    .foregroundStyle(Hi.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.top, 14)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    private var regionNote: String {
        let name = WorldRanking.regionName(regionSelection)
        if regionSelection != PostStore.regionIndex {
            return LF("{n} のランキングです（他の人はサンプル）。あなたの記録は、自分の地域に入ります。", ["n": name])
        }
        return stats.best == nil
            ? LF("{n} のランキングです（他の人はサンプル）。お題に合う写真と確認できた投稿を、ここに並べます。", ["n": name])
            : LF("{n} のランキングです（他の人はサンプル）。お題に合うと確認できた投稿の自己ベストを並べています。", ["n": name])
    }

    private func rankCard(position: Int, entry: WorldRankEntry) -> some View {
        let textColor: Color = entry.isYou ? Hi.onNeon : .white
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text("\(position)")
                    .font(.subheadline.weight(.black))
                    .frame(minWidth: 20, alignment: .leading)
                Text(entry.flag)
                Text(entry.name)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                DotText(text: TimeFormat.string(entry.time), pitch: 3, color: textColor)
            }
            HStack(spacing: 8) {
                Text(entry.rank.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(textColor.opacity(0.8))
                    .padding(.leading, 28)
                TrophyBadges(trophies: entry.trophies, color: textColor)
            }
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 30)
        .background(
            LinearGradient(colors: entry.isYou ? [Hi.neon, Hi.neon.opacity(0.72)] : entry.rank.cardColors,
                           startPoint: .leading, endPoint: .trailing)
                .background(Color.black)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
