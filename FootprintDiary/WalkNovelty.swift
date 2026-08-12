//
//  WalkNovelty.swift
//  FootprintDiary
//
//  "오늘 걸은 길 중 처음 걷는 구간은 얼마인가"를 센다.
//
//  이 값은 내 과거 기록 전체가 있어야 계산된다. 그래서 다른 앱이 흉내 낼 수 없고,
//  '탐험'이라는 말의 정의 그 자체이기도 하다. 늘 다니던 길만 걸으면 0이 나온다.
//

import Foundation
import CoreLocation

enum WalkNovelty {

    /// 이 거리(m) 안을 이미 걸었다면 같은 길로 본다.
    /// GPS 오차가 10~30m라 그보다 넉넉해야 하고, 길 건너편이 새 길로 잡히지 않을 정도여야 한다.
    static let sameRoadCell: CLLocationDistance = 30

    /// 이 시간(초) 안에 밟은 자리는 '이미 걸은 길'로 치지 않는다.
    ///
    /// 경로 점은 12m 간격으로 찍히는데 판정 격자는 30m라, 방금 지나온 내 발자국이
    /// 바로 옆 칸에 남는다. 시간을 보지 않으면 두 번째 점부터 전부 헌 길이 되어
    /// 새로 걷는 길이 언제나 0이 된다.
    static let recentWindow: TimeInterval = 10 * 60

    /// 날짜별 '처음 걷는 거리(m)'.
    /// 오래된 날부터 훑으면서 그때까지 밟은 자리를 쌓아 가므로, 어제 간 길은 오늘 새롭지 않다.
    static func newDistances(for walks: [DayWalk]) -> [Date: CLLocationDistance] {
        let step = SpatialGrid.step(meters: sameRoadCell)
        /// 칸마다 마지막으로 밟은 시각
        var lastWalked: [GridCell: Date] = [:]
        var result: [Date: CLLocationDistance] = [:]

        for walk in walks.sorted(by: { $0.day < $1.day }) {
            var newMeters: CLLocationDistance = 0

            for segment in walk.segments {
                if let first = segment.first {
                    lastWalked[cell(of: first.coordinate, step: step)] = first.timestamp
                }
                for (previous, point) in zip(segment, segment.dropFirst()) {
                    let target = cell(of: point.coordinate, step: step)
                    // 바로 옆 칸까지 본다 — 같은 길을 반대편 인도로 걸었다고 새 길은 아니다.
                    // 단, 방금(recentWindow 안에) 지나온 자리는 빼고 본다.
                    let isNew = !neighbors(of: target).contains { neighbor in
                        guard let walkedAt = lastWalked[neighbor] else { return false }
                        return point.timestamp.timeIntervalSince(walkedAt) > recentWindow
                    }
                    if isNew {
                        newMeters += CLLocation(
                            latitude: previous.coordinate.latitude,
                            longitude: previous.coordinate.longitude
                        ).distance(from: CLLocation(
                            latitude: point.coordinate.latitude,
                            longitude: point.coordinate.longitude
                        ))
                    }
                    lastWalked[target] = point.timestamp
                }
            }
            result[walk.day] = newMeters
        }
        return result
    }

    private static func cell(of coordinate: CLLocationCoordinate2D, step: Double) -> GridCell {
        SpatialGrid.cell(latitude: coordinate.latitude, longitude: coordinate.longitude, step: step)
    }

    private static func neighbors(of cell: GridCell) -> [GridCell] {
        var cells: [GridCell] = []
        for row in -1...1 {
            for col in -1...1 {
                cells.append(GridCell(row: cell.row + row, col: cell.col + col))
            }
        }
        return cells
    }
}

/// 카드가 보여줄 하루치 묶음
struct DayEntry: Identifiable {
    let walk: DayWalk
    /// 그날 처음 걸은 거리(m)
    let newDistance: CLLocationDistance

    var id: Date { walk.day }

    /// 그날 걸은 것 중 처음 걷는 길의 비율 (0~1)
    var novelty: Double {
        guard walk.distance > 0 else { return 0 }
        return min(newDistance / walk.distance, 1)
    }
}
