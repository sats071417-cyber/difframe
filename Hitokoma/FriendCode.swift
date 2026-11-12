import SwiftUI
import UIKit
import AVFoundation
import CoreImage

/// 自分の友達コード（ID）と、共有用のURL・QRコード
enum FriendCode {
    private static let key = "myFriendID"
    static let scheme = "hitokoma"

    /// 自分のID（最初の1回だけ作って端末に保存）
    static var myID: String {
        if let saved = UserDefaults.standard.string(forKey: key) { return saved }
        let chars = Array("abcdefghjkmnpqrstuvwxyz23456789")
        let id = String((0..<8).compactMap { _ in chars.randomElement() })
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    /// 共有用のURL（LINEなどで送れる）
    static var shareURL: URL {
        URL(string: "\(scheme)://add?id=\(myID)")!
    }

    /// 貼られた文字（URLまたはID）から友達のIDを取り出す
    static func parse(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
           !id.isEmpty {
            return id
        }
        // IDだけが貼られた場合
        let allowed = CharacterSet.alphanumerics
        if !trimmed.isEmpty, trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            return trimmed
        }
        return nil
    }

    /// QRコードの画像を作る
    static func qrImage(for url: URL, size: CGFloat = 220) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(url.absoluteString.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// 相手のQRコードを読み取るカメラ画面
struct QRScannerView: UIViewControllerRepresentable {
    let onFound: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onFound = onFound
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {}

    final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onFound: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var didFind = false

        override func viewDidLoad() {
            super.viewDidLoad()
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds
            view.layer.addSublayer(preview)
            DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if session.isRunning { session.stopRunning() }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !didFind,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = object.stringValue else { return }
            didFind = true
            onFound?(value)
        }
    }
}
