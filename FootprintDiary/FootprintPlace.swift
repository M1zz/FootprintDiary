//
//  FootprintPlace.swift
//  FootprintDiary
//
//  발자국을 '장소' 단위로 묶는 집계 로직.
//  누적 지도·도감·안개 지도가 모두 이 결과를 쓴다.
//
//  좌표 비교를 전부 대 전부로 하면 기록이 늘수록 느려지므로,
//  위경도를 고정 간격 격자로 나눈 공간 해시로 후보를 먼저 좁힌다.
//

import Foundation
import CoreLocation
import SwiftData

// MARK: - 공간 격자

/// 위경도를 고정 각도 간격으로 나눈 격자 칸.
/// 경도 간격을 위도에 따라 바꾸지 않기 때문에 칸끼리 겹치지 않는다.
struct GridCell: Hashable {
    let row: Int
    let col: Int
}

enum SpatialGrid {
    /// 미터 → 위경도 각도 (경도는 고위도에서 실제 폭이 좁아진다)
    static func step(meters: CLLocationDistance) -> Double {
        meters / 111_320
    }

    static func cell(latitude: Double, longitude: Double, step: Double) -> GridCell {
        GridCell(
            row: Int(floor(latitude / step)),
            col: Int(floor(longitude / step))
        )
    }

    /// 칸의 남서쪽 모서리 좌표
    static func origin(of cell: GridCell, step: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: Double(cell.row) * step,
            longitude: Double(cell.col) * step
        )
    }

    /// 반경 meters를 덮으려면 좌우로 몇 칸까지 봐야 하는지.
    /// 경도 칸은 고위도로 갈수록 실제 폭이 좁아져 더 많은 칸을 봐야 한다.
    static func columnRadius(atLatitude latitude: Double, step: Double, meters: CLLocationDistance) -> Int {
        let widthAtLatitude = 111_320 * max(cos(latitude * .pi / 180), 0.01) * step
        return max(1, Int(ceil(meters / widthAtLatitude)))
    }

    /// 주어진 좌표 주변에서 검사해야 할 칸들
    static func neighbors(
        latitude: Double,
        longitude: Double,
        step: Double,
        meters: CLLocationDistance
    ) -> [GridCell] {
        let center = cell(latitude: latitude, longitude: longitude, step: step)
        let rowRadius = max(1, Int(ceil(meters / (111_320 * step))))
        let colRadius = columnRadius(atLatitude: latitude, step: step, meters: meters)
        var cells: [GridCell] = []
        for dRow in -rowRadius...rowRadius {
            for dCol in -colRadius...colRadius {
                cells.append(GridCell(row: center.row + dRow, col: center.col + dCol))
            }
        }
        return cells
    }
}

// MARK: - 장소 집계

/// 가까운 발자국들을 하나로 묶은 '장소'
struct FootprintPlace: Identifiable {
    let id: Int
    let coordinate: CLLocationCoordinate2D
    /// 이 자리를 밟은 횟수
    let visitCount: Int
    /// 사용자가 붙인 이름 (없으면 주소)
    let name: String?
    /// 이 자리의 발견 번호 (첫 방문 기록이 있으면 그 번호)
    let discoveryIndex: Int
    let firstDate: Date
    let lastDate: Date
    /// 이 장소를 이루는 발자국들. 이름을 고치거나 지울 때 원본을 찾아가는 데 쓴다.
    let visitIDs: [PersistentIdentifier]

    var isDiscovered: Bool { discoveryIndex > 0 }

    /// 방문 횟수에 따른 표시 등급 — 자주 간 곳일수록 크고 진하게 그린다
    var rank: Int {
        switch visitCount {
        case 0...1: return 0
        case 2...4: return 1
        case 5...9: return 2
        default: return 3
        }
    }

    /// 5번 이상 간 곳은 '단골'로 본다
    var isFavorite: Bool { visitCount >= 5 }
}

