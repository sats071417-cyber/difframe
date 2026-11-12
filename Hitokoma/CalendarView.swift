import SwiftUI

/// 自分の投稿だけをカレンダーで見る。日付をタップすると、その日の履歴（お題と写真）が出る。
/// 下の一覧は、過去のお題をいつでも開ける履歴。
struct CalendarView: View {
    @EnvironmentObject private var store: PostStore
    @State private var month = Date()
    @State private var selectedKey: String? = nil
    @State private var viewerID: String? = nil               // 大きく見る写真
    @State private var commentTarget: CommentTarget? = nil  // コメントを書く・読む

    private var calendar: Calendar { Calendar(identifier: .gregorian) }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = L("yyyy年M月")
        return f.string(from: month)
    }

    /// 表示する月の日付（先頭の空白を含む）
    private var days: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month))
        else { return [] }
        let leading = calendar.component(.weekday, from: first) - 1
        var result: [Date?] = Array(repeating: nil, count: leading)
        for day in range {
            result.append(calendar.date(byAdding: .day, value: day - 1, to: first))
        }
        return result
    }

    /// 履歴（お題が出た日の一覧。新しい順）
    private var history: [String] {
        Array(Set(store.records.map(\.dayKey))).sorted(by: >)
    }

    /// プロフィールの中に置くときは true（見出しと背景は、プロフィール側に任せる）
    var embedded = false

    var body: some View {
        if embedded {
            content
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ScreenHeader(title: L("カレンダー"))
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(Color.black.ignoresSafeArea())
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            EmptyView()
                .fullScreenCover(isPresented: Binding(get: { viewerID != nil }, set: { if !$0 { viewerID = nil } })) {
                    PhotoViewer(startID: viewerID ?? "")
                        .environmentObject(store)
                }
                .sheet(item: $commentTarget) { target in
                    CommentSheet(postID: target.id, owner: target.owner, caption: target.caption,
                                 image: target.image, prompt: target.prompt)
                        .environmentObject(store)
                }
            header
            grid
            if let key = selectedKey {
                dayDetail(key)
            }
            Text(L("お題の履歴")).font(.title3.weight(.black))
            if history.isEmpty {
                Text(L("お題が届くと、ここに並びます")).foregroundStyle(Hi.dim)
            }
            ForEach(history, id: \.self) { key in
                historyRow(key)
            }
        }
    }

    private var header: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(monthTitle).font(.title3.bold())
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
        }
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible()), count: 7)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach([L("日"), L("月"), L("火"), L("水"), L("木"), L("金"), L("土")], id: \.self) { w in
                Text(w).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                dayCell(date)
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ date: Date?) -> some View {
        if let date {
            let key = PostStore.dayKey(for: date)
            let record = store.latestPosted(day: key) ?? store.record(day: key, slot: .morning)
            let hasPost = store.hasPosted(day: key)
            Button {
                selectedKey = key
            } label: {
                Text("\(calendar.component(.day, from: date))")
                    .font(.callout.weight(hasPost ? .black : .regular))
                    .foregroundStyle(hasPost ? Color.black.opacity(0.85) : (record != nil ? Color.white : Hi.dim))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background {
                        if hasPost, let record {
                            GlowBackground(palette: .forPrompt(record.prompt), focus: .center)
                        } else {
                            Hi.tile
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        if selectedKey == key {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Hi.neon, lineWidth: 2)
                        }
                    }
            }
            .buttonStyle(.plain)
        } else {
            Text("")
        }
    }

    /// その日の履歴（お題と、投稿した写真）
    private func dayDetail(_ key: String) -> some View {
        let all = store.records(day: key)
        let posted = all.filter { $0.postedPhotoFile != nil }
        return VStack(alignment: .leading, spacing: 16) {
            Text(key).font(.headline)
            if let first = all.first {
                Text(LF("お題：{p}", ["p": L(first.prompt)])).font(.title3.weight(.black))
            } else {
                Text(L("お題はありません")).foregroundStyle(Hi.dim)
            }
            if posted.isEmpty && !all.isEmpty {
                Text(L("投稿はありません")).foregroundStyle(Hi.dim)
            }
            ForEach(posted) { record in
                if let file = record.postedPhotoFile, let image = store.image(for: file) {
                    VStack(alignment: .leading, spacing: 8) {
                        // 押すと、全画面で大きく見られる（ピンチで拡大）
                        Button {
                            viewerID = record.id
                        } label: {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("写真を大きく見る"))
                        if let caption = record.caption, !caption.isEmpty {
                            Text(caption).font(.subheadline)
                        }
                        // その投稿のコメント（全部見られる）
                        let list = store.comments(for: record.id)
                        if list.isEmpty {
                            Text(L("まだコメントはありません")).font(.caption).foregroundStyle(Hi.dim)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(list) { comment in
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text(comment.text).font(.subheadline)
                                        Spacer(minLength: 0)
                                        Text(comment.date, style: .time).font(.caption2).foregroundStyle(Hi.dim)
                                    }
                                }
                            }
                        }
                        Button {
                            commentTarget = CommentTarget(id: record.id, owner: L("あなた"), caption: record.caption, image: image)
                        } label: {
                            Label(L("コメントを書く"), systemImage: "bubble.left")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Hi.neon)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Hi.tile)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func historyRow(_ key: String) -> some View {
        Button {
            selectedKey = key
        } label: {
            HStack {
                Text(key).font(.callout.monospacedDigit())
                Spacer()
                let posts = store.postedCount(day: key)
                Text(LF("投稿 {a}/{b}", ["a": "\(posts)", "b": "\(PromptSlot.maxPerDay)"]))
                    .font(.caption)
                    .foregroundStyle(posts > 0 ? Hi.neon : Hi.dim)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func shiftMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: month) {
            month = next
            selectedKey = nil
        }
    }
}
