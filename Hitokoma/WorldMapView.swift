import SwiftUI
import MapKit

/// 世界の投稿を、Appleの地図の上に出す。ピンは、その土地のいまの光（朝・昼・夕・夜）の色。
/// 選んだ都市へは、地図が動く。ピンは、世界の人の本物の公開投稿。
struct WorldMapView: View {
    let samples: [WorldPin]
    let base: Date
    var myPhoto: UIImage? = nil
    /// 「世界の今」から来たとき、地図を動かす先
    var focus: WorldFocusRequest? = nil
    @Binding var selectedID: String?
    @StateObject private var me = MyLocation()
    @State private var cameraDistance: CLLocationDistance = WorldMapView.overview   // いま見ている高さ（選んでも縮小しないため）
    @State private var appliedFocus: UUID? = nil
    @State private var centerPlace: CenterPlace? = nil           // 近づいたとき、地図の中心の現地時刻
    @State private var geocoder = CLGeocoder()

    /// 最初は、自分のいるあたりを中心に、地球の半分が見える高さで見る
    @State private var position: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: WorldMapView.home, distance: WorldMapView.overview, heading: 0, pitch: 0)
    )

    /// 地球が丸く、まるごと見える高さ
    static let overview: CLLocationDistance = 24_000_000

    /// 自分のいるあたり。位置情報は使わず、iPhone のタイムゾーンから推定する
    /// （経度は時差 × 15度。緯度は、南半球のタイムゾーンなら南、それ以外は北の中緯度）
    static var home: CLLocationCoordinate2D {
        let tz = TimeZone.current
        let lon = max(-170, min(170, Double(tz.secondsFromGMT()) / 3600 * 15))
        let id = tz.identifier
        let south = ["Australia/", "Pacific/Auckland", "Antarctica/", "America/Sao_Paulo", "America/Argentina",
                     "America/Santiago", "America/Montevideo", "America/Lima", "Africa/Johannesburg", "Africa/Maputo",
                     "Indian/Antananarivo", "Indian/Mauritius", "Asia/Jakarta"].contains { id.hasPrefix($0) }
        return CLLocationCoordinate2D(latitude: south ? -25 : 32, longitude: lon)
    }

    private var selected: WorldPin? { samples.first { $0.id == selectedID } }

    var body: some View {
        flatMap
            .overlay(alignment: .topLeading) {
                // 位置が推定のときは、そう分かるように書く
                if me.coordinate == nil && focus == nil && cameraDistance >= 6_000_000 {
                    Label(L("位置は大まかな推定です。設定で位置情報を許可すると、正確に表示します"), systemImage: "location.slash")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.orange.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 260, alignment: .leading)
                        .padding(12)
                        .allowsHitTesting(false)
                }
            }
            .onAppear { applyFocus() }
            .onChange(of: focus?.id) { _, _ in applyFocus() }
    }

    /// 「世界の今」で選んだ地域へ、平らな地図で飛ぶ
    private func applyFocus() {
        guard let focus, focus.id != appliedFocus else { return }
        appliedFocus = focus.id
        if selectedID != nil { selectedID = nil }
        DispatchQueue.main.async {
            cameraDistance = 3_500_000
            withAnimation(.easeInOut(duration: 1.0)) {
                position = .camera(MapCamera(centerCoordinate: focus.coordinate, distance: 3_500_000, heading: 0, pitch: 0))
            }
        }
    }

    private var flatMap: some View {
        // 地図の文字（地名）は出さない。文字があると、重なったピンが消えてしまうため
        // 近づける限界：街が見える程度まで。家や道が見分けられるほど拡大はできない（位置の特定を防ぐ）
        Map(position: $position, bounds: MapCameraBounds(minimumDistance: 15_000, maximumDistance: 40_000_000)) {
            ForEach(samples) { sample in
                Annotation("", coordinate: sample.coordinate) {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selectedID = sample.id }
                    } label: {
                        pin(sample, isSelected: sample.id == selectedID)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(sample.city) \(sample.localTime(base: base)) \(sample.light(base: base).name)")
                }
            }
            // 自分のいる場所（位置情報が使えるときは本当の位置。使えないときはタイムゾーンからの推定）
            Annotation("", coordinate: me.coordinate ?? WorldMapView.home) {
                VStack(spacing: 2) {
                    if let myPhoto {
                        Image(uiImage: myPhoto).resizable().scaledToFill()
                            .frame(width: 44, height: 44).clipShape(Circle())
                            .overlay(Circle().stroke(Hi.neon, lineWidth: 2.5))
                    }
                    Circle().fill(Hi.neon).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.black, lineWidth: 2))
                    Text(L("あなた")).font(.system(size: 10, weight: .black)).foregroundStyle(Hi.neon)
                }
                .accessibilityLabel(L("あなたのいるあたり"))
            }
        }
        // Apple の地図そのまま（衛星写真・文字なし）。遠くまで引くと、丸い地球になる
        .mapStyle(.imagery(elevation: .realistic))
        .onAppear {
            me.request()
            fly(to: selected)
        }
        .overlay(alignment: .topTrailing) {
            // 左上の「◯◯の投稿」と重ならないよう、地域のボタンが出ているときは、その下に置く
            localTimeBadge
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 10)
                .padding(.top, focus == nil ? 10 : 58)
                .animation(.easeOut(duration: 0.2), value: focus == nil)
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            cameraDistance = context.camera.distance
            updateCenterPlace(context.camera)
        }
        .onChange(of: selectedID) { _, _ in
            if let selected { fly(to: selected) }
        }
        .sensoryFeedback(.selection, trigger: selectedID)
    }

    /// 近づいたとき（一定の高さより下）、地図の中心の現地時刻を出す
    @ViewBuilder
    private var localTimeBadge: some View {
        if let place = centerPlace, cameraDistance < 6_000_000 {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text(LF("現地 {t}", ["t": Self.clock(context.date, in: place.zone)])).monospacedDigit()
                    if !place.name.isEmpty { Text("・" + place.name).lineLimit(1).truncationMode(.tail) }
                }
                .font(.subheadline.weight(.black))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).frame(height: 36)
                .background(Capsule().fill(Color.black.opacity(0.7)))
            }
            .transition(.opacity)
        }
    }

    private static func clock(_ date: Date, in zone: TimeZone) -> String {
        Clock.string(date, zone: zone)
    }

    /// 地図の中心がどこか（名前と時間帯）を調べる。海の上などで分からないときは、経度から推定する
    private func updateCenterPlace(_ camera: MapCamera) {
        guard camera.distance < 6_000_000 else { return }
        let c = camera.centerCoordinate
        let fallback = TimeZone(secondsFromGMT: Int((c.longitude / 15).rounded()) * 3600) ?? .gmt
        centerPlace = CenterPlace(name: centerPlace?.name ?? "", zone: fallback)
        geocoder.cancelGeocode()
        // 地名は、アプリの言語で（iPhone の言語ではなく）
        let lang = AppLanguage.current == .zh ? "zh-Hans" : AppLanguage.current.rawValue
        geocoder.reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude), preferredLocale: Locale(identifier: lang)) { marks, _ in
            guard let mark = marks?.first else { return }
            let name = mark.locality ?? mark.administrativeArea ?? mark.country ?? ""
            let zone = mark.timeZone ?? fallback
            DispatchQueue.main.async { centerPlace = CenterPlace(name: name, zone: zone) }
        }
    }

    private func pin(_ sample: WorldPin, isSelected: Bool) -> some View {
        let light = sample.light(base: base)
        let size: CGFloat = isSelected ? 52 : 38
        return VStack(spacing: 3) {
            ZStack {
                if let photo = sample.photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else {
                    GlowBackground(palette: light.palette, focus: .center)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(isSelected ? Hi.neon : Color.white.opacity(0.85), lineWidth: isSelected ? 3 : 1.5))
            if isSelected {
                Text("\(sample.city)・\(sample.localTime(base: base))")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.8)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSelected)
    }

    /// 選んだ場所へ、地図を動かす
    private func fly(to sample: WorldPin?) {
        guard let sample else { return }
        // 近づいて見ているときは、その高さのまま動く（選ぶたびに縮小しない）。遠いときだけ、都市が見える高さまで近づく
        let distance = min(cameraDistance, 3_500_000)
        cameraDistance = distance
        withAnimation(.easeInOut(duration: 0.8)) {
            position = .camera(MapCamera(centerCoordinate: sample.coordinate, distance: distance, heading: 0, pitch: 0))
        }
    }
}


struct CenterPlace { let name: String; let zone: TimeZone }

/// 地図に出す、自分のいる場所（この端末の中だけで使う。送信しない）
@MainActor
final class MyLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways { manager.requestLocation() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        Task { @MainActor in self.coordinate = c }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
