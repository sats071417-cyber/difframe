import Foundation
import CoreLocation

/// 1件の投稿（方法A：サンプル投稿）
struct Post: Codable, Identifiable {
    let id: String
    let isDemo: Bool
    let prompt: String        // お題（例：「赤いもの」）
    let caption: String       // 一言
    let city: String
    let latitude: Double
    let longitude: Double
    let photo: String         // バンドル内の写真ファイル名
    let postedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// サンプル投稿の読み込み
enum SamplePosts {
    private struct File: Codable {
        let posts: [Post]
    }

    /// 失敗しても空の配列を返し、アプリが落ちないようにする
    static func load() -> [Post] {
        guard let url = Bundle.main.url(forResource: "sample_posts", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(File.self, from: data).posts) ?? []
    }
}
