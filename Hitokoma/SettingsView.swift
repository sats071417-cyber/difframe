import SwiftUI

/// プロフィールの右上の「設定」。ここで変えた内容は、すぐにアプリ全体へ反映される
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var languageRaw = ""
    @AppStorage(Account.phoneKey) private var phone: String = ""
    @AppStorage(NotificationScheduler.zoneKey) private var zoneID: String = ""
    @AppStorage("mute.comment") private var muteComment = false
    @AppStorage("mute.like") private var muteLike = false
    @AppStorage("mute.friendRequest") private var muteRequest = false
    @AppStorage("mute.friendAccepted") private var muteAccepted = false
    @AppStorage("mute.friendPost") private var mutePost = false
    @AppStorage("mute.message") private var muteMessage = false
    // 撮影
    @AppStorage("dualCamera") private var dualCamera = true
    // 投稿の初期設定（次の投稿の、最初の選択になる）
    @AppStorage("shareFriends") private var sendFriends = true
    @AppStorage("sharePublic") private var sendPublic = true
    @AppStorage("publicCommentsDefault") private var publicComments = true
    @AppStorage("shareLocation") private var addLocation = true

    @State private var changingPhone = false

    /// 問い合わせの送り先（公開前に、実際の窓口のアドレスに変えること）
    static let supportEmail = "support@example.com"

    private var zoneLabel: String {
        if zoneID.isEmpty { return L("iPhone の時間に合わせる") }
        return Self.regionName(forZone: zoneID)
    }

    /// 選べるのは、世界の4つの地域。それぞれの代表の時間帯で、通知の時刻を決める
    private static let zones: [(id: String, region: Int)] = [
        ("Asia/Tokyo", 0), ("Asia/Kolkata", 1), ("Europe/Paris", 2), ("America/New_York", 3),
    ]

    /// 時間帯の名前を、4つの地域のどれかで言う（前の版で選んだ都市の時間帯も、地域に直す）
    private static func regionName(forZone id: String) -> String {
        guard let zone = TimeZone(identifier: id) else { return id }
        return L(PostStore.regionShortNames[PostStore.regionIndex(forOffset: zone.secondsFromGMT())])
    }

    /// 前の版で選んだ時間帯が4つの代表と違うときは、同じ地域の代表に直す
    private func normalizeZone() {
        guard !zoneID.isEmpty, !Self.zones.contains(where: { $0.id == zoneID }),
              let zone = TimeZone(identifier: zoneID) else { return }
        let region = PostStore.regionIndex(forOffset: zone.secondsFromGMT())
        if let match = Self.zones.first(where: { $0.region == region }) { zoneID = match.id }
    }

    private var supportURL: URL? {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let subject = "Difframe お問い合わせ".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let body = "\n\n— Difframe \(version)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "mailto:\(Self.supportEmail)?subject=\(subject)&body=\(body)")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L("言語"), selection: Binding(
                        get: { AppLanguage.current },
                        set: { languageRaw = $0.rawValue }
                    )) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.label).tag(lang)
                        }
                    }
                } header: {
                    Text(L("言語"))
                } footer: {
                    Text(L("初めは、iPhone の言語に合わせています。"))
                }

                Section {
                    HStack {
                        Text(L("電話番号"))
                        Spacer()
                        Text(phone.isEmpty ? L("未登録") : Account.masked(phone))
                            .foregroundStyle(Hi.dim)
                            .monospacedDigit()
                    }
                    Button(phone.isEmpty ? L("電話番号を登録") : L("電話番号を変える")) {
                        changingPhone = true
                    }
                } header: {
                    Text(L("アカウント"))
                } footer: {
                    Text(L("電話番号は、この端末の中にだけ保存されます。"))
                }

                Section {
                    Picker(L("通知の時間"), selection: $zoneID) {
                        Text(L("iPhone の時間に合わせる")).tag("")
                        ForEach(Self.zones, id: \.id) { zone in
                            Text(L(PostStore.regionShortNames[zone.region])).tag(zone.id)
                        }
                    }
                    .onAppear(perform: normalizeZone)
                    .onChange(of: zoneID) { _, id in
                        NotificationScheduler.changeZone(to: id)
                    }
                } header: {
                    Text(L("通知"))
                } footer: {
                    Text(L("お題の通知は、この地域の時間で、朝10時〜夜8時の間に届きます。変えると、明日から反映されます。"))
                }

                Section {
                    Toggle(L("両方のカメラで撮る"), isOn: $dualCamera)
                        .tint(Hi.neon)
                } header: {
                    Text(L("撮影"))
                } footer: {
                    Text(L("オンにすると、撮るたびに、外カメラと内カメラの両方で撮ります。"))
                }

                Section {
                    Toggle(L("友達に送る"), isOn: $sendFriends).tint(Hi.neon)
                    Toggle(L("みんなに送る"), isOn: $sendPublic).tint(Hi.neon)
                    if sendPublic {
                        Toggle(L("みんなからのコメントを受け付ける"), isOn: $publicComments).tint(Hi.neon)
                    }
                    Toggle(L("場所をつける"), isOn: $addLocation).tint(Hi.neon)
                } header: {
                    Text(L("投稿の初期設定"))
                } footer: {
                    Text(L("投稿のたびに、送り先の画面で変えられます。ここで選んだものが、最初の選択になります。"))
                }

                Section {
                    Toggle(L("コメント"), isOn: Binding(get: { !muteComment }, set: { muteComment = !$0 }))
                    Toggle(L("いいね"), isOn: Binding(get: { !muteLike }, set: { muteLike = !$0 }))
                    Toggle(L("友達リクエスト"), isOn: Binding(get: { !muteRequest }, set: { muteRequest = !$0 }))
                    Toggle(L("友達になったお知らせ"), isOn: Binding(get: { !muteAccepted }, set: { muteAccepted = !$0 }))
                    Toggle(L("友達の投稿"), isOn: Binding(get: { !mutePost }, set: { mutePost = !$0 }))
                    Toggle(L("DM"), isOn: Binding(get: { !muteMessage }, set: { muteMessage = !$0 }))
                } header: {
                    Text(L("通知の種類"))
                } footer: {
                    Text(L("オフにした種類は、通知の一覧にも未読の数にも出なくなります。"))
                }
                .tint(Hi.neon)

                Section {
                    if let url = supportURL {
                        Link(destination: url) {
                            Label(L("お問い合わせ"), systemImage: "envelope")
                        }
                    }
                    CloudStatusRow()
                    HStack {
                        Text(L("バージョン"))
                        Spacer()
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                            .foregroundStyle(Hi.dim)
                    }
                } header: {
                    Text(L("その他"))
                } footer: {
                    Text(L("お問い合わせは、メールアプリで送られます。"))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(L("設定"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("閉じる")) { dismiss() }
                }
            }
            .sheet(isPresented: $changingPhone) {
                SignUpView(onFinish: { changingPhone = false }, phoneOnly: true)
            }
        }
        .presentationBackground(.black)
        .preferredColorScheme(.dark)
    }
}
