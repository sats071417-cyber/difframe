import SwiftUI
import AVFoundation
import UIKit

/// DM の写真を、送れる大きさに縮める（1メッセージは 1MB まで。目安 800KB）
enum ChatPhoto {
    static func encode(_ image: UIImage, startSide: CGFloat = 1200, budget: Int = 800_000) -> Data {
        var side: CGFloat = startSide
        var quality: CGFloat = 0.7
        while true {
            let data = image.scaled(maxSide: side).jpegData(compressionQuality: quality) ?? Data()
            if data.count < budget || side < 400 { return data }
            side *= 0.85
            quality = max(0.4, quality - 0.08)
        }
    }
}

/// ボイスの録音。押している間だけ録る（最長60秒）
@MainActor
final class VoiceRecorder: ObservableObject {
    @Published private(set) var recording = false
    private var recorder: AVAudioRecorder?
    private var url: URL?
    private var elapsed: Double = 0
    private var timer: Timer?

    /// 録音を始める。マイクを使えないときは false
    func start() async -> Bool {
        guard !recording else { return true }
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 22050,
                                           AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32000]
            let r = try AVAudioRecorder(url: file, settings: settings)
            r.record()
            recorder = r
            url = file
            elapsed = 0
            recording = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let r = self.recorder else { return }
                    self.elapsed = r.currentTime
                    if r.currentTime >= 60 { r.stop() }   // 60秒で止める（離すまで、録れた分は送れる）
                }
            }
            return true
        } catch {
            return false
        }
    }

    /// 録音を終えて、データと長さを返す（短すぎるときは nil）
    func stop() -> (data: Data, duration: Double)? {
        timer?.invalidate()
        timer = nil
        guard let r = recorder, let url else { return nil }
        let duration = min(60, elapsed)
        r.stop()
        recorder = nil
        recording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        defer { try? FileManager.default.removeItem(at: url) }
        guard duration >= 0.6, let data = try? Data(contentsOf: url) else { return nil }
        return (data, duration)
    }
}

/// ボイスの再生（1つずつ）
@MainActor
final class VoicePlayer: ObservableObject {
    @Published private(set) var playing = false
    private var player: AVAudioPlayer?

    func toggle(_ data: Data) {
        if playing {
            player?.stop()
            playing = false
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(data: data)
            p.play()
            player = p
            playing = true
            let length = p.duration
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64((length + 0.2) * 1_000_000_000))
                if self.player === p { self.playing = false }
            }
        } catch {
            playing = false
        }
    }
}

/// カメラで1枚撮る（DM の中だけに送る。フィードには出ない）
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        init(onImage: @escaping (UIImage) -> Void) { self.onImage = onImage }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { onImage(image) }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onImage(UIImage())   // 空の画像は、送らずに閉じる印
        }
    }
}
