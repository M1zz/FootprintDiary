//
//  AtlasScreen.swift
//  FootprintDiary
//
//  앱의 본체 — 내가 걸어서 그린 지도 한 장.
//
//  지표는 '걸은 거리'가 아니라 '그린 길이'다. 같은 길을 백 번 걸어도 지도는 자라지 않고,
//  처음 지나는 길을 걸어야만 자란다. 그래서 이 숫자는 줄지 않고, 늘리려면 새 길로 가야 한다.
//

import SwiftUI
import SwiftData
import CoreLocation
import TipKit

/// 지도가 그릴 것들을 한 번만 계산해 들고 있는 상자.
/// 점이 쌓일수록 계산이 무거워지므로 본문에서 매번 하지 않고 백그라운드에서 만든다.
/// 스탬프를 찍을 자리 하나. 좌표는 Identifiable이 아니라서 시트에 바로 못 넘긴다.
struct StampSpot: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    /// 내가 가 본 자리인지. 거짓이면 아직 한 번도 밟지 않은 곳에 미리 찍는 것이다.
    ///
    /// 찍는 순간에 정해 두어야 한다. 나중에 다시 재면 그 사이에 그 앞을 지나갔다는
    /// 이유만으로 '가볼 곳으로 찍어 뒀던 자리'라는 사실이 조용히 사라진다.
    var isHere: Bool = true
}

@MainActor
final class AtlasState: ObservableObject {
    /// 걸은 자리를 칸으로 센 것 (지도에 점으로 찍힌다)
    @Published private(set) var cells: [HeatCell] = []
    /// 길게 누를 때 붙일 대상이 되는 길
    @Published private(set) var trails: [[CLLocationCoordinate2D]] = []
    /// 내가 그린 지도의 총 길이(m) — 날짜별 '처음 걷는 거리'의 합
    @Published private(set) var atlasLength: CLLocationDistance = 0
    /// 오늘 새로 그은 길이(m)
    @Published private(set) var todayLength: CLLocationDistance = 0
    /// 걸음이 남은 날 수 (익명 통계에만 쓴다)
    @Published private(set) var walkedDays: Int = 0
    /// 내가 밟아 본 땅. 길게 눌러 찍는 자리가 '가본 곳'인지 가리는 데 쓴다.
    @Published private(set) var ground = VisitedGround()
    @Published private(set) var isReady = false
    /// 고른 기간에 처음 그은 길이(m). 기간을 고르지 않았으면 atlasLength와 같다.
    @Published private(set) var periodLength: CLLocationDistance = 0

    /// 마지막으로 셈한 하루치 걸음들. 기간을 바꿀 때 다듬기부터 다시 하지 않으려고 들고 있다.
    private var walks: [DayWalk] = []
    /// 날마다 처음 그은 길이(m)
    private var novelty: [Date: CLLocationDistance] = [:]
    /// 지금 보고 있는 기간. nil이면 전체다.
    private var period: DateInterval?
    /// 나중에 시작한 셈이 먼저 끝난 셈을 덮지 않게 매기는 번호
    private var drawGeneration = 0

    /// 다시 셈할 만큼 기록이 늘었는지 가리는 표. 걸음과 머무름을 함께 본다 —
    /// 밟아 본 땅은 걸은 길만이 아니라 머문 자리로도 넓어진다.
    private struct Signature: Equatable {
        let track: Int
        let stays: Int
    }

    private var signature: Signature?

