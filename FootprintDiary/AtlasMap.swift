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
//  빛깔은 오늘 걸은 자리가 주묵, 지난 걸음이 남빛이고, 다시 밟지 않은 채 석 달이 지나면
//  잿빛으로 바랜다 (WalkHeatmap.swift).
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
    /// 물과 산을 먹 한 빛으로 칠할지, 봉우리·나무를 그려 넣을지
    var terrainSkin: TerrainSkin = .ink
    /// 걸은 자리로 뜬 내 동네 테두리를 그릴지
    var showsNeighborhood = true

    /// 열자마자 여기를 한가운데 놓는다.
    ///
    /// 정해 두면 내 위치가 도착해도 화면을 빼앗지 않는다. 안내에서 종이 한 조각을
    /// 보여 줄 때처럼 '보여 줄 자리가 이미 정해져 있는' 지도에 쓴다.
    var focus: CLLocationCoordinate2D?

    /// 내 위치로 돌아가는 단추를 달지. 안내에서 보여 주는 종이에는 달지 않는다 —
    /// 만질 수 없는 지도에 단추만 붙어 있으면 눌러 보고 고장 난 줄 안다.
    var showsTrackingButton = true

    /// 지금 내가 선 점을 그릴지.
    ///
    /// 이 점은 늘 도장보다 위에 선다(그래야 도장이 겹쳐도 지금 어디인지 안 묻힌다).
    /// 그런데 안내에서 첫 도장을 보여 줄 때는 도장이 바로 그 자리에 찍히므로, 점이
    /// 무엇을 찍었는지를 통째로 덮어 버린다. 보여 주려던 장면을 가리게 되는 그때만 끈다.
    var showsUserLocation = true

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
        mapView.showsUserLocation = showsUserLocation

        // 종이로 덮을 때 지명이 비쳐 보이지 않도록 관심지점을 끈다
        let configuration = MKStandardMapConfiguration(emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        mapView.preferredConfiguration = configuration
        mapView.register(
            StampAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: StampAnnotationView.reuseIdentifier
        )
        mapView.register(
            WalkSpotView.self,
            forAnnotationViewWithReuseIdentifier: WalkSpotView.reuseIdentifier
        )

        if showsTrackingButton { addTrackingButton(to: mapView) }
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
        if mapView.showsUserLocation != showsUserLocation {
            mapView.showsUserLocation = showsUserLocation
        }
        coordinator.focus(focus, on: mapView)
        coordinator.syncTheme(on: mapView, scheme: colorScheme)
        coordinator.syncSkin(on: mapView, skin: terrainSkin)
        coordinator.syncPaper(on: mapView, showsBasemap: showsBasemap)
        coordinator.syncNeighborhood(on: mapView, shows: showsNeighborhood)
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
        private var terrainSkin: TerrainSkin = .ink
        /// 내 동네 테두리. 뜨는 데 시간이 걸려 뒤쪽에서 뜨고, 다 뜬 것만 올린다.
        private var neighborhoodOverlay: NeighborhoodOverlay?
        private var neighborhoodAreas: [NeighborhoodArea] = []
        private var showsNeighborhood = true
        /// 늦게 끝난 옛 셈이 새 테두리를 덮지 않도록 차례를 센다
        private var neighborhoodGeneration = 0
        /// 멀리 물러났을 때 세우는 발자국 표지들 (WalkSpots.swift)
        private var walkSpots: [WalkSpotAnnotation] = []
        /// 지금 멀리 물러나 있는지. 표지와 동네 이름표가 이것으로 갈린다.
        private var isFarAway = false
        /// 걸은 자리. 그림지도의 그림이 이 자리를 비켜 선다.
        private var walkedGround: WalkedGround?
        /// 물·산의 본은 바둑판 조각마다 뜬다 (아래 '물과 산'). 뜬 조각과 지도에 얹은 조각.
        private var terrainTiles: [TerrainTileKey: TerrainTileState] = [:]
        private var terrainOverlays: [TerrainTileKey: TerrainOverlay] = [:]
        /// 뜰 차례를 기다리는 조각. 보이는 것이 앞, 둘레가 뒤다.
        private var terrainQueue: [TerrainTileKey] = []
        /// 지금 뜨고 있는 조각. 한 번에 하나씩만 뜬다.
        private var terrainBusy: TerrainTileKey?
        /// 지금 화면에 맞는 조각의 크기 단계
        private var terrainLevel: Int?
        private let terrainFinder = TerrainFinder()

        /// 조각 하나를 뜨고 다음 조각을 뜨기까지 두는 틈(초).
        /// 애플은 지도 찍기를 몰아치는 앱을 잠시 막아 버린다. 한 번 막히면 본이 통째로 빈다.
        static let terrainGap: TimeInterval = 0.15
        /// 막혔을 때 다시 해 보기까지 두는 시간(초). 서둘러 다시 조르면 더 오래 막힌다.
        static let terrainRetryDelay: TimeInterval = 4
        /// 지도에 얹어 두는 조각의 수. 넘치면 화면에서 먼 것부터 내린다 (뜬 본은 기기에 남아 있다).
        static let maxTerrainOverlays = 30
        private var didCenterOnUser = false
        /// 마지막으로 붙들어 놓은 자리 (focus로 받은 것)
        private var focused: CLLocationCoordinate2D?

        /// 붙들어 놓은 자리를 볼 때의 화면 너비(m).
        /// 도장 하나를 보여 주는 자리라 동네가 아니라 골목이 보여야 한다.
        static let focusMeters: CLLocationDistance = 500

        var proxy: MapProxy?
        var stampsByID: [PersistentIdentifier: MapStamp] = [:]

        func stopFindingTerrain() {
            terrainQueue.removeAll()
            terrainBusy = nil
            terrainFinder.cancel()
        }

        /// 보여 줄 자리를 붙들어 놓는다.
        ///
        /// 자리를 잡은 것으로 쳐서(didCenterOnUser) 내 위치가 도착해도 화면을 빼앗기지
        /// 않는다. 처음 잡을 때는 소리 없이 놓고, 자리가 옮겨질 때만 미끄러지듯 옮긴다 —
        /// 열자마자 화면이 날아가면 무엇을 보고 있었는지 알 수 없다.
        func focus(_ coordinate: CLLocationCoordinate2D?, on mapView: MKMapView) {
            guard let coordinate else { return }
            if let focused,
               focused.latitude == coordinate.latitude,
               focused.longitude == coordinate.longitude { return }
            let isFirst = focused == nil
            focused = coordinate
            didCenterOnUser = true
            mapView.setRegion(
                MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: Self.focusMeters,
                    longitudinalMeters: Self.focusMeters
                ),
                animated: !isFirst
            )
            proxy?.report(mapView)
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

            // 테두리는 다 뜬 고리를 그대로 들고 있다가, 점이 다시 올라가면 새 빛깔로 다시 얹는다
            if let neighborhoodOverlay { mapView.removeOverlay(neighborhoodOverlay) }
            neighborhoodOverlay = nil
        }
        var trails: [[CLLocationCoordinate2D]] = []
        var onSelectStamp: (MapStamp) -> Void = { _ in }
        var onPickCoordinate: (CLLocationCoordinate2D) -> Void = { _ in }
        var onMoveStamp: (MapStamp, CLLocationCoordinate2D) -> Void = { _, _ in }

        /// 칠하는 법이 바뀌면 본은 그대로 두고 지도에 올린 것만 갈아 끼운다
        func syncSkin(on mapView: MKMapView, skin: TerrainSkin) {
            guard skin != terrainSkin else { return }
            terrainSkin = skin
            detachTerrain(from: mapView)
            attachTerrainTiles(to: mapView)
            // 종이도 갈아 끼운다. 걷어 두면 바로 뒤의 syncPaper가 새 종이를 맨 아래에 깐다.
            if let paperOverlay { mapView.removeOverlay(paperOverlay) }
            paperOverlay = nil
            paperRect = nil
        }

        // MARK: 종이

        /// 배경 지도를 덮는 종이.
        ///
        /// 온 세상을 한 장으로 덮는 폴리곤은 경도 ±180°에서 뒤집혀 제대로 그려지지 않는다.
        /// 그래서 보이는 범위보다 넉넉한 만큼만 덮고, 옮겨서 모자라면 다시 만든다.
        func syncPaper(on mapView: MKMapView, showsBasemap: Bool) {
            let changed = showsBasemap != self.showsBasemap
            self.showsBasemap = showsBasemap
            if changed { applyCover(on: mapView) }
            rebuildPaper(on: mapView, force: false)
            refreshTerrain(on: mapView)
        }

        /// 비춰 볼 때 종이와 물·산을 걷어 내지 않고 투명하게만 둔다.
        ///
        /// 전에는 통째로 걷었다가 다시 얹었다. 그러면 돌아올 때마다 타일을 처음부터 다시
        /// 그려야 해서 — 그림지도는 봉우리·나무를 일일이 놓는다 — 화면이 한참 버벅였다.
        /// 얹어 둔 채 투명도만 바꾸면 이미 그려 둔 타일을 그대로 다시 보여 준다.
        private var coverAlpha: CGFloat { showsBasemap ? 0 : 1 }

        private func applyCover(on mapView: MKMapView) {
            for overlay in [paperOverlay as MKOverlay?].compactMap({ $0 }) + Array(terrainOverlays.values) {
                mapView.renderer(for: overlay)?.alpha = coverAlpha
            }
        }

        private func rebuildPaper(on mapView: MKMapView, force: Bool) {
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
            redrawSoon(paper, on: mapView)
        }

        /// 멀리 물러났는지 가까이 들어왔는지가 바뀌면 발자국 표지를 세우거나 걷는다
        private func syncDistance(on mapView: MKMapView) {
            let far = metersPerPoint(on: mapView) > WalkSpots.showAboveMetersPerPoint
            guard far != isFarAway else { return }
            isFarAway = far
            if far {
                mapView.addAnnotations(walkSpots)
            } else {
                mapView.removeAnnotations(walkSpots)
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            syncDistance(on: mapView)
            rebuildPaper(on: mapView, force: false)
            refreshTerrain(on: mapView)
            proxy?.report(mapView)
        }

        // MARK: 물과 산

        /// 물·산은 바둑판 조각으로 미리 떠 둔다.
        ///
        /// 전에는 보이는 범위의 두 배만 한 장으로 떴다. 그러면 조금만 밀어도 범위를 벗어났고,
        /// 지도가 멎은 뒤에야 새로 떠서 나무와 물이 뒤늦게 돋았다. 이제는 땅을 배율에 맞는
        /// 정해진 조각으로 나눠, 보이는 조각과 그 둘레를 미리 떠서 얹어 둔다. 지도를 밀면
        /// 이미 그려진 곳으로 들어가게 된다. 조각의 자리가 늘 같으므로 기기에 적어 둔 본
        /// (TerrainCache)도 그대로 다시 쓰인다.
        private func refreshTerrain(on mapView: MKMapView) {
            // 비추는 동안에는 진짜 물과 산이 보인다. 얹어 둔 조각은 투명하게 그대로 두고(applyCover)
            // 새로 뜨지만 않는다. 돌아오면 그 자리에서 곧바로 다시 보인다.
            guard !showsBasemap else { return }
            let visible = mapView.visibleMapRect
            guard visible.size.width > 0 else { return }

            let level = TerrainTileKey.level(for: visible)
            if level != terrainLevel {
                terrainLevel = level
                // 다른 크기의 조각은 이제 성글거나 너무 잘다. 본은 기기에 남아 있으니 들고 있지 않는다.
                terrainTiles = terrainTiles.filter { $0.key.level == level }
            }

            let showing = TerrainTileKey.keys(covering: visible, level: level)
            // 보이는 범위 둘레로 한 조각씩 더 — 밀어 들어갈 곳을 미리 떠 둔다
            let around = TerrainTileKey.keys(covering: visible, level: level, padding: 1)
            let center = MKMapPoint(x: visible.midX, y: visible.midY)

            terrainQueue = around
                .filter { terrainTiles[$0] == nil && $0 != terrainBusy }
                .sorted { a, b in
                    let aShown = showing.contains(a), bShown = showing.contains(b)
                    if aShown != bShown { return aShown }
                    return a.distance(to: center) < b.distance(to: center)
                }

            attachTerrainTiles(to: mapView)
            // 보이는 조각이 모두 이 크기로 갖춰졌으면, 앞서 얹어 둔 다른 크기의 조각을 내린다.
            // 갖춰지기 전에 내리면 그사이 물과 산이 통째로 비어 보인다.
            if showing.allSatisfy({ terrainTiles[$0] != nil }) {
                for (key, overlay) in terrainOverlays where key.level != level {
                    mapView.removeOverlay(overlay)
                    terrainOverlays[key] = nil
                }
            }
            trimTerrainOverlays(on: mapView, around: center)
            pumpTerrain(on: mapView)
        }

        /// 줄 맨 앞 조각을 뜬다. 다 뜨면 얹고 다음 조각으로 넘어간다.
        private func pumpTerrain(on mapView: MKMapView) {
            guard terrainBusy == nil, !showsBasemap, !terrainQueue.isEmpty else { return }
            let key = terrainQueue.removeFirst()
            terrainBusy = key
            terrainFinder.find(in: key.rect) { [weak self, weak mapView] result in
                guard let self, let mapView else { return }
                self.terrainBusy = nil
                switch result {
                case .found(let mask):
                    self.terrainTiles[key] = .found(mask)
                    if key.level == self.terrainLevel { self.attachTerrainTiles(to: mapView) }
                    self.continueTerrain(on: mapView, after: Self.terrainGap)
                case .bare:
                    self.terrainTiles[key] = .bare
                    self.continueTerrain(on: mapView, after: Self.terrainGap)
                case .failed:
                    // 막혔다. 이 조각은 줄 끝에 다시 세우고 좀 뜸을 들였다가 이어 간다.
                    self.terrainQueue.append(key)
                    self.continueTerrain(on: mapView, after: Self.terrainRetryDelay)
                }
            }
        }

        private func continueTerrain(on mapView: MKMapView, after delay: TimeInterval) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak mapView] in
                guard let self, let mapView else { return }
                self.pumpTerrain(on: mapView)
            }
        }

        /// 떠 둔 조각 가운데 아직 지도에 없는 것을 얹는다. 종이 바로 위, 발자국 바로 아래 — 물은 배경이지 기록이 아니다.
        private func attachTerrainTiles(to mapView: MKMapView) {
            for (key, state) in terrainTiles where terrainOverlays[key] == nil {
                guard case .found(let mask) = state else { continue }
                let overlay = TerrainOverlay(mask: mask, owned: key.rect)
                terrainOverlays[key] = overlay
                if let paperOverlay {
                    mapView.insertOverlay(overlay, above: paperOverlay)
                } else {
                    mapView.insertOverlay(overlay, at: 0, level: .aboveLabels)
                }
                redrawSoon(overlay, on: mapView)
            }
        }

        /// 얹어 둔 조각이 너무 많으면 화면에서 먼 것부터 내린다
        private func trimTerrainOverlays(on mapView: MKMapView, around center: MKMapPoint) {
            guard terrainOverlays.count > Self.maxTerrainOverlays else { return }
            let far = terrainOverlays.keys
                .sorted { $0.distance(to: center) > $1.distance(to: center) }
                .prefix(terrainOverlays.count - Self.maxTerrainOverlays)
            for key in far {
                if let overlay = terrainOverlays[key] { mapView.removeOverlay(overlay) }
                terrainOverlays[key] = nil
                terrainTiles[key] = nil
            }
        }

        /// 지도가 이미 다 그려져 멎어 있을 때 얹으면 MapKit이 손수 만든 그리개를 한 번도 부르지 않는다.
        /// 다시 열었을 때처럼 타일이 이미 들어와 있는 경우가 바로 그렇다 — 화면을 한 번 밀어야
        /// 그제야 물과 산이 나타난다. 얹은 다음 차례에 한 번 다시 그리라고 일러 둔다.
        private func redrawSoon(_ overlay: MKOverlay, on mapView: MKMapView) {
            DispatchQueue.main.async { [weak mapView] in
                mapView?.renderer(for: overlay)?.setNeedsDisplay()
            }
        }

        /// 걸은 자리가 바뀌었으면 그림지도의 그리개들에게 알려 다시 그리게 한다
        private func syncWalked(on mapView: MKMapView, cells: [HeatCell]) {
            walkedGround = cells.isEmpty ? nil : WalkedGround(cells: cells)
            for overlay in Array(terrainOverlays.values) as [MKOverlay] + [paperOverlay].compactMap({ $0 }) {
                guard let renderer = mapView.renderer(for: overlay) as? WalkAwareRenderer else { continue }
                renderer.walked.current = walkedGround
                renderer.setNeedsDisplay()
            }
        }

        /// 지도에서 걷어 내기만 한다. 본은 그대로 들고 있는다.
        private func detachTerrain(from mapView: MKMapView) {
            mapView.removeOverlays(Array(terrainOverlays.values))
            terrainOverlays.removeAll()
        }

        // MARK: 점

        /// 지난번에 받은 칸 배열의 자리. 같은 배열이 다시 오면 칸 수만 개를 훑지 않고 넘긴다 —
        /// 배율 눈금이 바뀌는 것처럼 지도와 상관없는 일로도 화면이 자주 다시 맞춰지기 때문이다.
        /// 배열을 쥐고 있어야 그 자리가 다른 배열에 다시 쓰이지 않는다 (자리만 견주면 헷갈린다).
        private var lastCells: [HeatCell] = []

        func syncDots(on mapView: MKMapView, cells: [HeatCell]) {
            if dotSignature != nil, !cells.isEmpty, cells.count == lastCells.count,
               cells.withUnsafeBufferPointer({ $0.baseAddress }) == lastCells.withUnsafeBufferPointer({ $0.baseAddress }) {
                return
            }
            lastCells = cells
            // 마지막으로 밟은 때까지 지문에 넣는다. 같은 칸을 다시 밟으면 칸 수도 통과 수도
            // 그대로인 채 빛깔만 바뀌는 날이 있는데, 그것까지 봐야 다시 그린다.
            let latest = cells.map(\.lastVisit).max() ?? .distantPast
            let signature = "\(cells.count)-\(cells.reduce(0) { $0 + $1.passes })-\(Int(latest.timeIntervalSinceReferenceDate))"
            guard signature != dotSignature else { return }
            dotSignature = signature
            syncWalked(on: mapView, cells: cells)
            findNeighborhood(from: cells, on: mapView)

            if let dotOverlay { mapView.removeOverlay(dotOverlay) }
            dotOverlay = nil
            guard !cells.isEmpty else { return }

            let dots = DotGridOverlay(cells: cells)
            dotOverlay = dots
            mapView.addOverlay(dots, level: .aboveLabels)
        }

        // MARK: 내 동네

        func syncNeighborhood(on mapView: MKMapView, shows: Bool) {
            guard shows != showsNeighborhood else { return }
            showsNeighborhood = shows
            placeNeighborhood(on: mapView)
        }

        /// 걸은 자리가 바뀌면 테두리를 다시 뜬다. 칸을 훑는 일이라 뒤쪽에서 한다.
        private func findNeighborhood(from cells: [HeatCell], on mapView: MKMapView) {
            neighborhoodGeneration += 1
            let generation = neighborhoodGeneration
            let points = cells.map { MKMapPoint($0.center) }
            DispatchQueue.global(qos: .utility).async { [weak self, weak mapView] in
                let areas = Neighborhood.outlines(of: points)
                let spots = WalkSpots.spots(of: points)
                DispatchQueue.main.async {
                    guard let self, let mapView, generation == self.neighborhoodGeneration else { return }
                    mapView.removeAnnotations(self.walkSpots)
                    self.walkSpots = spots
                    if self.isFarAway { mapView.addAnnotations(spots) }
                    self.neighborhoodAreas = areas
                    self.placeNeighborhood(on: mapView)
                }
            }
        }

        private func placeNeighborhood(on mapView: MKMapView) {
            if let neighborhoodOverlay { mapView.removeOverlay(neighborhoodOverlay) }
            neighborhoodOverlay = nil
            guard showsNeighborhood, !neighborhoodAreas.isEmpty else { return }
            let overlay = NeighborhoodOverlay(areas: neighborhoodAreas)
            neighborhoodOverlay = overlay
            // 발자국 점 바로 밑 — 점이 선에 가리지 않게
            if let dotOverlay {
                mapView.insertOverlay(overlay, below: dotOverlay)
            } else {
                mapView.addOverlay(overlay, level: .aboveLabels)
            }
            redrawSoon(overlay, on: mapView)
        }

        // MARK: 그리기

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let dots = overlay as? DotGridOverlay {
                return DotGridRenderer(overlay: dots, traits: mapView.traitCollection)
            }
            if let neighborhood = overlay as? NeighborhoodOverlay {
                return NeighborhoodRenderer(overlay: neighborhood, traits: mapView.traitCollection)
            }
            if let terrain = overlay as? TerrainOverlay {
                let renderer = TerrainRenderer(overlay: terrain, traits: mapView.traitCollection, skin: terrainSkin)
                renderer.walked.current = walkedGround
                renderer.alpha = coverAlpha
                return renderer
            }
            if let paper = overlay as? MKPolygon, terrainSkin == .picture {
                let renderer = PicturePaperRenderer(overlay: paper, traits: mapView.traitCollection)
                renderer.walked.current = walkedGround
                renderer.alpha = coverAlpha
                return renderer
            }
            if let paper = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: paper)
                renderer.fillColor = InkStyle.paper.resolvedColor(with: mapView.traitCollection)
                renderer.strokeColor = .clear
                renderer.lineWidth = 0
                renderer.alpha = coverAlpha
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
                // 도장 그림과 이름표는 만들 때 값을 복사해 두므로, 갈래·이름·심볼이 바뀌면 새로 찍는다.
                // 심볼은 몇 십 KB짜리 Data라 통째로 견주지 않고 있고 없음과 크기만 본다 —
                // 도장 하나 옮길 때마다 수십 개를 바이트째 맞대면 지도가 끊긴다.
                let stickerChanged = (annotation.sticker == nil) != (stamp.sticker == nil)
                    || annotation.stickerBytes != (stamp.sticker?.count ?? 0)
                if annotation.kind.id != stamp.kindID
                    || annotation.placeName != stamp.placeName
                    || annotation.isUnvisited != stamp.isUnvisited
                    || stickerChanged {
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
            if annotation is WalkSpotAnnotation
                || (annotation as? MKClusterAnnotation)?.memberAnnotations.first is WalkSpotAnnotation {
                return mapView.dequeueReusableAnnotationView(
                    withIdentifier: WalkSpotView.reuseIdentifier,
                    for: annotation
                )
            }
            guard annotation is StampAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: StampAnnotationView.reuseIdentifier,
                for: annotation
            )
            (view as? StampAnnotationView)?.stickerScale = stickerScale(on: mapView)
            return view
        }

        /// 확대·축소하는 동안 스티커가 손가락을 따라 커지고 작아진다
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            let scale = stickerScale(on: mapView)
            guard abs(scale - lastStickerScale) > 0.01 else { return }
            lastStickerScale = scale
            for annotation in mapView.annotations where annotation is StampAnnotation {
                (mapView.view(for: annotation) as? StampAnnotationView)?.stickerScale = scale
            }
        }

        private var lastStickerScale: CGFloat = 1

        private func stickerScale(on mapView: MKMapView) -> CGFloat {
            StampSeal.stickerScale(metersPerPoint: metersPerPoint(on: mapView))
        }

        /// 화면 1pt가 덮는 땅(m)
        private func metersPerPoint(on mapView: MKMapView) -> Double {
            let visible = mapView.visibleMapRect
            guard mapView.bounds.width > 0, visible.size.width > 0 else { return 0 }
            let center = MKMapPoint(x: visible.midX, y: visible.midY).coordinate
            return visible.size.width / Double(mapView.bounds.width)
                / MKMapPointsPerMeterAtLatitude(center.latitude)
        }

        /// 무리들이 한눈에 들어오게 옮긴다. 무리 하나면 동네가 보일 만큼은 들어간다.
        private func fly(to spots: [WalkSpotAnnotation], on mapView: MKMapView) {
            var rect = spots.reduce(MKMapRect.null) { $0.union($1.area) }
            guard !rect.isNull else { return }
            let perMeter = MKMapPointsPerMeterAtLatitude(MKMapPoint(x: rect.midX, y: rect.midY).coordinate.latitude)
            let least = 1_500 * perMeter
            if rect.size.width < least || rect.size.height < least {
                let grow = max(least - rect.size.width, least - rect.size.height, 0) / 2
                rect = rect.insetBy(dx: -grow, dy: -grow)
            }
            mapView.setUserTrackingMode(.none, animated: false)
            mapView.setVisibleMapRect(
                rect,
                edgePadding: UIEdgeInsets(top: 120, left: 60, bottom: 140, right: 60),
                animated: true
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
            // 발자국 표지를 누르면 그 무리가 한눈에 들어오게 날아간다
            let spots: [WalkSpotAnnotation]
            if let spot = view.annotation as? WalkSpotAnnotation {
                spots = [spot]
            } else if let cluster = view.annotation as? MKClusterAnnotation {
                spots = cluster.memberAnnotations.compactMap { $0 as? WalkSpotAnnotation }
            } else {
                spots = []
            }
            if !spots.isEmpty, let annotation = view.annotation {
                mapView.deselectAnnotation(annotation, animated: false)
                fly(to: spots, on: mapView)
                return
            }
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
