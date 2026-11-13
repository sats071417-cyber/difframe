import Foundation

/// サーバー（Firebase）の設定。どちらかが空なら、サーバーは使わず、端末の中だけで動く。
/// Firebase コンソール → プロジェクトの設定 で確認できる。
enum CloudConfig {
    static let projectID = "difframe-acae0"
    static let apiKey = "AIzaSyC8jNFSxoQml1C2FAkgKbCx40Vnr0kiq0k"

    static var isEnabled: Bool { !projectID.isEmpty && !apiKey.isEmpty }
}
