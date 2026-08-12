//
//  FogMapView.swift
//  FootprintDiary
//
//  앱의 유일한 지도. 세상을 안개로 덮고, 내가 지나간 자리만 걷어낸다.
//  그 위에 쌓인 발자국과 아직 가보지 않은 스팟을 함께 얹는다.
//
//  SwiftUI의 MapPolygon은 구멍(interior polygon)을 지원하지 않아
//  MKMapView + MKPolygon(coordinates:interiorPolygons:)로 직접 그린다.
//  그래서 마커도 MKAnnotation으로 올리고, 생김새는 SwiftUI 뷰를 그림으로 구워 쓴다.
//

import SwiftUI
import MapKit

/// 걸은 길을 두 겹으로 그리기 위한 구분표
enum TrailStyle {
    static let glow = "trail.glow"
    static let core = "trail.core"
}

// MARK: - 어노테이션

/// 쌓인 발자국을 묶은 장소
final class PlaceAnnotation: NSObject, MKAnnotation {
    let place: FootprintPlace
    var coordinate: CLLocationCoordinate2D { place.coordinate }
    var title: String? { place.name }

    init(place: FootprintPlace) {
        self.place = place
    }
}

/// 아직 가보지 않은(또는 수집한) 사진 스팟
final class SpotAnnotation: NSObject, MKAnnotation {
    let spot: PhotoSpot
    let coordinate: CLLocationCoordinate2D
    let title: String?

    init(spot: PhotoSpot) {
        self.spot = spot
        // 모델이 나중에 지워져도 지도가 흔들리지 않도록 값을 복사해 둔다
        self.coordinate = spot.coordinate
        self.title = spot.name
    }
}

// MARK: - 지도

struct FogMapView: UIViewRepresentable {
    /// 안개를 걷어낸 칸들
    let clearedCells: Set<GridCell>
    /// 걸어서 지나온 길
    let trail: [[CLLocationCoordinate2D]]
    /// 지도에 올릴 장소와 스팟
    let places: [FootprintPlace]
    let spots: [PhotoSpot]
    /// 지도를 처음 열 때 잡을 화면
    let focus: MapInitialFocus

    var onSelectPlace: (FootprintPlace) -> Void = { _ in }
    var onSelectSpot: (PhotoSpot) -> Void = { _ in }

    /// 한 번에 그리는 구멍 수 상한. 이보다 많으면 지도 렌더링이 눈에 띄게 느려진다.
    static let maxHoles = 8_000
    /// 한 번에 올리는 장소 마커 수 상한 (넘으면 자주 간 곳부터)
    static let maxPlaceAnnotations = 500

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.pointOfInterestFilter = .excludingAll
        mapView.register(
            MarkerImageAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: MarkerImageAnnotationView.reuseIdentifier
        )
        addTrackingButton(to: mapView)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onSelectPlace = onSelectPlace
        context.coordinator.onSelectSpot = onSelectSpot

        // 첫 화면을 잡는다. 앱을 막 켠 직후에는 내 위치가 아직 없을 수 있어,
        // 위치가 도착해 화면이 바뀌면 한 번 더(내 위치로 맞출 때까지만) 당겨 준다.
        let applied = context.coordinator.appliedFocus
        if applied != focus, applied?.isUserCentered != true {
            context.coordinator.appliedFocus = focus
            mapView.setRegion(focus.region, animated: applied != nil)
        }

        // 칸이 그대로면 오버레이를 다시 만들지 않는다 (매 렌더마다 재구성하면 깜빡인다)
        if context.coordinator.renderedCells != clearedCells {
            context.coordinator.renderedCells = clearedCells
            context.coordinator.rebuildFog(on: mapView, force: true)
        }

        context.coordinator.syncTrail(on: mapView, segments: trail)

