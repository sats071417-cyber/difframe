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

    private let auth: PhoneAuthProvider = FirebaseBoot.available ? FirebasePhoneAuth.shared : DemoPhoneAuth()

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
            Text(L("本人確認と、連絡先から友達とつながるために使います。番号そのものは、ほかの人には見えません。"))
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

            if !auth.isReal { demoNotice }

            if let error { Text(error).font(.footnote).foregroundStyle(.red) }

            // 続けると、規約に同意したことになる
            (Text(L("続けると、")) + Text("[\(L("利用規約"))](\(SettingsView.termsURL.absoluteString))") + Text(L("と")) +
             Text("[\(L("プライバシーポリシー"))](\(SettingsView.privacyURL.absoluteString))") + Text(L("に同意したことになります。")))
                .font(.caption).foregroundStyle(Hi.dim)

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
                NSLog("phone send failed: \(error)")
                self.error = Self.sendFailureMessage(error)
            }
            busy = false
        }
    }

    /// コードを送れなかったときの理由。Firebase のエラー番号も添えて、原因を探しやすくする
    private static func sendFailureMessage(_ error: Error) -> String {
        let ns = error as NSError
        let base: String
        switch ns.code {
        case 17010: base = L("短い間に何度も試したため、いまは送れません。しばらく待って、もう一度試してください")   // too many requests
        case 17052: base = L("今日の送信の上限に達しました。明日、もう一度試してください")                       // quota exceeded
        case 17042, 17041: base = L("電話番号を確認してください")                                                  // invalid / missing number
        case 17020: base = L("通信できません。ネットワークを確認してください")                                    // network
        case 17058: base = L("確認の画面が閉じられました。もう一度試してください")                                // reCAPTCHA closed
        default: base = L("コードを送れませんでした。もう一度試してください")
        }
        return ns.domain.contains("FIRAuth") ? base + " (\(ns.code))" : base
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

            OTPField(code: $code, focused: $focused, hasError: error != nil)
                .onChange(of: code) { _, _ in if error != nil { error = nil } }

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
                    Task { await CloudSync.shared.syncPhoneDiscovery(force: true) }
                    onFinish()
                } else if !myName.trimmingCharacters(in: .whitespaces).isEmpty, myName != L("あなた"), !myHandle.isEmpty {
                    // ログアウトしたあと、同じ番号で入り直した：前の名前とIDが戻っているので、そのまま入る
                    phone = e164
                    verified = auth.isReal
                    onFinish()
                } else {
                    // はじめての登録：名前とIDを決めてもらう
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
        let newID = normalizedHandle
        let oldID = myHandle
        let newName = name.trimmingCharacters(in: .whitespaces)
        busy = true
        error = nil
        Task {
            do {
                if CloudSync.shared.isOn {
                    try await CloudSync.shared.claimID(newID, code: FriendCode.myID)
                    if !oldID.isEmpty, oldID != newID { await CloudSync.shared.releaseID(oldID) }
                }
                myName = newName
                myHandle = newID
                phone = e164
                verified = auth.isReal
                if CloudSync.shared.isOn { try? await CloudSync.shared.publishProfile() }
                Task { await CloudSync.shared.syncPhoneDiscovery(force: true) }
                busy = false
                onFinish()
            } catch IDError.taken {
                busy = false
                error = L("このIDは、もう使われています。別のIDにしてください。")
            } catch {
                busy = false
                self.error = L("通信できませんでした。電話かWi-Fiを確かめて、もう一度押してください。")
            }
        }
    }
}


/// 認証コードの入力：1つの本物の入力欄（貼り付けも、SMS のコード自動入力も効く）の上に、1桁ずつの枠を重ねる。
/// 3桁ずつ2組に分け、次に入る枠に輪と点滅する線を出す。間違えたときは、枠が揺れる。
struct OTPField: View {
    @Binding var code: String
    var focused: FocusState<Bool>.Binding
    var hasError = false
    var length = 6

    @State private var blink = false
    @State private var shake: CGFloat = 0

    var body: some View {
        ZStack {
            // 本物の入力欄：見えないが、フォーカスと貼り付け・自動入力を受ける
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused(focused)
                .foregroundStyle(.clear).tint(.clear)
                .opacity(0.02)
                .onChange(of: code) { _, v in
                    let digits = String(v.filter(\.isNumber).prefix(length))   // 空白や「-」を取り除く
                    if digits != v { code = digits }
                }
                .accessibilityLabel(L("6桁のコード"))

            HStack(spacing: 8) {
                ForEach(0..<length, id: \.self) { i in
                    if i == length / 2 { Capsule().fill(Hi.dim.opacity(0.6)).frame(width: 10, height: 3) }
                    slot(i)
                }
            }
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .contentShape(Rectangle())
        .onTapGesture { focused.wrappedValue = true }
        .modifier(Shake(amount: shake))
        .onAppear { withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { blink = true } }
        .onChange(of: hasError) { _, now in
            guard now else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(.linear(duration: 0.4)) { shake += 1 }
        }
    }

    private func slot(_ i: Int) -> some View {
        let chars = Array(code)
        let digit = i < chars.count ? String(chars[i]) : ""
        let active = focused.wrappedValue && i == min(chars.count, length - 1)
        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Hi.tile)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(hasError ? Color.red : (active ? Hi.neon : Color.white.opacity(0.08)), lineWidth: active || hasError ? 2.5 : 1)
            if digit.isEmpty {
                if active { Capsule().fill(Hi.neon).frame(width: 2, height: 26).opacity(blink ? 1 : 0) }   // 点滅する線
            } else {
                Text(digit).font(.system(size: 28, weight: .black, design: .monospaced)).foregroundStyle(.white)
            }
        }
        .frame(width: 44, height: 56)
    }
}

/// 左右に揺らす（間違えたときの合図）
private struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat { get { amount } set { amount = newValue } }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(amount * .pi * 4), y: 0))
    }
}
