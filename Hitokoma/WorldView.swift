import SwiftUI
import CoreLocation

/// 世界の画面：同じお題を、世界のどこで・いつ撮ったかを見せる。地図が主役。
/// 「地図」「タイムライン」「タイムアタック」を切り替える。
struct WorldView: View {
    private enum Mode: Hashable { case now, ranking }

    /// true のときは、世界の投稿の一覧だけを出す（タイムラインの「みんな」）
    var feedOnly = false
    /// タブのスワイプを止める先。タイムラインの「みんな」の中に置くときは、タイムラインのタブ
    private var gateTab: AppTab { feedOnly ? .friends : .world }
    /// 見えていないときは地図を描かない（裏で地図が動くと、カメラが重くなるため）
    var isActive = true

    @EnvironmentObject private var store: PostStore
    @ObservedObject private var cloud = CloudSync.shared
    @AppStorage("myHandle") private var myHandle: String = ""
    @AppStorage("friendList") private var friendList: String = MyProfile.defaultFriends
    @State private var mode: Mode = .now
    @State private var selectedID: String? = nil
    @State private var base = Date()
    @State private var regionSelection = PostStore.regionIndex   // タイムアタックで見ている地域
    @State private var commentTarget: CommentTarget? = nil
    @State private var mapCity: String? = nil
    @ObservedObject private var focus = WorldFocus.shared
    @State private var regionSheet: WorldRegion? = nil
    @State private var regionPos: Int? = 0
    @State private var dotsWidth: CGFloat = 0   // 点々の幅（なぞった位置を、どの都市にするかに使う）

    /// 世界の人の本物の公開投稿のうち、場所（都市の中心あたり）がわかるもの
    private var pins: [WorldPin] { cloud.publicPosts.compactMap(WorldPin.init) }

    /// いま見せるお題（今日の通知の前は前日。はじめての日は伏せる）
    private var prompt: String { store.activePrompt() ?? "？" }
    private var stats: TimeAttackStats { TimeAttackStats(records: store.records) }

    private var board: [WorldRankEntry] {
        let input = AchievementInput(records: store.records, friendCount: MyProfile.friendCount(friendList))
        let monthly = MonthlyPoints(records: store.records, month: MonthlyPoints.monthKey(for: Date()))
        let todayBest = store.records(day: store.activeDayKey()).compactMap(\.elapsed).min()
        return WorldRanking.board(region: regionSelection, others: cloud.worldTimes, myBest: todayBest,
                                  myName: "@" + MyProfile.handle(myHandle),
                                  myTrophies: Trophy.allCases.filter { $0.isUnlocked(input) },
                                  myRank: monthly.rank, ranks: cloud.worldRanks)
    }

