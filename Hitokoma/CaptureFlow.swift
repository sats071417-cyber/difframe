import SwiftUI
import AVFoundation
import UIKit

// MARK: - カメラ（アプリの中のカメラだけを使う。アルバムは使えない）

/// 正方形の写真を撮るカメラ。外カメラ → 内カメラの順に、1つのカメラを切り替えながら撮る。
final class CameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "hitokoma.camera")
    private var configured = false
    private var pending: ((UIImage?) -> Void)?

    @Published private(set) var position: AVCaptureDevice.Position = .back
    @Published private(set) var canFlash = false
    @Published var flashOn = false
    @Published private(set) var isDenied = false
    @Published private(set) var isUnavailable = false
    @Published private(set) var isCapturing = false
    /// 画面に出す倍率（1 = 普通のカメラ。0.5 = 超広角）
    @Published private(set) var zoom: CGFloat = 1
    /// 0.5倍（超広角）が使えるか
    @Published private(set) var hasUltraWide = false
    /// 拡大できる上限（画面の倍率）
    @Published private(set) var maxZoom: CGFloat = 5
    /// 0.5倍の下限（超広角がないときは 1）
    @Published private(set) var minZoom: CGFloat = 1
    /// 倍率ボタン（iPhone の純正カメラと同じく、機種のレンズに合わせる。例：.5 / 1 / 2 / 3）
    @Published private(set) var zoomStops: [CGFloat] = [1, 2]
    /// 複数レンズをまとめたカメラで、「1倍」にあたる内部の倍率（超広角があると 2 など）
    private var wideFactor: CGFloat = 1
    private var device: AVCaptureDevice?

    func start() {
        #if targetEnvironment(simulator)
        // シミュレーターにはカメラがない。許可の確認も出さず、テスト用の画像で進める
        isUnavailable = true
        hasUltraWide = true; minZoom = 0.5; maxZoom = 15   // 倍率の操作だけ試せるようにする
        zoomStops = [0.5, 1, 2, 3]
        return
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.configureAndRun() } else { self.isDenied = true }
                }
            }
        default:
            isDenied = true
        }
        #endif
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureAndRun() {
        queue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                let added = self.setInput(position: .back)
                if self.session.canAddOutput(self.output) { self.session.addOutput(self.output) }
                self.tuneOutput()
                self.session.commitConfiguration()
                self.configured = true
                if !added {
                    DispatchQueue.main.async { self.isUnavailable = true }
                    return
                }
            }
            if !self.session.isRunning { self.session.startRunning() }
            self.refreshFlash()
        }
    }

    /// 前後どちらかのカメラを入力にする（queue の上で呼ぶ）
    @discardableResult
    private func setInput(position: AVCaptureDevice.Position) -> Bool {
        // 外カメラは、超広角を含む「まとめたカメラ」を優先する（0.5倍が使える）
        let types: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera]
            : [.builtInWideAngleCamera]
        let found = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: position).devices
        let picked = types.lazy.compactMap { t in found.first { $0.deviceType == t } }.first
        guard let device = picked, let input = try? AVCaptureDeviceInput(device: device) else { return false }
        for old in session.inputs { session.removeInput(old) }
        guard session.canAddInput(input) else { return false }
        session.addInput(input)
        self.device = device
        // 超広角があるとき、「1倍」は切り替え点の倍率（例：2.0）になる
        let switchOver = device.virtualDeviceSwitchOverVideoZoomFactors.first.map { CGFloat(truncating: $0) }
        let ultra = device.isVirtualDevice && (device.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera })
        wideFactor = ultra ? (switchOver ?? 2) : 1
        let minDisplay = device.minAvailableVideoZoomFactor / wideFactor
        let stops = position == .back ? CameraModel.lensStops(device: device, wideFactor: wideFactor, ultra: ultra) : []
        // 上限：望遠があれば、その5倍まで（3倍レンズなら15倍、5倍レンズなら25倍）。なければ10倍（超広角あり）か5倍
        let tele = stops.last.flatMap { $0 > 2 ? $0 : nil }
        let cap: CGFloat = position == .front ? 3 : (tele.map { min($0 * 5, 25) } ?? (ultra ? 10 : 5))
        let maxDisplay = min(device.maxAvailableVideoZoomFactor / wideFactor, cap)
        if (try? device.lockForConfiguration()) != nil {
            device.videoZoomFactor = max(device.minAvailableVideoZoomFactor, min(wideFactor, device.maxAvailableVideoZoomFactor))
            device.unlockForConfiguration()
        }
        DispatchQueue.main.async {
            self.position = position
            self.hasUltraWide = ultra
            self.minZoom = ultra ? minDisplay : 1
            self.maxZoom = maxDisplay
            self.zoomStops = stops
            self.zoom = 1
        }
        return true
    }

    /// 機種のレンズから、倍率ボタンを決める
    /// ・超広角があれば .5
    /// ・1（広角）
    /// ・広角が48MPなら 2（純正カメラと同じ、画質の落ちない2倍）。望遠がない機種でも 2 を出す（48MP でない古い機種は除く）
    /// ・望遠があれば、その倍率（3 や 5 や 4 など。切り替え点から求める）
    static func lensStops(device: AVCaptureDevice, wideFactor: CGFloat, ultra: Bool) -> [CGFloat] {
        var stops: [CGFloat] = []
        if ultra { stops.append(0.5) }
        stops.append(1)
        let wideLens = device.isVirtualDevice
            ? (device.constituentDevices.first { $0.deviceType == .builtInWideAngleCamera } ?? device)
            : device
        let is48MP = wideLens.formats.contains { format in
            format.supportedMaxPhotoDimensions.contains { max($0.width, $0.height) >= 8000 }
        }
        let hasTele = device.constituentDevices.contains { $0.deviceType == .builtInTelephotoCamera }
        if is48MP || (!ultra && !hasTele) { stops.append(2) }
        if hasTele {
            // 切り替え点：超広角→広角、広角→望遠。広角より先の点が望遠の倍率
            let factors = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) / wideFactor }
            for f in factors where f > 1.05 {
                let r = (f * 10).rounded() / 10
                if !stops.contains(where: { abs($0 - r) < 0.05 }) { stops.append(r) }
            }
        }
        // 切り出しでも画質が落ちない倍率（48MP の切り出し。例：広角の2倍、望遠の2倍＝8倍など）。iPhone 自身が返す一覧を使う
        for f in device.activeFormat.secondaryNativeResolutionZoomFactors {
            let r = (CGFloat(f) / wideFactor * 10).rounded() / 10
            if r > 1.05, r <= 10, !stops.contains(where: { abs($0 - r) < 0.05 }) { stops.append(r) }
        }
        return stops.sorted()
    }

    /// 倍率を変える（画面の倍率で指定。0.5 = 超広角）。ramp が true なら、なめらかに変える
    func setZoom(_ display: CGFloat, ramp: Bool = false) {
        let target = max(minZoom, min(display, maxZoom))
        zoom = target
        #if !targetEnvironment(simulator)
        queue.async { [weak self] in
            guard let self, let device = self.device, (try? device.lockForConfiguration()) != nil else { return }
            let factor = max(device.minAvailableVideoZoomFactor, min(target * self.wideFactor, device.maxAvailableVideoZoomFactor))
            if ramp { device.ramp(toVideoZoomFactor: factor, withRate: 12) } else { device.videoZoomFactor = factor }
            device.unlockForConfiguration()
        }
        #endif
    }

    /// 撮るまでの速さを優先する設定（queue の上、設定の途中で呼ぶ）
    /// ・連続ですぐ撮れるようにする（対応している機種だけ）
    /// ・写真の大きさは、保存する大きさ（1600px）より少し大きい程度にする（処理が軽くなる）
    private func tuneOutput() {
        output.maxPhotoQualityPrioritization = .balanced
        if output.isResponsiveCaptureSupported { output.isResponsiveCaptureEnabled = true }
        if output.isFastCapturePrioritizationSupported { output.isFastCapturePrioritizationEnabled = true }
        if let device {
            let sizes = device.activeFormat.supportedMaxPhotoDimensions
                .sorted { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }
            if let pick = sizes.first(where: { min($0.width, $0.height) >= 1600 }) ?? sizes.last {
                output.maxPhotoDimensions = pick
            }
        }
    }

    private func refreshFlash() {
        let supported = output.supportedFlashModes.contains(.on)
        DispatchQueue.main.async {
            self.canFlash = supported
            if !supported { self.flashOn = false }
        }
    }

    /// 外カメラか内カメラに切り替える。切り替えが終わったら completion を呼ぶ
    func switchTo(_ target: AVCaptureDevice.Position, completion: (() -> Void)? = nil) {
        #if targetEnvironment(simulator)
        position = target
        completion?()
        #else
        queue.async { [weak self] in
            guard let self else { return }
            if self.currentPosition != target {
                self.session.beginConfiguration()
                _ = self.setInput(position: target)
                self.tuneOutput()
                self.session.commitConfiguration()
            }
            self.refreshFlash()
            DispatchQueue.main.async { completion?() }
        }
        #endif
    }

    /// queue の上で見る、いまの入力のカメラの向き
    private var currentPosition: AVCaptureDevice.Position {
        (session.inputs.first as? AVCaptureDeviceInput)?.device.position ?? .unspecified
    }

    /// いまのカメラで1枚撮る（3:4 に整えて返す）
    func capture(useFlash: Bool, completion: @escaping (UIImage?) -> Void) {
        guard !isCapturing else { return }
        isCapturing = true
        #if targetEnvironment(simulator)
        // 実機では使われない。シミュレーター用のテスト画像
        let image = CameraModel.testImage(front: position == .front)
        isCapturing = false
        completion(image)
        #else
        pending = completion
        queue.async { [weak self] in
            guard let self else { return }
            let isFront = self.currentPosition == .front
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .speed            // 押してすぐ撮れることを優先
            settings.maxPhotoDimensions = self.output.maxPhotoDimensions
            if useFlash, !isFront, self.output.supportedFlashModes.contains(.on) { settings.flashMode = .on }
            if let connection = self.output.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                // 内カメラは、画面で見えている鏡のような向きに合わせる
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = isFront
                }
            }
            self.output.capturePhoto(with: settings, delegate: self)
        }
        #endif
    }

    /// 撮影を中止する（途中で閉じたときなど）
    func cancelPending() {
        pending = nil
        isCapturing = false
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        var result: UIImage?
        if error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) {
            result = CameraModel.cropped(image)
        }
        DispatchQueue.main.async {
            self.isCapturing = false
            let done = self.pending
            self.pending = nil
            done?(result)
        }
    }

    /// 向きを直して、中央を 3:4（縦長）に切り抜く（大きすぎる写真は、長い辺を maxSide に小さくする）
    static func cropped(_ image: UIImage, maxSide: CGFloat = 2000) -> UIImage {
        let width = image.size.width, height = image.size.height
        let ratio = PhotoShape.ratio
        // 元の写真から取れる、いちばん大きい 3:4
        let cropW = min(width, height * ratio)
        let cropH = cropW / ratio
        let scale = min(1, maxSide / cropH)
        let outSize = CGSize(width: (cropW * scale).rounded(), height: (cropH * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: outSize, format: format).image { _ in
            image.draw(in: CGRect(x: -(width - cropW) / 2 * scale, y: -(height - cropH) / 2 * scale,
                                  width: width * scale, height: height * scale))
        }
    }

    /// 外カメラの写真に、内カメラの写真を角丸の小さな枠で重ねる
    static func composite(back: UIImage, front: UIImage) -> UIImage {
        let side = back.size.width
        let inset = side * 0.30
        let margin = side * 0.04
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: back.size, format: format).image { context in
            back.draw(in: CGRect(origin: .zero, size: back.size))
            let frame = CGRect(x: side - inset - margin, y: margin, width: inset, height: inset)
            let path = UIBezierPath(roundedRect: frame, cornerRadius: inset * 0.16)
            context.cgContext.saveGState()
            path.addClip()
            front.draw(in: frame)
            context.cgContext.restoreGState()
            UIColor.white.setStroke()
            path.lineWidth = side * 0.006
            path.stroke()
        }
    }

    #if targetEnvironment(simulator)
    private static func testImage(front: Bool) -> UIImage {
        let size = CGSize(width: 900, height: 1200)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let top = front ? UIColor(red: 0.85, green: 0.35, blue: 0.5, alpha: 1) : UIColor(red: 0.2, green: 0.45, blue: 0.5, alpha: 1)
            let bottom = front ? UIColor(red: 0.95, green: 0.7, blue: 0.4, alpha: 1) : UIColor(red: 0.85, green: 0.7, blue: 0.45, alpha: 1)
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            UIColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 250, y: 250, width: 400, height: 400))
            if front {
                UIColor.white.setFill()
                context.cgContext.fillEllipse(in: CGRect(x: 350, y: 350, width: 200, height: 200))
            }
        }
    }
    #endif
}

