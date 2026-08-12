//
//  CollectionScreen.swift
//  FootprintDiary
//
//  도감 — 지금까지 모은 것을 한 화면에 진열한다.
//  아직 밟지 못한 시·도가 회색 칸으로 남아 있어서 '채우고 싶은' 자리가 보인다.
//

import SwiftUI
import SwiftData
import CoreLocation

// MARK: - 집계 결과

/// 시·도 하나의 수집 현황
struct ProvinceProgress: Identifiable {
    let key: String
    let isKorean: Bool
    /// 밟은 시·군·구 이름들 (정렬됨)
    let districts: [String]
    let visitCount: Int
    /// 시·군·구 총 개수 (0이면 분모를 표시하지 않는다)
    let districtTotal: Int

    var id: String { key }
    var isVisited: Bool { visitCount > 0 }

    /// 진행도 0~1 (분모를 모르면 nil)
    var ratio: Double? {
        guard districtTotal > 0 else { return nil }
        return min(Double(districts.count) / Double(districtTotal), 1)
    }

    /// "11 / 25" 표시. 수집 수가 분모를 넘으면(행정구역 개편 등) 분모를 숨긴다.
    var progressText: String {
        guard districtTotal > 0, districts.count <= districtTotal else {
            return "\(districts.count)곳"
        }
        return "\(districts.count) / \(districtTotal)"
    }
}

/// 도감 화면이 쓰는 집계 묶음. 발자국을 한 번만 훑어서 만든다.
struct CollectionStats {
    let totalVisits: Int
    let discoveries: [Visit]
    let places: [FootprintPlace]
    let koreanProvinces: [ProvinceProgress]
    let overseas: [ProvinceProgress]
    let clearedAreaKm2: Double
    /// 걸어서 지나온 총 거리(m)
    let walkedDistance: CLLocationDistance

    var discoveredCount: Int { places.filter(\.isDiscovered).count }
    var favorites: [FootprintPlace] {
        places.filter(\.isFavorite).sorted { $0.visitCount > $1.visitCount }
    }
    var visitedProvinceCount: Int { koreanProvinces.filter(\.isVisited).count }
    var districtCount: Int { koreanProvinces.reduce(0) { $0 + $1.districts.count } }

    static func make(from visits: [Visit], track: [TrackPoint]) -> CollectionStats {
        let walkedCoordinates = track.map(\.coordinate)
        let walkedDistance = WalkTrail.distance(
            of: track.map { WalkTrail.Point(coordinate: $0.coordinate, timestamp: $0.timestamp) }
        )
        var districtsByProvince: [String: Set<String>] = [:]
        var countByProvince: [String: Int] = [:]

        for visit in visits {
            guard let key = visit.provinceKey, !key.isEmpty else { continue }
            countByProvince[key, default: 0] += 1
            if let district = visit.districtName, !district.isEmpty {
                districtsByProvince[key, default: []].insert(district)
            }
        }

        let korean = RegionCatalog.provinces.map { province in
            ProvinceProgress(
                key: province.key,
                isKorean: true,
                districts: (districtsByProvince[province.key] ?? []).sorted(),
                visitCount: countByProvince[province.key] ?? 0,
                districtTotal: province.districtTotal
            )
        }

        let overseas = countByProvince.keys
            .filter { !RegionCatalog.isKoreanProvinceKey($0) }
            .sorted()
            .map { key in
                ProvinceProgress(
                    key: key,
                    isKorean: false,
                    districts: (districtsByProvince[key] ?? []).sorted(),
                    visitCount: countByProvince[key] ?? 0,
                    districtTotal: 0
                )
            }

        return CollectionStats(
            totalVisits: visits.count,
            discoveries: visits.filter(\.isFirstVisit).sorted { $0.discoveryIndex > $1.discoveryIndex },
            places: FootprintAggregator.places(from: visits),
            koreanProvinces: korean,
            overseas: overseas,
            clearedAreaKm2: FogGrid.clearedAreaSquareKilometers(
                FogGrid.clearedCells(walked: walkedCoordinates, stayed: visits.map(\.coordinate))
            ),
            walkedDistance: walkedDistance
        )
    }
}

// MARK: - 화면

struct CollectionScreen: View {
    @EnvironmentObject private var locationManager: LocationManager
    @Query(sort: \Visit.arrivalDate) private var allVisits: [Visit]
    @Query(sort: \TrackPoint.timestamp) private var track: [TrackPoint]
    @Query(sort: \PhotoSpot.collectedAt, order: .reverse) private var spots: [PhotoSpot]

    @State private var selectedProvince: ProvinceProgress?
    @State private var selectedSpot: PhotoSpot?

    private var collectedSpots: [PhotoSpot] { spots.filter(\.isCollected) }

