//
//  AtlasMapView.swift
//  FootprintDiary
//
//  대동여지도 — 백지 위에 내가 걸은 자리만 남는다.
//
//  세상은 이미 네이버·카카오·구글이 다 그려 놓았다. 그 위에 하나 더 그릴 이유는 없다.
//  이 지도의 값어치는 '내 두 발로 지난 자리만 그려져 있다'는 것 하나뿐이므로,
//  기본은 배경 지도를 종이로 덮어 두고 필요할 때만 비춰 본다.
//
//  걸은 자리는 선이 아니라 촘촘한 점으로 찍는다. 선으로 그리면 한 번 지난 길과
//  백 번 지난 길이 똑같아 보이지만, 점은 자주 지난 자리일수록 짙어진다.
//

import SwiftUI
import MapKit
import SwiftData

/// 먹과 종이의 빛깔
enum InkStyle {
    /// 먹 — 밝은 배경에선 짙은 먹, 어두운 배경에선 종이빛으로 뒤집는다
    static let ink = UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.97, green: 0.94, blue: 0.87, alpha: 1)
        : UIColor(red: 0.11, green: 0.12, blue: 0.16, alpha: 1)
    }

    /// 배경 지도를 덮는 종이. 옛 지도의 닥종이처럼 아주 옅은 누런빛.
    static let paper = UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1)
        : UIColor(red: 0.96, green: 0.95, blue: 0.91, alpha: 1)
    }

    /// 오늘 지난 자리는 주묵(붉은 먹)으로 찍는다.
    /// 옛 지도가 길을 붉은 선으로 표시하던 것과 같고, 오늘 무엇을 더했는지 바로 보인다.
    static let vermilion = UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 1.0, green: 0.45, blue: 0.35, alpha: 1)
        : UIColor(red: 0.78, green: 0.20, blue: 0.13, alpha: 1)
    }

    /// 낙관을 찍는 인주 빛. 주묵보다 짙어 점과 도장이 섞이지 않는다.
    static let sealRed = UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.86, green: 0.30, blue: 0.24, alpha: 1)
        : UIColor(red: 0.66, green: 0.14, blue: 0.11, alpha: 1)
    }
}

// MARK: - 스탬프

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
        let image = renderer.image { _ in
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
                glyph.draw(in: CGRect(
                    x: (size.width - glyph.size.width) / 2,
                    y: (size.height - glyph.size.height) / 2,
                    width: glyph.size.width,
                    height: glyph.size.height
                ))
            }
        }
        cache[kind.id] = image
        return image
    }
}

final class StampAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "stamp"
    /// 내 위치(.max)보다 낮게 둔다
    static let stampPriority = MKAnnotationViewZPriority(rawValue: 200)

    override var annotation: (any MKAnnotation)? {
        didSet {
            guard let stamp = annotation as? StampAnnotation else { return }
            image = StampSeal.image(for: stamp.kind)
            centerOffset = .zero
            canShowCallout = false
            isDraggable = true
            // 내 위치 점보다 아래에 깔린다. 스탬프가 여러 개 겹쳐도 지금 내가 어디인지는
            // 늘 보여야 한다 — 백지 지도에서는 그것이 유일한 '지금'의 기준이다.
            zPriority = Self.stampPriority
        }
    }
}

// MARK: - 지도

struct AtlasMapView: UIViewRepresentable {
    /// 걸은 자리를 칸으로 센 것
    let cells: [HeatCell]
    /// 길게 눌렀을 때 붙일 대상이 되는 길
    let trails: [[CLLocationCoordinate2D]]
    /// 배경 지도를 비춰 볼지. 꺼 두면 종이 위에 내 발자국만 남는다.
    let showsBasemap: Bool
    /// 지도에 찍은 스탬프
    let stamps: [MapStamp]

    var onSelectStamp: (MapStamp) -> Void = { _ in }
    /// 지도를 길게 눌러 자리를 골랐을 때
    var onPickCoordinate: (CLLocationCoordinate2D) -> Void = { _ in }
    /// 찍힌 스탬프를 끌어 옮겼을 때
    var onMoveStamp: (MapStamp, CLLocationCoordinate2D) -> Void = { _, _ in }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true

