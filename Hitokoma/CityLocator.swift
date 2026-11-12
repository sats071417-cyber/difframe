import Foundation
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
