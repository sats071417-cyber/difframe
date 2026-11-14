import SwiftUI
import UIKit

/// 今日の画面。お題を大きな光るカードで見せ、通知からのタイムをドットの数字で刻む。
struct TodayView: View {
    @EnvironmentObject private var store: PostStore
    let onCapture: () -> Void
    /// 見えていないときは、タイムの表示を止める（カメラを軽くするため）
    var isActive = true
    @State private var page: String = ""     // いま見ている写真（記録の id）。お題のカードは "open"

    /// いま見せる日（今日の通知の前は、前日）
    private var todayKey: String { store.activeDayKey() }

    var body: some View {
        VStack(spacing: 10) {
            ScreenHeader(title: L("Difframe")) {
                HStack(spacing: 12) { streakBadge; NotificationBell() }
            }
            let posted = todaysPhotos
            let open = store.nextOpenRecord(day: todayKey)
            if store.isPromptHidden() {
                hiddenCard
            } else if posted.isEmpty {
                if let open { promptCard(open) } else { Spacer() }
            } else {
                // 今日撮った写真を、左右にスワイプして見る。まだ撮れるなら、最後のページはお題のカード
                TabView(selection: $page) {
                    ForEach(posted, id: \.record.id) { item in
                        postedCard(item.record, image: item.image).tag(item.record.id)
                    }
                    if let open { promptCard(open).tag("open") }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .onAppear { if page.isEmpty { page = posted.last?.record.id ?? "" } }
                .onChange(of: posted.count) { _, _ in page = posted.last?.record.id ?? page }
                // ページの点（カードの下）。写真と、まだ撮れるときのお題のカード
                let ids = posted.map(\.record.id) + (open == nil ? [] : ["open"])
                if ids.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(ids, id: \.self) { id in
                            Capsule()
                                .fill(id == page ? Color.white : Color.white.opacity(0.3))
                                .frame(width: id == page ? 18 : 7, height: 7)
                        }
                    }
                    .animation(.easeOut(duration: 0.2), value: page)
                    .accessibilityHidden(true)
                }
            }
            summaryTiles
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(background.ignoresSafeArea())
    }

    /// 今日の写真（撮った順）
    private var todaysPhotos: [(record: PromptRecord, image: UIImage)] {
        store.records(day: todayKey)
            .filter { $0.postedPhotoFile != nil }
            .sorted { ($0.postedAt ?? .distantPast) < ($1.postedAt ?? .distantPast) }
            .compactMap { r in r.postedPhotoFile.flatMap { store.image(for: $0) }.map { (r, $0) } }
    }

    /// 色のお題の日は、画面全体をその色に寄せる。ほかの日は黒
    @ViewBuilder
    private var background: some View {
        let prompt = store.activePrompt() ?? ""
        if PromptCatalog.colors[prompt] != nil {
            let palette = GlowPalette.forPrompt(prompt)
            LinearGradient(colors: [palette.bottom.opacity(0.55), palette.top.opacity(0.35), .black],
                           startPoint: .top, endPoint: .bottom)
                .background(Color.black)
        } else {
            Color.black
        }
    }

    private var streakBadge: some View {
        let days = store.currentStreak()
        return Label(LF("{n}日連続", ["n": "\(days)"]), systemImage: "flame.fill")
            .font(.headline.weight(.black))
            .foregroundStyle(days > 0 ? Color.orange : Hi.dim)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityLabel(LF("連続 {n} 日", ["n": "\(days)"]))
    }