        // 종이로 덮을 때 지명이 비쳐 보이지 않도록 관심지점을 끈다
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
        let coordinator = context.coordinator
        coordinator.onSelectStamp = onSelectStamp
        coordinator.onPickCoordinate = onPickCoordinate
        coordinator.onMoveStamp = onMoveStamp
        coordinator.stampsByID = Dictionary(
            stamps.map { ($0.persistentModelID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        coordinator.trails = trails
        coordinator.syncPaper(on: mapView, showsBasemap: showsBasemap)
        coordinator.syncDots(on: mapView, cells: cells)
        coordinator.syncStamps(on: mapView, stamps: stamps)
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

        // 지금 올라가 있는 것들
        private var paperOverlay: MKPolygon?
        private var paperRect: MKMapRect?
        private var showsBasemap = false
        private var dotOverlay: DotGridOverlay?
        private var dotSignature: String?
        private var stampSignature: String?
        private var didCenterOnUser = false

        var stampsByID: [PersistentIdentifier: MapStamp] = [:]
        var trails: [[CLLocationCoordinate2D]] = []
        var onSelectStamp: (MapStamp) -> Void = { _ in }
        var onPickCoordinate: (CLLocationCoordinate2D) -> Void = { _ in }
        var onMoveStamp: (MapStamp, CLLocationCoordinate2D) -> Void = { _, _ in }

        // MARK: 종이

        /// 배경 지도를 덮는 종이.
        ///
        /// 온 세상을 한 장으로 덮는 폴리곤은 경도 ±180°에서 뒤집혀 제대로 그려지지 않는다.
        /// 그래서 보이는 범위보다 넉넉한 만큼만 덮고, 옮겨서 모자라면 다시 만든다.
        func syncPaper(on mapView: MKMapView, showsBasemap: Bool) {
            let changed = showsBasemap != self.showsBasemap
            self.showsBasemap = showsBasemap
            rebuildPaper(on: mapView, force: changed)
        }

        private func rebuildPaper(on mapView: MKMapView, force: Bool) {
            guard !showsBasemap else {
                if let paperOverlay { mapView.removeOverlay(paperOverlay) }
                paperOverlay = nil
                paperRect = nil
                return
            }

            let visible = mapView.visibleMapRect
            guard visible.size.width > 0 else { return }
            if !force, let paperRect, paperRect.contains(visible) { return }

            // 보이는 범위의 세 배를 덮어 두면 웬만큼 옮겨도 다시 만들지 않는다
            let target = visible.insetBy(dx: -visible.size.width, dy: -visible.size.height)
            paperRect = target

            if let paperOverlay { mapView.removeOverlay(paperOverlay) }
            // MKPolygon에는 사각형으로 만드는 생성자가 없어 네 꼭짓점으로 만든다
            let corners = [
                MKMapPoint(x: target.minX, y: target.minY),
                MKMapPoint(x: target.maxX, y: target.minY),
                MKMapPoint(x: target.maxX, y: target.maxY),
                MKMapPoint(x: target.minX, y: target.maxY)
            ]
            let paper = MKPolygon(points: corners, count: corners.count)
            paperOverlay = paper
            // 맨 아래에 깔아야 점이 그 위로 온다 (다시 만들어도 순서가 지켜진다)
            mapView.insertOverlay(paper, at: 0, level: .aboveLabels)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            rebuildPaper(on: mapView, force: false)
        }

        // MARK: 점

        func syncDots(on mapView: MKMapView, cells: [HeatCell]) {
            let signature = "\(cells.count)-\(cells.reduce(0) { $0 + $1.passes })"
            guard signature != dotSignature else { return }
            dotSignature = signature

            if let dotOverlay { mapView.removeOverlay(dotOverlay) }
            dotOverlay = nil
            guard !cells.isEmpty else { return }

            let dots = DotGridOverlay(cells: cells)
            dotOverlay = dots
            mapView.addOverlay(dots, level: .aboveLabels)
        }

        // MARK: 그리기

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let dots = overlay as? DotGridOverlay {
                return DotGridRenderer(overlay: dots, traits: mapView.traitCollection)
            }
            if let paper = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: paper)
                renderer.fillColor = InkStyle.paper.resolvedColor(with: mapView.traitCollection)
                renderer.strokeColor = .clear
                renderer.lineWidth = 0
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        // MARK: 스탬프

        func syncStamps(on mapView: MKMapView, stamps: [MapStamp]) {
            let signature = stamps
                .map { "\($0.persistentModelID.hashValue):\($0.kindID)" }
                .joined(separator: ",")
            guard signature != stampSignature else { return }
            stampSignature = signature

            mapView.removeAnnotations(mapView.annotations.compactMap { $0 as? StampAnnotation })
            mapView.addAnnotations(stamps.map(StampAnnotation.init))
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            guard annotation is StampAnnotation else { return nil }
            return mapView.dequeueReusableAnnotationView(
                withIdentifier: StampAnnotationView.reuseIdentifier,
                for: annotation
            )
        }

        /// 내 위치 점을 맨 위로 올린다.
        /// 기본값으로 두면 같은 자리에 찍힌 스탬프가 점을 덮어 지금 어디인지 알 수 없다.
        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            for view in views where view.annotation is MKUserLocation {
                view.zPriority = .max
                view.superview?.bringSubviewToFront(view)
            }
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation as? StampAnnotation else { return }
            // 고른 표시를 남겨 두면 다음에 같은 걸 눌러도 반응하지 않는다
            mapView.deselectAnnotation(annotation, animated: false)
            if let stamp = stampsByID[annotation.id] { onSelectStamp(stamp) }
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

        // MARK: 길게 눌러 찍기

        /// 길게 누른 자리에서 이 거리(pt) 안에 내 길이 있으면 길 위로 붙인다.
        /// 화면 거리로 재기 때문에 지도를 확대할수록 더 정확히 짚을 수 있다.
        static let snapDistance: CGFloat = 44

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            // began에서만 받는다. changed까지 받으면 누른 채 손이 흔들릴 때마다 열린다.
            guard gesture.state == .began, let mapView = gesture.view as? MKMapView else { return }
            onPickCoordinate(snapped(gesture.location(in: mapView), on: mapView))
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
                guard trail.contains(where: { visible.contains(MKMapPoint($0)) }) else { continue }
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

        // MARK: 첫 화면

        /// 앱을 켠 직후에는 내 위치가 아직 없다. 위치가 도착하면 한 번만 그리로 당겨 준다.
        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard !didCenterOnUser, let coordinate = userLocation.location?.coordinate else { return }
            didCenterOnUser = true
            // 동네 한 눈에 — 이 배율이라야 한 번 걸을 때마다 점이 눈에 띄게 는다
            mapView.setRegion(
                MKCoordinateRegion(center: coordinate, latitudinalMeters: 1_600, longitudinalMeters: 1_600),
                animated: true
            )
        }
    }
}
