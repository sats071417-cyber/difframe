import Foundation
import SwiftUI
import CoreLocation

/// 投稿につける「場所」。正確な位置ではなく、「東京」のような都市の名前だけを求める。
/// ・都市の境目で間違えないよう、正確な位置で調べる
/// ・名前に変えたら、位置そのものは捨てる（保存も送信もしない）
@MainActor
final class CityLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum State: Equatable { case idle, locating, found(String), denied, failed }

    @Published private(set) var state: State = .idle
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters   // 都市を正しく見分けるため、正確な位置で調べる（保存・送信するのは都市の名前だけ）
    }

    var city: String? {
        if case .found(let name) = state { return name }
        return nil
    }

    func request() {
        switch manager.authorizationStatus {
        case .notDetermined:
            state = .locating
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            state = .denied
        default:
            state = .locating
            manager.requestLocation()
        }
    }

    func reset() { state = .idle }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.state == .locating else { return }
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
            case .denied, .restricted: self.state = .denied
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.name(for: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if self.state == .locating { self.state = .failed }
        }
    }

    /// 位置を、都市の名前に変える（アプリの言語で）
    /// 東京の23区は、区の名前（千代田区など）ではなく「東京」にする
    private func name(for location: CLLocation) {
        let lang = AppLanguage.current.rawValue
        // まず日本語で調べて、東京の区かどうかを見分ける（区の名前は「〜区」で終わる）
        geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "ja")) { [weak self] marks, _ in
            Task { @MainActor in
                guard let self else { return }
                guard let ja = marks?.first else { self.state = .failed; return }
                let isTokyoWard = ja.isoCountryCode == "JP" && (ja.locality?.hasSuffix("区") ?? false)
                    && (ja.administrativeArea == "東京都")
                if lang == "ja" {
                    self.finish(ja, useArea: isTokyoWard)
                } else {
                    self.geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: lang)) { marks, _ in
                        Task { @MainActor in self.finish(marks?.first ?? ja, useArea: isTokyoWard) }
                    }
                }
            }
        }
    }

    private func finish(_ mark: CLPlacemark, useArea: Bool) {
        var name = useArea ? mark.administrativeArea : (mark.locality ?? mark.administrativeArea ?? mark.country)
        if useArea, name == "東京都" { name = "東京" }
        if let name { state = .found(name) } else { state = .failed }
    }
}


// MARK: - 見る人の言語での、都市の名前

/// 投稿の都市名は、投稿した人の言語で保存されている。見る人の言語で出すために、座標（都市の中心あたり）から、見る人の言語で名前を調べ直す。
/// 結果は覚えておく（同じ場所を何度も調べない）。調べられないときは、保存されている名前のまま。
@MainActor
final class CityNames {
    static let shared = CityNames()
    private var cache: [String: String] = [:]
    private let geocoder = CLGeocoder()
    private var busy = false

    private func key(_ lat: Double, _ lon: Double) -> String {
        "\(AppLanguage.current.rawValue):\(String(format: "%.2f,%.2f", lat, lon))"
    }

    func cached(lat: Double, lon: Double) -> String? { cache[key(lat, lon)] }

    func resolve(lat: Double, lon: Double) async -> String? {
        let k = key(lat, lon)
        if let hit = cache[k] { return hit }
        // 調べるのは、1回に1件ずつ（続けて頼むと、断られるため）
        while busy { try? await Task.sleep(nanoseconds: 200_000_000); if let hit = cache[k] { return hit } }
        busy = true
        defer { busy = false }
        let lang = AppLanguage.current == .zh ? "zh-Hans" : AppLanguage.current.rawValue
        let marks = try? await geocoder.reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon), preferredLocale: Locale(identifier: lang))
        guard let mark = marks?.first, let name = mark.locality ?? mark.administrativeArea ?? mark.country, !name.isEmpty else { return nil }
        cache[k] = name
        return name
    }
}

/// 都市の名前（見る人の言語）。座標がなければ、保存されている名前のまま
struct CityText: View {
    let city: String
    var latitude: Double? = nil
    var longitude: Double? = nil
    @State private var name: String? = nil

    var body: some View {
        Text(name ?? city)
            .task(id: "\(latitude ?? 0),\(longitude ?? 0),\(AppLanguage.current.rawValue)") {
                guard let lat = latitude, let lon = longitude else { return }
                if let hit = CityNames.shared.cached(lat: lat, lon: lon) { name = hit; return }
                if let found = await CityNames.shared.resolve(lat: lat, lon: lon) { name = found }
            }
    }
}