        context.coordinator.syncAnnotations(on: mapView, places: shownPlaces, spots: spots)
    }

    /// 마커가 너무 많으면 자주 간 곳부터 남긴다
    private var shownPlaces: [FootprintPlace] {
        guard places.count > Self.maxPlaceAnnotations else { return places }
        return Array(places.sorted { $0.visitCount > $1.visitCount }.prefix(Self.maxPlaceAnnotations))
    }

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

    static func dismantleUIView(_ mapView: MKMapView, coordinator: Coordinator) {
        mapView.delegate = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - 조정자

    final class Coordinator: NSObject, MKMapViewDelegate {
        var renderedCells: Set<GridCell> = []
        var appliedFocus: MapInitialFocus?
        var onSelectPlace: (FootprintPlace) -> Void = { _ in }
        var onSelectSpot: (PhotoSpot) -> Void = { _ in }

        /// 지금 덮여 있는 안개의 범위
        private var fogRegion: MKCoordinateRegion?
        /// 지금 올라가 있는 마커의 지문 — 달라졌을 때만 다시 올린다
        private var annotationSignature: String?
        /// 지금 그려져 있는 길
        private var fogOverlay: MKPolygon?
        private var trailOverlays: [MKPolyline] = []
        private var trailPointCount = -1

        // MARK: 그리기

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.fillColor = UIColor(red: 0.09, green: 0.11, blue: 0.20, alpha: 0.82)
                renderer.strokeColor = .clear
                renderer.lineWidth = 0
                return renderer
            }
            if let line = overlay as? MKPolyline {
                // 두 겹으로 그려 빛나는 자취처럼 보이게 한다 (넓고 흐린 층 + 좁고 밝은 층)
                let renderer = MKPolylineRenderer(polyline: line)
                let isGlow = line.title == TrailStyle.glow
                renderer.strokeColor = isGlow
                    ? UIColor(red: 0.55, green: 0.95, blue: 0.62, alpha: 0.28)
                    : UIColor(red: 0.72, green: 1.0, blue: 0.55, alpha: 0.95)
                renderer.lineWidth = isGlow ? 12 : 4
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        // MARK: 걸은 길

        func syncTrail(on mapView: MKMapView, segments: [[CLLocationCoordinate2D]]) {
            let count = segments.reduce(0) { $0 + $1.count }
            guard count != trailPointCount else { return }
            trailPointCount = count

            mapView.removeOverlays(trailOverlays)
            trailOverlays = segments.flatMap { segment -> [MKPolyline] in
                let glow = MKPolyline(coordinates: segment, count: segment.count)
                glow.title = TrailStyle.glow
                let line = MKPolyline(coordinates: segment, count: segment.count)
                line.title = TrailStyle.core
                return [glow, line]
            }
            // 안개 위에 얹어야 길이 보인다
            mapView.addOverlays(trailOverlays, level: .aboveLabels)
        }

        /// 지도를 옮기면 안개가 모자라는지 확인하고 필요할 때만 다시 만든다
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            rebuildFog(on: mapView, force: false)
        }

        func rebuildFog(on mapView: MKMapView, force: Bool) {
            let visible = mapView.region
            guard visible.span.latitudeDelta > 0, visible.span.longitudeDelta > 0 else { return }
            if !force, let fogRegion, FogMapView.region(fogRegion, covers: visible) { return }

            let target = FogMapView.fogRegion(covering: visible)
            fogRegion = target
            if let fogOverlay { mapView.removeOverlay(fogOverlay) }
            fogOverlay = FogMapView.makeFogPolygon(clearedCells: renderedCells, covering: target)
            if let fogOverlay {
                mapView.addOverlay(fogOverlay, level: .aboveRoads)
            }
        }

        // MARK: 마커

        func syncAnnotations(on mapView: MKMapView, places: [FootprintPlace], spots: [PhotoSpot]) {
            let signature = places.map { "p\($0.id):\($0.visitCount):\($0.name ?? "")" }.joined(separator: ",")
                + "|" + spots.map { "s\($0.name):\($0.isCollected)" }.joined(separator: ",")
            guard signature != annotationSignature else { return }
            annotationSignature = signature

            let existing = mapView.annotations.filter { !($0 is MKUserLocation) }
            mapView.removeAnnotations(existing)
            mapView.addAnnotations(places.map(PlaceAnnotation.init))
            mapView.addAnnotations(spots.map(SpotAnnotation.init))
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: MarkerImageAnnotationView.reuseIdentifier,
                for: annotation
            )
            if let place = annotation as? PlaceAnnotation {
                view.image = MarkerImageCache.shared.image(for: PlaceMarker(place: place.place))
            } else if let spot = annotation as? SpotAnnotation {
                view.image = MarkerImageCache.shared.image(for: SpotMarker(spot: spot.spot))
            }
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
            mapView.deselectAnnotation(annotation, animated: false)
            if let place = annotation as? PlaceAnnotation {
                onSelectPlace(place.place)
            } else if let spot = annotation as? SpotAnnotation {
                onSelectSpot(spot.spot)
            }
        }
    }

    // MARK: - 오버레이 만들기

    /// 안개는 지구 전체가 아니라 '보이는 곳보다 넉넉히 넓은 사각형'으로 만든다.
    /// 경도 폭이 180°를 넘으면 MapKit이 반대편으로 감싸는 것으로 해석해
    /// 폴리곤이 엉뚱한 조각이 되기 때문이다.
    static func fogRegion(covering visible: MKCoordinateRegion) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: visible.center,
            span: MKCoordinateSpan(
                latitudeDelta: min(visible.span.latitudeDelta * 3, 120),
                longitudeDelta: min(visible.span.longitudeDelta * 3, 150)
            )
        )
    }

    /// outer가 inner를 여유 있게 품고 있는지
    static func region(_ outer: MKCoordinateRegion, covers inner: MKCoordinateRegion) -> Bool {
        let latMargin = (outer.span.latitudeDelta - inner.span.latitudeDelta) / 2
        let lonMargin = (outer.span.longitudeDelta - inner.span.longitudeDelta) / 2
        guard latMargin > 0, lonMargin > 0 else { return false }
        return abs(outer.center.latitude - inner.center.latitude) < latMargin * 0.6
            && abs(outer.center.longitude - inner.center.longitude) < lonMargin * 0.6
    }

    /// 사각형에서 걷어낸 칸들을 구멍으로 뚫은 안개 폴리곤.
    /// 칸들은 서로 겹치지 않는 격자라서 구멍이 겹쳐 생기는 얼룩이 없다.
    static func makeFogPolygon(
        clearedCells: Set<GridCell>,
        covering region: MKCoordinateRegion
    ) -> MKPolygon? {
        let minLat = max(region.center.latitude - region.span.latitudeDelta / 2, -85)
        let maxLat = min(region.center.latitude + region.span.latitudeDelta / 2, 85)
        let minLon = max(region.center.longitude - region.span.longitudeDelta / 2, -179.9)
        let maxLon = min(region.center.longitude + region.span.longitudeDelta / 2, 179.9)
        guard minLat < maxLat, minLon < maxLon else { return nil }

        // 안개 밖의 칸은 어차피 보이지 않으므로 구멍을 만들지 않는다
        let step = SpatialGrid.step(meters: FogGrid.cellMeters)
        let holes = clearedCells
            .filter { cell in
                let lat = (Double(cell.row) + 0.5) * step
                let lon = (Double(cell.col) + 0.5) * step
                return lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon
            }
            .prefix(maxHoles)
            .map { MKPolygon(coordinates: FogGrid.corners(of: $0), count: 4) }

        let outer = [
            CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
            CLLocationCoordinate2D(latitude: maxLat, longitude: minLon),
            CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon),
            CLLocationCoordinate2D(latitude: minLat, longitude: maxLon)
        ]
        return MKPolygon(coordinates: outer, count: outer.count, interiorPolygons: Array(holes))
    }
}

