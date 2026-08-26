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

/// 지도가 그릴 것들을 한 번만 계산해 들고 있는 상자.
/// 점이 쌓일수록 계산이 무거워지므로 본문에서 매번 하지 않고 백그라운드에서 만든다.
/// 스탬프를 찍을 자리 하나. 좌표는 Identifiable이 아니라서 시트에 바로 못 넘긴다.
struct StampSpot: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
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
    @Published private(set) var isReady = false

    private var signature: Int?

    /// - Parameter newPlacesToday: 오늘 처음 밟은 자리 수. 위젯에만 쓰인다.
    ///   저장소를 여기서 다시 뒤지지 않고 화면이 이미 들고 있는 것을 받는다.
    func rebuild(track: [TrackPoint], newPlacesToday: Int, calendar: Calendar) {
        guard signature != track.count else { return }
        signature = track.count

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

        Task.detached(priority: .userInitiated) {
            // 저장된 점은 그대로 두고, 그릴 값만 다듬는다.
            // 여러 번 지난 길을 겹쳐 붙이는 것도 해 봤으나 나란한 골목이 하나로
            // 뭉개져 접었다. 까닭은 TrackConsolidation.swift 머리말에 적어 두었다.
            let points = TrackSmoothing.smoothed(raw).map {
                WalkTrail.Point(coordinate: $0.coordinate, timestamp: $0.timestamp)
            }
            let walks = DayWalk.build(from: points, calendar: calendar)
            let novelty = WalkNovelty.newDistances(for: walks)

            let segments = walks.flatMap(\.segments)
            let cells = WalkHeatmap.cells(passes: segments, calendar: calendar)
            // 길게 눌러 붙일 때만 쓰는 선. 모서리를 깎아 두면 손가락이 길에 더 잘 붙는다.
            let trails = segments.map { TrackSmoothing.rounded($0.map(\.coordinate)) }

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
                self.cells = cells
                self.trails = trails
                self.atlasLength = total
                self.todayLength = todayNew
                self.walkedDays = walks.count
                self.isReady = true
            }
        }
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
    @State private var showDiary = false
    @State private var showSupport = false
    @State private var showFilm = false
    @State private var showStampList = false
    /// 스탬프를 찍을 자리. 정해지면 고르는 화면이 열린다.
    @State private var pendingCoordinate: StampSpot?
    @State private var selectedStamp: MapStamp?
    @State private var showNoLocation = false
    /// 배경 지도를 비추는 중인지. 누르고 있는 동안에만 참이 된다.
    ///
    /// 켜 두는 설정으로 두지 않는 까닭이 있다. 한 번 켜 두면 그게 기본이 되어 버리고,
    /// 그러면 이 앱은 그냥 '지도 위에 선 긋는 앱'이 된다. 손가락을 하나 붙들고 있어야
    /// 보이게 해 두면 비춰보기는 잠깐 확인하는 일로 남는다.
    @State private var isPeeking = false
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

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                AtlasMapView(
                    cells: state.cells,
                    trails: state.trails,
                    showsBasemap: isPeeking,
                    stamps: stamps,
                    proxy: mapProxy,
                    onSelectStamp: { selectedStamp = $0 },
                    onPickCoordinate: { pendingCoordinate = StampSpot(coordinate: $0) },
                    onMoveStamp: { stamp, coordinate in
                        stamp.latitude = coordinate.latitude
                        stamp.longitude = coordinate.longitude
                        try? modelContext.save()
                    }
                )
                .ignoresSafeArea(edges: .bottom)

                summary
                    .padding(.horizontal)
                    .padding(.top, 8)

                if isEmptyMap && showsEmptyHint {
                    emptyHint
                        .transition(.opacity)
                }

                VStack(alignment: .leading, spacing: 10) {
                    scaleBar
                    peekButton
                    stampButton
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 16)
                // 애플 지도 저작권 표기를 가리지 않도록 띄운다 (가리면 심사에서 걸린다)
                .padding(.bottom, 52)

                zoomButtons
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 12)
            }
            .navigationTitle("내 지도")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showDiary = true
                    } label: {
                        Image(systemName: "book.closed")
                    }
                    .accessibilityLabel("일지")
                }
                ToolbarItem(placement: .topBarLeading) {
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFilm = true
                    } label: {
                        Image(systemName: "play.rectangle")
                    }
                    .accessibilityLabel("그려지는 것 보기")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSupport = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("설정")
                }
            }
            .sheet(isPresented: $showDiary) {
                // DiaryScreen이 NavigationStack을 자체적으로 갖는다 (여기서 또 감싸면 바가 두 개가 된다)
                DiaryScreen()
            }
            .sheet(isPresented: $showSupport) {
                FootprintDiarySupportView()
            }
            .sheet(isPresented: $showFilm) {
                FilmScreen()
            }
            .sheet(isPresented: $showStampList) {
                // 목록에서 고른 자리로 지도를 데려간다. 목록은 이미 제 손으로 닫힌 뒤다.
                StampListScreen { coordinate in
                    mapProxy.show(coordinate)
                }
            }
            .sheet(item: $pendingCoordinate) { spot in
                StampPicker { kind in
                    modelContext.insert(MapStamp(kind: kind, coordinate: spot.coordinate))
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
                    stamps: stamps.count,
                    places: visits.count,
                    diaries: diaryCount
                )
            }
            .onAppear { state.rebuild(track: track, newPlacesToday: newPlacesToday, calendar: calendar) }
            .onChange(of: track.count) { state.rebuild(track: track, newPlacesToday: newPlacesToday, calendar: calendar) }
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

    /// 아직 한 걸음도 그려지지 않은 지도인지
    private var isEmptyMap: Bool {
        state.isReady && state.atlasLength == 0
    }

    /// 빈 지도 안내를 띄워 두는 시간(초). 한 번 읽을 만큼만.
    private static let emptyHintDuration: TimeInterval = 5

    // MARK: - 요약

    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(distanceText(state.atlasLength))
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .contentTransition(.numericText())
                Text("내가 그린 길")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(state.todayLength >= 1 ? "+\(distanceText(state.todayLength))" : "—")
                    .font(.headline)
                    .foregroundStyle(state.todayLength >= 1 ? Color(DotPalette.today) : .secondary)
                    .contentTransition(.numericText())
                Text("오늘 그은 길")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("내가 그린 길 \(distanceText(state.atlasLength)), 오늘 그은 길 \(distanceText(state.todayLength))")
    }

    /// 배경 지도를 잠깐 비춰 본다. 누르고 있는 동안에만 비친다.
    private var peekButton: some View {
        Image(systemName: isPeeking ? "map.fill" : "map")
            .font(.title3)
            .foregroundStyle(isPeeking ? Color(InkStyle.sealRed) : .secondary)
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: Circle())
            // 눌렀다 떼는 것을 바로 알아야 해서 단추가 아니라 몸짓으로 받는다
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !isPeeking { isPeeking = true } }
                    .onEnded { _ in isPeeking = false }
            )
            .accessibilityLabel("누르고 있는 동안 지도 비춰보기")
            .accessibilityHint("손을 떼면 다시 종이로 돌아갑니다")
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
            zoomButton("plus", label: "확대") { mapProxy.zoomIn() }
            Divider().frame(width: 30)
            zoomButton("minus", label: "축소") { mapProxy.zoomOut() }
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
                pendingCoordinate = StampSpot(coordinate: coordinate)
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

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.walk")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("아직 그린 길이 없어요")
                .font(.headline)
            Text("걸으면 지나온 길이 이 지도에 그려집니다.\n차나 지하철로 지난 길은 그려지지 않아요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 40)
        .frame(maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func distanceText(_ meters: CLLocationDistance) -> String {
        meters < 1_000 ? "\(Int(meters))m" : String(format: "%.1fkm", meters / 1_000)
    }
}
