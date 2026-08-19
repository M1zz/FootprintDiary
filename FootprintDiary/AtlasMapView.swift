//
//  AtlasMapView.swift
//  FootprintDiary
//
//  대동여지도 — 배경 지도는 종이처럼 눌러 두고, 내가 걸어서 지난 길만 먹선으로 남긴다.
//
//  세상은 이미 네이버·카카오·구글이 다 그려 놓았다. 그 위에 하나 더 그릴 이유는 없다.
//  이 지도의 값어치는 '내 두 발로 지난 길만 그려져 있다'는 것 하나뿐이므로,
//  배경은 muted로 누르고 관심지점을 전부 끈다. 화면에서 눈에 띄는 건 내 선이어야 한다.
//

import SwiftUI
import MapKit
import SwiftData

/// 선을 두 겹(번짐 + 심)으로 그리기 위한 구분표.
/// 한 겹으로 그리면 배경 위에서 선이 얇게 떠 보이고, 두 겹으로 그리면 먹이 번진 것처럼 앉는다.
enum InkStyle {
    static let pastBleed = "ink.past.bleed"
    static let pastCore = "ink.past.core"
    static let todayBleed = "ink.today.bleed"
    static let todayCore = "ink.today.core"

    /// 지난 날의 먹 — 밝은 배경에선 짙은 먹, 어두운 배경에선 종이빛으로 뒤집는다
    static let ink = UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.97, green: 0.94, blue: 0.87, alpha: 1)
        : UIColor(red: 0.11, green: 0.12, blue: 0.16, alpha: 1)
    }

    /// 낙관을 찍는 인주 빛. 오늘의 주묵보다 짙어서 선과 도장이 섞이지 않는다.
    static let sealRed = UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.86, green: 0.30, blue: 0.24, alpha: 1)
        : UIColor(red: 0.66, green: 0.14, blue: 0.11, alpha: 1)
    }

    /// 오늘 그린 길은 주묵(붉은 먹)으로 얹는다.
    /// 옛 지도가 길을 붉은 선으로 표시하던 것과 같고, 오늘 내가 무엇을 더했는지 바로 보인다.
    static let vermilion = UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 1.0, green: 0.45, blue: 0.35, alpha: 1)
        : UIColor(red: 0.78, green: 0.20, blue: 0.13, alpha: 1)
    }
}

/// 지도에 찍힌 스탬프 하나
final class StampAnnotation: NSObject, MKAnnotation {
    let id: PersistentIdentifier
    let kind: StampKind
    /// 끌어서 옮길 수 있어야 하므로 MKAnnotation 규약대로 쓰기 가능해야 한다
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { kind.title }

    init(stamp: MapStamp) {
        // 모델이 지워져도 지도가 흔들리지 않도록 값을 복사해 둔다
        self.id = stamp.persistentModelID
        self.kind = stamp.kind
        self.coordinate = stamp.coordinate
    }
}

/// 낙관처럼 보이는 도장 그림. SF Symbol을 붉은 인장 안에 새긴다.
enum StampSeal {
    static let size = CGSize(width: 30, height: 30)
    private static var cache: [String: UIImage] = [:]

    static func image(for kind: StampKind) -> UIImage {
        if let cached = cache[kind.id] { return cached }

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            // 옛 도장처럼 모서리가 둥근 네모로 찍는다
            let seal = UIBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: 8)
            InkStyle.sealRed.setFill()
            seal.fill()
            UIColor.white.withAlphaComponent(0.9).setStroke()
            seal.lineWidth = 1.5
            seal.stroke()

            let configuration = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            if let glyph = UIImage(systemName: kind.symbolName, withConfiguration: configuration)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                let box = CGRect(
                    x: (size.width - glyph.size.width) / 2,
                    y: (size.height - glyph.size.height) / 2,
                    width: glyph.size.width,
                    height: glyph.size.height
                )
                glyph.draw(in: box)
            }
            _ = context
        }
        cache[kind.id] = image
        return image
    }
}

final class StampAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "stamp"

    override var annotation: (any MKAnnotation)? {
        didSet {
            guard let stamp = annotation as? StampAnnotation else { return }
            image = StampSeal.image(for: stamp.kind)
            centerOffset = .zero
            canShowCallout = false
            isDraggable = true
        }
    }
}

