import SwiftUI

/// 友達に探してもらう「ID」（@から始まる、ユニークな名前）。
/// サーバーの handles/{ID} に、ID → 友達コード を置く。同じIDは、2人は持てない。
enum IDError: Error { case taken }

extension CloudSync {
    private static let docsBase = "https://firestore.googleapis.com/v1/projects/\(CloudConfig.projectID)/databases/(default)/documents"

    /// 入力を、IDの形にそろえる（@を取る・小文字にする）
    static func normalizeID(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("@") { s.removeFirst() }
        return HandleRule.normalize(s)
    }

    /// IDを自分のものにする。ほかの人が持っていれば IDError.taken
    func claimID(_ id: String, code: String) async throws {
        try await ensureSignedIn()
        guard let uid else { throw CloudError.disabled }
        let url = URL(string: "\(Self.docsBase)/handles?documentId=\(id)")!
        let body: [String: Any] = ["fields": ["uid": ["stringValue": uid], "code": ["stringValue": code]]]
        do {
            _ = try await send("POST", url: url, json: body)
        } catch {
            let text = "\(error)"
            guard text.contains("ALREADY_EXISTS") || text.contains("already exists") || text.contains("409") else { throw error }
            // 自分がもう持っているIDなら、そのまま使える
            let mine = (try? await get("handles/\(id)"))?["fields"] as? [String: Any]
            if FS.string(mine ?? [:], "uid") == uid { return }
            throw IDError.taken
        }
    }

    /// IDを手放す（アカウント削除・IDを変えたとき）
    func releaseID(_ id: String) async {
        guard !id.isEmpty else { return }
        try? await delete("handles/\(id)")
    }

    /// IDから、その人の友達コードを探す（見つからなければ nil）
    func resolveID(_ text: String) async -> String? {
        let id = Self.normalizeID(text)
        guard isOn, !id.isEmpty else { return nil }
        guard let doc = try? await get("handles/\(id)"), let f = doc["fields"] as? [String: Any] else { return nil }
        return FS.string(f, "code")
    }
}

/// 名前とIDを、はじめに必ず決めてもらう画面。閉じられない（IDがないと、友達に見つけてもらえないため）
struct RequiredProfileView: View {
    @AppStorage("myName") private var myName: String = ""
    @AppStorage("myHandle") private var myHandle: String = ""
    @State private var name = ""
    @State private var idText = ""
    @State private var message: String? = nil
    @State private var saving = false
    @State private var loggingIn = false

    private var normalized: String { CloudSync.normalizeID(idText) }
    private var idError: String? { HandleRule.error(for: normalized) }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && idError == nil && !saving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("表示される名前"), text: $name)
                } header: {
                    Text(L("名前"))
                }

                Section {
                    HStack(spacing: 2) {
                        Text("@").foregroundStyle(.gray)
                        TextField("ID", text: $idText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                    }
                } header: {
                    Text(L("ID（友達追加に使う）"))
                } footer: {
                    if !idText.isEmpty, let idError {
                        Text(idError).foregroundStyle(.red)
                    } else {
                        Text(L("IDは、友達が探すときに使います。英小文字・数字・ピリオド・アンダースコアで、3〜20文字。世界の投稿には表示されません。"))
                    }
                }

                if let message {
                    Section { Text(message).foregroundStyle(.red) }
                }

                Section {
                    Button {
                        save()
                    } label: {
                        if saving { ProgressView().frame(maxWidth: .infinity) } else { Text(L("はじめる")).frame(maxWidth: .infinity) }
                    }
                    .disabled(!canSave)
                }

                Section {
                    Button {
                        loggingIn = true
                    } label: {
                        Text(L("すでにアカウントがある人はログイン")).frame(maxWidth: .infinity)
                    }
                } footer: {
                    Text(L("前に使っていたアカウントの電話番号で、確認コードを受け取ると、名前とIDを元に戻して入れます。"))
                }
            }
            .navigationTitle(L("はじめに設定"))
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
            .onAppear {
                if name.isEmpty { name = myName }
                if idText.isEmpty { idText = myHandle }
            }
            .fullScreenCover(isPresented: $loggingIn) {
                SignUpView(onFinish: { loggingIn = false })
            }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        saving = true
        message = nil
        let newName = name.trimmingCharacters(in: .whitespaces)
        let newID = normalized
        let oldID = myHandle
        Task {
            do {
                if CloudSync.shared.isOn {
                    try await CloudSync.shared.claimID(newID, code: FriendCode.myID)
                    if !oldID.isEmpty, oldID != newID { await CloudSync.shared.releaseID(oldID) }
                }
                myName = newName
                myHandle = newID
                if CloudSync.shared.isOn { try? await CloudSync.shared.publishProfile() }
            } catch IDError.taken {
                message = L("このIDは、もう使われています。別のIDにしてください。")
            } catch {
                message = L("通信できませんでした。電話かWi-Fiを確かめて、もう一度押してください。")
            }
            saving = false
        }
    }
}
