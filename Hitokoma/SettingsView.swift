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
    @AppStorage("mute.rankUp") private var muteRankUp = false
    @AppStorage("mute.message") private var muteMessage = false
    // 撮影
    @AppStorage("dualCamera") private var dualCamera = true
    // 投稿の初期設定（次の投稿の、最初の選択になる）
    @AppStorage("shareFriends") private var sendFriends = true
    @AppStorage("sharePublic") private var sendPublic = true
    @AppStorage("publicCommentsDefault") private var publicComments = true
    @AppStorage("shareLocation") private var addLocation = true
    @AppStorage("pickupOptOut") private var pickupOptOut = false
    @AppStorage("presenceShare") private var presenceShare = true
    @AppStorage(CloudSync.discoverableKey) private var discoverable = true

    @State private var changingPhone = false
    @State private var confirmDelete = false
    @State private var confirmSignOut = false
    @State private var signingOut = false
    @AppStorage(Account.verifiedKey) private var phoneVerified = false
    @State private var deleting = false
    @State private var deleteResult: DeleteResult? = nil

    /// 公開のページ（プライバシーポリシーと利用規約）
    static let privacyURL = URL(string: "https://difframe-acae0.web.app/privacy.html")!
    static let termsURL = URL(string: "https://difframe-acae0.web.app/terms.html")!

    /// 問い合わせの送り先（公開前に、実際の窓口のアドレスに変えること）
    static let supportEmail = "support@lpstudio.app"

    private var zoneLabel: String {
        Self.regionName(forZone: NotificationScheduler.zone.identifier)
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

    /// 未選択（初期値）や前の版の時間帯は、いまの端末の地域の代表に直して表示する
    private func normalizeZone() {
        let id = NotificationScheduler.zone.identifier
        if zoneID != id { zoneID = id }
    }

    private var supportURL: URL? {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let subject = L("Difframe お問い合わせ").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
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
                    Toggle(L("連絡先から見つけてもらう"), isOn: $discoverable)
                        .tint(Hi.neon)
                        .disabled(!phoneVerified || phone.isEmpty)
                        .onChange(of: discoverable) { _, _ in Task { await CloudSync.shared.syncPhoneDiscovery(force: true) } }
                    Button { confirmSignOut = true } label: {
                        if signingOut { ProgressView() } else { Text(L("ログアウト")) }
                    }
                    .disabled(signingOut || deleting)
                    Button(role: .destructive) { confirmDelete = true } label: {
                        if deleting { ProgressView() } else { Text(L("アカウントを削除")) }
                    }
                    .disabled(deleting)
                } header: {
                    Text(L("アカウント"))
                } footer: {
                    Text(FirebaseBoot.available
                         ? L("電話番号は、本人確認と、別の端末で同じアカウントに入るために使います。「連絡先から見つけてもらう」がオンのときは、あなたの番号を連絡先に入れている人が、あなたを見つけられます。番号そのものは、ほかの人には見えません。")
                         : L("電話番号は、この端末の中にだけ保存されます。"))
                }

                Section {
                    Picker(L("通知の時間"), selection: $zoneID) {
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
                    Toggle(L("オンラインの状態を見せる"), isOn: $presenceShare).tint(Hi.neon)
                } header: {
                    Text(L("DM"))
                } footer: {
                    Text(L("オンにすると、アプリを開いているあいだ、友達のDMに「オンライン」の印が出ます。オフにすると、あなたの状態は見えなくなり、友達の状態も見えなくなります。"))
                }

                Section {
                    Toggle(L("「今日の10枚」に選ばれる"), isOn: Binding(
                        get: { !pickupOptOut },
                        set: { on in
                            pickupOptOut = !on
                            Task { await CloudSync.shared.setPickupOff(!on) }
                        })).tint(Hi.neon)
                } header: {
                    Text(L("今日の10枚"))
                } footer: {
                    Text(L("オンにすると、みんなに送った投稿が、毎朝の「今日の10枚」に選ばれることがあります。オフにすると、選ばれません。"))
                }

                Section {
                    Toggle(L("コメント"), isOn: Binding(get: { !muteComment }, set: { muteComment = !$0 }))
                    Toggle(L("いいね"), isOn: Binding(get: { !muteLike }, set: { muteLike = !$0 }))
                    Toggle(L("友達リクエスト"), isOn: Binding(get: { !muteRequest }, set: { muteRequest = !$0 }))
                    Toggle(L("友達になったお知らせ"), isOn: Binding(get: { !muteAccepted }, set: { muteAccepted = !$0 }))
                    Toggle(L("友達の投稿"), isOn: Binding(get: { !mutePost }, set: { mutePost = !$0 }))
                    Toggle(L("友達のランクアップ"), isOn: Binding(get: { !muteRankUp }, set: { muteRankUp = !$0 }))
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
                    Link(destination: Self.privacyURL) { Label(L("プライバシーポリシー"), systemImage: "hand.raised") }
                    Link(destination: Self.termsURL) { Label(L("利用規約"), systemImage: "doc.text") }
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
            .confirmationDialog(L("ログアウトしますか？"), isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button(L("ログアウト"), role: .destructive) {
                    signingOut = true
                    // 先に設定の画面を閉じてから、消す（開いたまま消すと、最初の画面が出せない）
                    dismiss()
                    Task {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        await CloudSync.shared.signOut()
                    }
                }
                Button(L("キャンセル"), role: .cancel) {}
            } message: {
                Text(phoneVerified && !phone.isEmpty
                     ? L("アカウントと投稿は、サーバーに残ります。同じ電話番号でログインすると、戻れます。この端末の写真と記録も、そのまま残ります。")
                     : L("電話番号を登録していないので、ログアウトすると、このアカウントには戻れません。先に電話番号を登録してください。"))
            }
            .confirmationDialog(L("アカウントを削除しますか？"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(L("削除する"), role: .destructive) {
                    deleting = true
                    Task {
                        let result = await CloudSync.shared.deleteAccount()
                        deleting = false
                        if result == .done {
                            // 先に設定の画面を閉じてから、端末のデータを消す（最初の画面を出せるように）
                            dismiss()
                            try? await Task.sleep(nanoseconds: 600_000_000)
                            CloudSync.shared.wipeLocalData()
                        } else { deleteResult = result }
                    }
                }
                Button(L("キャンセル"), role: .cancel) {}
            } message: {
                Text(L("投稿、コメント、友達、メッセージ、電話番号を、サーバーから消します。この端末のデータも消えます。元に戻せません。"))
            }
            .alert(deleteResult == .needsRecentLogin ? L("もう一度、確認が必要です") : L("削除できませんでした"),
                   isPresented: Binding(get: { deleteResult != nil }, set: { if !$0 { deleteResult = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteResult == .needsRecentLogin
                     ? L("安全のため、電話番号をもう一度確認してください。「電話番号を変える」で確認したあと、もう一度削除してください。")
                     : L("通信を確かめて、もう一度試してください。"))
            }
            .fullScreenCover(isPresented: $changingPhone) {
                SignUpView(onFinish: { changingPhone = false }, phoneOnly: true)
            }
        }
        .presentationBackground(.black)
        .preferredColorScheme(.dark)
    }
}