// MARK: - 마커 그림

/// 그림 하나만 보여 주는 단순한 어노테이션 뷰
final class MarkerImageAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "MarkerImage"

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        centerOffset = .zero
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// SwiftUI로 만든 마커를 그림으로 구워 두고 다시 쓴다.
/// MKMapView는 SwiftUI 뷰를 직접 얹을 수 없고, 스크롤할 때마다 새로 그리면 버벅인다.
@MainActor
final class MarkerImageCache {
    static let shared = MarkerImageCache()

    private var cache: [String: UIImage] = [:]

    func image(for marker: PlaceMarker) -> UIImage? {
        image(key: "place-\(marker.place.rank)-\(marker.place.isDiscovered)-\(marker.place.visitCount)") {
            marker
        }
    }

    func image(for marker: SpotMarker) -> UIImage? {
        image(key: "spot-\(marker.spot.symbolName)-\(marker.spot.isCollected)") {
            marker
        }
    }

    private func image<V: View>(key: String, content: () -> V) -> UIImage? {
        if let cached = cache[key] { return cached }
        let renderer = ImageRenderer(content: content().padding(6))
        renderer.scale = UIScreen.main.scale
        guard let image = renderer.uiImage else { return nil }
        cache[key] = image
        return image
    }
}

// MARK: - 화면

