import SwiftUI
import MapKit

/// 投稿の場所を、大まかな地図で見せる（都市の中心あたり。拡大も、動かすこともできない）。
struct LocationMapSheet: View {
    let city: String
    let latitude: Double?
    let longitude: Double?
    let photo: UIImage?
    @Environment(\.dismiss) private var dismiss
    @State private var coordinate: CLLocationCoordinate2D?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let coordinate {
                    // 地図の高さ 約150万m = 地方（関東なら、東北から近畿まで）が見える程度。指で動かしたり拡大したりはできない
                    Map(initialPosition: .camera(MapCamera(centerCoordinate: coordinate, distance: 1_500_000)),
                        interactionModes: []) {
                        Annotation("", coordinate: coordinate) {
                            Group {
                                if let photo {
                                    Image(uiImage: photo).resizable().scaledToFill()
                                } else {
                                    Color.white.opacity(0.2).overlay(Image(systemName: "mappin").foregroundStyle(.white))
                                }
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white, lineWidth: 3))
                            .shadow(radius: 4)
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic))
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.headline.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(Circle().fill(Color.black.opacity(0.5)))
            }
            .padding(16)
            .accessibilityLabel(L("戻る"))
        }
        .background(Color.black.ignoresSafeArea())
        .edgeSwipeBack()
        .overlay(alignment: .bottomLeading) {
            if !city.isEmpty {
                Label(city, systemImage: "mappin").font(.subheadline.weight(.black)).foregroundStyle(.white)
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    .padding(.leading, 16).padding(.bottom, 40)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .task {
            if let latitude, let longitude {
                coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            } else if !city.isEmpty {
                if let c = await CityCoordinates.lookup(city) { coordinate = CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude) }
            }
        }
    }
}