    /// まだ投稿していないとき：お題とタイム
    private func promptCard(_ record: PromptRecord) -> some View {
        Button(action: onCapture) {
            ZStack {
                GlowBackground(palette: .forPrompt(record.prompt))
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.dayKey == PostStore.dayKey(for: Date()) ? L("今日のお題") : L("前日のお題（次の通知まで撮れます）"))
                        .font(.subheadline.weight(.bold))
                    Text(L(record.prompt))
                        .font(.system(size: 46, weight: .black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Spacer()
                    if let start = record.startedAt {
                        TimelineView(.animation(minimumInterval: 0.1, paused: !isActive)) { context in
                            let elapsed = context.date.timeIntervalSince(start)
                            VStack(spacing: 8) {
                                if elapsed < 0 {
                                    // 通知が届くまでは、タイムは始まらない
                                    Text(L("通知を待っています"))
                                        .font(.title3.weight(.black))
                                        .foregroundStyle(Color.black.opacity(0.82))
                                    Text(L("通知の前に撮ると、タイムは記録されません"))
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Color.black.opacity(0.6))
                                        .multilineTextAlignment(.center)
                                } else if elapsed < TodayView.lateAfter {
                                    FitDotText(text: TimeFormat.string(elapsed), color: Color.black.opacity(0.82))
                                    Text(L("通知が届いてからの時間"))
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Color.black.opacity(0.6))
                                } else {
                                    // 時間がたったら、タイムを数え続けずに、やさしい表示にする
                                    Text(L("遅れてもOK"))
                                        .font(.system(size: 34, weight: .black))
                                        .foregroundStyle(Color.black.opacity(0.82))
                                    Text(LF("あと{n}枚撮れます", ["n": "\(PromptSlot.maxPerDay - store.postedCount(day: todayKey))"]))
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Color.black.opacity(0.6))
                                }
                                captureLabel(elapsed < 0 ? L("先に撮る（タイムなし）") : L("タップして撮る"))
                                    .padding(.top, 6)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        captureLabel(L("タップして撮る"))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LF("今日のお題 {p}。撮影に進む", ["p": L(record.prompt)]))
    }

    /// はじめての日：通知が届くまで、お題を伏せる
    private var hiddenCard: some View {
        let start = store.records(day: PostStore.dayKey(for: Date())).compactMap(\.startedAt).min()
        return ZStack {
            GlowBackground(palette: .forPrompt("?"))
            VStack(spacing: 12) {
                Image(systemName: "bell.badge.fill").font(.system(size: 44))
                Text(L("今日のお題は、通知で届きます")).font(.title2.weight(.black)).multilineTextAlignment(.center)
                Text(L("届くまで、お題はヒミツです。届いた瞬間から、タイムが始まります。"))
                    .font(.subheadline.weight(.bold)).multilineTextAlignment(.center).opacity(0.8)
                if let start {
                    Text(LF("通知は {t} ごろ", ["t": start.formatted(date: .omitted, time: .shortened)]))
                        .font(.caption.weight(.bold)).opacity(0.7)
                }
            }
            .foregroundStyle(Color.black.opacity(0.82))
            .padding(24)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    /// 通知からこの時間（秒）を過ぎたら、タイムの代わりに「遅れてもOK」を出す
    static let lateAfter: TimeInterval = 10 * 60

    private func captureLabel(_ text: String) -> some View {
        Label(text, systemImage: "camera.fill")
            .font(.subheadline.weight(.black))
            .foregroundStyle(Hi.onNeon)
            .padding(.horizontal, 18).frame(height: 44)
            .background(Capsule().fill(Hi.neon))
            .frame(maxWidth: .infinity)
    }

    /// 投稿済みのとき：自分の写真とタイム
    private func postedCard(_ record: PromptRecord, image: UIImage) -> some View {
        DualPhotoView(main: image, inset: record.frontPhotoFile.flatMap { store.image(for: $0) })
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L(record.prompt)).font(.title2.weight(.black))
                        if record.verified == true {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Hi.neon)
                                .accessibilityLabel(L("お題に合う写真"))
                        }
                        Text("\(store.postedCount(day: todayKey))/\(PromptSlot.maxPerDay)")
                            .font(.caption.weight(.black))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.25)))
                            .accessibilityLabel(LF("今日 {n} 枚投稿", ["n": "\(store.postedCount(day: todayKey))"]))
                        Spacer()
                        if let elapsed = record.elapsed {
                            DotText(text: TimeFormat.string(elapsed), pitch: 4, color: Hi.neon)
                        }
                    }
                    if store.nextOpenRecord(day: todayKey) != nil {
                        Text(LF("真ん中のボタンで、あと{n}枚撮れます。遅れてもOK", ["n": "\(PromptSlot.maxPerDay - store.postedCount(day: todayKey))"]))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    } else {
                        Text(LF("今日は{n}枚すべて投稿しました。次のお題は明日届きます", ["n": "\(PromptSlot.maxPerDay)"]))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    if let caption = record.caption, !caption.isEmpty {
                        Text(caption).font(.subheadline)
                    }
                }
                .foregroundStyle(.white)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [.black.opacity(0), .black.opacity(0.8)],
                                   startPoint: .top, endPoint: .bottom)
                )
            }
            .overlay(alignment: .topTrailing) { DeletePostMenu(recordID: record.id).padding(12) }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var summaryTiles: some View {
        let monthly = MonthlyPoints(records: store.records, month: MonthlyPoints.monthKey(for: Date()))
        let position = WorldRanking.position(myBest: TimeAttackStats(records: store.records).best)
        return HStack(spacing: 10) {
            tile(title: L("今月のランク"), value: monthly.rank.name, note: L("投稿で貯めたポイントで決まります"), color: monthly.rank.color)
            tile(title: L("地域の最速順位"), value: position.map { LF("{n}位", ["n": "\($0)"]) } ?? L("まだありません"), note: L("お題に合う写真を撮ると入ります"), color: .white)
        }
    }

    private func tile(title: String, value: String, note: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Hi.dim)
            Text(value).font(.headline.weight(.black)).foregroundStyle(color)
            Text(note).font(.caption2).foregroundStyle(Hi.dim).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .hiTile()
    }
}