/// カメラの映像を表示する
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

// MARK: - 撮る → 確認 → 投稿

/// 真ん中のボタンから開く、全画面のカメラ。
/// 初期は、外カメラの1枚だけ。左のボタンで「内カメラも撮る」をオンにすると、
/// 外カメラで撮ったあとに内カメラのカウントダウンが始まり、2枚を1枚にして確認画面へ進む。
struct CaptureFlow: View {
    private enum Stage: Equatable { case camera, review, done }
    /// DM から開いたとき：投稿の代わりに、撮った写真をその会話に送る（投稿・フィードには出ない）
    var directSend: ((UIImage) -> Void)? = nil

    @EnvironmentObject private var store: PostStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraModel()

    @AppStorage("dualCamera") private var dualCamera = false   // 内カメラも撮る（初期は外カメラだけ）
    @State private var stage: Stage = .camera
    @State private var photo: UIImage? = nil          // 確認画面に出す、重ねた1枚
    @State private var backShot: UIImage? = nil       // 外カメラの写真（お題の確認は、これだけで行う）
    @State private var frontShot: UIImage? = nil      // 2枚撮りの内カメラの写真（合成せずに、別に保存する）
    @State private var frozenBack: UIImage? = nil     // 内カメラを撮っている間、大きい枠に止めて見せる外カメラの写真
    @State private var countdown: Int? = nil          // 内カメラまで、あと何秒
    @State private var sequence: Task<Void, Never>? = nil
    @State private var caption = ""
    @AppStorage("publicCommentsDefault") private var publicComments = true   // みんなの投稿で、コメントを受け付けるか（前回の選択を覚える）
    @AppStorage("shareFriends") private var sendFriends = true     // 友達に送る（前回の選択を覚える）
    @AppStorage("sharePublic") private var sendPublic = true       // みんなに送る
    @AppStorage("shareLocation") private var addLocation = false   // 場所（都市の名前）をつける
    @StateObject private var locator = CityLocator()
    @State private var showShare = false
    @State private var checking = false
    @State private var mismatchAlert = false
    @State private var pinchBase: CGFloat? = nil     // つまみ始めたときの倍率
    @State private var mainPosition: AVCaptureDevice.Position = .back   // 先に撮る（大きく出す）カメラ。撮る前に切り替えられる
    @State private var dialBase: CGFloat? = nil      // 倍率ダイヤルを回し始めたときの倍率
    @State private var dialVisible = false           // 倍率ダイヤル（純正カメラの、ボタンを横に滑らせると出る目盛り）
    @State private var dialHide: Task<Void, Never>? = nil

