//
//  AtlasMap.swift
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
//  빛깔은 그날그날의 원색으로 찍히고 다시 밟지 않으면 해가 갈수록 바랜다 (WalkHeatmap.swift).
//
//  지도에 얹는 낙관은 AtlasStampAnnotation.swift에, 먹과 종이의 빛깔은 InkStyle.swift에 있다.
//

import SwiftUI
import MapKit
import SwiftData

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
    /// 확대·축소와 배율을 주고받는 손잡이
    let proxy: MapProxy

    /// 화면이 밝은지 어두운지.
    /// 그리개는 만들어질 때 빛깔을 미리 뽑아 두므로, 바뀌면 우리가 다시 얹어 줘야 한다.
    @Environment(\.colorScheme) private var colorScheme

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
        proxy.mapView = mapView
        context.coordinator.proxy = proxy

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
        coordinator.syncTheme(on: mapView, scheme: colorScheme)
        coordinator.syncPaper(on: mapView, showsBasemap: showsBasemap)
        coordinator.syncDots(on: mapView, cells: cells)
        coordinator.syncStamps(on: mapView, stamps: stamps)
    }

    static func dismantleUIView(_ mapView: MKMapView, coordinator: Coordinator) {
        mapView.delegate = nil
        coordinator.proxy?.mapView = nil
        coordinator.stopFindingTerrain()
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
        private var terrainOverlay: TerrainOverlay?
        /// 떠 둔 본. 지도를 비추는 동안에도 들고 있다가 손을 떼면 곧바로 다시 얹는다.
        private var terrainMask: TerrainMask?
        /// 마지막으로 물을 찾아본 범위 (물이 없던 자리도 여기 남는다 — 헛되이 다시 찍지 않으려고)
        private var terrainRect: MKMapRect?
        /// 그 본을 뜰 때의 화면 너비. 이보다 훨씬 좁혀 들어가면 본이 성겨 보여 다시 뜬다.
        private var terrainSpan: Double = 0
        private let terrainFinder = TerrainFinder()
        /// 아직 기다리고 있는 본 뜨기
        private var pendingTerrain: DispatchWorkItem?

        /// 지도가 이만큼(초) 잠잠해진 뒤에야 본을 뜬다.
        ///
        /// 화면이 움직이는 동안에는 지역 바뀜이 수십 번 들어온다. 그때마다 찍겠다고 달려들면
        /// 앞선 요청을 계속 취소하게 되고, 애플은 그렇게 몰아치는 앱을 잠시 막아 버린다.
        /// 한 번 막히면 본이 통째로 비어 물도 산도 나오지 않는다.
        static let terrainSettleDelay: TimeInterval = 0.45
        /// 막혔을 때 다시 해 보기까지 두는 시간(초). 서둘러 다시 조르면 더 오래 막힌다.
        static let terrainRetryDelay: TimeInterval = 4
        private var didCenterOnUser = false

        var proxy: MapProxy?
        var stampsByID: [PersistentIdentifier: MapStamp] = [:]

        func stopFindingTerrain() {
            pendingTerrain?.cancel()
            terrainFinder.cancel()
        }

        /// 마지막으로 그린 화면 밝기
        private var scheme: ColorScheme?

        /// 밝은 화면과 어두운 화면이 바뀌면 지도에 올린 것을 모두 걷어 낸다.
        ///
        /// MKOverlayRenderer는 만들어질 때 빛깔을 한 번 뽑아 두고, 화면 설정이 바뀌어도
        /// MapKit이 그리개를 다시 만들어 주지 않는다. 그대로 두면 어두운 화면에서 종이만
        /// 허옇게 남는다. 걷어 내면 바로 뒤의 sync들이 새 빛깔로 다시 얹는다.
        /// (물은 떠 둔 본을 그대로 쓰므로 지도를 새로 찍지 않는다)
        func syncTheme(on mapView: MKMapView, scheme: ColorScheme) {
            let previous = self.scheme
            self.scheme = scheme
            guard let previous, previous != scheme else { return }

            if let paperOverlay { mapView.removeOverlay(paperOverlay) }
            paperOverlay = nil
            paperRect = nil

            detachTerrain(from: mapView)

            if let dotOverlay { mapView.removeOverlay(dotOverlay) }
            dotOverlay = nil
            dotSignature = nil
        }
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
            refreshTerrain(on: mapView)
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

            // 보이는 범위의 세 배를 덮어 두면 웬만큼 옮겨도 다시 만들지 않는다.
            // 다만 지도 밖으로 넘기면 안 된다 — 지도가 막 열렸을 때는 보이는 범위가 온 세상이라
            // 세 배를 잡으면 좌표가 지도 밖으로 나가고, 그 종이는 그려지지도 않으면서
            // 그 뒤의 모든 화면을 '이미 덮었다'고 셈해 다시는 만들어지지 않는다.
            let target = visible
                .insetBy(dx: -visible.size.width, dy: -visible.size.height)
                .intersection(.world)
            guard !target.isNull, target.size.width > 0 else { return }
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
            refreshTerrain(on: mapView)
            proxy?.report(mapView)
        }

        // MARK: 물과 산

        /// 종이보다 좁게 덮는다.
        ///
        /// 본은 픽셀 수가 정해져 있어서, 넓게 덮을수록 같은 픽셀로 더 넓은 땅을 담아
        /// 물가가 뭉개진다. 종이는 한 번 크게 깔아 두면 그만이지만 물은 그렇지 않다.
        private func refreshTerrain(on mapView: MKMapView) {
            guard !showsBasemap else {
                // 비추는 동안에는 진짜 물과 산이 보인다. 그 위에 겹쳐 칠할 까닭이 없어 걷어 둔다.
                // 다만 걷어 두기만 하고 본은 그대로 들고 있는다. 여기서 본까지 버리면 손을 뗄 때
                // 지도를 다시 찍어야 하는데, 이어 찍기는 곧잘 막히고 그러면 무늬가 사라진 채 남는다.
                detachTerrain(from: mapView)
                pendingTerrain?.cancel()
                terrainFinder.cancel()
                return
            }

            let visible = mapView.visibleMapRect
            guard visible.size.width > 0 else { return }

            // 지난번에 찾아본 범위가 지금 보는 자리를 아직 덮고 있으면 다시 찍지 않는다.
            // 너무 깊이 확대해 들어가면 본이 성겨 보이므로 그때는 다시 뜬다.
            if let terrainRect, terrainRect.contains(visible), visible.size.width > terrainSpan * 0.4 {
                // 비추다 돌아온 참이면 들고 있던 본을 여기서 곧바로 되얹는다
                attachTerrain(to: mapView)
                return
            }

            scheduleTerrain(on: mapView, after: Self.terrainSettleDelay)
        }

        /// 지도가 멎기를 기다렸다가 본을 뜬다
        private func scheduleTerrain(on mapView: MKMapView, after delay: TimeInterval) {
            pendingTerrain?.cancel()
            let work = DispatchWorkItem { [weak self, weak mapView] in
                guard let self, let mapView else { return }
                self.findTerrain(on: mapView)
            }
            pendingTerrain = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        private func findTerrain(on mapView: MKMapView) {
            guard !showsBasemap else { return }
            let visible = mapView.visibleMapRect
            guard visible.size.width > 0 else { return }

            // 종이보다 좁게 덮는다. 본은 픽셀 수가 정해져 있어서, 넓게 덮을수록
            // 같은 픽셀로 더 넓은 땅을 담아 물가가 뭉개진다.
            let target = visible
                .insetBy(dx: -visible.size.width / 2, dy: -visible.size.height / 2)
                .intersection(.world)
            guard !target.isNull, target.size.width > 0 else { return }
            terrainRect = target
            terrainSpan = visible.size.width

            terrainFinder.find(in: target) { [weak self, weak mapView] result in
                guard let self, let mapView else { return }
                switch result {
                case .found(let mask):
                    self.terrainMask = mask
                    self.detachTerrain(from: mapView)
                    self.attachTerrain(to: mapView)
                case .bare:
                    self.terrainMask = nil
                    self.detachTerrain(from: mapView)
                case .failed:
                    // 찾아본 것으로 쳐 두면 이 자리에서는 두 번 다시 시도하지 않는다.
                    // 표시를 지우고, 좀 뜸을 들였다가 다시 해 본다.
                    self.terrainRect = nil
                    self.scheduleTerrain(on: mapView, after: Self.terrainRetryDelay)
                }
            }
        }

        /// 들고 있는 본을 지도에 얹는다. 종이 바로 위, 발자국 바로 아래 — 물은 배경이지 기록이 아니다.
        private func attachTerrain(to mapView: MKMapView) {
            guard !showsBasemap, terrainOverlay == nil, let terrainMask else { return }
            let overlay = TerrainOverlay(mask: terrainMask)
            terrainOverlay = overlay
            if let paperOverlay {
                mapView.insertOverlay(overlay, above: paperOverlay)
            } else {
                mapView.insertOverlay(overlay, at: 0, level: .aboveLabels)
            }
        }

        /// 지도에서 걷어 내기만 한다. 본은 그대로 들고 있는다.
        private func detachTerrain(from mapView: MKMapView) {
            if let terrainOverlay { mapView.removeOverlay(terrainOverlay) }
            terrainOverlay = nil
        }

        // MARK: 점

        func syncDots(on mapView: MKMapView, cells: [HeatCell]) {
            // 마지막으로 밟은 때까지 지문에 넣는다. 같은 칸을 다시 밟으면 칸 수도 통과 수도
            // 그대로인 채 빛깔만 바뀌는 날이 있는데, 그것까지 봐야 다시 그린다.
            let latest = cells.map(\.lastVisit).max() ?? .distantPast
            let signature = "\(cells.count)-\(cells.reduce(0) { $0 + $1.passes })-\(Int(latest.timeIntervalSinceReferenceDate))"
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
            if let terrain = overlay as? TerrainOverlay {
                return TerrainRenderer(overlay: terrain, traits: mapView.traitCollection)
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

        /// 지도 위의 도장을 지금 기록과 맞춘다.
        ///
        /// 예전에는 스탬프 목록으로 서명을 만들어 두고 '서명이 같으면 아무것도 하지 않는'
        /// 지름길을 썼다. 빠르긴 하나 지름길이 한 번이라도 어긋나면 지운 도장이 화면에
        /// 그대로 남고, 그러면 다시 그릴 방법이 없다 — 서명은 이미 같아져 있기 때문이다.
        /// 그래서 지금 얹혀 있는 것과 있어야 할 것을 그때그때 맞대어 본다. 도장은 많아야
        /// 수백 개라 맞대는 값이 싸고, 바뀐 것만 손대므로 지도가 깜빡이지도 않는다.
        func syncStamps(on mapView: MKMapView, stamps: [MapStamp]) {
            // 지워진 모델이 배열에 한 박자 더 남아 있을 수 있다. 그것으로 도장을 찍으면
            // 방금 지운 자리가 되살아난 것처럼 보인다.
            let live = stamps.filter { !$0.isDeleted }
            let wanted = Dictionary(
                live.map { ($0.persistentModelID, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            var kept: Set<PersistentIdentifier> = []
            var stale: [StampAnnotation] = []
            for annotation in mapView.annotations.compactMap({ $0 as? StampAnnotation }) {
                guard let stamp = wanted[annotation.id] else {
                    stale.append(annotation)
                    continue
                }
                // 도장 그림과 이름표는 만들 때 값을 복사해 두므로, 갈래나 이름이 바뀌면 새로 찍는다
                if annotation.kind.id != stamp.kindID || annotation.placeName != stamp.placeName {
                    stale.append(annotation)
                    continue
                }
                kept.insert(annotation.id)
                // 끌어 옮긴 자리가 기록과 어긋나 있으면 맞춘다
                if annotation.coordinate.latitude != stamp.latitude
                    || annotation.coordinate.longitude != stamp.longitude {
                    annotation.coordinate = stamp.coordinate
                }
            }

            if !stale.isEmpty { mapView.removeAnnotations(stale) }
            let added = live
                .filter { !kept.contains($0.persistentModelID) }
                .map(StampAnnotation.init)
            if !added.isEmpty { mapView.addAnnotations(added) }
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
            // 옮긴 자리는 맞대어 볼 때 저절로 맞춰진다 (도장을 다시 얹지 않는다)
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
            proxy?.report(mapView)
        }
    }
}
