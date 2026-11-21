import Foundation
import CoreLocation

/// 太陽の位置から、昼と夜の境目を計算する（外部のデータは使わない）
enum Sun {
    private static func rad(_ d: Double) -> Double { d * .pi / 180 }
    private static func norm360(_ d: Double) -> Double { let r = d.truncatingRemainder(dividingBy: 360); return r < 0 ? r + 360 : r }

    /// 太陽が真上に来ている場所（太陽直下点）
    static func subsolar(_ date: Date) -> CLLocationCoordinate2D {
        let jd = date.timeIntervalSince1970 / 86400 + 2440587.5
        let n = jd - 2451545.0
        let L = norm360(280.460 + 0.9856474 * n)
        let g = rad(357.528 + 0.9856003 * n)
        let lambda = rad(L + 1.915 * sin(g) + 0.020 * sin(2 * g))
        let eps = rad(23.439 - 0.0000004 * n)
        let dec = asin(sin(eps) * sin(lambda))
        let ra = atan2(cos(eps) * sin(lambda), cos(lambda)) * 180 / .pi
        let gmst = norm360(280.46061837 + 360.98564736629 * n)
        var lon = norm360(ra - gmst)
        if lon > 180 { lon -= 360 }
        return CLLocationCoordinate2D(latitude: dec * 180 / .pi, longitude: lon)
    }

    /// 太陽の高さ（度）
    static func altitude(lat: Double, lon: Double, sun: CLLocationCoordinate2D) -> Double {
        let p = rad(lat), d = rad(sun.latitude), dl = rad(lon - sun.longitude)
        return asin(sin(p) * sin(d) + cos(p) * cos(d) * cos(dl)) * 180 / .pi
    }

    /// 太陽の高さが altitude 度より低い側（夜側）の、地図に塗る多角形
    static func nightPolygon(altitude h: Double, sun: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        var decDeg = sun.latitude
        if abs(decDeg) < 0.5 { decDeg = decDeg < 0 ? -0.5 : 0.5 }
        let dec = rad(decDeg), sinH = sin(rad(h))
        let nightPole = decDeg > 0 ? -85.0 : 85.0
        var points: [CLLocationCoordinate2D] = []
        for lon in stride(from: -180.0, through: 180.0, by: 3.0) {
            let a = sin(dec), b = cos(dec) * cos(rad(lon - sun.longitude))
            let r = hypot(a, b), psi = atan2(b, a)
            var lat: Double? = nil
            if r > 1e-9, abs(sinH / r) <= 1 {
                let s = asin(sinH / r)
                for cand in [s - psi, .pi - s - psi] {
                    var c = cand
                    while c > .pi { c -= 2 * .pi }
                    while c < -.pi { c += 2 * .pi }
                    if abs(c) <= .pi / 2 { lat = c * 180 / .pi; break }
                }
            }
            if lat == nil {
                // この経線は、端から端まで、夜か昼のどちらか
                let sunPole = -nightPole
                lat = altitude(lat: sunPole, lon: lon, sun: sun) < h ? sunPole : nightPole
            }
            points.append(CLLocationCoordinate2D(latitude: max(-85, min(85, lat!)), longitude: lon))
        }
        points.append(CLLocationCoordinate2D(latitude: nightPole, longitude: 180))
        points.append(CLLocationCoordinate2D(latitude: nightPole, longitude: -180))
        return points
    }

    /// 平らな地図用：夜が深くなるほど濃くなる、重ねた多角形（薄明のグラデーション）
    static func nightLayers(_ date: Date) -> [[CLLocationCoordinate2D]] {
        let sun = subsolar(date)
        return stride(from: 3.0, through: -21.0, by: -3.0).map { nightPolygon(altitude: $0, sun: sun) }
    }
}
