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
    /// 지난 날들에 그린 길
    @Published private(set) var past: [[CLLocationCoordinate2D]] = []
    /// 오늘 그린 길
    @Published private(set) var today: [[CLLocationCoordinate2D]] = []
    /// 내가 그린 지도의 총 길이(m) — 날짜별 '처음 걷는 거리'의 합
    @Published private(set) var atlasLength: CLLocationDistance = 0
    /// 오늘 새로 그은 길이(m)
    @Published private(set) var todayLength: CLLocationDistance = 0
    @Published private(set) var isReady = false

    private var signature: Int?

    func rebuild(track: [TrackPoint], calendar: Calendar) {
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

            var past: [[CLLocationCoordinate2D]] = []
            var today: [[CLLocationCoordinate2D]] = []
            for walk in walks {
                // 모서리 깎기는 그리는 선에만 쓴다.
                // 각을 자르면 길이가 조금 줄어들어 '내가 그린 길'이 실제보다 짧아진다.
                let segments = walk.segments.map { TrackSmoothing.rounded($0.map(\.coordinate)) }
                if walk.day == startOfToday {
                    today += segments
                } else {
                    past += segments
                }
            }

            let total = novelty.values.reduce(0, +)
            let todayNew = novelty[startOfToday] ?? 0

            await MainActor.run {
                self.past = past
                self.today = today
                self.atlasLength = total
                self.todayLength = todayNew
                self.isReady = true
            }
        }
    }
}

struct AtlasScreen: View {
    @Query(sort: \TrackPoint.timestamp) private var track: [TrackPoint]
    @Query(sort: \MapStamp.createdAt) private var stamps: [MapStamp]

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var locationManager: LocationManager

    @StateObject private var state = AtlasState()
    @State private var showDiary = false
    @State private var showSupport = false
    /// 스탬프를 찍을 자리. 정해지면 고르는 화면이 열린다.
    @State private var pendingCoordinate: StampSpot?
    @State private var selectedStamp: MapStamp?
    @State private var showNoLocation = false

    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                AtlasMapView(
                    past: state.past,
                    today: state.today,
                    stamps: stamps,
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

                if state.isReady && state.atlasLength == 0 {
                    emptyHint
                }

                stampButton
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 16)
                    // 애플 지도 저작권 표기를 가리지 않도록 띄운다 (가리면 심사에서 걸린다)
                    .padding(.bottom, 52)
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
            .sheet(item: $pendingCoordinate) { spot in
                StampPicker { kind in
                    modelContext.insert(MapStamp(kind: kind, coordinate: spot.coordinate))
                    try? modelContext.save()
                }
            }
            .sheet(item: $selectedStamp) { stamp in
                StampDetailView(stamp: stamp) {
                    modelContext.delete(stamp)
                    try? modelContext.save()
                }
            }
            .alert("현재 위치를 아직 못 찾았어요", isPresented: $showNoLocation) {
                Button("확인", role: .cancel) {}
            } message: {
                Text("잠시 뒤 다시 시도하거나, 지도를 길게 눌러 원하는 자리에 찍어 주세요.")
            }
            .onAppear { state.rebuild(track: track, calendar: calendar) }
            .onChange(of: track.count) { state.rebuild(track: track, calendar: calendar) }
        }
    }

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
                    .foregroundStyle(state.todayLength >= 1 ? Color(InkStyle.vermilion) : .secondary)
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