enum FootprintAggregator {
    /// 발자국들을 radius(m) 안에서 하나의 장소로 묶는다.
    /// 먼저 찍힌 발자국이 그 장소의 중심이 되도록 시간순으로 훑는다.
    static func places(
        from visits: [Visit],
        radius: CLLocationDistance = LocationManager.discoveryRadius
    ) -> [FootprintPlace] {
        guard !visits.isEmpty else { return [] }

        let step = SpatialGrid.step(meters: radius)
        let ordered = visits.sorted { $0.arrivalDate < $1.arrivalDate }

        struct Bucket {
            var latitude: Double
            var longitude: Double
            var count: Int
            var name: String?
            var discoveryIndex: Int
            var firstDate: Date
            var lastDate: Date
            var visitIDs: [PersistentIdentifier]
        }

        var buckets: [Bucket] = []
        var index: [GridCell: [Int]] = [:]

        for visit in ordered {
            let candidates = SpatialGrid
                .neighbors(latitude: visit.latitude, longitude: visit.longitude, step: step, meters: radius)
                .flatMap { index[$0] ?? [] }

            let matched = candidates.first { position in
                let bucket = buckets[position]
                return CLLocation(latitude: bucket.latitude, longitude: bucket.longitude)
                    .distance(from: CLLocation(latitude: visit.latitude, longitude: visit.longitude)) < radius
            }

            if let matched {
                buckets[matched].count += 1
                buckets[matched].lastDate = max(buckets[matched].lastDate, visit.arrivalDate)
                buckets[matched].visitIDs.append(visit.persistentModelID)
                if buckets[matched].name == nil, let placeName = visit.placeName, !placeName.isEmpty {
                    buckets[matched].name = placeName
                }
                if buckets[matched].discoveryIndex == 0, visit.discoveryIndex > 0 {
                    buckets[matched].discoveryIndex = visit.discoveryIndex
                }
            } else {
                let bucket = Bucket(
                    latitude: visit.latitude,
                    longitude: visit.longitude,
                    count: 1,
                    name: visit.placeName?.isEmpty == false ? visit.placeName : nil,
                    discoveryIndex: visit.discoveryIndex,
                    firstDate: visit.arrivalDate,
                    lastDate: visit.arrivalDate,
                    visitIDs: [visit.persistentModelID]
                )
                buckets.append(bucket)
                let cell = SpatialGrid.cell(latitude: visit.latitude, longitude: visit.longitude, step: step)
                index[cell, default: []].append(buckets.count - 1)
            }
        }

        return buckets.enumerated().map { position, bucket in
            FootprintPlace(
                id: position,
                coordinate: CLLocationCoordinate2D(latitude: bucket.latitude, longitude: bucket.longitude),
                visitCount: bucket.count,
                name: bucket.name,
                discoveryIndex: bucket.discoveryIndex,
                firstDate: bucket.firstDate,
                lastDate: bucket.lastDate,
                visitIDs: bucket.visitIDs
            )
        }
    }
}

// MARK: - 걸은 길

/// 걸은 경로를 지도에 그릴 선으로 자른다.
///
/// 젤다의 '영웅의 길'처럼 지나온 자취를 그대로 남기되,
/// 기록이 끊긴 구간(차를 탔거나 앱이 꺼져 있던 사이)을 직선으로 이어 버리면
/// 걷지 않은 길이 걸은 것처럼 보이므로 거기서 선을 끊는다.
enum WalkTrail {
    struct Point {
        let coordinate: CLLocationCoordinate2D
        let timestamp: Date
    }

    /// 이 거리(m)나 시간(초)을 넘겨 뛰면 다른 구간으로 본다
    static let maxGapDistance: CLLocationDistance = 250
    static let maxGapInterval: TimeInterval = 15 * 60

    /// 끊긴 곳에서 나눈 구간들 (시각 정보를 유지한다)
    static func pointSegments(from points: [Point]) -> [[Point]] {
        guard points.count >= 2 else { return [] }
        var segments: [[Point]] = []
        var current: [Point] = [points[0]]

        for (previous, point) in zip(points, points.dropFirst()) {
            let gap = CLLocation(latitude: previous.coordinate.latitude, longitude: previous.coordinate.longitude)
                .distance(from: CLLocation(latitude: point.coordinate.latitude, longitude: point.coordinate.longitude))
            let interval = point.timestamp.timeIntervalSince(previous.timestamp)

            if gap > maxGapDistance || interval > maxGapInterval {
                if current.count >= 2 { segments.append(current) }
                current = [point]
            } else {
                current.append(point)
            }
        }
        if current.count >= 2 { segments.append(current) }
        return segments
    }