/// 지도가 그릴 것들을 한 번만 계산해 들고 있는 상자.
/// 걸은 점이 늘어날수록 계산이 무거워지므로 본문에서 매번 하지 않고,
/// 좌표만 뽑아 백그라운드에서 만든 뒤 결과를 돌려받는다.
@MainActor
final class ExplorationMapState: ObservableObject {
    @Published private(set) var cells: Set<GridCell> = []
    @Published private(set) var trail: [[CLLocationCoordinate2D]] = []
    @Published private(set) var places: [FootprintPlace] = []
    @Published private(set) var walkedDistance: CLLocationDistance = 0

    private var signature: String?

    func rebuild(visits: [Visit], track: [TrackPoint]) {
        let key = "\(visits.count)-\(track.count)-\(visits.last?.persistentModelID.hashValue ?? 0)"
        guard key != signature else { return }
        signature = key

        // @Model 객체는 다른 스레드로 넘길 수 없으므로 값만 뽑아 둔다
        let stayed = visits.map(\.coordinate)
        let walked = track.map { WalkTrail.Point(coordinate: $0.coordinate, timestamp: $0.timestamp) }
        places = FootprintAggregator.places(from: visits)

        Task.detached(priority: .userInitiated) {
            let cells = FogGrid.clearedCells(
                walked: walked.map(\.coordinate),
                stayed: stayed
            )
            let segments = WalkTrail.segments(from: walked)
            let distance = WalkTrail.distance(of: walked)
            await MainActor.run {
                self.cells = cells
                self.trail = segments
                self.walkedDistance = distance
            }
        }
    }
}

/// 안개 지도 + 탐험 요약
struct FogScreen: View {
    let visits: [Visit]
    let track: [TrackPoint]
    let spots: [PhotoSpot]
    let focus: MapInitialFocus
    var onSelectPlace: (FootprintPlace) -> Void = { _ in }
    var onSelectSpot: (PhotoSpot) -> Void = { _ in }

    @StateObject private var state = ExplorationMapState()

    var body: some View {
        ZStack(alignment: .top) {
            FogMapView(
                clearedCells: state.cells,
                trail: state.trail,
                places: state.places,
                spots: spots,
                focus: focus,
                onSelectPlace: onSelectPlace,
                onSelectSpot: onSelectSpot
            )
            .ignoresSafeArea(edges: .bottom)

            summary
                .padding(.horizontal)
                .padding(.top, 8)
        }
        .onAppear { state.rebuild(visits: visits, track: track) }
        .onChange(of: track.count) { state.rebuild(visits: visits, track: track) }
        .onChange(of: visits.count) { state.rebuild(visits: visits, track: track) }
    }

    private var summary: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("밝힌 땅 \(areaText(FogGrid.clearedAreaSquareKilometers(state.cells)))")
                    .font(.subheadline.bold())
                Text(state.cells.isEmpty
                     ? "걸으면 지나온 길의 안개가 걷혀요"
                     : "걸어온 거리 \(distanceText(state.walkedDistance))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            item(value: "\(state.places.filter(\.isDiscovered).count)", label: "발견")
            Divider().frame(height: 24)
            item(value: "\(state.places.filter(\.isFavorite).count)", label: "단골")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func item(value: String, label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func areaText(_ area: Double) -> String {
        area < 1
        ? String(format: "%.2f㎢", area)
        : String(format: "%.1f㎢", area)
    }

    private func distanceText(_ meters: CLLocationDistance) -> String {
        meters < 1_000
        ? "\(Int(meters))m"
        : String(format: "%.1fkm", meters / 1_000)
    }
}