/// タイムの表示（例：1:23.4。1時間を超えたら 10:17:41）
enum TimeFormat {
    static func string(_ seconds: TimeInterval) -> String {
        let total = max(0, seconds)
        if total >= 3600 {
            let whole = Int(total)
            return String(format: "%d:%02d:%02d", whole / 3600, (whole % 3600) / 60, whole % 60)
        }
        // 0.1秒単位で数えてから分けると、秒が 60.0 と表示されるずれが起きない
        let tenths = Int(total * 10)
        return String(format: "%d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
    }
}


/// 自分の投稿を消すメニュー。消す前に確認する。
struct DeletePostMenu: View {
    @EnvironmentObject private var store: PostStore
    let recordID: String
    var onDeleted: () -> Void = {}
    @State private var confirm = false
    @State private var editingCaption = false
    @State private var shareImage: UIImage? = nil
    @State private var showShare = false
    @State private var saveMessage: String? = nil
    @AppStorage("myHandle") private var myHandle: String = ""

    var body: some View {
        Menu {
            Button {
                editingCaption = true
            } label: {
                Label(L("一言を編集"), systemImage: "pencil")
            }
            Button {
                saveCard()
            } label: {
                Label(L("カメラロールに保存"), systemImage: "square.and.arrow.down")
            }
            Button {
                if let card = makeCard() { shareImage = card; showShare = true }
            } label: {
                Label(L("シェア（ストーリーなど）"), systemImage: "square.and.arrow.up")
            }
            // みんな（公開）の投稿で、コメントを受け付けるか（あとから変えられる）
            let record = store.records.first { $0.id == recordID }
            let off = record?.publicCommentsOff == true
            if record?.isForPublic ?? true {
                Button {
                    store.setPublicComments(id: recordID, on: off)
                } label: {
                    Label(off ? L("みんなからのコメントをオンにする") : L("みんなからのコメントをオフにする"),
                          systemImage: off ? "bubble.left" : "bubble.left.and.exclamationmark.bubble.right")
                }
            }
            Button(role: .destructive) { confirm = true } label: {
                Label(L("投稿を削除"), systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.black.opacity(0.45)))
                .contentShape(Circle())
        }
        .accessibilityLabel(L("投稿のメニュー"))
        .sheet(isPresented: $editingCaption) {
            CaptionEditSheet(recordID: recordID)
                .environmentObject(store)
        }
        .sheet(isPresented: $showShare) {
            if let shareImage { ActivitySheet(items: [shareImage]) }
        }
        .alert(saveMessage ?? "", isPresented: Binding(get: { saveMessage != nil }, set: { if !$0 { saveMessage = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .confirmationDialog(L("この投稿を削除しますか？"), isPresented: $confirm, titleVisibility: .visible) {
            Button(L("削除する"), role: .destructive) {
                store.deletePost(id: recordID)
                onDeleted()
            }
            Button(L("キャンセル"), role: .cancel) {}
        } message: {
            Text(L("写真は元に戻せません。消すと、この枠でもう一度撮れます。"))
        }
    }
}


/// 2枚撮りの写真：大きい写真の上に、小さい写真を重ねる。
/// 小さい写真は指で好きな場所へ動かせて、離すと近い方の上の角に戻る。押すと大きい写真と入れ替わる。
struct DualPhotoView: View {
    let main: UIImage
    let inset: UIImage?
    var insetRatio: CGFloat = 0.3
    @State private var swapped = false
    @State private var drag: CGSize = .zero
    @State private var onLeft = true      // 小さい写真が、上の左右どちらの角にいるか
    @State private var zoom: CGFloat = 1
    @State private var zoomAnchor: UnitPoint = .center
    @State private var pan: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let big = swapped ? (inset ?? main) : main
            let small: UIImage? = inset == nil ? nil : (swapped ? main : inset)
            let side = geo.size.width * insetRatio
            let margin: CGFloat = 14
            ZStack(alignment: onLeft ? .topLeading : .topTrailing) {
                Color.clear
                    .overlay(Image(uiImage: big).resizable().scaledToFill())
                    .clipped()
                    .scaleEffect(zoom, anchor: zoomAnchor)
                    .offset(pan)
                    .clipped()
                    // 2本指でつまむと拡大。指を動かすと一緒に動き、離すと元に戻る
                    .overlay(PinchCatcher { scale, anchor, move in
                        zoomAnchor = anchor
                        zoom = max(1, min(scale, 5))
                        pan = move
                    } onEnd: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            zoom = 1
                            pan = .zero
                        }
                    })
                if let small, zoom <= 1.01 {
                    Image(uiImage: small)
                        .resizable()
                        .scaledToFill()
                        .frame(width: side, height: side / PhotoShape.ratio)
                        .clipShape(RoundedRectangle(cornerRadius: side * 0.18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: side * 0.18, style: .continuous)
                            .stroke(Color.black.opacity(0.7), lineWidth: 2))
                        .shadow(color: .black.opacity(0.3), radius: 6)
                        .padding(margin)
                        .offset(drag)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) { swapped.toggle() }
                        }
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 4)
                                .onChanged { drag = $0.translation }
                                .onEnded { value in
                                    // 離した位置に近い方の、上の角へ戻る
                                    let startX = onLeft ? margin + side / 2 : geo.size.width - margin - side / 2
                                    let endX = startX + value.translation.width
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        onLeft = endX < geo.size.width / 2
                                        drag = .zero
                                    }
                                }
                        )
                        .accessibilityLabel(L("小さい写真（押すと入れ替え）"))
                        .accessibilityAddTraits(.isButton)
                }
            }
        }
    }
}

