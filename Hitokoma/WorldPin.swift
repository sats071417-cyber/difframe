import SwiftUI
import CoreLocation

/// 世界の地図・地球に立つ、1件の本物の投稿（サーバーの公開投稿から作る）。
/// 座標は都市の中心あたり（正確な位置ではない）。写真は投稿された本物の写真。
struct WorldPin: Identifiable, Equatable {
    let id: String
    let city: String
    let handle: String
    let name: String
    let latitude: Double
    let longitude: Double
    let tzOffset: Int           // 投稿した場所の、世界標準時との差（秒）
    let postedAt: Date
    let elapsed: Double?        // 今日のお題のタイム（秒）
    let photo: UIImage?
    let greeting: String?

    static func == (a: WorldPin, b: WorldPin) -> Bool { a.id == b.id }

    /// 座標のついた公開投稿だけを、ピンにする
    init?(_ post: CloudPost) {
        guard let lat = post.latitude, let lon = post.longitude else { return nil }
        id = post.id
        city = post.city ?? ""
        handle = post.handle
        name = post.name
        latitude = lat
        longitude = lon
        tzOffset = post.tzOffset
        postedAt = post.postedAt
        elapsed = post.elapsed
        photo = post.photo
        greeting = post.greeting
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var timeZone: TimeZone { TimeZone(secondsFromGMT: tzOffset) ?? .gmt }

    /// 投稿した場所の、投稿したときの現地時刻（例："07:45"）
    func localTime(base: Date = Date()) -> String {
        Clock.string(postedAt, zone: timeZone)
    }

    func localHour(base: Date = Date()) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.component(.hour, from: postedAt)
    }

    func light(base: Date = Date()) -> LocalLight { LocalLight(hour: localHour(base: base)) }
}

/// その土地のいまの光
enum LocalLight {
    case dawn, day, dusk, night

    init(hour: Int) {
        switch hour {
        case 5...7: self = .dawn
        case 8...16: self = .day
        case 17...20: self = .dusk
        default: self = .night
        }
    }

    var name: String {
        switch self {
        case .dawn: return L("朝")
        case .day: return L("昼")
        case .dusk: return L("夕方")
        case .night: return L("夜")
        }
    }

    var icon: String {
        switch self {
        case .dawn: return "sunrise.fill"
        case .day: return "sun.max.fill"
        case .dusk: return "sunset.fill"
        case .night: return "moon.stars.fill"
        }
    }

    var palette: GlowPalette {
        func c(_ hex: UInt32) -> Color {
            Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
        }
        switch self {
        case .dawn:
            return GlowPalette(top: c(0x7A2E6B), bottom: c(0xFF8F6B), left: c(0xFFB347), right: c(0xFF5C8A), halo: c(0xFFE0A8), core: c(0xFFF6E0))
        case .day:
            return GlowPalette(top: c(0x1A6BE0), bottom: c(0x6FD0FF), left: c(0x19D3C5), right: c(0xFFE45C), halo: c(0xE6F8FF), core: c(0xFFFFFF))
        case .dusk:
            return GlowPalette(top: c(0x5B16B8), bottom: c(0xFF7A3D), left: c(0xFF3D8B), right: c(0xFFC247), halo: c(0xFFD0A0), core: c(0xFFF1DC))
        case .night:
            return GlowPalette(top: c(0x0A0F3C), bottom: c(0x2B2F8F), left: c(0x6A3DFF), right: c(0x19A0E0), halo: c(0xB8C4FF), core: c(0xF2F4FF))
        }
    }

    /// 明るい光の上では黒い文字、夜は白い文字
    var textColor: Color {
        self == .night ? .white : Color.black.opacity(0.82)
    }
}
