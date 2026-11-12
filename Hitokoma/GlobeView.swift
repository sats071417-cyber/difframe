import SwiftUI
import SceneKit
import MapKit

/// 丸い地球。指で回せて、ピンは地球の上の正しい場所に立つ（裏側のピンは地球に隠れる）。
/// ・地球の写真は、Apple の地図の衛星写真から作り、端末に保存して使い回す
/// ・つまんで近づくと onZoomIn を呼ぶ（そこからは平らな地図に切り替える）
struct GlobeView: UIViewRepresentable {
    let samples: [WorldSample]
    let base: Date
    let you: CLLocationCoordinate2D?
    let center: CLLocationCoordinate2D
    let onSelect: (String) -> Void
    let onZoomIn: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.cameraNode
        view.isPlaying = false
        context.coordinator.attach(to: view)
        context.coordinator.face(center, animated: false)
        context.coordinator.setPins(samples: samples, base: base)
        context.coordinator.setYou(you)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.setYou(you)
        // 中心が変わったとき（自分の位置がわかったときなど）だけ、そこへ回す
        if let last = context.coordinator.lastCenter,
           abs(last.latitude - center.latitude) + abs(last.longitude - center.longitude) > 0.5 {
            context.coordinator.face(center, animated: true)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: GlobeView
        let scene = SCNScene()
        let cameraNode = SCNNode()
        private let tilt = SCNNode()     // 上下の傾き（X軸）
        private let spin = SCNNode()     // 東西の回転（Y軸）
        private let earth = SCNNode()
        private let pins = SCNNode()
        private var youNode: SCNNode?
        private var spinAngle: Float = 0
        private var tiltAngle: Float = 0
        private var cameraZ: Float = 3.1
        private var pinchStartZ: Float = 3.1
        private var switched = false
        var lastCenter: CLLocationCoordinate2D?

        init(_ parent: GlobeView) {
            self.parent = parent
            super.init()
            build()
        }

        private func build() {
            scene.background.contents = UIColor.black
            let camera = SCNCamera()
            // 横幅で合わせる（縦長の画面でも、地球が左右で切れないように）
            camera.projectionDirection = .horizontal
            camera.fieldOfView = 52
            camera.zNear = 0.05
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(0, 0, cameraZ)
            scene.rootNode.addChildNode(cameraNode)

            // 光：正面から少し左上（昼の側が明るく見える）
            let sun = SCNNode()
            sun.light = SCNLight()
            sun.light?.type = .directional
            sun.light?.intensity = 900
            sun.eulerAngles = SCNVector3(-0.35, -0.45, 0)
            scene.rootNode.addChildNode(sun)
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 420
            scene.rootNode.addChildNode(ambient)

            let sphere = SCNSphere(radius: 1)
            sphere.segmentCount = 96
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(red: 0.12, green: 0.33, blue: 0.62, alpha: 1)   // 写真ができるまでの仮の色
            material.specular.contents = UIColor(white: 0.15, alpha: 1)
            material.shininess = 0.2
            sphere.firstMaterial = material
            earth.geometry = sphere

            // うっすら光る大気
            let air = SCNSphere(radius: 1.035)
            air.segmentCount = 64
            let airMaterial = SCNMaterial()
            airMaterial.diffuse.contents = UIColor(red: 0.45, green: 0.7, blue: 1, alpha: 0.16)
            airMaterial.lightingModel = .constant
            airMaterial.cullMode = .front
            airMaterial.blendMode = .add
            air.firstMaterial = airMaterial
            let airNode = SCNNode(geometry: air)

            scene.rootNode.addChildNode(tilt)
            tilt.addChildNode(spin)
            spin.addChildNode(earth)
            spin.addChildNode(pins)
            scene.rootNode.addChildNode(airNode)

            EarthTexture.load { [weak self] image in
                guard let image else { return }
                self?.earth.geometry?.firstMaterial?.diffuse.contents = image
            }
        }

        func attach(to view: SCNView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
            let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
            pan.delegate = self; pinch.delegate = self
            view.addGestureRecognizer(pan)
            view.addGestureRecognizer(pinch)
            view.addGestureRecognizer(tap)
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        // MARK: 位置

        /// SceneKit の球に貼った写真は、経度0°が正面から90°ずれた位置に来る。ピンと回転をそれに合わせる
        static let lonOffset: Double = 0

        /// 緯度・経度を、地球の上の点にする（地球の写真の貼り方と同じ向き）
        static func point(_ c: CLLocationCoordinate2D, radius: Float) -> SCNVector3 {
            let lat = Float(c.latitude) * .pi / 180
            let lon = Float(c.longitude + Coordinator.lonOffset) * .pi / 180
            return SCNVector3(radius * cos(lat) * sin(lon), radius * sin(lat), radius * cos(lat) * cos(lon))
        }

        /// その場所が正面に来るように回す
        func face(_ c: CLLocationCoordinate2D, animated: Bool) {
            lastCenter = c
            spinAngle = -Float(c.longitude + Coordinator.lonOffset) * .pi / 180
            tiltAngle = Float(c.latitude) * .pi / 180
            apply(animated: animated)
        }

        private func apply(animated: Bool) {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = animated ? 0.6 : 0
            spin.eulerAngles = SCNVector3(0, spinAngle, 0)
            tilt.eulerAngles = SCNVector3(tiltAngle, 0, 0)
            cameraNode.position = SCNVector3(0, 0, cameraZ)
            SCNTransaction.commit()
        }

        /// いま正面に見えている場所
        private var centerCoordinate: CLLocationCoordinate2D {
            var lon = Double(-spinAngle) * 180 / .pi - Coordinator.lonOffset
            lon = (lon + 540).truncatingRemainder(dividingBy: 360) - 180
            return CLLocationCoordinate2D(latitude: Double(tiltAngle) * 180 / .pi, longitude: lon)
        }

        // MARK: ピン

        func setPins(samples: [WorldSample], base: Date) {
            pins.childNodes.forEach { $0.removeFromParentNode() }
            for sample in samples {
                let light = sample.light(base: base)
                let image = PinImage.make(flag: sample.flag, top: UIColor(light.palette.top), bottom: UIColor(light.palette.bottom))
                let node = billboard(image: image, size: 0.12)
                node.name = sample.id
                node.position = Coordinator.point(sample.coordinate, radius: 1.02)
                pins.addChildNode(node)
            }
        }

        func setYou(_ c: CLLocationCoordinate2D?) {
            let coordinate = c ?? WorldMapView.home
            if youNode == nil {
                let node = billboard(image: PinImage.you(label: L("あなた")), size: 0.16)
                node.name = "you"
                pins.addChildNode(node)
                youNode = node
            }
            youNode?.position = Coordinator.point(coordinate, radius: 1.025)
        }

        private func billboard(image: UIImage, size: CGFloat) -> SCNNode {
            let plane = SCNPlane(width: size, height: size * image.size.height / image.size.width)
            let m = SCNMaterial()
            m.diffuse.contents = image
            m.lightingModel = .constant
            m.isDoubleSided = true
            plane.firstMaterial = m
            let node = SCNNode(geometry: plane)
            node.constraints = [SCNBillboardConstraint()]
            return node
        }

        // MARK: 指の操作

        @objc private func onPan(_ g: UIPanGestureRecognizer) {
            guard let view = g.view else { return }
            let d = g.translation(in: view)
            g.setTranslation(.zero, in: view)
            // 近いほど、ゆっくり回す
            let k = Float(0.005) * (cameraZ - 1) / 2.1
            spinAngle += Float(d.x) * k
            tiltAngle = max(-1.35, min(1.35, tiltAngle + Float(d.y) * k))
            apply(animated: false)
            if g.state == .ended {
                // 指を離したあと、少しだけ滑らせる
                let v = g.velocity(in: view)
                spinAngle += Float(v.x) * k * 0.12
                tiltAngle = max(-1.35, min(1.35, tiltAngle + Float(v.y) * k * 0.12))
                apply(animated: true)
            }
        }

        @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
            switch g.state {
            case .began:
                pinchStartZ = cameraZ
                switched = false
            case .changed:
                cameraZ = max(1.55, min(5.5, pinchStartZ / Float(g.scale)))
                apply(animated: false)
                // 十分に近づいたら、平らな地図へ
                if cameraZ < 1.6, !switched {
                    switched = true
                    parent.onZoomIn(centerCoordinate)
                }
            default:
                if !switched, cameraZ < 1.8 { cameraZ = 1.8; apply(animated: true) }
            }
        }

        @objc private func onTap(_ g: UITapGestureRecognizer) {
            guard let view = g.view as? SCNView else { return }
            let hits = view.hitTest(g.location(in: view), options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            if let id = hits.lazy.compactMap({ $0.node.name }).first(where: { $0 != "you" }) {
                parent.onSelect(id)
            }
        }
    }
}

/// ピンの絵（丸の中に国旗）
enum PinImage {
    static func make(flag: String, top: UIColor, bottom: UIColor) -> UIImage {
        let size = CGSize(width: 96, height: 96)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4)
            let path = UIBezierPath(ovalIn: rect)
            ctx.cgContext.saveGState()
            path.addClip()
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 96, y: 96), options: [])
            }
            ctx.cgContext.restoreGState()
            UIColor.white.setStroke()
            path.lineWidth = 5
            path.stroke()
            let text = NSAttributedString(string: flag, attributes: [.font: UIFont.systemFont(ofSize: 44)])
            let t = text.size()
            text.draw(at: CGPoint(x: (size.width - t.width) / 2, y: (size.height - t.height) / 2))
        }
    }

    /// 自分の場所（黄緑の点と「あなた」）
    static func you(label: String) -> UIImage {
        let size = CGSize(width: 160, height: 120)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let neon = UIColor(red: 0.894, green: 1.0, blue: 0.102, alpha: 1)
            let dot = UIBezierPath(ovalIn: CGRect(x: 56, y: 8, width: 48, height: 48))
            neon.setFill(); dot.fill()
            UIColor.black.setStroke(); dot.lineWidth = 6; dot.stroke()
            let text = NSAttributedString(string: label, attributes: [
                .font: UIFont.systemFont(ofSize: 34, weight: .black), .foregroundColor: neon,
                .strokeColor: UIColor.black, .strokeWidth: -3,
            ])
            let t = text.size()
            text.draw(at: CGPoint(x: (size.width - t.width) / 2, y: 62))
        }
    }
}