    /// - Parameters:
    ///   - stays: 머무름으로 남은 자리들. 걸음이 끊긴 채 남은 자리도 가 본 곳이다.
    ///   - newPlacesToday: 오늘 처음 밟은 자리 수. 위젯에만 쓰인다.
    ///     저장소를 여기서 다시 뒤지지 않고 화면이 이미 들고 있는 것을 받는다.
    func rebuild(
        track: [TrackPoint],
        stays: [CLLocationCoordinate2D],
        newPlacesToday: Int,
        calendar: Calendar
    ) {
        let now = Signature(track: track.count, stays: stays.count)
        guard signature != now else { return }
        signature = now

        // @Model 객체는 다른 스레드로 넘길 수 없으므로 값만 뽑아 둔다.
        // 정확도까지 함께 가져가야 어느 점을 더 믿을지 판단할 수 있다.
        //
        // 저장은 관대하게 하고 거르는 건 여기서 한다. 크게 밀린 점을 직선으로 이으면
        // 선이 건물을 가로지르지만, 저장까지 안 하면 나중에 보정이 좋아져도 되살릴 수 없다.
        // (이 속성이 생기기 전에 쌓인 점은 정확도가 -1이라 알 수 없으므로 그대로 쓴다)
        let raw = track
            .filter { $0.horizontalAccuracy <= 0 || $0.horizontalAccuracy <= LocationManager.maxDrawAccuracy }
            .map {
                TrackSmoothing.RawPoint(
                    coordinate: $0.coordinate,
                    timestamp: $0.timestamp,
                    accuracy: $0.horizontalAccuracy
                )
            }
        let startOfToday = calendar.startOfDay(for: .now)
        let period = self.period
        drawGeneration += 1
        let generation = drawGeneration

        Task.detached(priority: .userInitiated) {
            // 저장된 점은 그대로 두고, 그릴 값만 다듬는다.
            // 여러 번 지난 길을 겹쳐 붙이는 것도 해 봤으나 나란한 골목이 하나로
            // 뭉개져 접었다. 까닭은 TrackConsolidation.swift 머리말에 적어 두었다.
            let points = TrackSmoothing.smoothed(raw).map {
                WalkTrail.Point(coordinate: $0.coordinate, timestamp: $0.timestamp)
            }
            let walks = DayWalk.build(from: points, calendar: calendar)
            let novelty = WalkNovelty.newDistances(for: walks)
            let drawing = Self.drawing(walks: walks, novelty: novelty, in: period, calendar: calendar)
            // 다듬은 뒤의 점으로 담는다. 크게 밀린 점까지 '가 본 자리'로 세면
            // 건물 저편 골목이 걸어 본 곳이 되어, 거기 찍는 자리가 잘못 굳는다.
            let ground = VisitedGround(walked: points.map(\.coordinate), stayed: stays)

            let total = novelty.values.reduce(0, +)
            let todayNew = novelty[startOfToday] ?? 0

            // 위젯에 건넬 꾸러미도 여기서 적는다. 오늘 걸음과 지난 걸음을 갈라 놓은
            // 곳이 여기뿐이라, 다른 데서 적으려면 이 셈을 통째로 한 번 더 해야 한다.
            let todayWalk = walks.first { $0.day == startOfToday }
            WalkSnapshotWriter.write(
                todayPoints: (todayWalk?.segments.flatMap { $0 } ?? []).map(\.coordinate),
                pastPoints: walks
                    .filter { $0.day < startOfToday }
                    .flatMap { $0.segments.flatMap { $0 } }
                    .map(\.coordinate),
                newMeters: todayNew,
                walkedMeters: todayWalk?.distance ?? 0,
                newPlaces: newPlacesToday,
                calendar: calendar
            )

            await MainActor.run {
                self.walks = walks
                self.novelty = novelty
                if generation == self.drawGeneration { self.apply(drawing) }
                self.atlasLength = total
                self.todayLength = todayNew
                self.walkedDays = walks.count
                self.ground = ground
                self.isReady = true
            }
        }
    }

    /// 지도에 남길 것을 이 기간으로 좁힌다. nil이면 전체를 그린다.
    ///
    /// 기록을 다시 다듬지 않고 들고 있던 하루치 걸음에서 고르기만 한다.
    /// 밟아 본 땅(ground)과 위젯은 건드리지 않는다 — 기간은 보는 방법일 뿐, 가 본
    /// 자리가 줄어드는 것은 아니다.
    func show(period: DateInterval?, calendar: Calendar) {
        guard self.period != period else { return }
        self.period = period
        guard isReady else { return }
        drawGeneration += 1
        let generation = drawGeneration
        let walks = self.walks
        let novelty = self.novelty
        Task.detached(priority: .userInitiated) {
            let drawing = Self.drawing(walks: walks, novelty: novelty, in: period, calendar: calendar)
            await MainActor.run {
                guard generation == self.drawGeneration else { return }
                self.apply(drawing)
            }
        }
    }

    private struct Drawing {
        let cells: [HeatCell]
        let trails: [[CLLocationCoordinate2D]]
        let length: CLLocationDistance
    }

    private func apply(_ drawing: Drawing) {
        cells = drawing.cells
        trails = drawing.trails
        periodLength = drawing.length
    }

    /// 기간 안의 날에 걸은 것만 칸으로 센다.
    nonisolated private static func drawing(
        walks: [DayWalk],
        novelty: [Date: CLLocationDistance],
        in period: DateInterval?,
        calendar: Calendar
    ) -> Drawing {
        // 칸은 '마지막으로 밟은 때' 하나만 들고 있어서, 다 셈한 칸을 기간으로 거르면
        // 그 기간에 걸었더라도 나중에 다시 밟은 자리가 빠진다. 그래서 걸음부터 고른다.
        let chosen = period.map { period in walks.filter { $0.day >= period.start && $0.day < period.end } } ?? walks
        let segments = chosen.flatMap(\.segments)
        let cells = WalkHeatmap.cells(passes: segments, calendar: calendar)
        // 길게 눌러 붙일 때만 쓰는 선. 모서리를 깎아 두면 손가락이 길에 더 잘 붙는다.
        let trails = segments.map { TrackSmoothing.rounded($0.map(\.coordinate)) }
        let length = chosen.reduce(0) { $0 + (novelty[$1.day] ?? 0) }
        return Drawing(cells: cells, trails: trails, length: length)
    }
}