    var body: some View {
        if feedOnly {
            timeline
                .fullScreenCover(item: Binding(get: { mapCity.map { MapCityTarget(id: $0) } }, set: { mapCity = $0?.id })) {
                    LocationMapSheet(city: $0.id, latitude: nil, longitude: nil, photo: myLatestPhoto)
                }
                .fullScreenCover(item: $commentTarget) { target in
                    CommentSheet(postID: target.id, owner: target.owner, caption: target.caption,
                                 image: target.image, front: target.front, prompt: target.prompt, cloudID: target.cloudID, ownRecordID: target.ownRecordID)
                        .environmentObject(store)
                }
                .fullScreenCover(item: $regionSheet) { RegionPostsSheet(region: $0, base: base).environmentObject(store) }
        } else {
            worldBody
                .fullScreenCover(item: $regionSheet) { RegionPostsSheet(region: $0, base: base).environmentObject(store) }
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
                            WorldMapView(samples: pins, base: base, myPhoto: myLatestPhoto, focus: focus.request, selectedID: $selectedID)
                        } else {
                            Color.black
                        }
                    }
                        .frame(maxHeight: .infinity)
                        .overlay(alignment: .bottom) {
                            // 地図の下の Apple のロゴと「法律に基づく情報」は隠さない（上に余白を取る）
                            mapBottom.padding(.horizontal, 10).padding(.bottom, 40)
                        }
                        .overlay(alignment: .topLeading) { regionBadge.padding(10) }
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
        .task { await cloud.refresh() }
        .onChange(of: focus.request?.id) { _, _ in mode = .now }
    }

    /// 「世界の今」から来たときの、左上のボタン（押すと、その地域の投稿）
    @ViewBuilder
    private var regionBadge: some View {
        if let region = focus.request?.region {
            HStack(spacing: 4) {
                Button { regionSheet = region } label: {
                    HStack(spacing: 6) {
                        Text(region.flag)
                        Text(LF("{c}の投稿", ["c": L(region.city)])).font(.subheadline.weight(.black))
                        Image(systemName: "chevron.right").font(.caption.weight(.black))
                    }
                    .foregroundStyle(.white)
                    .padding(.leading, 12).padding(.trailing, 10)
                    .frame(height: 38)
                }
                .buttonStyle(.plain)
                Button { focus.request = nil } label: {
                    Image(systemName: "xmark").font(.caption.weight(.black)).foregroundStyle(.white.opacity(0.8))
                        .frame(width: 30, height: 38)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("閉じる"))
            }
            .background(Capsule().fill(Color.black.opacity(0.7)))
        }
    }

    // MARK: - 地図の下：選んだ投稿のカード、または投稿の一覧

    @ViewBuilder
    private var mapBottom: some View {
        if let pin = pins.first(where: { $0.id == selectedID }) {
            cityCard(pin)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if pins.isEmpty {
            Text(L("まだ世界の公開投稿はありません"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Capsule().fill(Color.black.opacity(0.65)))
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pins.sorted { $0.postedAt > $1.postedAt }) { pin in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selectedID = pin.id }
                        } label: {
                            pinName(pin)
                                .font(.subheadline.weight(.bold)).lineLimit(1)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .frame(height: 38)
                                .background(Capsule().fill(Color.black.opacity(0.65)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .blocksTabSwipe(gateTab, id: "pins")
        }
    }

    /// 選んだ投稿のカード：本物の写真、都市、現地時刻、タイム
    /// 都市の名前（見る人の言語）。名前がなければ、投稿した人の @ハンドル
    @ViewBuilder
    private func pinName(_ pin: WorldPin) -> some View {
        if pin.city.isEmpty { Text("@" + pin.handle) } else { CityText(city: pin.city, latitude: pin.latitude, longitude: pin.longitude) }
    }

    private func cityCard(_ pin: WorldPin) -> some View {
        let light = pin.light(base: base)
        return HStack(spacing: 12) {
            ZStack {
                if let photo = pin.photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else {
                    GlowBackground(palette: light.palette, focus: .center)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                pinName(pin).font(.headline.weight(.black))
                Text(LF("現地 {t}", ["t": pin.localTime(base: base)]) + "・" + light.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Hi.dim)
                HStack(spacing: 6) {
                    Text("@" + pin.handle)
                    if let elapsed = pin.elapsed { Text(TimeFormat.string(elapsed)) }
                }
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

    private var timeline: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                Color.clear.frame(height: 0).reportScroll(tag: 1)
                // 自分の投稿（みんなにも出る。コメントを受け付けるかは、自分で選べる）
                if !myPublicPosts.isEmpty { myStrip }
                // 毎朝、世界の公開投稿からランダムに10枚（同じ日は、同じ10枚）
                pickupStrip
                // サーバーから届いた、世界の人の本物の投稿
                ForEach(cloud.publicPosts) { post in
                    CloudPostCard(post: post) { commentTarget = $0 }
                        .riseIn()
                }
                if cloud.publicPosts.isEmpty {
                    VStack(spacing: 4) {
                        Text(L("まだ世界の公開投稿はありません")).font(.subheadline.weight(.black))
                        Text(L("公開で投稿すると、世界のみんなの地図と一覧に出ます。"))
                            .font(.caption).foregroundStyle(Hi.dim)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
            }
            .padding(.horizontal, 16)
        }
        .coordinateSpace(name: "feedScroll")
        .refreshable { await cloud.refresh(force: true) }
    }

    /// 自分のピンの上に出す、今日いちばん新しい自分の写真（公開でなくても、自分の画面にだけ出す）
    private var myLatestPhoto: UIImage? {
        store.records(day: store.activeDayKey())
            .filter { $0.postedPhotoFile != nil }
            .max { ($0.postedAt ?? .distantPast) < ($1.postedAt ?? .distantPast) }
            .flatMap { $0.postedPhotoFile }.flatMap { store.image(for: $0) }
    }

    /// みんなに出す、自分の投稿（いま見せる日のもの）
    private var myPublicPosts: [(record: PromptRecord, image: UIImage)] {
        store.records(day: store.activeDayKey())
            .filter { $0.postedPhotoFile != nil && $0.isForPublic }
            .sorted { ($0.postedAt ?? .distantPast) > ($1.postedAt ?? .distantPast) }
            .compactMap { r in r.postedPhotoFile.flatMap { store.image(for: $0) }.map { (r, $0) } }
    }

    /// 自分の今日の投稿は、みんなの画面の上に小さく一列にまとめる（押すと、写真とコメントを開く）
    /// 世界12都市の、いまの光・あいさつ・時刻（時計から計算するので、いつでも本物）
    private static let regionClocks = WorldRegion.all

    private var pickupStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("世界の今")).font(.subheadline.weight(.black))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) { ForEach(Self.regionClocks) { regionCard($0).id($0.id) } }
                    .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $regionPos)
            .sensoryFeedback(.selection, trigger: regionPos)
            .blocksTabSwipe(gateTab, id: "clocks")   // 横にスワイプしても、タブは切り替えない
            HStack { Spacer(); regionDots; Spacer() }
        }
    }

    /// 点々：なぞると、その位置の都市へ送れる（タブは切り替えない）
    private var regionDots: some View {
        PillIndicator(count: Self.regionClocks.count, index: regionPos ?? 0)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { dotsWidth = g.size.width }
                    .onChange(of: g.size.width) { _, w in dotsWidth = w }
            })
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let n = Self.regionClocks.count
                        guard dotsWidth > 0, n > 0 else { return }
                        let i = min(n - 1, max(0, Int(v.location.x / dotsWidth * CGFloat(n))))
                        let id = Self.regionClocks[i].id
                        if regionPos != id {
                            withAnimation(.easeOut(duration: 0.25)) { regionPos = id }
                        }
                    }
            )
            .blocksTabSwipe(gateTab, id: "dots")
    }

    private func regionCard(_ clock: WorldRegion) -> some View {
        let tz = TimeZone(identifier: clock.zone) ?? .gmt
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let hour = calendar.component(.hour, from: base)
        let light = LocalLight(hour: hour)
        let time = Clock.string(base, zone: tz)
        // 押すと「世界」の地図がその地域へ。長押しで、その地域の投稿
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            focus.request = WorldFocusRequest(region: clock)
        } label: {
            ZStack(alignment: .topLeading) {
                GlowBackground(palette: light.palette)
                VStack(alignment: .leading, spacing: 0) {
                    Label(light.name, systemImage: light.icon).font(.caption.weight(.black))
                    Spacer()
                    Text("「\(clock.greeting)」").font(.footnote.weight(.black)).lineLimit(1)
                    Text("\(clock.flag) \(L(clock.city))").font(.subheadline.weight(.black)).lineLimit(1)
                    Text(LF("現地 {t}", ["t": time])).font(.caption.weight(.bold).monospacedDigit())
                }
                .foregroundStyle(light.textColor)
                .padding(12)
            }
            .frame(width: 150, height: 116)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { regionSheet = clock } label: { Label(L("この地域の投稿を見る"), systemImage: "photo.on.rectangle") }
            Button { focus.request = WorldFocusRequest(region: clock) } label: { Label(L("地図で見る"), systemImage: "map") }
        }
        .accessibilityLabel("\(L(clock.city)) \(time) \(light.name)")
    }

    private var myStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(myPublicPosts, id: \.record.id) { item in
                    Button {
                        commentTarget = CommentTarget(id: item.record.id, owner: L("あなた"), caption: item.record.caption,
                                                      image: item.image, cloudID: cloud.cloudID(for: item.record.id), ownRecordID: item.record.id)
                    } label: {
                        VStack(spacing: 6) {
                            Image(uiImage: item.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 66, height: 66)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Hi.neon, lineWidth: 2.5))
                            Text(L("自分")).font(.caption.weight(.black)).foregroundStyle(.white)
                            if let at = item.record.postedAt {
                                Text(at.appFormatted(date: .omitted, time: .shortened))
                                    .font(.caption2).foregroundStyle(Hi.dim)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func myPublicCard(_ record: PromptRecord, image: UIImage) -> some View {
        let commentsOn = record.publicCommentsOff != true
        let open = {
            commentTarget = CommentTarget(id: record.id, owner: L("あなた"), caption: record.caption, image: image,
                                          cloudID: cloud.cloudID(for: record.id), ownRecordID: record.id)
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
                            Button { mapCity = city } label: { Label(city, systemImage: "mappin").foregroundStyle(Hi.neon) }
                                .buttonStyle(.plain)
                        }
                    }
                    .font(.caption).foregroundStyle(Hi.dim).lineLimit(1)
                }
                Spacer(minLength: 0)
                DeletePostMenu(recordID: record.id)
            }
            DualPhotoView(main: image, inset: record.frontPhotoFile.flatMap { store.image(for: $0) })
                .aspectRatio(PhotoShape.ratio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .socialPhoto(postID: record.id, canReact: false, allowComments: commentsOn, onComment: open)
            if let caption = record.caption, !caption.isEmpty {
                Text(caption).font(.subheadline)
            }
            CommentLine(postID: record.id, allowComments: commentsOn, cloudID: cloud.cloudID(for: record.id), onComment: open)
        }
    }

    // MARK: - タイムアタック

    private var ranking: some View {
        let mine = PostStore.regionIndex
        return ScrollView {
            VStack(spacing: 14) {
                // 4つの地域から選ぶ（初期は、自分の地域）
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach([mine, WorldRanking.world], id: \.self) { region in
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

                if board.isEmpty {
                    Text(L("お題に合う写真を撮ると入ります"))
                        .font(.subheadline.weight(.bold)).foregroundStyle(Hi.dim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                } else {
                    VStack(spacing: -16) {
                        ForEach(Array(board.enumerated()), id: \.element.id) { index, entry in
                            rankCard(position: index + 1, entry: entry)
                        }
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
        LF("{n} の、今日のタイムのランキングです。公開で投稿した人が入ります。", ["n": WorldRanking.regionName(regionSelection)])
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

struct MapCityTarget: Identifiable { let id: String }


// MARK: - 世界の今：地域

/// 「世界の今」に並ぶ12都市（時計から、いまの光・あいさつ・時刻を出す）
struct WorldRegion: Identifiable, Equatable {
    let id: Int
    let city: String
    let flag: String
    let zone: String
    let greeting: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    static func == (a: WorldRegion, b: WorldRegion) -> Bool { a.id == b.id }

    static let all = [
        WorldRegion(id: 0, city: "シドニー", flag: "🇦🇺", zone: "Australia/Sydney", greeting: "G'day", latitude: -33.9, longitude: 151.2),
        WorldRegion(id: 1, city: "東京", flag: "🇯🇵", zone: "Asia/Tokyo", greeting: "やあ", latitude: 35.7, longitude: 139.7),
        WorldRegion(id: 2, city: "ソウル", flag: "🇰🇷", zone: "Asia/Seoul", greeting: "안녕", latitude: 37.6, longitude: 127.0),
        WorldRegion(id: 3, city: "シンガポール", flag: "🇸🇬", zone: "Asia/Singapore", greeting: "你好", latitude: 1.4, longitude: 103.8),
        WorldRegion(id: 4, city: "ムンバイ", flag: "🇮🇳", zone: "Asia/Kolkata", greeting: "नमस्ते", latitude: 19.1, longitude: 72.9),
        WorldRegion(id: 5, city: "カイロ", flag: "🇪🇬", zone: "Africa/Cairo", greeting: "مرحبا", latitude: 30.0, longitude: 31.2),
        WorldRegion(id: 6, city: "ナイロビ", flag: "🇰🇪", zone: "Africa/Nairobi", greeting: "Jambo", latitude: -1.3, longitude: 36.8),
        WorldRegion(id: 7, city: "パリ", flag: "🇫🇷", zone: "Europe/Paris", greeting: "Salut", latitude: 48.9, longitude: 2.4),
        WorldRegion(id: 8, city: "レイキャビク", flag: "🇮🇸", zone: "Atlantic/Reykjavik", greeting: "Halló", latitude: 64.1, longitude: -21.9),
        WorldRegion(id: 9, city: "サンパウロ", flag: "🇧🇷", zone: "America/Sao_Paulo", greeting: "Oi", latitude: -23.5, longitude: -46.6),
        WorldRegion(id: 10, city: "ニューヨーク", flag: "🇺🇸", zone: "America/New_York", greeting: "Hey", latitude: 40.7, longitude: -74.0),
        WorldRegion(id: 11, city: "バンクーバー", flag: "🇨🇦", zone: "America/Vancouver", greeting: "Hi", latitude: 49.3, longitude: -123.1),
    ]
}

/// 地図を動かす頼み（「世界の今」を押したとき）
struct WorldFocusRequest: Equatable {
    let id = UUID()
    let region: WorldRegion
    var coordinate: CLLocationCoordinate2D { region.coordinate }
    static func == (a: WorldFocusRequest, b: WorldFocusRequest) -> Bool { a.id == b.id }
}

/// タイムラインの「世界の今」から、「世界」タブの地図へ橋渡しする
@MainActor
final class WorldFocus: ObservableObject {
    static let shared = WorldFocus()
    @Published var request: WorldFocusRequest? = nil
}

/// ある地域の、世界の公開投稿の一覧
struct RegionPostsSheet: View {
    let region: WorldRegion
    let base: Date
    @ObservedObject private var cloud = CloudSync.shared
    @EnvironmentObject private var store: PostStore
    @Environment(\.dismiss) private var dismiss
    @State private var commentTarget: CommentTarget? = nil

    private var posts: [CloudPost] {
        let offset = (TimeZone(identifier: region.zone) ?? .gmt).secondsFromGMT(for: base)
        return cloud.publicPosts.filter { abs($0.tzOffset - offset) <= 3600 }.sorted { $0.postedAt > $1.postedAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 32, height: 32).background(Circle().fill(Color.white.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("戻る"))
                Text("\(region.flag) " + LF("{c}の投稿", ["c": L(region.city)])).font(.headline.weight(.black))
                Spacer()
            }
            .padding(16)
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(posts) { post in
                        CloudPostCard(post: post) { commentTarget = $0 }
                            .riseIn()
                    }
                    if posts.isEmpty {
                        Text(L("この地域の投稿は、まだありません"))
                            .font(.subheadline.weight(.bold)).foregroundStyle(Hi.dim)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $commentTarget) { target in
            CommentSheet(postID: target.id, owner: target.owner, caption: target.caption,
                         image: target.image, front: target.front, prompt: target.prompt, cloudID: target.cloudID, ownRecordID: target.ownRecordID)
                .environmentObject(store)
        }
    }
}