    var body: some View {
        let stats = CollectionStats.make(from: allVisits, track: track)

        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    summaryGrid(stats)
                    provinceSection(stats)
                    if !stats.overseas.isEmpty {
                        overseasSection(stats)
                    }
                    spotSection
                    discoverySection(stats)
                    favoriteSection(stats)
                }
                .padding()
            }
            .navigationTitle("탐험 기록")
            .background(Color(.systemGroupedBackground))
            .sheet(item: $selectedProvince) { province in
                ProvinceDetailSheet(province: province)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $selectedSpot) { spot in
                SpotDetailSheet(spot: spot)
                    .presentationDetents([.medium])
            }
            .onAppear {
                // 예전 기록에도 발견 번호와 행정구역을 채워 넣는다
                locationManager.backfillDiscoveriesIfNeeded()
                locationManager.backfillRegions()
            }
        }
    }

    // MARK: 요약

    private func summaryGrid(_ stats: CollectionStats) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            statCard(value: "\(stats.discoveredCount)", label: "발견한 곳", symbol: "sparkles", tint: .orange)
            statCard(value: "\(stats.districtCount)", label: "밟은 시·군·구", symbol: "map.fill", tint: .blue)
            statCard(value: areaText(stats.clearedAreaKm2), label: "밝힌 땅", symbol: "cloud.fog.fill", tint: .purple)
            statCard(value: distanceText(stats.walkedDistance), label: "걸은 거리", symbol: "figure.walk", tint: .pink)
        }
    }

    private func statCard(value: String, label: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.bold())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func distanceText(_ meters: CLLocationDistance) -> String {
        meters < 1_000 ? "\(Int(meters))m" : String(format: "%.1fkm", meters / 1_000)
    }

    private func areaText(_ area: Double) -> String {
        area < 1 ? String(format: "%.2f㎢", area) : String(format: "%.0f㎢", area)
    }

    // MARK: 시·도 도감

    private func provinceSection(_ stats: CollectionStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("전국 도감", detail: "\(stats.visitedProvinceCount)곳 수집")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(stats.koreanProvinces) { province in
                    Button {
                        selectedProvince = province
                    } label: {
                        provinceTile(province)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func provinceTile(_ province: ProvinceProgress) -> some View {
        VStack(spacing: 4) {
            Text(province.key)
                .font(.headline)
                .foregroundStyle(province.isVisited ? .primary : .secondary)
            if province.isVisited {
                Text(province.progressText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let ratio = province.ratio {
                    ProgressView(value: ratio)
                        .tint(.accentColor)
                        .scaleEffect(y: 0.6)
                }
            } else {
                Text("미발견")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(province.isVisited
                      ? Color.accentColor.opacity(0.14)
                      : Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    province.isVisited ? Color.accentColor.opacity(0.4) : Color.clear,
                    style: StrokeStyle(lineWidth: 1)
                )
        )
        .opacity(province.isVisited ? 1 : 0.55)
    }

    // MARK: 해외

    private func overseasSection(_ stats: CollectionStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("해외", detail: "\(stats.overseas.count)개국")
            FlowChips(items: stats.overseas.map { "\($0.key) \($0.visitCount)" })
        }
    }

    // MARK: 사진 스팟

    private var spotSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("사진 스팟", detail: "\(collectedSpots.count)곳 수집")
            if collectedSpots.isEmpty {
                emptyRow("지도에 뜬 스팟에 찾아가 사진을 찍으면 여기에 모여요.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(collectedSpots, id: \.persistentModelID) { spot in
                            Button {
                                selectedSpot = spot
                            } label: {
                                spotCard(spot)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func spotCard(_ spot: PhotoSpot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let data = spot.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 132, height: 100)
                    .clipped()
            } else {
                Image(systemName: spot.symbolName)
                    .font(.title)
                    .foregroundStyle(.orange)
                    .frame(width: 132, height: 100)
            }
            Text(spot.name)
                .font(.caption)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .frame(width: 132)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: 최근 발견

    private func discoverySection(_ stats: CollectionStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("최근 발견", detail: "\(stats.discoveries.count)곳")
            if stats.discoveries.isEmpty {
                emptyRow("아직 발견한 곳이 없어요. 가보지 않은 길로 한 번 걸어보세요.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(stats.discoveries.prefix(8)), id: \.persistentModelID) { visit in
                        HStack(spacing: 12) {
                            Text("#\(visit.discoveryIndex)")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                                .frame(width: 44, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(visit.displayName)
                                    .lineLimit(1)
                                Text(dateText(visit.arrivalDate))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "sparkles")
                                .foregroundStyle(.yellow)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        if visit.persistentModelID != stats.discoveries.prefix(8).last?.persistentModelID {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: 단골

    private func favoriteSection(_ stats: CollectionStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("단골", detail: "5번 이상 간 자리")
            if stats.favorites.isEmpty {
                emptyRow("같은 자리를 5번 밟으면 단골이 돼요.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(stats.favorites.prefix(5))) { place in
                        HStack(spacing: 12) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                            Text(place.name ?? "이름 없는 자리")
                                .lineLimit(1)
                            Spacer()
                            Text("\(place.visitCount)번")
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        if place.id != stats.favorites.prefix(5).last?.id {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: 공통

    private func sectionHeader(_ title: String, detail: String) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일"
        return formatter.string(from: date)
    }
}

// MARK: - 시·도 상세

struct ProvinceDetailSheet: View {
    let province: ProvinceProgress

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(province.progressText)
                                .font(.largeTitle.bold())
                            Text(province.districtTotal > 0 ? "시·군·구 수집" : "밟은 지역")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(province.visitCount)")
                                .font(.title2.bold())
                            Text("발자국").font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    if let ratio = province.ratio {
                        ProgressView(value: ratio)
                    }

                    if province.districts.isEmpty {
                        Text(province.isVisited
                             ? "이 지역의 발자국은 있지만 아직 세부 지역을 확인하지 못했어요."
                             : "아직 이 지역에는 발자국이 없어요.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        FlowChips(items: province.districts)
                    }
                }
                .padding()
            }
            .navigationTitle(province.key)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 칩 목록

/// 폭에 맞춰 자동으로 줄바꿈되는 칩 나열
struct FlowChips: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            }
        }
    }
}

/// 한 줄에 담을 수 있는 만큼 넣고 넘치면 다음 줄로 내리는 단순 레이아웃
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                maxRowWidth = max(maxRowWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        maxRowWidth = max(maxRowWidth, rowWidth)
        return CGSize(width: maxRowWidth, height: totalHeight + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
