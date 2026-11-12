import SwiftUI

/// 電話番号でアカウントを作る画面（3ステップ：電話番号 → コード → 名前）。
/// いまはデモ：SMSは送られず、コードが画面に出る。「あとで」で飛ばしてもアプリは全部使える。
struct SignUpView: View {
    let onFinish: () -> Void
    /// 電話番号だけを変える（設定から）。名前の画面は出さず、確認コードのあとで保存して閉じる
    var phoneOnly = false

    private enum Stage { case phone, code, profile }

    @AppStorage("myName") private var myName: String = L("あなた")
    @AppStorage("myHandle") private var myHandle: String = ""
    @AppStorage(Account.phoneKey) private var phone: String = ""
    @AppStorage(Account.verifiedKey) private var verified: Bool = false

    @State private var stage: Stage = .phone
    @State private var country = Country.current
    @State private var number = ""
    @State private var e164: String = ""
    @State private var code = ""
    @State private var shownCode: String? = nil
    @State private var busy = false
    @State private var error: String? = nil
    @State private var name = ""
    @State private var handle = ""
    @State private var handleTouched = false
    @FocusState private var focused: Bool
    @FocusState private var handleFocused: Bool

    private let auth: PhoneAuthProvider = DemoPhoneAuth()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .onTapGesture { focused = false }
            GlowBackground(palette: .forPrompt(L("窓")), focus: UnitPoint(x: 0.5, y: 0.1))
                .opacity(0.3)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    if stage != .phone {
                        Button {
                            error = nil
                            stage = stage == .profile ? .code : .phone
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.headline)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(Hi.tile))
                        }
                        .accessibilityLabel(L("戻る"))
                    }
                    Spacer()
                    if stage == .phone {
                        Button(L("あとで")) { onFinish() }
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .background(Capsule().fill(Hi.tile))
                    }
                }
                .frame(height: 44)

                switch stage {
                case .phone: phoneStage
                case .code: codeStage
                case .profile: profileStage
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }

    // MARK: 1. 電話番号

    private var phoneStage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("電話番号で\nはじめる"))
                .font(.system(size: 38, weight: .black))
            Text(L("友達を連絡先から探すときに使います。番号はこの端末の中だけに保存します。"))
                .font(.subheadline)
                .foregroundStyle(Hi.dim)

            HStack(spacing: 10) {
                Menu {
                    Picker(L("国"), selection: $country) {
                        ForEach(Country.all) { c in
                            Text("\(c.flag) \(c.name) +\(c.dial)").tag(c)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(country.flag)
                        Text("+\(country.dial)").font(.body.weight(.bold))
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 56)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Hi.tile))
                }
                .accessibilityLabel(LF("国番号 {c}", ["c": country.name]))

                TextField(L("電話番号"), text: $number)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .focused($focused)
                    .font(.title3.weight(.bold))
                    .padding(.horizontal, 14)
                    .frame(height: 56)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Hi.tile))
            }

            demoNotice

            if let error { Text(error).font(.footnote).foregroundStyle(.red) }

            Button {
                sendCode()
            } label: {
                if busy { ProgressView().tint(Hi.onNeon) } else { Text(L("コードを受け取る")) }
            }
            .buttonStyle(NeonButtonStyle())
            .disabled(busy || Account.e164(country: country, input: number) == nil)
            .opacity(Account.e164(country: country, input: number) == nil ? 0.4 : 1)
        }
    }

    /// デモであることを、はっきり伝える
    private var demoNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(Hi.neon)
            Text(L("デモ版です。SMSは送られず、確認コードが次の画面に表示されます。"))
                .font(.footnote)
                .foregroundStyle(Hi.dim)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Hi.tile))
    }

    private func sendCode() {
        focused = false
        guard let value = Account.e164(country: country, input: number) else {
            error = L("電話番号を確認してください")
            return
        }
        busy = true
        error = nil
        Task {
            do {
                let sent = try await auth.sendCode(to: value)
                e164 = value
                shownCode = sent
                code = ""
                stage = .code
            } catch {
                self.error = L("コードを送れませんでした。もう一度試してください")
            }
            busy = false
        }
    }

    // MARK: 2. 確認コード

    private var codeStage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("コードを\n入力"))
                .font(.system(size: 38, weight: .black))
            Text(LF("{f} +{d} {m} あてのコードです。", ["f": country.flag, "d": country.dial, "m": Account.masked(e164)]))
                .font(.subheadline)
                .foregroundStyle(Hi.dim)

            if let shownCode {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("デモのコード")).font(.caption).foregroundStyle(Hi.dim)
                        Text(shownCode)
                            .font(.system(size: 28, weight: .black, design: .monospaced))
                    }
                    Spacer()
                    Button(L("入力する")) { code = shownCode }
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Capsule().fill(Hi.neon))
                        .foregroundStyle(Hi.onNeon)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Hi.tile))
            }

            TextField(L("6桁のコード"), text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .font(.system(size: 28, weight: .black, design: .monospaced))
                .padding(.horizontal, 14)
                .frame(height: 60)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Hi.tile))
                .onChange(of: code) { _, value in
                    code = String(value.filter(\.isNumber).prefix(6))
                }

            if let error { Text(error).font(.footnote).foregroundStyle(.red) }

            Button {
                confirm()
            } label: {
                if busy { ProgressView().tint(Hi.onNeon) } else { Text(L("確認する")) }
            }
            .buttonStyle(NeonButtonStyle())
            .disabled(busy || code.count != 6)
            .opacity(code.count == 6 ? 1 : 0.4)

            Button(L("コードをもう一度受け取る")) { sendCode() }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Hi.dim)
                .frame(maxWidth: .infinity)
        }
    }

    private func confirm() {
        busy = true
        error = nil
        Task {
            if await auth.verify(code: code, for: e164) {
                focused = false
                if phoneOnly {
                    phone = e164
                    verified = auth.isReal
                    onFinish()
                } else {
                    stage = .profile
                }
            } else {
                error = L("コードが違います。もう一度確認してください")
            }
            busy = false
        }
    }

    // MARK: 3. 名前とハンドル名

    private var normalizedHandle: String { HandleRule.normalize(handle) }
    private var handleError: String? { HandleRule.error(for: normalizedHandle) }
    private var canFinish: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && handleError == nil
    }

    private var profileStage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("あなたの\n名前"))
                .font(.system(size: 38, weight: .black))
            Text(L("友達や世界のランキングに表示されます。あとから変えられます。"))
                .font(.subheadline)
                .foregroundStyle(Hi.dim)

            TextField(L("名前"), text: $name)
                .focused($focused)
                .font(.title3.weight(.bold))
                .padding(.horizontal, 14)
                .frame(height: 56)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Hi.tile))
                .onChange(of: name) { _, value in
                    // ハンドル名は、まだ自分で触っていなければ、英数字の名前から作る
                    guard !handleTouched else { return }
                    handle = HandleRule.normalize(value).filter { "abcdefghijklmnopqrstuvwxyz0123456789._".contains($0) }
                }

            HStack(spacing: 2) {
                Text("@").foregroundStyle(Hi.dim)
                TextField("handle", text: $handle)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .focused($handleFocused)
                    .font(.title3.weight(.bold))
                    .onChange(of: handle) { _, _ in
                        if handleFocused { handleTouched = true }
                    }
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Hi.tile))

            if handle.count >= HandleRule.minLength, let handleError {
                Text(handleError).font(.footnote).foregroundStyle(.red)
            } else {
                Text(L("ハンドル名：英小文字・数字・. _ で3〜20文字")).font(.footnote).foregroundStyle(Hi.dim)
            }

            Button(L("はじめる")) { finish() }
                .buttonStyle(NeonButtonStyle())
                .disabled(!canFinish)
                .opacity(canFinish ? 1 : 0.4)
        }
    }

    private func finish() {
        myName = name.trimmingCharacters(in: .whitespaces)
        myHandle = normalizedHandle
        phone = e164
        verified = auth.isReal
        onFinish()
    }
}