/// 2本指のピンチだけを受け取る透明な板。1本指の操作（スワイプ・タップ）は下や親にそのまま通す
struct PinchCatcher: UIViewRepresentable {
    var onChange: (CGFloat, UnitPoint, CGSize) -> Void
    var onEnd: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handle(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PinchCatcher
        private var start: CGPoint = .zero
        private var anchor: UnitPoint = .center

        init(parent: PinchCatcher) { self.parent = parent }

        @objc func handle(_ g: UIPinchGestureRecognizer) {
            guard let view = g.view else { return }
            let p = g.location(in: view)
            switch g.state {
            case .began:
                start = p
                let w = max(view.bounds.width, 1), h = max(view.bounds.height, 1)
                anchor = UnitPoint(x: p.x / w, y: p.y / h)
                parent.onChange(g.scale, anchor, .zero)
            case .changed:
                // 指を2本→1本にした瞬間などは位置が飛ぶので、2本のときだけ動かす
                guard g.numberOfTouches >= 2 else { return }
                parent.onChange(g.scale, anchor, CGSize(width: p.x - start.x, height: p.y - start.y))
            default:
                parent.onEnd()
            }
        }

        // 親のスクロール（写真の横スワイプ）とは同時に動いてよい
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

extension DeletePostMenu {
    /// この投稿の、共有用の画像
    @MainActor
    func makeCard() -> UIImage? {
        guard let record = store.records.first(where: { $0.id == recordID }),
              let file = record.postedPhotoFile, let photo = store.image(for: file) else { return nil }
        let inset = record.frontPhotoFile.flatMap { store.image(for: $0) }
        return ShareCard.make(record: record, photo: photo, inset: inset, handle: MyProfile.handle(myHandle))
    }

    @MainActor
    func saveCard() {
        guard let card = makeCard() else { return }
        ShareCard.saveToLibrary(card) { message in
            saveMessage = message
        }
    }
}

/// 投稿の一言を、あとから書き換える画面
struct CaptionEditSheet: View {
    @EnvironmentObject private var store: PostStore
    @Environment(\.dismiss) private var dismiss
    let recordID: String
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField(L("一言（任意）"), text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focused)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Hi.tile))
                Text(L("空にすると、一言は消えます。"))
                    .font(.caption).foregroundStyle(Hi.dim)
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(L("一言を編集"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("キャンセル")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("保存")) {
                        store.updateCaption(id: recordID, caption: text)
                        dismiss()
                    }
                    .fontWeight(.black)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(.black)
        .preferredColorScheme(.dark)
        .onAppear {
            text = store.records.first { $0.id == recordID }?.caption ?? ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { focused = true }
        }
    }
}