struct AtlasScreen: View {
    @Query(sort: \TrackPoint.timestamp) private var track: [TrackPoint]
    @Query(sort: \MapStamp.createdAt) private var stamps: [MapStamp]
    @Query(sort: \Visit.arrivalDate) private var visits: [Visit]
    /// 일기 편 수. 익명 통계에만 쓰고, 글은 읽지도 보내지도 않는다.
    @Query private var diaryEntries: [DiaryEntry]

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var locationManager: LocationManager

    @StateObject private var state = AtlasState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showDiary = false
    @State private var showSupport = false
    @State private var showFilm = false
    @State private var showStampList = false
    @State private var showCompass = false
    @State private var showTimeline = false
    @State private var showWhatsNew = false
    /// 설정·새 기능 안내에서 고른 화면. 그 장이 다 닫힌 뒤에 연다 —
    /// 닫히는 중인 시트 위에 다른 시트를 올리면 SwiftUI가 둘 중 하나를 버린다.
    @State private var pendingDestination: AtlasDestination?

    // 지도 위에 무엇을 띄울지. 설정의 '지도에 보이기'와 같은 열쇠를 본다 (MapControls.swift)
    @AppStorage(MapControl.diary.storageKey) private var showsDiaryButton = MapControl.diary.isVisibleByDefault
    @AppStorage(MapControl.stampList.storageKey) private var showsStampListButton = MapControl.stampList.isVisibleByDefault
    @AppStorage(MapControl.compass.storageKey) private var showsCompassButton = MapControl.compass.isVisibleByDefault
    @AppStorage(MapControl.film.storageKey) private var showsFilmButton = MapControl.film.isVisibleByDefault
    @AppStorage(MapControl.peek.storageKey) private var showsPeekButton = MapControl.peek.isVisibleByDefault
    @AppStorage(MapControl.scaleBar.storageKey) private var showsScaleBar = MapControl.scaleBar.isVisibleByDefault
    @AppStorage(MapControl.period.storageKey) private var showsPeriodButton = MapControl.period.isVisibleByDefault
    @AppStorage(MapControl.skin.storageKey) private var showsSkinButton = MapControl.skin.isVisibleByDefault
    @AppStorage(MapControl.zoom.storageKey) private var showsZoomButtons = MapControl.zoom.isVisibleByDefault
    @AppStorage(MapControl.neighborhood.storageKey) private var showsNeighborhood = MapControl.neighborhood.isVisibleByDefault

    private let peekTip = PeekTip()
    private let mapControlsTip = MapControlsTip()
    @State private var showPeriodPicker = false
    /// 지도를 좁혀 보는 기간. 앱을 다시 열면 전체로 돌아온다 — 좁혀 둔 것을 잊고
    /// 다음에 열었을 때 길이 사라진 줄 아는 것이 더 나쁘다.
    @State private var period: AtlasPeriod = .all
    /// 스탬프를 찍을 자리. 정해지면 고르는 화면이 열린다.
    @State private var pendingCoordinate: StampSpot?
    @State private var selectedStamp: MapStamp?
    @State private var showNoLocation = false
    /// 배경 지도를 비추는 중인지. 단추로 켜고 끈다.
    ///
    /// 전에는 누르고 있는 동안에만 비췄다. 그러면 지도를 보며 손가락으로 옮겨 볼 수가 없어서
    /// 한 번 누르면 켜지고 다시 누르면 꺼지게 바꿨다. 다만 앱을 다시 열면 늘 종이로 돌아온다 —
    /// 켜 둔 채로 남으면 이 앱은 그냥 '지도 위에 선 긋는 앱'이 된다.
    @State private var isPeeking = false
    /// 왼쪽 아래 도구(동네 테두리·기간·비춰보기·그림지도·도장)를 펼쳐 두었는지.
    ///
    /// 단추 넷이 늘 서 있으면 지도 왼쪽 아래가 단추 기둥이 된다. 평소에는 하나로 접어 두고
    /// 쓸 때만 편다. 다만 아직 아무 길도 없는 지도에서는 도장이 첫 할 일이라 펴 둔 채로 연다.
    @State private var toolsExpanded = false
    /// 이름을 붙이려고 고른 동네
    /// 물과 산을 무엇으로 칠할지. 한 번 고르면 다음에 열어도 그대로다.
    @AppStorage("footprint.terrainSkin") private var terrainSkinRaw = TerrainSkin.ink.rawValue
    /// 빈 지도 안내를 아직 띄우고 있는지.
    ///
    /// 이 안내는 화면 한가운데에 서는데, 거기가 마침 내 위치 점이 서는 자리다. 걷기 시작한
    /// 사람은 '지금 내가 어디인가'부터 보고 싶은데 안내가 그 위를 덮고 있으면 안내가 아니라
    /// 가림막이다. 그래서 읽을 만큼만 보여 주고 스스로 비켜난다.
    @State private var showsEmptyHint = true
    @StateObject private var mapProxy = MapProxy()

