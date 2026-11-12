import SwiftUI
import MapKit

/// 世界の投稿を、Appleの地図の上に出す。ピンは、その土地のいまの光（朝・昼・夕・夜）の色。
/// 選んだ都市へは、地図が動く。投稿はサンプル。
struct WorldMapView: View {
    let samples: [WorldSample]
    let base: Date
    @Binding var selectedID: String?
    @StateObject private var me = MyLocation()
    @State private var showGlobe = true                       // 遠くから見るときは、丸い地球
    @State private var globeCenter: CLLocationCoordinate2D? = nil

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

    private var selected: WorldSample? { samples.first { $0.id == selectedID } }

    var body: some View {
        ZStack {
            if showGlobe && selectedID == nil {
                GlobeView(samples: samples, base: base, you: me.coordinate,
                          center: globeCenter ?? me.coordinate ?? WorldMapView.home,
                          onSelect: { id in
                              withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selectedID = id }
                          },
                          onZoomIn: { c in
                              // 地球に近づいたら、その場所の平らな地図へ
                              position = .camera(MapCamera(centerCoordinate: c, distance: 9_000_000, heading: 0, pitch: 0))
                              withAnimation(.easeInOut(duration: 0.35)) { showGlobe = false }
                          })
                    .transition(.opacity)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            // 地球の写真の出典（Apple の地図）
                            Text("Imagery: Apple Maps").font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.5))
                            // 位置が推定のときは、そう分かるように書く
                            if me.coordinate == nil {
                                Label(L("位置は大まかな推定です。設定で位置情報を許可すると、正確に表示します"), systemImage: "location.slash")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.orange.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: 260, alignment: .leading)
                            }
                        }
                        .padding(12)
                        .allowsHitTesting(false)
                    }
                    .onAppear { me.request() }
            } else {
                flatMap.transition(.opacity)
            }
        }
        .onChange(of: me.coordinate?.latitude) { _, _ in
            if globeCenter == nil, let c = me.coordinate { globeCenter = c }
        }
    }

    private var flatMap: some View {
        // 地図の文字（地名）は出さない。文字があると、重なったピンが消えてしまうため
        Map(position: $position) {
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
                    Circle().fill(Hi.neon).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.black, lineWidth: 2))
                    Text(L("あなた")).font(.system(size: 10, weight: .black)).foregroundStyle(Hi.neon)
                }
                .accessibilityLabel(L("あなたのいるあたり"))
            }
        }
        // 平らな地図の写真（立体にすると、ピンが正しく出ないため）。遠くまで縮小すると、丸い地球に切り替える
        .mapStyle(.imagery(elevation: .flat))
        .onAppear {
            me.request()
            fly(to: selected)
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            if context.camera.distance > 14_000_000 {
                globeCenter = context.camera.centerCoordinate
                withAnimation(.easeInOut(duration: 0.35)) {
                    selectedID = nil
                    showGlobe = true
                }
            }
        }
        .onChange(of: selectedID) { old, _ in
            if let selected { fly(to: selected) } else {
                if let prev = samples.first(where: { $0.id == old }) { globeCenter = prev.coordinate }
                backToOverview()
            }
        }
    }

    /// 選ぶのをやめたら、丸い地球に戻る（いま見ていた都市を正面にする）
    private func backToOverview() {
        withAnimation(.easeInOut(duration: 0.35)) { showGlobe = true }
    }

    private func pin(_ sample: WorldSample, isSelected: Bool) -> some View {
        let light = sample.light(base: base)
        let size: CGFloat = isSelected ? 52 : 38
        return VStack(spacing: 3) {
            ZStack {
                if let photo = sample.photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else {
                    GlowBackground(palette: light.palette, focus: .center)
                }
                Text(sample.flag).font(.system(size: isSelected ? 24 : 18))
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
    private func fly(to sample: WorldSample?) {
        guard let sample else { return }
        showGlobe = false
        withAnimation(.easeInOut(duration: 1.2)) {
            position = .camera(MapCamera(centerCoordinate: sample.coordinate, distance: 3_500_000, heading: 0, pitch: 0))
        }
    }
}


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