/// 地球の写真：Apple の地図の衛星写真（メルカトル図法）を、球に貼れる形（正距円筒図法）に変えて保存する。
/// 地図は一度に世界全体を写せないので、4×4 の16枚に分けて撮り、つなぎ合わせてから変換する。
enum EarthTexture {
    private static var cached: UIImage?
    private static var fileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("earth_v5.jpg")
    }

    static func load(_ done: @escaping (UIImage?) -> Void) {
        if let cached { done(cached); return }
        if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
            cached = image; done(image); return
        }
        buildMercator { mercator in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let mercator, let image = reproject(mercator) else {
                    DispatchQueue.main.async { done(nil) }
                    return
                }
                if let data = image.jpegData(compressionQuality: 0.85) { try? data.write(to: fileURL) }
                DispatchQueue.main.async { cached = image; done(image) }
            }
        }
    }

    /// 世界を 4×4 に分けて撮り、1枚のメルカトル図（2048×2048）にする
    private static func buildMercator(_ done: @escaping (CGImage?) -> Void) {
        let n = 4, tile = 512
        let world = MKMapRect.world
        let tw = world.width / Double(n), th = world.height / Double(n)
        var tiles = [[CGImage?]](repeating: [CGImage?](repeating: nil, count: n), count: n)
        let lock = NSLock()
        let group = DispatchGroup()
        var keep: [MKMapSnapshotter] = []
        for row in 0..<n {
            for col in 0..<n {
                let options = MKMapSnapshotter.Options()
                options.mapRect = MKMapRect(x: world.minX + Double(col) * tw, y: world.minY + Double(row) * th, width: tw, height: th)
                options.size = CGSize(width: tile, height: tile)
                options.scale = 1
                options.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
                let snapshotter = MKMapSnapshotter(options: options)
                keep.append(snapshotter)
                group.enter()
                snapshotter.start(with: .global(qos: .userInitiated)) { snapshot, _ in
                    lock.lock(); tiles[row][col] = snapshot?.image.cgImage; lock.unlock()
                    group.leave()
                }
            }
        }
        group.notify(queue: .global(qos: .userInitiated)) {
            _ = keep
            let size = n * tile
            guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { done(nil); return }
            ctx.setFillColor(red: 0.12, green: 0.3, blue: 0.55, alpha: 1)   // 撮れなかった所は海の色
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            for row in 0..<n {
                for col in 0..<n {
                    guard let image = tiles[row][col] else { continue }
                    // CGContext は下が原点。上の行（北）ほど y が大きい
                    ctx.draw(image, in: CGRect(x: col * tile, y: (n - 1 - row) * tile, width: tile, height: tile))
                }
            }
            // 各タイルの左下に入る地図のロゴを、すぐ上の色で塗りつぶす（地球の上に小さな文字が出ないように）
            if let data = ctx.data {
                let p = data.bindMemory(to: UInt32.self, capacity: size * size)
                let logoW = 120, logoH = 40
                for row in 0..<n {
                    for col in 0..<n {
                        let bottom = row * tile + tile            // メモリの行は上から（0 = 北）
                        let source = bottom - logoH - 1
                        for y in (bottom - logoH)..<bottom {
                            for x in (col * tile)..<(col * tile + logoW) {
                                p[y * size + x] = p[source * size + x]
                            }
                        }
                    }
                }
            }
            done(ctx.makeImage())
        }
    }

    /// メルカトル → 正距円筒（横 = 経度、縦 = 緯度がそのまま比例する形）
    private static func reproject(_ src: CGImage) -> UIImage? {
        let sw = src.width, sh = src.height
        guard let srcCtx = CGContext(data: nil, width: sw, height: sh, bitsPerComponent: 8, bytesPerRow: sw * 4,
                                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let srcData = srcCtx.data else { return nil }
        srcCtx.draw(src, in: CGRect(x: 0, y: 0, width: sw, height: sh))
        let w = 2048, h = 1024
        guard let dstCtx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let dstData = dstCtx.data else { return nil }
        let s = srcData.bindMemory(to: UInt32.self, capacity: sw * sh)
        let d = dstData.bindMemory(to: UInt32.self, capacity: w * h)
        let ice: UInt32 = 0xFFF5F0EB   // 極地は白っぽい氷の色
        for y in 0..<h {
            let latDeg = 90.0 - (Double(y) + 0.5) / Double(h) * 180.0     // 画像の上（y = 0）が北
            if abs(latDeg) > 84 {
                for x in 0..<w { d[y * w + x] = ice }
                continue
            }
            let lat = latDeg * .pi / 180
            let merc = log(tan(.pi / 4 + lat / 2))                      // -π…π
            let sy = Int((1 - (merc / .pi + 1) / 2) * Double(sh))        // 0 = 北
            let row = min(sh - 1, max(0, sy)) * sw
            for x in 0..<w {
                d[y * w + x] = s[row + min(sw - 1, x * sw / w)]
            }
        }
        guard let out = dstCtx.makeImage() else { return nil }
        return UIImage(cgImage: out)
    }
}
