import SwiftUI
import CoreLocation

/// 世界の「いま」のサンプル。サーバーがないため、世界各地の人の投稿を、サンプルとして並べる。
/// 同じお題でも、場所によって時刻・光・言葉が違う、というこのアプリの見どころを見せるためのもの。
/// 写真は本物ではないので、その土地の「いまの光」（朝・昼・夕・夜）の色で表す。
struct WorldSample: Identifiable, Equatable {
    let id: String
    let city: String
    let country: String        // 日本語の国名
    let code: String           // 国コード（国旗の絵文字に使う）
    let timeZoneID: String
    let latitude: Double
    let longitude: Double
    let minutesAgo: Int        // 何分前に投稿したか
    let greeting: String       // その土地の言葉のあいさつ
    let language: String       // 言語の名前（日本語）
    let handle: String         // ハンドル名（@の後ろ）
    let time: TimeInterval     // 今日のお題のタイム（秒）
    let rank: Rank             // 今月のランク
    let trophies: [Trophy]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// 投稿した人が、コメントをオフにしているか（サンプル：一部の人だけ）
    var commentsOff: Bool {
        ["seoul", "berlin", "saopaulo"].contains(id)
    }

    var flag: String {
        code.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(127397 + $0.value) }
            .map { String($0) }
            .joined()
    }

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .gmt }

    /// 投稿した時刻（読み込んだ時刻から、何分前か）
    func postedAt(base: Date) -> Date {
        base.addingTimeInterval(-Double(minutesAgo) * 60)
    }

    /// その土地の現地時刻（例："07:45"）
    func localTime(base: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: postedAt(base: base))
    }

    func localHour(base: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.component(.hour, from: postedAt(base: base))
    }

    func light(base: Date) -> LocalLight { LocalLight(hour: localHour(base: base)) }

    /// 写真。同梱の「world-<id>.jpg」があればそれを使う（無ければ nil で、光の色で表す）
    var photo: UIImage? {
        guard let path = Bundle.main.path(forResource: "world-\(id)", ofType: "jpg") else { return nil }
        return UIImage(contentsOfFile: path)
    }
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

