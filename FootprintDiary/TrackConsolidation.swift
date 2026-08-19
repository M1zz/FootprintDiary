//
//  TrackConsolidation.swift
//  FootprintDiary
//
//  [보관] 여러 번 지난 길을 겹쳐 붙여 오차를 줄이려던 시도. 지금은 쓰지 않는다.
//
//  생각은 이랬다. 같은 길을 다섯 번 걸으면 어긋남의 대부분은 점 하나하나가 흔들려서가
//  아니라 그날 통과 전체가 통째로 10~20m 밀려서 생긴다. 그러니 통과를 통째로 옮겨
//  이미 그려 둔 지도에 겹쳐 붙이면(ICP) 반경보다 큰 밀림도 잡을 수 있다.
//
//  실제로 재 보니 얻는 것보다 잃는 것이 컸다. 같은 코스 5회, 통과별 편향 σ=14m 기준:
//
//    매칭 반경   통과끼리 흩어짐        나란한 골목 두 개 (진짜 25m)
//    ────────────────────────────────────────────────────────────
//       12m       15.9m  (  +0%)          18.7m
//       18m       14.9m  (  -6%)          18.7m
//       25m       14.9m  (  -6%)          -2.3m  ← 두 길이 하나로 붙음
//       45m       11.8m  ( -26%)          -2.2m  ← 두 길이 하나로 붙음
//
//  안전한 지점이 없다. 나란한 길을 지키는 반경에서는 개선이 거의 없고, 개선이 나오는
//  반경에서는 25m 떨어진 골목 두 개가 한 줄로 붙어 버린다. 곧게 뻗은 나란한 두 길은
//  '같은 길이 밀린 것'과 '다른 길 두 개'를 좌표만으로 가릴 방법이 원래 없다.
//
//  지도에 없는 골목을 그리는 것이 이 앱의 값어치인데 그 골목들을 뭉개면서 얻는
//  25%는 남는 장사가 아니라고 보아 파이프라인에서 뺐다. 되살리려면 길의 생김새
//  (굽이·갈림)까지 견주는 방식이어야 한다. 좌표 거리만으로는 모자란다.
//

import Foundation
import CoreLocation

enum TrackConsolidation {

    /// 이 시간(초)을 넘겨 끊기면 다른 통과로 본다
    static let passGap: TimeInterval = 15 * 60

    /// 겹쳐 붙일 때 짝을 찾는 반경(m).
    /// 통과끼리 밀린 폭(10~20m)보다 넉넉해야 서로를 알아본다.
    static let matchRadius: CLLocationDistance = 45

    /// 진행 방향이 이 각도(도) 안에서 갈리면 같은 길로 본다.
    /// 방향은 180°로 접어 재므로 같은 길의 왕복은 하나로 묶인다.
    /// 이 조건이 없으면 나란한 골목이나 큰길 양쪽 인도가 한 줄로 뭉개진다.
    static let headingTolerance: Double = 40

    /// 밀린 양을 다시 재는 횟수. 옮기고 나면 짝이 달라지므로 몇 번 되풀이해야 자리를 잡는다.
    static let alignmentPasses = 8

    /// 통과의 점 가운데 이 비율만큼은 지도에서 짝을 찾아야 옮긴다.
    /// 처음 가 보는 길을 엉뚱한 옛 길로 끌어다 붙이지 않기 위한 안전장치다.
    static let minimumOverlap = 0.35

    /// 정확도를 모르는 점에 매길 값(m)
    static let assumedAccuracy: CLLocationDistance = 20

    struct Pass {
        let coordinate: CLLocationCoordinate2D
        let timestamp: Date
        let accuracy: CLLocationDistance
    }

    // MARK: - 들머리

    /// 통과별로 지도에 맞춰 붙인 결과. 입력의 시간 순서는 그대로 지킨다.
    static func consolidated(
        _ points: [Pass],
        matchRadius: CLLocationDistance = TrackConsolidation.matchRadius
    ) -> [Pass] {
        guard points.count >= 3 else { return points }

        let step = SpatialGrid.step(meters: matchRadius)
        /// 지금까지 자리를 잡은 점들 — 뒤에 오는 통과는 여기에 맞춰 붙는다
        var atlas: [Pass] = []
        var atlasHeadings: [Double] = []
        var index: [GridCell: [Int]] = [:]
        var result: [Pass] = []

        for pass in split(points) {
            let headings = self.headings(of: pass)
            let shift = atlas.isEmpty
                ? Offset.zero
                : estimateShift(of: pass, headings: headings, atlas: atlas,
                                atlasHeadings: atlasHeadings, index: index, step: step,
                                matchRadius: matchRadius)

            let moved = pass.map { shift.applied(to: $0) }
            result += moved

            for (point, heading) in zip(moved, headings) {
                index[cell(of: point.coordinate, step: step), default: []].append(atlas.count)
                atlas.append(point)
                atlasHeadings.append(heading)
            }
        }
        return result
    }

    // MARK: - 통과 나누기

