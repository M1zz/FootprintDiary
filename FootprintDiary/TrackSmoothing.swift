//
//  TrackSmoothing.swift
//  FootprintDiary
//
//  저장된 경로를 '그릴 때' 다듬는다.
//
//  저장은 언제나 원본으로 한다. 한 번 뭉갠 좌표는 되돌릴 수 없고, 다듬는 방법은
//  앞으로 계속 나아질 것이기 때문이다. 그래서 이 파일은 저장된 점을 건드리지 않고
//  화면에 올릴 값만 만들어 낸다.
//
//  여기서 하는 일은 네 가지다.
//   1. 끊긴 곳에서 나누기 — 다듬기는 '이어서 걸은 한 줄기' 안에서만 뜻이 있다
//   2. 튄 점 걷어내기 — 앞뒤와 견줘 혼자 멀리 떨어진 점
//   3. 정확도 가중 평균 — 정확도가 좋다고 보고된 점에 더 무게를 준다
//   4. 모서리 깎기 — 12m 간격 직선이 만드는 각을 둥글린다
//

import Foundation
import CoreLocation

enum TrackSmoothing {

    /// 저장된 점에서 뽑아 온 값. 정확도까지 함께 들고 다녀야 무게를 줄 수 있다.
    struct RawPoint {
        let coordinate: CLLocationCoordinate2D
        let timestamp: Date
        /// 수평 정확도(m). 0 이하면 알 수 없음.
        let accuracy: CLLocationDistance
    }

    /// 정확도를 모르는 점에 매길 값(m). 이 속성이 생기기 전에 쌓인 기록이 여기 해당한다.
    static let assumedAccuracy: CLLocationDistance = 20
    /// 가중 평균을 낼 때 앞뒤로 보는 점 수
    static let windowRadius = 2
    /// 앞뒤 점을 이은 선에서 이만큼(m) 넘게 벗어난 점은 튄 것으로 본다
    static let outlierThreshold: CLLocationDistance = 40
    /// 이상치 판정으로 연달아 버릴 수 있는 최대 개수
    static let maxConsecutiveDrops = 3
    /// 모서리를 깎는 횟수. 늘릴수록 부드럽지만 점이 배로 늘어난다.
    static let cornerCuts = 2

    /// 흔들림을 걷어낸 점들.
    ///
    /// 튄 점을 빼기 때문에 개수가 줄어든다. 그래서 입력과 짝을 맞춰 쓰면 안 되고,
    /// 뒤 단계가 정확도를 계속 쓸 수 있도록 RawPoint 그대로 돌려준다.
    ///
    /// 시각 순으로 정렬된 점을 받는다고 본다.
    static func smoothed(_ points: [RawPoint]) -> [RawPoint] {
        guard points.count >= 3 else { return points }
        return runs(of: points).flatMap { weightedAverage(removingOutliers($0)) }
    }

    // MARK: - 1. 끊긴 곳에서 나누기

    /// 기록이 끊긴 곳에서 줄기를 나눈다.
    ///
    /// 이 단계가 없으면 어제 집 앞에서 끝난 점과 오늘 3km 떨어진 곳에서 시작한 점이
    /// 한 줄에 나란히 놓인다. 그 사이의 도약을 이웃으로 견주게 되므로 오늘 걸은 점이
    /// 통째로 '튄 점'으로 몰려 사라지고, 가중 평균은 어제의 끝을 오늘 쪽으로 끌어당긴다.
    ///
    /// 나누는 자리는 지도에 선을 끊는 자리와 같아야 한다. 그래서 기준을 WalkTrail에서 빌린다.
    /// (점이 하나뿐인 줄기도 버리지 않고 그대로 돌려준다 — 버릴지는 그리는 쪽이 정한다)
    private static func runs(of points: [RawPoint]) -> [[RawPoint]] {
        guard !points.isEmpty else { return [] }

        var runs: [[RawPoint]] = []
        var current: [RawPoint] = [points[0]]

        for (previous, point) in zip(points, points.dropFirst()) {
            let gap = distance(previous.coordinate, point.coordinate)
            let interval = point.timestamp.timeIntervalSince(previous.timestamp)
            if gap > WalkTrail.maxGapDistance || interval > WalkTrail.maxGapInterval {
                runs.append(current)
                current = [point]
            } else {
                current.append(point)
            }
        }
        runs.append(current)
        return runs
    }