enum WorldSamples {
    /// 世界の各地のサンプル（時差が大きく違う場所を選んでいる）
    static let all: [WorldSample] = [
        WorldSample(id: "tokyo", city: L("東京"), country: L("日本"), code: "JP", timeZoneID: "Asia/Tokyo",
                    latitude: 35.68, longitude: 139.77, minutesAgo: 4, greeting: L("やあ"), language: L("日本語"),
                    handle: "yuki.t", time: 8.4, rank: .diamond, trophies: [.streak30, .under10, .posts10, .firstPost]),
        WorldSample(id: "seoul", city: L("ソウル"), country: L("韓国"), code: "KR", timeZoneID: "Asia/Seoul",
                    latitude: 37.57, longitude: 126.98, minutesAgo: 142, greeting: "안녕", language: L("韓国語"),
                    handle: "jin.seoul", time: 33.1, rank: .silver, trophies: [.streak3, .firstPost]),
        WorldSample(id: "singapore", city: L("シンガポール"), country: L("シンガポール"), code: "SG", timeZoneID: "Asia/Singapore",
                    latitude: 1.35, longitude: 103.82, minutesAgo: 262, greeting: L("你好"), language: L("中国語"),
                    handle: "wei.sg", time: 19.0, rank: .gold, trophies: [.under30, .firstPost]),
        WorldSample(id: "mumbai", city: L("ムンバイ"), country: L("インド"), code: "IN", timeZoneID: "Asia/Kolkata",
                    latitude: 19.08, longitude: 72.88, minutesAgo: 104, greeting: "नमस्ते", language: L("ヒンディー語"),
                    handle: "priya_m", time: 26.8, rank: .silver, trophies: [.under60, .firstPost]),
        WorldSample(id: "cairo", city: L("カイロ"), country: L("エジプト"), code: "EG", timeZoneID: "Africa/Cairo",
                    latitude: 30.04, longitude: 31.24, minutesAgo: 72, greeting: "مرحبا", language: L("アラビア語"),
                    handle: "omar.cairo", time: 96.7, rank: .bronze, trophies: [.firstPost]),
        WorldSample(id: "nairobi", city: L("ナイロビ"), country: L("ケニア"), code: "KE", timeZoneID: "Africa/Nairobi",
                    latitude: -1.29, longitude: 36.82, minutesAgo: 192, greeting: "Jambo", language: L("スワヒリ語"),
                    handle: "amara.k", time: 14.2, rank: .platinum, trophies: [.streak7, .under30, .firstPost]),
        WorldSample(id: "paris", city: L("パリ"), country: L("フランス"), code: "FR", timeZoneID: "Europe/Paris",
                    latitude: 48.86, longitude: 2.35, minutesAgo: 29, greeting: "Salut", language: L("フランス語"),
                    handle: "camille_p", time: 132.5, rank: .bronze, trophies: [.firstPost]),
        WorldSample(id: "berlin", city: L("ベルリン"), country: L("ドイツ"), code: "DE", timeZoneID: "Europe/Berlin",
                    latitude: 52.52, longitude: 13.40, minutesAgo: 166, greeting: "Hallo", language: L("ドイツ語"),
                    handle: "lena_b", time: 11.9, rank: .platinum, trophies: [.streak7, .under10, .firstPost]),
        WorldSample(id: "reykjavik", city: L("レイキャビク"), country: L("アイスランド"), code: "IS", timeZoneID: "Atlantic/Reykjavik",
                    latitude: 64.15, longitude: -21.94, minutesAgo: 222, greeting: "Halló", language: L("アイスランド語"),
                    handle: "sigrun.is", time: 47.3, rank: .silver, trophies: [.streak3, .firstPost]),
        WorldSample(id: "saopaulo", city: L("サンパウロ"), country: L("ブラジル"), code: "BR", timeZoneID: "America/Sao_Paulo",
                    latitude: -23.55, longitude: -46.63, minutesAgo: 123, greeting: "Oi", language: L("ポルトガル語"),
                    handle: "sofia_sp", time: 41.5, rank: .silver, trophies: [.firstPost]),
        WorldSample(id: "newyork", city: L("ニューヨーク"), country: L("アメリカ"), code: "US", timeZoneID: "America/New_York",
                    latitude: 40.71, longitude: -74.01, minutesAgo: 16, greeting: "Hey", language: L("英語"),
                    handle: "emma_ny", time: 74.2, rank: .bronze, trophies: [.firstPost]),
        WorldSample(id: "mexicocity", city: L("メキシコシティ"), country: L("メキシコ"), code: "MX", timeZoneID: "America/Mexico_City",
                    latitude: 19.43, longitude: -99.13, minutesAgo: 57, greeting: "Hola", language: L("スペイン語"),
                    handle: "mateo_mx", time: 17.6, rank: .gold, trophies: [.under30, .posts10, .firstPost]),
        WorldSample(id: "vancouver", city: L("バンクーバー"), country: L("カナダ"), code: "CA", timeZoneID: "America/Vancouver",
                    latitude: 49.28, longitude: -123.12, minutesAgo: 88, greeting: "Hi", language: L("英語"),
                    handle: "chloe.v", time: 21.3, rank: .gold, trophies: [.streak3, .under60, .firstPost]),
        WorldSample(id: "sydney", city: L("シドニー"), country: L("オーストラリア"), code: "AU", timeZoneID: "Australia/Sydney",
                    latitude: -33.87, longitude: 151.21, minutesAgo: 41, greeting: "G'day", language: L("英語"),
                    handle: "liam.syd", time: 58.0, rank: .bronze, trophies: [.firstPost]),
    ]
}