    private var todayKey: String { store.activeDayKey() }
    /// 撮っている枠（開いたときに決める。投稿すると次の枠に移るので、id で探す）
    @State private var slotID: String? = nil
    private var record: PromptRecord? {
        guard let slotID else { return nil }
        return store.records.first { $0.id == slotID }
    }
    private var isShootingFront: Bool { frozenBack != nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch stage {
            case .camera: cameraStage
            case .review: reviewStage
            case .done: doneStage
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if slotID == nil { slotID = store.nextOpenRecord(day: todayKey)?.id }
            camera.start()
        }
        .onDisappear { abortSequence(); camera.stop() }
        .onChange(of: stage) { _, newStage in
            // 撮る画面以外では、カメラを止める
            if newStage == .camera { camera.start() } else { camera.stop() }
        }
        .alert(L("お題と違うかもしれません"), isPresented: $mismatchAlert) {
            Button(L("撮り直す")) { retake() }
            Button(L("このまま投稿")) {
                if let record, let photo {
                    store.savePost(id: record.id, photo: photo, front: frontShot, caption: caption, verified: false)
                    applyShare(to: record.id)
                    stage = .done
                }
            }
        } message: {
            Text(LF("「{p}」の写真に見えません。このまま投稿すると、タイムはランキングに入りません。", ["p": record.map { L($0.prompt) } ?? ""]))
        }
    }