    // MARK: - 2. 튄 점 걷어내기

    /// 앞뒤 점을 곧장 이었을 때의 중간 자리에서 혼자 멀리 떨어진 점을 뺀다.
    /// 사람은 한 걸음 사이에 40m를 옆으로 옮겨 갔다가 돌아오지 않는다.
    ///
    /// 견주는 기준은 '마지막으로 살린 점'이다. 그래서 한 번 버리기 시작하면 기준이
    /// 뒤처진 자리에 굳어 그 뒤가 줄줄이 버려질 수 있다. 몇 번 이어지면 기준을 지금
    /// 점으로 옮겨 다시 잇는다 — 잘못 본 점 하나가 그 뒤를 영원히 막지 않도록.
    /// (저장할 때도 같은 까닭으로 LocationManager가 점프 판정을 몇 번에서 끊는다)
    private static func removingOutliers(_ points: [RawPoint]) -> [RawPoint] {
        guard points.count >= 3 else { return points }
        var kept: [RawPoint] = [points[0]]
        var dropped = 0

        for index in 1..<(points.count - 1) {
            let previous = kept.last ?? points[index - 1]
            let next = points[index + 1]
            let middle = CLLocationCoordinate2D(
                latitude: (previous.coordinate.latitude + next.coordinate.latitude) / 2,
                longitude: (previous.coordinate.longitude + next.coordinate.longitude) / 2
            )
            if distance(points[index].coordinate, middle) <= outlierThreshold
                || dropped >= maxConsecutiveDrops {
                kept.append(points[index])
                dropped = 0
            } else {
                dropped += 1
            }
        }

        kept.append(points[points.count - 1])
        return kept
    }

    // MARK: - 3. 정확도 가중 평균

    /// 앞뒤 몇 점을 함께 보되, 정확도가 좋다고 보고된 점에 더 무게를 준다.
    /// 무게를 1/정확도²로 두는 건 오차가 정규분포일 때의 최적 가중이다.
    private static func weightedAverage(_ points: [RawPoint]) -> [RawPoint] {
        guard points.count >= 3 else { return points }

        return points.indices.map { index in
            // 양 끝은 평균할 이웃이 한쪽뿐이라 그대로 둔다 (움직이면 선의 시작과 끝이 잘린다)
            guard index >= windowRadius, index < points.count - windowRadius else { return points[index] }

            var latitude = 0.0, longitude = 0.0, total = 0.0
            for offset in -windowRadius...windowRadius {
                let point = points[index + offset]
                let accuracy = point.accuracy > 0 ? point.accuracy : assumedAccuracy
                let weight = 1 / (accuracy * accuracy)
                latitude += point.coordinate.latitude * weight
                longitude += point.coordinate.longitude * weight
                total += weight
            }
            guard total > 0 else { return points[index] }

            return RawPoint(
                coordinate: CLLocationCoordinate2D(latitude: latitude / total, longitude: longitude / total),
                timestamp: points[index].timestamp,
                accuracy: points[index].accuracy
            )
        }
    }

    // MARK: - 4. 모서리 깎기

    /// 채이킨(Chaikin) 방식으로 모서리를 잘라 낸다.
    /// 각 변에서 1/4, 3/4 지점을 새 점으로 삼기를 되풀이하면 꺾인 선이 곡선에 가까워진다.
    /// 오차를 줄이는 건 아니지만, 오차가 만든 각짐이 눈에 덜 띈다.
    static func rounded(_ coordinates: [CLLocationCoordinate2D], cuts: Int = cornerCuts) -> [CLLocationCoordinate2D] {
        guard coordinates.count >= 3, cuts > 0 else { return coordinates }

        var current = coordinates
        for _ in 0..<cuts {
            var next: [CLLocationCoordinate2D] = [current[0]]
            for (start, end) in zip(current, current.dropFirst()) {
                next.append(interpolate(start, end, 0.25))
                next.append(interpolate(start, end, 0.75))
            }
            next.append(current[current.count - 1])
            current = next
        }
        return current
    }

    // MARK: - 거들기

    private static func interpolate(
        _ start: CLLocationCoordinate2D,
        _ end: CLLocationCoordinate2D,
        _ t: Double
    ) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: start.latitude + (end.latitude - start.latitude) * t,
            longitude: start.longitude + (end.longitude - start.longitude) * t
        )
    }

    private static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}