struct AtlasMapView: UIViewRepresentable {
    /// 지난 날들에 그린 길
    let past: [[CLLocationCoordinate2D]]
    /// 오늘 그린 길
    let today: [[CLLocationCoordinate2D]]
    /// 지도에 찍은 스탬프
    let stamps: [MapStamp]
    /// 스탬프를 눌렀을 때
    var onSelectStamp: (MapStamp) -> Void = { _ in }
    /// 지도를 길게 눌러 자리를 골랐을 때
    var onPickCoordinate: (CLLocationCoordinate2D) -> Void = { _ in }
    /// 찍힌 스탬프를 끌어 옮겼을 때
    var onMoveStamp: (MapStamp, CLLocationCoordinate2D) -> Void = { _, _ in }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true

        // 상호명·아이콘이 남아 있으면 내 선이 그 사이에 묻힌다
        let configuration = MKStandardMapConfiguration(emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        mapView.preferredConfiguration = configuration
        mapView.register(
            StampAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: StampAnnotationView.reuseIdentifier
        )

        addTrackingButton(to: mapView)

        // 길게 눌러 원하는 자리에 찍는다
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.45
        mapView.addGestureRecognizer(longPress)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onSelectStamp = onSelectStamp
        context.coordinator.onPickCoordinate = onPickCoordinate
        context.coordinator.onMoveStamp = onMoveStamp
        context.coordinator.stampsByID = Dictionary(
            stamps.map { ($0.persistentModelID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        context.coordinator.trails = past + today
        context.coordinator.sync(on: mapView, past: past, today: today)
        context.coordinator.syncStamps(on: mapView, stamps: stamps)
    }

    static func dismantleUIView(_ mapView: MKMapView, coordinator: Coordinator) {
        mapView.delegate = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func addTrackingButton(to mapView: MKMapView) {
        let button = MKUserTrackingButton(mapView: mapView)
        button.layer.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.85).cgColor
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        mapView.addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            button.bottomAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    // MARK: - 조정자

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var overlays: [MKPolyline] = []
        /// 지금 그려져 있는 선의 지문 — 달라졌을 때만 다시 그린다 (매 렌더마다 다시 얹으면 깜빡인다)
        private var signature: String?
        private var didCenterOnUser = false
        /// 지금 올라가 있는 스탬프의 지문 — 달라졌을 때만 다시 얹는다
        private var stampSignature: String?
        var stampsByID: [PersistentIdentifier: MapStamp] = [:]
        var onSelectStamp: (MapStamp) -> Void = { _ in }
        var onPickCoordinate: (CLLocationCoordinate2D) -> Void = { _ in }
        var onMoveStamp: (MapStamp, CLLocationCoordinate2D) -> Void = { _, _ in }

        /// 길게 눌렀을 때 그 자리에서 이 거리(pt) 안에 내 길이 있으면 길 위로 붙인다.
        /// 화면 거리로 재기 때문에 지도를 확대할수록 더 정확히 짚을 수 있다.
        static let snapDistance: CGFloat = 44

        /// 지금 그려져 있는 길 (스냅 대상)
        var trails: [[CLLocationCoordinate2D]] = []

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            // began에서만 받는다. changed까지 받으면 누른 채 손이 흔들릴 때마다 열린다.
            guard gesture.state == .began, let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            onPickCoordinate(snapped(point, on: mapView))
        }

        /// 누른 자리에서 가장 가까운 '내가 걸은 길' 위의 점.
        /// 가까운 길이 없으면 누른 자리를 그대로 쓴다 — 길 밖에도 찍을 수 있어야 한다.
        private func snapped(_ point: CGPoint, on mapView: MKMapView) -> CLLocationCoordinate2D {
            var best: CGPoint?
            var bestDistance = Self.snapDistance

            // 길이 길어지면 점이 수만 개가 된다. 화면에 걸치지 않는 구간은 아예 건너뛴다.
            let visible = mapView.visibleMapRect.insetBy(
                dx: -mapView.visibleMapRect.size.width * 0.1,
                dy: -mapView.visibleMapRect.size.height * 0.1
            )

            for trail in trails {
                let onScreen = trail.contains { visible.contains(MKMapPoint($0)) }
                guard onScreen else { continue }
                let screen = trail.map { mapView.convert($0, toPointTo: mapView) }
                for (a, b) in zip(screen, screen.dropFirst()) {
                    let candidate = Self.closestPoint(to: point, onSegmentFrom: a, to: b)
                    let gap = hypot(candidate.x - point.x, candidate.y - point.y)
                    if gap < bestDistance {
                        bestDistance = gap
                        best = candidate
                    }
                }
            }
            guard let best else { return mapView.convert(point, toCoordinateFrom: mapView) }
            return mapView.convert(best, toCoordinateFrom: mapView)
        }

        /// 선분 위에서 주어진 점에 가장 가까운 자리
        private static func closestPoint(
            to point: CGPoint,
            onSegmentFrom a: CGPoint,
            to b: CGPoint
        ) -> CGPoint {
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            guard lengthSquared > 0 else { return a }
            // 선분 밖으로 넘어가지 않도록 0~1로 자른다
            let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
            return CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        }

        /// 스탬프를 끌어 옮겼을 때. 걸으면서 대충 찍어 두고 나중에 다듬을 수 있어야 한다.
        func mapView(
            _ mapView: MKMapView,
            annotationView view: MKAnnotationView,
            didChange newState: MKAnnotationView.DragState,
            fromOldState oldState: MKAnnotationView.DragState
        ) {
            guard newState == .ending || newState == .canceling else { return }
            view.dragState = .none
            guard newState == .ending,
                  let annotation = view.annotation as? StampAnnotation,
                  let stamp = stampsByID[annotation.id] else { return }
            onMoveStamp(stamp, annotation.coordinate)
            // 옮긴 자리를 그대로 두려면 다음 sync가 다시 얹지 않아야 한다
            stampSignature = nil
        }

        func syncStamps(on mapView: MKMapView, stamps: [MapStamp]) {
            let signature = stamps
                .map { "\($0.persistentModelID.hashValue):\($0.kindID)" }
                .joined(separator: ",")
            guard signature != stampSignature else { return }
            stampSignature = signature

            let existing = mapView.annotations.compactMap { $0 as? StampAnnotation }
            mapView.removeAnnotations(existing)
            mapView.addAnnotations(stamps.map(StampAnnotation.init))
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            guard annotation is StampAnnotation else { return nil }
            return mapView.dequeueReusableAnnotationView(
                withIdentifier: StampAnnotationView.reuseIdentifier,
                for: annotation
            )
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation as? StampAnnotation else { return }
            // 고른 표시를 남겨 두면 다음에 같은 걸 눌러도 반응하지 않는다
            mapView.deselectAnnotation(annotation, animated: false)
            if let stamp = stampsByID[annotation.id] { onSelectStamp(stamp) }
        }

        func sync(on mapView: MKMapView, past: [[CLLocationCoordinate2D]], today: [[CLLocationCoordinate2D]]) {
            let key = "\(past.count):\(past.reduce(0) { $0 + $1.count })"
                + "|\(today.count):\(today.reduce(0) { $0 + $1.count })"
            guard key != signature else { return }
            signature = key

            mapView.removeOverlays(overlays)
            overlays = past.flatMap { line(for: $0, bleed: InkStyle.pastBleed, core: InkStyle.pastCore) }
                + today.flatMap { line(for: $0, bleed: InkStyle.todayBleed, core: InkStyle.todayCore) }
            // 지명 위에 얹어야 선이 글자에 가리지 않는다
            mapView.addOverlays(overlays, level: .aboveLabels)
        }

        /// 한 구간을 번짐과 심 두 겹으로 만든다
        private func line(for segment: [CLLocationCoordinate2D], bleed: String, core: String) -> [MKPolyline] {
            guard segment.count >= 2 else { return [] }
            let under = MKPolyline(coordinates: segment, count: segment.count)
            under.title = bleed
            let over = MKPolyline(coordinates: segment, count: segment.count)
            over.title = core
            return [under, over]
        }

        // MARK: 그리기

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.lineCap = .round
            renderer.lineJoin = .round

            switch line.title {
            case InkStyle.pastBleed:
                renderer.strokeColor = InkStyle.ink.withAlphaComponent(0.18)
                renderer.lineWidth = 9
            case InkStyle.todayBleed:
                renderer.strokeColor = InkStyle.vermilion.withAlphaComponent(0.22)
                renderer.lineWidth = 11
            case InkStyle.todayCore:
                renderer.strokeColor = InkStyle.vermilion
                renderer.lineWidth = 4
            default:
                renderer.strokeColor = InkStyle.ink.withAlphaComponent(0.9)
                renderer.lineWidth = 3.5
            }
            return renderer
        }

        // MARK: 첫 화면

        /// 앱을 켠 직후에는 내 위치가 아직 없다. 위치가 도착하면 한 번만 그리로 당겨 준다.
        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard !didCenterOnUser, let coordinate = userLocation.location?.coordinate else { return }
            didCenterOnUser = true
            // 동네 한 눈에 — 이 배율이라야 한 번 걸을 때마다 선이 눈에 띄게 자란다
            mapView.setRegion(
                MKCoordinateRegion(center: coordinate, latitudinalMeters: 1_600, longitudinalMeters: 1_600),
                animated: true
            )
        }
    }
}