    static func segments(from points: [Point]) -> [[CLLocationCoordinate2D]] {
        pointSegments(from: points).map { $0.map(\.coordinate) }
    }

    /// 한 구간의 거리(m)
    static func distance(ofSegment segment: [Point]) -> CLLocationDistance {
        zip(segment, segment.dropFirst()).reduce(0) { sum, pair in
            sum + CLLocation(latitude: pair.0.coordinate.latitude, longitude: pair.0.coordinate.longitude)
                .distance(from: CLLocation(latitude: pair.1.coordinate.latitude, longitude: pair.1.coordinate.longitude))
        }
    }

    /// 걸은 총 거리(m)
    static func distance(of points: [Point]) -> CLLocationDistance {
        pointSegments(from: points).reduce(0) { $0 + distance(ofSegment: $1) }
    }
}

// MARK: - 안개 격자

enum FogGrid {
    /// 안개가 걷히는 칸의 한 변 길이(m). 한 번 지나가면 이만큼이 밝아진다.
    static let cellMeters: CLLocationDistance = 250

    /// 걸어서 지나간 자리가 걷어내는 반경(m). 길을 따라 좁게 열린다.
    static let walkClearRadius: CLLocationDistance = 150
    /// 머물렀던 자리가 걷어내는 반경(m). 잠시 지나친 길보다 넓게 열린다.
    static let stayClearRadius: CLLocationDistance = 300

    /// 지나간 좌표들이 걷어낸 칸 목록.
    /// 칸 중심이 좌표에서 clearRadius 안에 있는 것만 켜서, 걷힌 자리가
    /// 네모난 덩어리가 아니라 둥글게 퍼지고 오버레이 수도 줄어든다.
    static func clearedCells(
        from coordinates: [CLLocationCoordinate2D],
        clearRadius: CLLocationDistance,
        into cells: inout Set<GridCell>
    ) {
        let step = SpatialGrid.step(meters: cellMeters)
        for coordinate in coordinates {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            for cell in SpatialGrid.neighbors(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                step: step,
                meters: clearRadius
            ) where cells.contains(cell) == false {
                let center = CLLocation(
                    latitude: (Double(cell.row) + 0.5) * step,
                    longitude: (Double(cell.col) + 0.5) * step
                )
                if center.distance(from: location) <= clearRadius {
                    cells.insert(cell)
                }
            }
        }
    }

    /// 걸은 길과 머문 자리를 합쳐 걷어낸 칸을 만든다
    static func clearedCells(
        walked: [CLLocationCoordinate2D],
        stayed: [CLLocationCoordinate2D]
    ) -> Set<GridCell> {
        var cells = Set<GridCell>()
        clearedCells(from: walked, clearRadius: walkClearRadius, into: &cells)
        clearedCells(from: stayed, clearRadius: stayClearRadius, into: &cells)
        return cells
    }

    /// 칸 하나를 감싸는 사각형 좌표 (지도 오버레이용)
    static func corners(of cell: GridCell) -> [CLLocationCoordinate2D] {
        let step = SpatialGrid.step(meters: cellMeters)
        let origin = SpatialGrid.origin(of: cell, step: step)
        let maxLat = origin.latitude + step
        let maxLon = origin.longitude + step
        return [
            CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude),
            CLLocationCoordinate2D(latitude: maxLat, longitude: origin.longitude),
            CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon),
            CLLocationCoordinate2D(latitude: origin.latitude, longitude: maxLon)
        ]
    }

    /// 걷어낸 칸들이 지구 표면에서 차지하는 넓이(㎢)
    static func clearedAreaSquareKilometers(_ cells: Set<GridCell>) -> Double {
        let step = SpatialGrid.step(meters: cellMeters)
        let cellHeightKm = cellMeters / 1000
        return cells.reduce(0) { total, cell in
            let latitude = (Double(cell.row) + 0.5) * step
            let widthKm = 111.320 * max(cos(latitude * .pi / 180), 0) * step
            return total + widthKm * cellHeightKm
        }
    }
}