    // MARK: 撮る

    private var cameraStage: some View {
        VStack(spacing: 0) {
            HStack {
                circleButton("xmark", label: L("閉じる")) { abortSequence(); dismiss() }
                Spacer()
                if camera.canFlash && !isShootingFront {
                    circleButton(camera.flashOn ? "bolt.fill" : "bolt.slash.fill",
                                 label: camera.flashOn ? L("フラッシュをオフにする") : L("フラッシュをオンにする"),
                                 tint: camera.flashOn ? Hi.neon : .white) {
                        camera.flashOn.toggle()
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)

            Spacer(minLength: 0)

            GeometryReader { geo in
                let side = geo.size.width
                ZStack(alignment: .topTrailing) {
                    // 大きい枠：撮る前は外カメラの映像。内カメラを撮っている間は、撮れた外カメラの写真
                    ZStack {
                        if let frozenBack {
                            Image(uiImage: frozenBack).resizable().scaledToFill()
                        } else if camera.isDenied {
                            notice(L("カメラの許可が必要です"), detail: L("設定アプリで、Difframeのカメラを許可してください。"))
                        } else if camera.isUnavailable {
                            notice(isSimulator ? L("シミュレーターにはカメラがありません") : L("カメラが使えません"),
                                   detail: isSimulator ? L("撮るボタンを押すと、テスト用の画像で進めます。") : L("この端末では、カメラを開けませんでした。"))
                        } else {
                            CameraPreview(session: camera.session)
                        }
                    }
                    .frame(width: side, height: side / PhotoShape.ratio)
                    .clipped()
                    .contentShape(Rectangle())
                    // 純正カメラと同じく、2回タップで前後を切り替える
                    .onTapGesture(count: 2) { flip() }
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                guard !isShootingFront else { return }
                                let base = pinchBase ?? camera.zoom
                                if pinchBase == nil { pinchBase = base }
                                camera.setZoom(base * value.magnification)
                            }
                            .onEnded { _ in pinchBase = nil }
                    )
                    .overlay(alignment: .bottom) {
                        if !isShootingFront && mainPosition == .back && !camera.zoomStops.isEmpty {
                            ZStack(alignment: .bottom) {
                                if dialVisible {
                                    ZoomDial(zoom: camera.zoom, minZoom: camera.minZoom, maxZoom: camera.maxZoom,
                                             stops: camera.zoomStops, width: side)
                                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottom)))
                                        // 出ている間は、ダイヤルを触り直すと、いまの倍率の続きから回せる
                                        .contentShape(Rectangle())
                                        .gesture(dialDrag(minimumDistance: 0))
                                }
                                zoomBar
                                    .padding(.bottom, 12)
                                    .opacity(dialVisible ? 0 : 1)
                            }
                            .animation(.easeOut(duration: 0.2), value: dialVisible)
                        }
                    }

                    // 小さい枠：内カメラ（撮っている間だけ出る）
                    if isShootingFront {
                        selfieTile(side: side * 0.30)
                            .padding(side * 0.04)
                            .transition(.scale(scale: 0.6, anchor: .topTrailing).combined(with: .opacity))
                    }
                }
                .frame(width: side, height: side / PhotoShape.ratio)
            }
            .aspectRatio(PhotoShape.ratio, contentMode: .fit)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isShootingFront)

            Spacer(minLength: 0)

            HStack {
                // 内カメラも撮るか（オプション）。オンのときは黄緑
                VStack(spacing: 4) {
                circleButton("person.crop.square.fill",
                             label: dualCamera ? L("両方のカメラで撮る：オン") : L("両方のカメラで撮る：オフ"),
                             tint: dualCamera ? Hi.neon : Hi.dim) {
                    dualCamera.toggle()
                }
                .opacity(isShootingFront || camera.isCapturing ? 0.35 : 1)
                .disabled(isShootingFront || camera.isCapturing)
                Text(dualCamera ? L("両方：オン") : L("両方：オフ"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(dualCamera ? Hi.neon : Hi.dim)
                }
                Spacer()
                shutter
                Spacer()
                // 前後の切り替え（撮る前に、どちらのカメラで撮るか選ぶ）
                circleButton("arrow.triangle.2.circlepath", label: L("カメラを切り替える")) { flip() }
                    .rotation3DEffect(.degrees(mainPosition == .front ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                    .animation(.easeInOut(duration: 0.3), value: mainPosition)
                    .opacity(isShootingFront || camera.isCapturing ? 0.35 : 1)
                    .disabled(isShootingFront || camera.isCapturing)
            }
            .padding(.horizontal, 32)

            promptFooter
                .padding(.top, 14)
                .padding(.bottom, 14)
        }
    }

    /// 内カメラの小さな枠。映像と、あと何秒かの数字
    private func selfieTile(side: CGFloat) -> some View {
        ZStack {
            if isSimulator {
                Hi.tile
            } else {
                CameraPreview(session: camera.session)
            }
            if let countdown {
                Text("\(countdown)")
                    .font(.system(size: side * 0.5, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 6)
            }
        }
        .frame(width: side, height: side / PhotoShape.ratio)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: side * 0.16, style: .continuous).stroke(Color.white, lineWidth: 2))
        .accessibilityLabel(L("内カメラ"))
    }

    /// 倍率ボタン（純正カメラと同じ）。機種のレンズに合わせて .5 / 1 / 2 / 3 などが並ぶ。
    /// ・押すと、その倍率へ
    /// ・ボタンの上で指を横に滑らせると、目盛りのダイヤルが出て、細かく倍率を変えられる
    private var zoomBar: some View {
        let stops = camera.zoomStops
        // いまの倍率以下で一番近いボタンを、選ばれている印にする（1.4倍なら「1」が 1.4× になる）
        let active = stops.last { $0 <= camera.zoom + 0.01 } ?? stops.first ?? 1
        return HStack(spacing: 4) {
            ForEach(stops, id: \.self) { stop in
                let isActive = stop == active
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    camera.setZoom(stop, ramp: true)
                } label: {
                    Text(isActive ? zoomLabel(camera.zoom, active: true) : zoomLabel(stop, active: false))
                        .font(.system(size: isActive ? 12 : 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isActive ? Color(red: 1, green: 0.84, blue: 0.04) : .white)
                        .frame(width: isActive ? 40 : 34, height: isActive ? 40 : 34)
                        .background(Circle().fill(Color.black.opacity(isActive ? 0.55 : 0.35)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LF("{n}倍", ["n": zoomLabel(stop, active: false)]))
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.black.opacity(0.25)))
        .contentShape(Capsule())
        .highPriorityGesture(dialDrag(minimumDistance: 6))
        .animation(.easeOut(duration: 0.15), value: camera.zoom)
    }

    /// ボタンの上で横に滑らせる：ダイヤルを出して、倍率を細かく変える（左へ滑らせると拡大）
    private func dialDrag(minimumDistance: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: minimumDistance)
            .onChanged { value in
                dialHide?.cancel()
                if dialBase == nil { dialBase = camera.zoom; dialVisible = true }
                let before = camera.zoom
                let next = (dialBase ?? 1) * pow(2, -value.translation.width / ZoomDial.pointsPerOctave)
                camera.setZoom(next)
                // ボタンの倍率をまたいだら、軽く振動させる
                if camera.zoomStops.contains(where: { ($0 - before) * ($0 - camera.zoom) < 0 || $0 == camera.zoom }) {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
            .onEnded { _ in
                dialBase = nil
                dialHide = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)   // 離しても2秒は残す（その間に触り直せる）
                    guard !Task.isCancelled else { return }
                    dialVisible = false
                }
            }
    }

    /// 倍率の表示（純正カメラと同じ。選ばれているボタンは「1×」「1.4×」、ほかは「.5」「2」「3」）
    private func zoomLabel(_ z: CGFloat, active: Bool) -> String {
        let r = (z * 10).rounded() / 10
        let number: String
        if r < 1 {
            number = active ? String(format: "%.1f", r) : String(format: ".%d", Int((r * 10).rounded()))
        } else if r == r.rounded() {
            number = "\(Int(r))"
        } else {
            number = String(format: "%.1f", r)
        }
        return active ? number + "×" : number
    }

    /// 前後のカメラを切り替える（撮る前だけ）
    private func flip() {
        guard sequence == nil, !camera.isCapturing else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        mainPosition = mainPosition == .back ? .front : .back
        dialVisible = false
        camera.switchTo(mainPosition)
    }

    private var shutter: some View {
        Button {
            startSequence()
        } label: {
            ZStack {
                Circle().stroke(Hi.neon, lineWidth: 5).frame(width: 82, height: 82)
                Circle().fill(.white).frame(width: 66, height: 66)
            }
            .opacity(isShootingFront || camera.isCapturing ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isShootingFront || camera.isCapturing || camera.isDenied || (camera.isUnavailable && !isSimulator))
        .accessibilityLabel(dualCamera
                            ? (mainPosition == .back ? L("撮る（外カメラのあと、内カメラも撮ります）") : L("撮る（内カメラのあと、外カメラも撮ります）"))
                            : L("撮る"))
    }

    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// 動画の「What's up!」の場所：お題と、いま進んでいるタイム
    private var promptFooter: some View {
        VStack(spacing: 8) {
            if let record {
                Text(L(record.prompt))
                    .font(.title2.weight(.black))
                    .foregroundStyle(.white)
                if let start = record.startedAt {
                    TimelineView(.periodic(from: .now, by: 0.1)) { context in
                        if context.date < start {
                            Text(L("通知を待っています"))
                                .font(.headline.weight(.black))
                                .foregroundStyle(Hi.neon)
                                .frame(height: 24)
                        } else if context.date.timeIntervalSince(start) > TodayView.lateAfter {
                            Text(L("遅れてもOK"))
                                .font(.headline.weight(.black))
                                .foregroundStyle(Hi.neon)
                                .frame(height: 24)
                        } else {
                            DotText(text: TimeFormat.string(context.date.timeIntervalSince(start)),
                                    pitch: 3.5, color: Hi.neon)
                        }
                    }
                }
                Text(isShootingFront
                     ? (mainPosition == .back ? L("内カメラも撮ります。そのまま構えてください") : L("外カメラも撮ります。そのまま構えてください"))
                     : dualCamera
                     ? (mainPosition == .back ? L("外カメラのあと、内カメラも撮ります") : L("内カメラのあと、外カメラも撮ります"))
                     : (PromptVerifier.canVerify(record.prompt)
                        ? L("お題に合う写真だけが、世界ランキングに入ります")
                        : L("このお題は自動で確認できないため、ランキング対象外です")))
                    .font(.caption)
                    .foregroundStyle(Hi.dim)
                    .padding(.top, 4)
            }
        }
    }

    private func notice(_ title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.fill").font(.largeTitle).foregroundStyle(Hi.dim)
            Text(title).font(.headline.weight(.black))
            Text(detail).font(.footnote).foregroundStyle(Hi.dim).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Hi.tile)
    }

    // MARK: 外カメラ → 内カメラ

    /// 外カメラで撮り、すぐに内カメラへ切り替えて、2秒のカウントダウンのあとに撮る
    private func startSequence() {
        guard sequence == nil else { return }
        sequence = Task { @MainActor in
            // 1. 選んでいるカメラ（初めは外カメラ）
            let first = mainPosition
            let second: AVCaptureDevice.Position = first == .back ? .front : .back
            camera.switchTo(first)
            let back: UIImage? = await withCheckedContinuation { continuation in
                camera.capture(useFlash: first == .back && camera.flashOn) { continuation.resume(returning: $0) }
            }
            guard !Task.isCancelled, let back else { finishSequence(); return }
            backShot = back

            // 初期設定：外カメラだけ。そのまま確認画面へ
            guard dualCamera else {
                photo = back
                sequence = nil
                stage = .review
                return
            }
            frozenBack = back

            // 2. もう片方のカメラへ切り替えて、数える
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                camera.switchTo(second) { continuation.resume() }
            }
            for second in [2, 1] {
                guard !Task.isCancelled else { finishSequence(); return }
                countdown = second
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard !Task.isCancelled else { finishSequence(); return }
            countdown = nil

            // 3. 内カメラ
            let front: UIImage? = await withCheckedContinuation { continuation in
                camera.capture(useFlash: false) { continuation.resume(returning: $0) }
            }
            guard !Task.isCancelled else { finishSequence(); return }
            // 内カメラが撮れなかったときは、外カメラだけで進む
            // 合成はしない。外カメラを大きく、内カメラを小さく重ねて見せ、別々に保存する
            photo = back
            frontShot = front
            sequence = nil
            frozenBack = nil
            stage = .review
        }
    }

    /// 途中でやめたとき：撮影を止めて、外カメラに戻す
    private func abortSequence() {
        sequence?.cancel()
        sequence = nil
        camera.cancelPending()
        countdown = nil
        frozenBack = nil
        camera.switchTo(mainPosition)
    }

    private func finishSequence() {
        sequence = nil
        camera.cancelPending()
        countdown = nil
        frozenBack = nil
        camera.switchTo(mainPosition)
    }

    // MARK: 確認して投稿

    private var reviewStage: some View {
        VStack(spacing: 14) {
            HStack {
                circleButton("chevron.left", label: L("撮り直す")) { retake() }
                Spacer()
                if let record {
                    Text(L(record.prompt)).font(.headline.weight(.black))
                }
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)

            if let photo {
                DualPhotoView(main: photo, inset: frontShot)
                    .aspectRatio(PhotoShape.ratio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipped()
            }

            TextField(L("一言（任意）"), text: $caption)
                .padding(12)
                .background(Hi.tile)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 16)

            Spacer(minLength: 0)

            // 投稿する → どこに送るかを選ぶ（DM から開いたときは、そのまま会話に送る）
            Button {
                if let directSend, let photo {
                    directSend(photo)
                    dismiss()
                } else {
                    showShare = true
                }
            } label: {
                if checking { ProgressView().tint(Hi.onNeon) } else { Text(directSend == nil ? L("投稿する") : L("送る")) }
            }
            .buttonStyle(NeonButtonStyle())
            .disabled(checking)
            .sheet(isPresented: $showShare) {
                ShareOptionsSheet(sendFriends: $sendFriends, sendPublic: $sendPublic,
                                  publicComments: $publicComments, addLocation: $addLocation,
                                  locator: locator) {
                    showShare = false
                    if let record, let photo { Task { await submit(record: record, photo: photo) } }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    /// 投稿の前に、外カメラの写真がお題に合うかを確かめる（重ねた1枚や、内カメラの写真では確かめない）
    private func submit(record: PromptRecord, photo: UIImage) async {
        checking = true
        let result = await PromptVerifier.verify(backShot ?? photo, prompt: record.prompt)
        checking = false
        if result == .notMatched {
            mismatchAlert = true
        } else {
            // お題に合うと確認できた写真だけ、ランキングに数える（不明なお題は数えない）
            store.savePost(id: record.id, photo: photo, front: frontShot, caption: caption, verified: result == .matched)
            applyShare(to: record.id)
            stage = .done
        }
    }

    /// 選んだ送り先・コメント・場所を、投稿に残す
    private func applyShare(to id: String) {
        store.setShareOptions(id: id, friends: sendFriends, everyone: sendPublic,
                              comments: publicComments, city: addLocation ? locator.city : nil)
    }

    private func retake() {
        photo = nil
        backShot = nil
        frontShot = nil
        frozenBack = nil
        caption = ""
        stage = .camera
    }

    // MARK: 投稿しました

    private var doneStage: some View {
        VStack(spacing: 14) {
            if let record {
                ZStack {
                    GlowBackground(palette: .forPrompt(record.prompt))
                    VStack(spacing: 10) {
                        // 上はカードの濃い色の上なので、白い文字にする（今日のカードと同じ）
                        Text(L("投稿しました"))
                            .font(.title3.weight(.black))
                            .foregroundStyle(.white)
                        Text(L(record.prompt))
                            .font(.system(size: 40, weight: .black))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                        Spacer()
                        if let elapsed = record.elapsed {
                            FitDotText(text: TimeFormat.string(elapsed), color: Color.black.opacity(0.82))
                            Text(L("今日のタイム"))
                                .font(.subheadline.weight(.bold))
                        } else {
                            Text(L("通知より前の投稿なので、タイムはありません"))
                                .font(.subheadline.weight(.bold))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .foregroundStyle(Color.black.opacity(0.82))
                    .padding(24)
                }
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 16)

                if record.verified == true && record.elapsed != nil {
                    Label(L("お題に合う写真と確認できました。世界ランキングに入ります"), systemImage: "checkmark.seal.fill")
                        .font(.subheadline)
                        .foregroundStyle(Hi.neon)
                        .padding(.horizontal, 16)
                } else {
                    Label(L("ランキングには入りません（お題との一致、または通知後のタイムが確認できないため）"), systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 16)
                }
            }
            if store.nextOpenRecord(day: todayKey) != nil {
                Button(LF("もう1枚撮る（今日 {a}/{b}）", ["a": "\(store.postedCount(day: todayKey))", "b": "\(PromptSlot.maxPerDay)"])) { nextShot() }
                    .buttonStyle(TileButtonStyle())
            }
            Button(L("閉じる")) { dismiss() }
                .buttonStyle(NeonButtonStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    /// 同じ日に、もう1枚撮る
    private func nextShot() {
        slotID = store.nextOpenRecord(day: todayKey)?.id
        photo = nil
        backShot = nil
        frontShot = nil
        frozenBack = nil
        caption = ""
        stage = .camera
    }

    // MARK: 部品

    private func circleButton(_ symbol: String, label: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Hi.tile))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}


// MARK: - 倍率ダイヤル（純正カメラの、弧の形の目盛り）

/// 倍率ボタンを横に滑らせたときに出る、弧の形の目盛り。
/// 目盛りは倍率の対数で並ぶ（.5→1 と 1→2 が同じ幅）。ボタンの倍率には数字と焦点距離（mm）を出す。
struct ZoomDial: View {
    let zoom: CGFloat
    let minZoom: CGFloat
    let maxZoom: CGFloat
    let stops: [CGFloat]
    let width: CGFloat

    /// 指を何ポイント動かすと、倍率が2倍（半分）になるか
    static let pointsPerOctave: CGFloat = 62
    private static let gold = Color(red: 1, green: 0.84, blue: 0.04)

    private var radius: CGFloat { width * 0.62 }
    private var height: CGFloat { width * 0.36 }

    /// 35mm 換算の焦点距離（純正カメラの表示に合わせる）
    static func millimeters(_ z: CGFloat) -> Int {
        switch (z * 10).rounded() / 10 {
        case 0.5: return 13
        case 3: return 77
        case 4: return 100
        case 5: return 120
        case 8: return 200
        default: return Int((24 * z).rounded())
        }
    }

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: radius + 26)
            let anglePerOctave = Self.pointsPerOctave / radius
            let now = log2(max(zoom, 0.01))
            func point(_ angle: CGFloat, _ r: CGFloat) -> CGPoint {
                CGPoint(x: center.x + r * sin(angle), y: center.y - r * cos(angle))
            }
            // 背景の円
            let bg = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            ctx.fill(bg, with: .color(.black.opacity(0.5)))

            // 細かい目盛り（1オクターブを10等分）
            let lo = log2(minZoom), hi = log2(maxZoom)
            var v = (lo * 10).rounded(.up) / 10
            while v <= hi + 0.0001 {
                let a = (v - now) * anglePerOctave
                if abs(a) < 1.25 {
                    var tick = Path()
                    tick.move(to: point(a, radius - 4))
                    tick.addLine(to: point(a, radius - 12))
                    ctx.stroke(tick, with: .color(.white.opacity(0.55)), lineWidth: 1)
                }
                v += 0.1
            }
            // ボタンの倍率：長い目盛り・数字・mm
            for stop in stops + [maxZoom] {
                let a = (log2(stop) - now) * anglePerOctave
                guard abs(a) < 1.25 else { continue }
                var tick = Path()
                tick.move(to: point(a, radius - 4))
                tick.addLine(to: point(a, radius - 18))
                ctx.stroke(tick, with: .color(.white), lineWidth: 1.5)
                let near = abs(a) < 0.12
                if !near {
                    let label = stop < 1 ? String(format: "%.1f", stop) : (stop == stop.rounded() ? "\(Int(stop))" : String(format: "%.1f", stop))
                    ctx.draw(Text(label).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(.white),
                             at: point(a, radius - 32))
                    if stops.contains(stop) {
                        ctx.draw(Text("\(Self.millimeters(stop))MM").font(.system(size: 8, weight: .semibold)).foregroundColor(.white.opacity(0.6)),
                                 at: point(a, radius - 46))
                    }
                }
            }
            // まんなかの印と、いまの倍率
            var mark = Path()
            mark.move(to: CGPoint(x: center.x - 5, y: center.y - radius + 1))
            mark.addLine(to: CGPoint(x: center.x + 5, y: center.y - radius + 1))
            mark.addLine(to: CGPoint(x: center.x, y: center.y - radius + 8))
            mark.closeSubpath()
            ctx.fill(mark, with: .color(Self.gold))
            let r = (zoom * 10).rounded() / 10
            let current = (r == r.rounded() ? "\(Int(r))" : String(format: "%.1f", r)) + "×"
            ctx.draw(Text(current).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundColor(Self.gold),
                     at: CGPoint(x: center.x, y: center.y - radius + 30))
            ctx.draw(Text("\(Self.millimeters(zoom))MM").font(.system(size: 9, weight: .semibold)).foregroundColor(Self.gold.opacity(0.8)),
                     at: CGPoint(x: center.x, y: center.y - radius + 46))
        }
        .frame(width: width, height: height)
        .clipped()
        .accessibilityLabel(LF("{n}倍", ["n": String(format: "%.1f", zoom)]))
    }
}


// MARK: - どこに送るか

/// 「投稿する」のあとに出る画面。友達・みんな（両方も可）、みんなでのコメント、場所（都市の名前だけ）を選ぶ
struct ShareOptionsSheet: View {
    @Binding var sendFriends: Bool
    @Binding var sendPublic: Bool
    @Binding var publicComments: Bool
    @Binding var addLocation: Bool
    @ObservedObject var locator: CityLocator
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("どこに送る？"))
                .font(.title2.weight(.black))
                .padding(.top, 24)
            Text(L("両方を選ぶこともできます"))
                .font(.footnote).foregroundStyle(Hi.dim)

            audienceRow(selected: $sendFriends, icon: "person.2.fill", title: L("友達"),
                        detail: L("友達だけが見られます。コメントはいつでもオン"))

            VStack(spacing: 0) {
                audienceRow(selected: $sendPublic, icon: "globe.asia.australia.fill", title: L("みんな"),
                            detail: L("世界中の人が見られます"))
                if sendPublic {
                    Toggle(isOn: $publicComments) {
                        Label(L("コメントを受け付ける"), systemImage: "bubble.left")
                            .font(.subheadline.weight(.bold))
                    }
                    .tint(Hi.neon)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Hi.tile.opacity(0.6))
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18, style: .continuous))
                    .padding(.top, -6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            // 場所：都市の名前だけ
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $addLocation) {
                    Label(L("場所をつける"), systemImage: "mappin.and.ellipse")
                        .font(.subheadline.weight(.bold))
                }
                .tint(Hi.neon)
                if addLocation {
                    locationStatus.font(.caption)
                }
                Text(L("「東京」のような都市の名前だけをつけます。正確な場所は送りません。"))
                    .font(.caption2).foregroundStyle(Hi.dim)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Hi.tile))

            Spacer(minLength: 0)

            Button(action: onSend) {
                Text(L("送る"))
            }
            .buttonStyle(NeonButtonStyle())
            .disabled(!sendFriends && !sendPublic)
            if !sendFriends && !sendPublic {
                Text(L("送り先を1つ以上選んでください"))
                    .font(.caption).foregroundStyle(Hi.dim)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .animation(.easeOut(duration: 0.2), value: sendPublic)
        .animation(.easeOut(duration: 0.2), value: addLocation)
        .presentationDetents([.large])
        .presentationBackground(.black)
        .preferredColorScheme(.dark)
        .onAppear { if addLocation && locator.city == nil { locator.request() } }
        .onChange(of: addLocation) { _, on in
            if on { locator.request() } else { locator.reset() }
        }
    }

    @ViewBuilder
    private var locationStatus: some View {
        switch locator.state {
        case .idle, .locating:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(L("場所を調べています…")) }
                .foregroundStyle(Hi.dim)
        case .found(let name):
            Label(name, systemImage: "mappin").foregroundStyle(Hi.neon).font(.subheadline.weight(.black))
        case .denied:
            Text(L("位置情報が許可されていません。設定アプリで許可すると、つけられます。")).foregroundStyle(.orange)
        case .failed:
            HStack {
                Text(L("場所がわかりませんでした")).foregroundStyle(.orange)
                Button(L("もう一度")) { locator.request() }.foregroundStyle(Hi.neon)
            }
        }
    }

    private func audienceRow(selected: Binding<Bool>, icon: String, title: String, detail: String) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selected.wrappedValue.toggle()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(selected.wrappedValue ? Hi.neon : Color.white.opacity(0.08)))
                    .foregroundStyle(selected.wrappedValue ? Hi.onNeon : .white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline.weight(.black))
                    Text(detail).font(.caption).foregroundStyle(Hi.dim)
                }
                Spacer(minLength: 0)
                Image(systemName: selected.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected.wrappedValue ? Hi.neon : Hi.dim)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Hi.tile))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(selected.wrappedValue ? Hi.neon : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected.wrappedValue ? .isSelected : [])
    }
}