    private var calendar: Calendar { .current }

    /// 글이 한 자라도 있는 일기 편 수. 사진만 붙인 날은 세지 않는다.
    private var diaryCount: Int {
        diaryEntries.filter { !$0.text.isEmpty }.count
    }

    /// 오늘 처음 밟은 자리 수. 위젯이 '처음 3곳'이라고 내거는 값이다.
    private var newPlacesToday: Int {
        visits.filter { $0.isFirstVisit && calendar.isDateInToday($0.arrivalDate) }.count
    }

    /// 오늘 오래 머물렀는데 아직 지도에 남기지 않은 자리
    private var asking: [Visit] {
        StayPrompt.candidates(visits: visits, stamps: stamps, calendar: calendar)
    }

    /// 지도에 올릴 도장. 기간을 골랐으면 그 기간에 찍은 것만.
    private var shownStamps: [MapStamp] {
        guard let interval = period.interval(calendar: calendar) else { return stamps }
        return stamps.filter { interval.contains($0.createdAt) }
    }

    /// 실제로 다녀온 자리만. 익명 통계에 세는 것은 이쪽이다 —
    /// 가볼 곳까지 세면 '몇 군데를 남겼나'가 '몇 군데를 꿈꿨나'와 섞인다.
    private var visitedStamps: [MapStamp] {
        stamps.filter { !$0.isUnvisited }
    }

    /// 이 좌표를 걸어 본 적이 있는지.
    ///
    /// 아직 한 걸음도 그려지지 않았으면 묻지 않는다. 그때는 어디를 찍든 '안 가본 곳'이
    /// 되는데, 앱을 처음 켠 날 지금 선 자리를 짚은 것까지 가볼 곳으로 남으면
    /// 시작부터 지도가 거짓말을 한다.
    private func hasBeenThere(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard !state.ground.isEmpty else { return true }
        return state.ground.hasBeen(at: coordinate)
    }

    /// 지금 서 있는 자리에서 가장 가까운, 아직 가보지 않은 스탬프.
    ///
    /// 오늘 한 번 물어본 자리는 나오지 않는다(canAskAboutVisit). 아니라고 한 자리를
    /// 걸음마다 다시 묻는 것이 이 앱에서 가장 성가신 물음이 될 수 있다.
    private var arriving: MapStamp? {
        guard let location = locationManager.currentLocation else { return nil }
        return stamps
            .filter { $0.isUnvisited && $0.isNearby(location) }
            .filter { $0.canAskAboutVisit(now: .now, calendar: calendar) }
            .min { $0.distance(from: location) < $1.distance(from: location) }
    }

    /// 가볼 곳으로 찍어 두었던 자리에 정말로 닿았다 — 가본 곳으로 굳힌다.
    private func confirmArrival(_ stamp: MapStamp) {
        stamp.addVisit()
        stamp.visitAskedAt = .now
        try? modelContext.save()
        FootprintUsage.log(.visitConfirmed)
    }

