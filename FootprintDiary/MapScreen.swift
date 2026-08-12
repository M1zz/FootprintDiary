//
//  MapScreen.swift
//  FootprintDiary
//
//  [보관] 안개 지도 화면과 장소 마커·상세, 발자국 자취 그리기.
//
//  앱이 '탐험 일지' 한 화면으로 정리되면서 쓰이지 않는다.
//  지우지 않고 통째로 주석 처리해 둔다 — 되살리려면 아래 주석을 벗기고
//  ContentView에서 다시 연결하면 된다. (동작하던 마지막 상태: 커밋 a0de097)
//

/*
//
//  MapScreen.swift
//  FootprintDiary
//
//  앱의 첫 화면. 안개로 덮인 지도 한 장에 지금까지의 발자국과
//  아직 가보지 않은 스팟이 함께 올라간다.
//

import SwiftUI
import SwiftData
import MapKit

struct MapScreen: View {
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @Query(sort: \Visit.arrivalDate) private var allVisits: [Visit]
    @Query(sort: \TrackPoint.timestamp) private var track: [TrackPoint]
    @Query(sort: \PhotoSpot.createdAt, order: .reverse) private var spots: [PhotoSpot]

    @State private var selectedPlace: FootprintPlace?
    @State private var selectedSpot: PhotoSpot?
    @State private var showTimelapse = false
    @State private var showDayTimelapse = false
    @StateObject private var replenisher = SpotReplenisher()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !locationManager.isTrackingEnabled {
                    trackingOffBanner
                }

                FogScreen(
                    visits: allVisits,
                    track: track,
                    spots: spots,
                    focus: MapFocus.initialFocus(
                        near: locationManager.currentLocation,
                        fitting: allVisits.map(\.coordinate)
                    ),
                    onSelectPlace: { selectedPlace = $0 },
                    onSelectSpot: { selectedSpot = $0 }
                )
            }
            .navigationTitle("탐험")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        showTimelapse = true
                    } label: {
                        Label("타임랩스", systemImage: "film")
                    }
                    Button {
                        showDayTimelapse = true
                    } label: {
                        Label("오늘 재생", systemImage: "play.circle")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        locationManager.isTrackingEnabled.toggle()
                    } label: {
                        Label(
                            locationManager.isTrackingEnabled ? "걷기 기록 켜짐" : "걷기 기록 꺼짐",
                            systemImage: locationManager.isTrackingEnabled ? "location.fill" : "location.slash.fill"
                        )
                    }
                    .tint(locationManager.isTrackingEnabled ? .accentColor : .secondary)

                    Button {
                        locationManager.recordCurrentLocation()
                    } label: {
                        if locationManager.isRecordingManually {
                            ProgressView()
                        } else {
                            Label("지금 자리 남기기", systemImage: "shoeprints.fill")
                        }
                    }
                }
            }
            .sheet(item: $selectedPlace) { place in
                PlaceDetailSheet(place: place)
                    .presentationDetents([.medium])
            }
            .sheet(item: $selectedSpot) { spot in
                SpotDetailSheet(spot: spot)
                    .presentationDetents([.medium])
            }
            .fullScreenCover(isPresented: $showTimelapse) {
                TimelapseView()
            }
            .fullScreenCover(isPresented: $showDayTimelapse) {
                DayTimelapseView(date: .now)
            }
            .onAppear {
                locationManager.refreshCurrentLocation()
                replenisher.replenishIfNeeded(near: locationManager.currentLocation, context: modelContext)
            }
            .onChange(of: locationManager.lastKnownLocation) {
                replenisher.replenishIfNeeded(near: locationManager.currentLocation, context: modelContext)
            }
            .alert(
                "현재 위치 기록",
                isPresented: Binding(
                    get: { locationManager.manualRecordError != nil },
                    set: { if !$0 { locationManager.manualRecordError = nil } }
                ),
                presenting: locationManager.manualRecordError
            ) { error in
                if error == .permissionDenied {
                    Button("설정 열기") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
                Button("확인", role: .cancel) {}
            } message: { error in
                Text(error.message)
            }
        }
    }

    private var trackingOffBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.slash.fill")
                .foregroundStyle(.secondary)
            Text("걷기 기록이 꺼져 있어요. 걸어도 길이 남지 않아요.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("켜기") {
                locationManager.isTrackingEnabled = true
            }
            .font(.caption.bold())
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.12))
    }
}

// MARK: - 첫 화면 범위

/// 지도를 처음 열 때 잡을 화면. 내 위치로 맞춘 것인지 함께 들고 다녀서
/// '기록 전체로 맞춰 둔 화면'을 나중에 내 위치로 한 번 더 당길 수 있게 한다.
struct MapInitialFocus: Equatable {
    let latitude: Double
    let longitude: Double
    let latitudeDelta: Double
    let longitudeDelta: Double
    let isUserCentered: Bool

    init(region: MKCoordinateRegion, isUserCentered: Bool) {
        self.latitude = region.center.latitude
        self.longitude = region.center.longitude
        self.latitudeDelta = region.span.latitudeDelta
        self.longitudeDelta = region.span.longitudeDelta
        self.isUserCentered = isUserCentered
    }

    var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }
}

enum MapFocus {
    /// 내 위치를 중심으로 잡을 때의 범위 (약 2.5km — 걸어 다니는 거리)
    static let nearbySpan = MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)

    /// 내 위치 주변을 가깝게 보여준다
    static func region(around location: CLLocation) -> MKCoordinateRegion {
        MKCoordinateRegion(center: location.coordinate, span: nearbySpan)
    }

    /// 좌표들이 모두 들어오도록 맞춘다
    static func region(fitting coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
                span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
            )
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.4, 0.02),
                longitudeDelta: max((maxLon - minLon) * 1.4, 0.02)
            )
        )
    }

    /// 지도의 첫 화면.
    /// 기록 전체를 담으면 나라 단위까지 멀어지므로, 내 위치를 알면 그 주변부터 보여준다.
    static func initialFocus(
        near location: CLLocation?,
        fitting coordinates: [CLLocationCoordinate2D]
    ) -> MapInitialFocus {
        if let location {
            return MapInitialFocus(region: region(around: location), isUserCentered: true)
        }
        return MapInitialFocus(region: region(fitting: coordinates), isUserCentered: false)
    }
}

// MARK: - 장소 마커와 상세

/// 지도 위 장소 하나. 방문 횟수에 따라 커지고, 첫 발견은 금색 테두리가 붙는다.
struct PlaceMarker: View {
    let place: FootprintPlace

    private var size: CGFloat {
        switch place.rank {
        case 0: return 16
        case 1: return 22
        case 2: return 28
        default: return 34
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.4 + Double(place.rank) * 0.18))
                .frame(width: size, height: size)
            Circle()
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                .frame(width: size, height: size)
            if place.isDiscovered {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color(red: 1, green: 0.84, blue: 0.3), Color(red: 0.85, green: 0.6, blue: 0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 2.5
                    )
                    .frame(width: size + 7, height: size + 7)
            }
            if place.isFavorite {
                Text("\(place.visitCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}

/// 지도에서 장소를 눌렀을 때. 이름을 고치거나 지울 수 있다.
struct PlaceDetailSheet: View {
    let place: FootprintPlace

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if place.isDiscovered {
                    Text("\(place.discoveryIndex)번째 발견")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                }

                HStack(spacing: 24) {
                    stat(value: "\(place.visitCount)", label: "방문")
                    stat(value: dateText(place.firstDate), label: "처음")
                    stat(value: dateText(place.lastDate), label: "마지막")
                }

                TextField("이 자리의 이름 (예: 회사, 단골 카페)", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit { rename() }

                if place.isFavorite {
                    Label("단골로 등록된 자리예요", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }

                Spacer()

                Button("이 자리의 발자국 지우기", role: .destructive) {
                    showDeleteConfirm = true
                }
                .font(.callout)
            }
            .padding()
            .navigationTitle(place.name ?? "이름 없는 자리")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { rename() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { name = place.name ?? "" }
            .confirmationDialog(
                "이 자리의 발자국 \(place.visitCount)개를 지울까요?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("지우기", role: .destructive) { deletePlace() }
                Button("취소", role: .cancel) {}
            } message: {
                Text("되돌릴 수 없어요.")
            }
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yy.M.d"
        return formatter.string(from: date)
    }

    /// 이 자리를 이루는 발자국 전부의 이름을 함께 바꾼다
    private func rename() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        for visit in visits() {
            visit.placeName = trimmed
            visit.isNamed = true
        }
        try? modelContext.save()
        dismiss()
    }

    private func deletePlace() {
        for visit in visits() {
            modelContext.delete(visit)
        }
        try? modelContext.save()
        dismiss()
    }

    private func visits() -> [Visit] {
        place.visitIDs.compactMap { modelContext.model(for: $0) as? Visit }
    }
}

// MARK: - 발자국 자취 (타임랩스와 발견 카드가 함께 쓴다)

/// 방문 지점 사이를 따라 일정 간격으로 찍히는 작은 발자국 자취
enum FootprintTrail {
    struct Step: Identifiable {
        let id: Int
        let coordinate: CLLocationCoordinate2D
        let heading: Double
    }

    /// 좌표 목록을 따라 spacing(미터) 간격으로 발자국 위치를 만든다.
    /// 긴 구간은 maxPerSegment개로 제한해 어노테이션 수가 폭증하지 않게 한다.
    static func steps(
        along coordinates: [CLLocationCoordinate2D],
        spacing: CLLocationDistance = 40,
        maxPerSegment: Int = 12
    ) -> [Step] {
        guard coordinates.count >= 2 else { return [] }
        var steps: [Step] = []
        for (from, to) in zip(coordinates, coordinates.dropFirst()) {
            let distance = CLLocation(latitude: from.latitude, longitude: from.longitude)
                .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
            guard distance > 15 else { continue }
            let count = min(max(Int(distance / spacing), 1), maxPerSegment)
            let heading = from.bearing(to: to)
            for i in 1...count {
                let fraction = Double(i) / Double(count + 1)
                steps.append(Step(
                    id: steps.count,
                    coordinate: CLLocationCoordinate2D(
                        latitude: from.latitude + (to.latitude - from.latitude) * fraction,
                        longitude: from.longitude + (to.longitude - from.longitude) * fraction
                    ),
                    heading: heading
                ))
            }
        }
        return steps
    }

    /// index번째 지점의 진행 방향(도). 다음 지점을 향하고, 마지막은 직전 방향을 유지한다.
    static func heading(through coordinates: [CLLocationCoordinate2D], at index: Int) -> Double {
        if index + 1 < coordinates.count {
            return coordinates[index].bearing(to: coordinates[index + 1])
        }
        if index > 0 {
            return coordinates[index - 1].bearing(to: coordinates[index])
        }
        return 0
    }

    /// 자취 발자국 하나의 모양
    static func mark(heading: Double, opacity: Double = 1) -> some View {
        Text("👣")
            .font(.system(size: 11))
            .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
            .rotationEffect(.degrees(heading))
            .opacity(0.55 * opacity)
    }
}

/// 발자국 마커. 진행 방향으로 발자국을 회전시키고, 번호 배지는 항상 똑바로 보여준다.
/// 처음 밟은 자리는 금빛 후광으로 구분한다.
struct FootprintMarker: View {
    let number: Int
    var heading: Double = 0
    var isDiscovery: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if isDiscovery {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.yellow.opacity(0.75), Color.yellow.opacity(0)],
                            center: .center,
                            startRadius: 2,
                            endRadius: 22
                        )
                    )
                    .frame(width: 44, height: 44)
            }
            Text("👣")
                .font(.title2)
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                .rotationEffect(.degrees(heading))
            Text("\(number)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(isDiscovery ? Color.orange : Color.accentColor))
                .offset(x: 8, y: -8)
        }
    }
}
*/