    /// 시간이 끊긴 곳에서 나눈다. 한 번의 산책이 한 통과다.
    private static func split(_ points: [Pass]) -> [[Pass]] {
        var passes: [[Pass]] = []
        var current: [Pass] = []

        for point in points {
            if let last = current.last, point.timestamp.timeIntervalSince(last.timestamp) > passGap {
                if current.count >= 2 { passes.append(current) }
                current = []
            }
            current.append(point)
        }
        if current.count >= 2 { passes.append(current) }
        return passes
    }

    // MARK: - 밀린 양 재기

    /// 통과 전체를 얼마나 옮겨야 지도에 겹치는지.
    private struct Offset {
        var latitude: Double
        var longitude: Double
        static let zero = Offset(latitude: 0, longitude: 0)

        func applied(to point: Pass) -> Pass {
            Pass(
                coordinate: CLLocationCoordinate2D(
                    latitude: point.coordinate.latitude + latitude,
                    longitude: point.coordinate.longitude + longitude
                ),
                timestamp: point.timestamp,
                accuracy: point.accuracy
            )
        }
    }

    /// 옮기고 → 짝을 다시 찾고 → 또 옮기기를 되풀이해 자리를 좁혀 간다.
    private static func estimateShift(
        of pass: [Pass],
        headings: [Double],
        atlas: [Pass],
        atlasHeadings: [Double],
        index: [GridCell: [Int]],
        step: Double,
        matchRadius: CLLocationDistance
    ) -> Offset {
        var offset = Offset.zero
        var settled = Offset.zero
        var bestOverlap = 0.0

        for _ in 0..<alignmentPasses {
            var sumLatitude = 0.0, sumLongitude = 0.0, matched = 0.0, weightTotal = 0.0

            for (point, heading) in zip(pass, headings) {
                let moved = offset.applied(to: point)
                guard let partner = nearestPartner(
                    to: moved, heading: heading, atlas: atlas,
                    atlasHeadings: atlasHeadings, index: index, step: step,
                    matchRadius: matchRadius
                ) else { continue }

                // 정확하다고 보고된 점일수록 더 믿는다
                let accuracy = point.accuracy > 0 ? point.accuracy : assumedAccuracy
                let weight = 1 / (accuracy * accuracy)
                sumLatitude += (partner.coordinate.latitude - moved.coordinate.latitude) * weight
                sumLongitude += (partner.coordinate.longitude - moved.coordinate.longitude) * weight
                weightTotal += weight
                matched += 1
            }

            let overlap = matched / Double(pass.count)
            guard weightTotal > 0, overlap >= minimumOverlap else { break }

            offset.latitude += sumLatitude / weightTotal
            offset.longitude += sumLongitude / weightTotal

            // 가장 많이 겹쳤을 때의 값을 채택한다 (되풀이하다 엉뚱한 데로 흘러가면 버린다)
            if overlap >= bestOverlap {
                bestOverlap = overlap
                settled = offset
            }
        }
        return settled
    }

    /// 반경 안에서 방향이 같은 가장 가까운 지도 점
    private static func nearestPartner(
        to point: Pass,
        heading: Double,
        atlas: [Pass],
        atlasHeadings: [Double],
        index: [GridCell: [Int]],
        step: Double,
        matchRadius: CLLocationDistance
    ) -> Pass? {
        let origin = point.coordinate
        let columnSpan = SpatialGrid.columnRadius(atLatitude: origin.latitude, step: step, meters: matchRadius)
        let home = cell(of: origin, step: step)

        var best: Pass?
        var bestDistance = matchRadius

        for row in -1...1 {
            for column in -columnSpan...columnSpan {
                for candidate in index[GridCell(row: home.row + row, col: home.col + column)] ?? [] {
                    guard angleGap(heading, atlasHeadings[candidate]) <= headingTolerance else { continue }
                    let gap = distance(origin, atlas[candidate].coordinate)
                    if gap < bestDistance {
                        bestDistance = gap
                        best = atlas[candidate]
                    }
                }
            }
        }
        return best
    }

    // MARK: - 진행 방향

    /// 각 점의 진행 방향(0~180°). 앞뒤 점을 이은 방향으로 재고, 왕복을 같은 길로 보려고 180°로 접는다.
    private static func headings(of points: [Pass]) -> [Double] {
        points.indices.map { index in
            let previous = points[max(index - 1, 0)].coordinate
            let next = points[min(index + 1, points.count - 1)].coordinate
            return bearing(from: previous, to: next).truncatingRemainder(dividingBy: 180)
        }
    }

    /// 180°로 접은 두 방향 사이의 각차. 179°와 1°는 2° 차이로 본다.
    private static func angleGap(_ a: Double, _ b: Double) -> Double {
        let gap = abs(a - b).truncatingRemainder(dividingBy: 180)
        return min(gap, 180 - gap)
    }

    private static func bearing(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let deltaLon = (end.longitude - start.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let degrees = atan2(y, x) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    // MARK: - 거들기

    private static func cell(of coordinate: CLLocationCoordinate2D, step: Double) -> GridCell {
        SpatialGrid.cell(latitude: coordinate.latitude, longitude: coordinate.longitude, step: step)
    }

    private static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}