    /// 아직 아니라고 답한 자리. 오늘은 다시 묻지 않는다.
    private func declineArrival(_ stamp: MapStamp) {
        stamp.visitAskedAt = .now
        try? modelContext.save()
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                AtlasMapView(
                    cells: state.cells,
                    trails: state.trails,
                    showsBasemap: isPeeking,
                    stamps: shownStamps,
                    proxy: mapProxy,
                    terrainSkin: terrainSkin,
                    showsNeighborhood: showsNeighborhood,
                    onSelectStamp: { selectedStamp = $0 },
                    onPickCoordinate: { coordinate in
                        pendingCoordinate = StampSpot(
                            coordinate: coordinate,
                            isHere: hasBeenThere(coordinate)
                        )
                    },
                    onMoveStamp: { stamp, coordinate in
                        stamp.latitude = coordinate.latitude
                        stamp.longitude = coordinate.longitude
                        try? modelContext.save()
                    }
                )
                // 위로도 끝까지 깐다. 막대 아래에서 지도가 잘리면 종이 위에 까만 띠가 하나 얹힌 꼴이 된다.
                .ignoresSafeArea()

                VStack(spacing: 8) {
                    if !period.isAll {
                        periodChip
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    // 가볼 곳으로 찍어 둔 자리에 닿았을 때만 선다. 지도를 가리지 않도록
                    // 요약 바로 아래, 한 자리에만.
                    if let arriving {
                        arrivalCard(arriving)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .animation(.easeOut(duration: 0.25), value: arriving?.persistentModelID)
                .animation(.easeOut(duration: 0.25), value: period)

                if isEmptyMap && showsEmptyHint {
                    emptyHint
                        .transition(.opacity)
                }

                VStack(alignment: .leading, spacing: 10) {
                    if showsScaleBar {
                        scaleBar
                    }
                    toolStack
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 16)
                // 애플 지도 저작권 표기를 가리지 않도록 띄운다 (가리면 심사에서 걸린다)
                .padding(.bottom, 52)

                // 안내가 떠 있는 동안에는 물러난다. 둘 다 화면 한가운데 높이에 서서
                // 서로 겹치는데, 아직 아무것도 안 그려진 종이에서 확대·축소는 할 일이 없다.
                if showsZoomButtons && !(isEmptyMap && showsEmptyHint) {
                    zoomButtons
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .padding(.trailing, 12)
                        .transition(.opacity)
                }
            }
            .navigationTitle("내 지도")
            .navigationBarTitleDisplayMode(.inline)
            // 막대는 바탕 없이 단추만 지도 위에 띄운다. 단추는 저마다 유리 바탕을 이미 갖고 있다.
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                // 단추는 설정에서 고른 것만 단다. 꺼 둔 화면은 설정의 '모아 보기'에서 연다.
                ToolbarItemGroup(placement: .topBarLeading) {
                    if showsDiaryButton {
                        Button {
                            showDiary = true
                        } label: {
                            Image(systemName: "book.closed")
                        }
                        .accessibilityLabel("일지")
                    }
                    if showsStampListButton {
                        Button {
                            showStampList = true
                        } label: {
                            Image(systemName: "list.bullet")
                                // 물어볼 자리가 있으면 작은 점 하나로만 알린다.
                                // 알림을 띄우면 걷는 중에 끼어들고, 아무 표시도 없으면 영영 안 본다.
                                .overlay(alignment: .topTrailing) {
                                    if !asking.isEmpty {
                                        Circle()
                                            .fill(Color(InkStyle.sealRed))
                                            .frame(width: 7, height: 7)
                                            .offset(x: 5, y: -3)
                                    }
                                }
                        }
                        .accessibilityLabel(asking.isEmpty ? "내가 찍은 곳" : "내가 찍은 곳, 물어볼 것 있음")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if showsCompassButton {
                        Button {
                            showCompass = true
                        } label: {
                            Image(systemName: "location.north.line")
                        }
                        .accessibilityLabel("개척 나침반")
                    }
                    if showsFilmButton {
                        Button {
                            showFilm = true
                        } label: {
                            Image(systemName: "play.rectangle")
                        }
                        .accessibilityLabel("그려지는 것 보기")
                    }
                    Button {
                        mapControlsTip.invalidate(reason: .actionPerformed)
                        showSupport = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .popoverTip(mapControlsTip)
                    .accessibilityLabel("설정")
                }
            }
            .sheet(isPresented: $showDiary) {
                // DiaryScreen이 NavigationStack을 자체적으로 갖는다 (여기서 또 감싸면 바가 두 개가 된다)
                DiaryScreen()
            }
            .sheet(isPresented: $showSupport, onDismiss: openPendingDestination) {
                // 내가 그린 길과 오늘 그은 길은 지도 위에서 내려 설정의 '모아 보기'에 둔다.
                // 지도에서는 길이보다 걸은 자리 자체가 보여야 한다.
                FootprintDiarySupportView(
                    record: .init(atlasMeters: state.atlasLength, todayMeters: state.todayLength)
                ) { pendingDestination = $0 }
            }
            .sheet(isPresented: $showWhatsNew, onDismiss: openPendingDestination) {
                WhatsNewView { pendingDestination = $0 }
            }
            .sheet(isPresented: $showFilm) {
                FilmScreen()
            }
            .sheet(isPresented: $showCompass) {
                ExplorerCompassScreen()
            }
            .sheet(isPresented: $showPeriodPicker) {
                AtlasPeriodPicker(period: $period)
            }
            .sheet(isPresented: $showTimeline) {
                DayTimelineScreen()
            }
            .sheet(isPresented: $showStampList) {
                // 목록에서 고른 자리로 지도를 데려간다. 목록은 이미 제 손으로 닫힌 뒤다.
                StampListScreen { coordinate in
                    mapProxy.show(coordinate)
                }
            }
            .sheet(item: $pendingCoordinate) { spot in
                StampPicker(isHere: spot.isHere) { kind in
                    modelContext.insert(MapStamp(
                        kind: kind,
                        coordinate: spot.coordinate,
                        isPlanned: !spot.isHere
                    ))
                    try? modelContext.save()
                    FootprintUsage.log(.stampPlaced)
                }
            }
            .sheet(item: $selectedStamp) { stamp in
                StampDetailView(stamp: stamp) {
                    // 고른 표시를 먼저 거둔다. 지워진 것을 붙들고 있으면 시트가 닫히는
                    // 동안 이미 없는 자리를 다시 그리게 된다.
                    selectedStamp = nil
                    modelContext.delete(stamp)
                    try? modelContext.save()
                }
            }
            .alert("현재 위치를 아직 못 찾았어요", isPresented: $showNoLocation) {
                Button("확인", role: .cancel) {}
            } message: {
                Text("잠시 뒤 다시 시도하거나, 지도를 길게 눌러 원하는 자리에 찍어 주세요.")
            }
            // 이 설치가 어디까지 왔는지 익명으로 한 장 갱신한다. 지도가 다 그려진 뒤에
            // 하는 까닭은, 그전에는 '내가 그린 길'이 아직 0이라 보내 봐야 거짓말이 되기
            // 때문이다. 실제 전송은 열두 시간에 한 번뿐이다. (FootprintUsage.swift)
            .task(id: state.isReady) {
                guard state.isReady else { return }
                FootprintUsage.report(
                    atlasMeters: state.atlasLength,
                    walkedDays: state.walkedDays,
                    stamps: visitedStamps.count,
                    places: visits.count,
                    diaries: diaryCount
                )
            }
            .onAppear {
                rebuildAtlas()
                AtlasTips.isMapIdle = isMapIdle
                #if DEBUG
                switch DemoSeed.screen {
                case "compass": showCompass = true
                case "stamps": showStampList = true
                case "diary": showDiary = true
                default: break
                }
                #endif
            }
            .onChange(of: isMapIdle) { AtlasTips.isMapIdle = isMapIdle }
            .onChange(of: period) { showPeriod() }
            // '이번 주'처럼 지금을 기준으로 잡는 기간은 날이 바뀌면 범위도 바뀐다
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in showPeriod() }
            // 이 판에서 새로 생긴 것을 처음 여는 한 번만 띄운다. 지도가 다 그려진 뒤에 띄워야
            // 닫았을 때 빈 종이가 아니라 내 지도가 기다리고 있다.
            .task(id: state.isReady) {
                guard state.isReady, WhatsNew.hasUnseen else { return }
                try? await Task.sleep(for: .seconds(0.6))
                guard !Task.isCancelled, !isPresentingSheet else { return }
                showWhatsNew = true
            }
            .onChange(of: track.count) { rebuildAtlas() }
            // 머무름이 늘면 밟아 본 땅도 넓어진다. 걸음이 끊긴 채 남은 자리에
            // 나중에 스탬프를 찍을 때 '안 가본 곳'으로 잘못 굳지 않게 함께 본다.
            .onChange(of: visits.count) { rebuildAtlas() }
            // 빈 지도가 확인된 순간부터 센다. 그리기가 끝나기 전부터 세면 셈이 다 지난 뒤에
            // 안내가 떠서 곧바로 사라지는 꼴이 된다.
            .task(id: isEmptyMap) {
                guard isEmptyMap else { return }
                showsEmptyHint = true
                try? await Task.sleep(for: .seconds(Self.emptyHintDuration))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.4)) { showsEmptyHint = false }
            }
        }
    }

    /// 지도 위에 무엇이든 한 장이 덮여 있는지
    private var isPresentingSheet: Bool {
        showDiary || showSupport || showFilm || showStampList || showCompass || showTimeline
            || showWhatsNew || showPeriodPicker || pendingCoordinate != nil || selectedStamp != nil
    }

    /// 단추 안내를 띄워도 되는 때. 가운데 안내가 서 있거나 다른 장이 덮여 있으면 미룬다.
    private var isMapIdle: Bool {
        state.isReady && !isEmptyMap && !isPresentingSheet
    }

    /// 설정·새 기능 안내가 닫힌 뒤, 거기서 고른 화면을 연다.
    private func openPendingDestination() {
        guard let destination = pendingDestination else { return }
        pendingDestination = nil
        switch destination {
        case .diary: showDiary = true
        case .stampList: showStampList = true
        case .timeline: showTimeline = true
        case .compass: showCompass = true
        case .film: showFilm = true
        case .period: showPeriodPicker = true
        }
    }

    private func rebuildAtlas() {
        state.rebuild(
            track: track,
            stays: visits.map(\.coordinate),
            newPlacesToday: newPlacesToday,
            calendar: calendar
        )
    }

    private func showPeriod() {
        state.show(period: period.interval(calendar: calendar), calendar: calendar)
    }

    /// 아직 한 걸음도 그려지지 않은 지도인지
    private var isEmptyMap: Bool {
        state.isReady && state.atlasLength == 0
    }

    /// 빈 지도 안내를 띄워 두는 시간(초). 한 번 읽을 만큼만.
    ///
    /// 할 수 있는 일 둘까지 적으면서 읽을 것이 늘었다. 다섯 셈으로는 첫 줄만 읽다가
    /// 사라져, 정작 무엇을 하면 되는지는 못 본 채로 빈 종이만 남는다.
    private static let emptyHintDuration: TimeInterval = 10

    // MARK: - 요약

    /// 지도 위에 뜬 오늘의 요약. 누르면 오늘의 발자취로 들어간다.
    ///
    /// 도구 막대에 단추를 하나 더 다는 대신 이 판을 눌리게 했다. 막대는 가벼울수록 좋고,
    /// 무엇보다 이 판이 이미 '오늘'을 말하고 있다. 오늘 그은 길을 읽고 나서 오늘 어디를 갔었는지 궁금해지는 것이 순서다.
    // MARK: - 도착

    /// "여기, 가보려던 곳이에요" — 미리 찍어 둔 자리에 닿았을 때 한 번 짚어 준다.
    ///
    /// 알림으로 띄우지 않는다. 걷는 중에 끼어드는 물음은 읽지도 않고 지워 버리게 되고,
    /// 무엇보다 이 물음은 지도를 보고 있을 때라야 뜻이 산다 — 흐리던 도장이 눌리면서
    /// 진해지는 것을 그 자리에서 보는 것이 답을 남기는 값의 절반이다.
    private func arrivalCard(_ stamp: MapStamp) -> some View {
        HStack(spacing: 12) {
            StampSymbolBadge(stamp: stamp, side: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(stamp.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("가보려던 곳이에요. 다녀온 곳으로 남길까요?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            VStack(spacing: 6) {
                Button("다녀왔어요") { confirmArrival(stamp) }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(Color(InkStyle.sealRed))
                Button("아직요") { declineArrival(stamp) }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    /// 왼쪽 아래 도구 묶음. 접어 두면 단추 하나, 누르면 위로 넷이 펼쳐진다.
    private var toolStack: some View {
        return VStack(alignment: .leading, spacing: 10) {
            if toolsExpanded {
                Group {
                    neighborhoodButton
                    if showsPeriodButton {
                        periodButton
                    }
                    if showsPeekButton {
                        peekButton
                    }
                    if showsSkinButton {
                        skinButton
                    }
                    // 가운데 안내는 내 위치 점을 덮으므로 스스로 비켜난다. 그러고 나면
                    // 다시 '무엇을 하지'가 되므로, 할 일 하나를 그 일을 하는 단추 옆에
                    // 붙여 둔다 — 여기는 아무것도 가리지 않는 자리다.
                    HStack(spacing: 8) {
                        stampButton
                        if isEmptyMap {
                            Text("눌러서 지금 자리 찍기")
                                .font(.body)
                                .foregroundStyle(Color(InkStyle.ink))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                                .allowsHitTesting(false)
                        }
                    }
                    .animation(.easeOut(duration: 0.3), value: isEmptyMap)
                }
                // 동작 줄이기: 튀어나오는 대신 겹쳐 나타난다
                .transition(reduceMotion ? .opacity : .scale(scale: 0.4, anchor: .bottom).combined(with: .opacity))
            }
            toolsToggle
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.32, dampingFraction: 0.78), value: toolsExpanded)
        .onAppear {
            if isEmptyMap { toolsExpanded = true }
        }
    }

    /// 내 동네 테두리를 켜고 끈다
    private var neighborhoodButton: some View {
        Button {
            showsNeighborhood.toggle()
        } label: {
            Image(systemName: "circle.dashed")
                .font(.title3.weight(showsNeighborhood ? .bold : .regular))
                .foregroundStyle(showsNeighborhood ? Color(InkStyle.sealRed) : .secondary)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel("내 동네 테두리")
        .accessibilityValue(showsNeighborhood ? "켬" : "끔")
    }

    /// 도구 묶음을 펴고 접는 단추. 접힌 채로도 무언가 켜져 있으면(기간·그림지도·비춰보기) 붉은 점으로 알린다.
    private var toolsToggle: some View {
        let somethingOn = !period.isAll || terrainSkin == .picture || isPeeking
        return Button {
            toolsExpanded.toggle()
        } label: {
            Image(systemName: toolsExpanded ? "xmark" : "square.grid.2x2")
                .font(.title3)
                .foregroundStyle(toolsExpanded ? Color.secondary : Color(InkStyle.ink))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(alignment: .topTrailing) {
                    if somethingOn && !toolsExpanded {
                        Circle()
                            .fill(Color(InkStyle.sealRed))
                            .frame(width: 9, height: 9)
                            .offset(x: -3, y: 3)
                    }
                }
        }
        .accessibilityLabel(toolsExpanded ? "지도 도구 접기" : "지도 도구 펼치기")
    }

    /// 배경 지도를 비춰 본다. 누르면 켜지고 다시 누르면 종이로 돌아간다.
    private var peekButton: some View {
        Button {
            isPeeking.toggle()
            peekTip.invalidate(reason: .actionPerformed)
        } label: {
            Image(systemName: isPeeking ? "map.fill" : "map")
                .font(.title3)
                .foregroundStyle(isPeeking ? Color(InkStyle.sealRed) : .secondary)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel("배경 지도 비춰보기")
        .accessibilityValue(isPeeking ? "켬" : "끔")
        .popoverTip(peekTip, arrowEdge: .leading)
    }

    private var terrainSkin: TerrainSkin {
        TerrainSkin(rawValue: terrainSkinRaw) ?? .ink
    }

    /// 먹 지도와 그림지도를 오간다
    private var skinButton: some View {
        Button {
            terrainSkinRaw = (terrainSkin == .picture ? TerrainSkin.ink : .picture).rawValue
        } label: {
            Image(systemName: terrainSkin == .picture ? "mountain.2.fill" : "mountain.2")
                .font(.title3)
                .foregroundStyle(terrainSkin == .picture ? Color(InkStyle.sealRed) : .secondary)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel("그림지도")
        .accessibilityValue(terrainSkin == .picture ? "켬" : "끔")
    }

    /// 기간으로 좁혀 보기
    private var periodButton: some View {
        Button {
            showPeriodPicker = true
        } label: {
            Image(systemName: period.isAll ? "calendar" : "calendar.badge.checkmark")
                .font(.title3)
                .foregroundStyle(period.isAll ? Color.secondary : Color(InkStyle.sealRed))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel("기간으로 보기")
        .accessibilityValue(Text(period.title))
    }

    /// 지금 기간으로 좁혀 보고 있다는 표시. 잊고 지나가면 길이 사라진 줄 안다.
    private var periodChip: some View {
        HStack(spacing: 8) {
            Button {
                showPeriodPicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                    Text(period.title)
                        .fontWeight(.semibold)
                    if let range = period.rangeText(calendar: calendar) {
                        Text(range)
                            .monospacedDigit()
                            .foregroundStyle(Color(InkStyle.ink).opacity(0.7))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .font(.body)
                .foregroundStyle(Color(InkStyle.ink))
            }
            .buttonStyle(.plain)

            Button {
                period = .all
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("전체 기간으로 돌아가기")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    /// 지금 배율. 막대 길이가 곧 그 거리다.
    private var scaleBar: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(mapProxy.scaleText)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(Color(InkStyle.ink).opacity(0.55))
                .frame(width: max(mapProxy.scaleBarWidth, 1), height: 2)
                .overlay(alignment: .leading) { tick }
                .overlay(alignment: .trailing) { tick }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .opacity(mapProxy.scaleBarWidth > 0 ? 1 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("지도 배율. 막대 하나가 \(mapProxy.scaleText)")
    }

    private var tick: some View {
        Rectangle()
            .fill(Color(InkStyle.ink).opacity(0.55))
            .frame(width: 2, height: 7)
    }

    /// 확대·축소
    private var zoomButtons: some View {
        VStack(spacing: 1) {
            zoomButton("plus", label: String(localized: "확대")) { mapProxy.zoomIn() }
            Divider().frame(width: 30)
            zoomButton("minus", label: String(localized: "축소")) { mapProxy.zoomOut() }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func zoomButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .frame(width: 42, height: 40)
        }
        .accessibilityLabel(label)
    }

    /// 지금 선 자리에 찍는다. 걷는 중에는 지도를 정확히 짚기 어려우므로 이쪽이 빠르다.
    private var stampButton: some View {
        Button {
            if let coordinate = locationManager.currentLocation?.coordinate {
                // 지금 선 자리다. 걸음이 아직 안 그려졌더라도 여기 있는 것은 틀림없다.
                pendingCoordinate = StampSpot(coordinate: coordinate, isHere: true)
            } else {
                showNoLocation = true
            }
        } label: {
            Image(systemName: "seal.fill")
                .font(.title3)
                .foregroundStyle(Color(InkStyle.sealRed))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel("지금 자리에 스탬프 찍기")
    }

    /// 아직 아무 길도 그려지지 않은 지도에 띄우는 안내.
    ///
    /// 전에는 '아직 그린 길이 없어요'라고만 적어 두었다. 그것은 지금 없는 것을 말할 뿐,
    /// 무엇을 하면 생기는지는 말하지 않는다. 백지도를 처음 연 사람에게 가장 막막한 것이
    /// 바로 그 대목이라, 할 수 있는 일 둘을 그 일을 하는 물건과 함께 짚어 준다.
    private var emptyHint: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Image(systemName: "figure.walk")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("이제 걸어 보세요")
                    .font(.headline)
                Text("지나온 자리가 한 점씩 이 종이에 찍힙니다.\n차나 지하철로 지난 길은 그려지지 않아요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                hintRow(
                    symbol: "seal.fill",
                    text: String(localized: "왼쪽 아래 **도장**을 누르면 지금 선 자리가 남아요")
                )
                hintRow(
                    symbol: "hand.point.up.left",
                    text: String(localized: "지도를 **길게 누르면** 가볼 곳을 미리 찍어 둘 수 있어요")
                )
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 32)
        .frame(maxHeight: .infinity)
        // 다 읽었으면 바로 걷어 낼 수 있게 둔다. 이 판이 서는 자리가 곧 내 위치 점이
        // 서는 자리라, 읽고 난 뒤에는 안내가 아니라 가림막이 된다.
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.25)) { showsEmptyHint = false }
        }
        // VoiceOver: 안내를 한 번에 읽고, 동작으로 걷어 낸다
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text("닫기")) { showsEmptyHint = false }
    }

    private func hintRow(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(Color(InkStyle.sealRed))
                .frame(width: 18)
            Text(.init(text))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
