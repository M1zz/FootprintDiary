//
//  DayWalk.swift
//  FootprintDiary
//
//  하루치 걸음을 '한 장의 그림'으로 다루기 위한 값.
//
//  지도 배경 없이 궤적만 그린다. 배경이 없으면 어디를 걸었는지는 드러나지 않고
//  그날의 모양만 남는다. 그래서 그대로 남에게 보여줄 수 있다.
//

import Foundation
import CoreLocation
import CoreGraphics

struct DayWalk: Identifiable {
    /// 그날의 자정
    let day: Date
    /// 끊긴 곳에서 나눈 구간들 (차를 탔거나 앱이 꺼져 있던 사이는 이어 붙이지 않는다)
    let segments: [[WalkTrail.Point]]
    /// 그날 걸은 총 거리(m)
    let distance: CLLocationDistance
    /// 실제로 걸은 시간 — 구간별 시간의 합.
    /// 첫 점부터 마지막 점까지로 재면 아침·저녁 두 번 걸었을 때 그 사이 쉰 시간까지 들어간다.
    let duration: TimeInterval

    var id: Date { day }
    var walkCount: Int { segments.count }
    var hasDrawing: Bool { primarySegment != nil }

    /// 그날의 대표 산책 — 가장 멀리 걸은 구간.
    ///
    /// 하루에 떨어진 두 곳을 걸으면 둘 다 한 그림에 넣을 때 각각이 점처럼 작아진다.
    /// 그래서 그림은 대표 구간 하나만 그리고, 거리·시간은 그날 전체로 센다.
    var primarySegment: [WalkTrail.Point]? {
        segments.max { WalkTrail.distance(ofSegment: $0) < WalkTrail.distance(ofSegment: $1) }
    }

    var startTime: Date? { segments.first?.first?.timestamp }
    var endTime: Date? { segments.last?.last?.timestamp }

    // MARK: - 만들기

    /// 저장된 점들을 값으로 바꾼다. (SwiftData 객체는 다른 스레드로 넘길 수 없다)
    static func values(of points: [TrackPoint]) -> [WalkTrail.Point] {
        points.map { WalkTrail.Point(coordinate: $0.coordinate, timestamp: $0.timestamp) }
    }

    /// 경로 점들을 날짜별로 묶는다
    static func build(from points: [WalkTrail.Point], calendar: Calendar = .current) -> [DayWalk] {
        guard !points.isEmpty else { return [] }

        var byDay: [Date: [WalkTrail.Point]] = [:]
        for point in points {
            byDay[calendar.startOfDay(for: point.timestamp), default: []].append(point)
        }

        return byDay
            .map { day, dayPoints in
                let sorted = dayPoints.sorted { $0.timestamp < $1.timestamp }
                let segments = WalkTrail.pointSegments(from: sorted)
                return DayWalk(
                    day: day,
                    segments: segments,
                    distance: segments.reduce(0) { $0 + WalkTrail.distance(ofSegment: $1) },
                    duration: segments.reduce(0) { total, segment in
                        guard let first = segment.first, let last = segment.last else { return total }
                        return total + max(0, last.timestamp.timeIntervalSince(first.timestamp))
                    }
                )
            }
            .sorted { $0.day > $1.day }
    }

    static func empty(on day: Date) -> DayWalk {
        DayWalk(day: day, segments: [], distance: 0, duration: 0)
    }

    // MARK: - 그림 좌표로 바꾸기

    /// 그날 걸은 것을 통째로 주어진 크기 안에 꽉 차게 눕힌다.
    ///
    /// 대표 구간 하나만 그리는 drawingPath와 따로 두는 까닭은 쓰는 자리가 다르기
    /// 때문이다. 저쪽은 '그날의 모양' 한 장을 보여 주는 카드라 여럿을 담으면 각각이
    /// 점처럼 작아진다. 이쪽은 달력에서 '그날 그린 지도'를 묻는 자리라, 아침에 걸은
    /// 동네와 저녁에 걸은 동네가 둘 다 있어야 그날이 된다.
    ///
    /// 다만 아주 짧은 구간은 뺀다. 먼 카페에 다녀와 그 앞에서 스무 걸음 걸은 날,
    /// 그 스무 걸음이 화면에 끼면 하루 종일 걸은 동네가 손톱만 해진다.
    /// (같은 까닭으로 영상 앵글도 지점을 골라 담는다 — WalkFilm.swift)
    ///
    /// - Parameter minimumShare: 가장 긴 구간에 견주어 이 몫이 안 되는 구간은 뺀다.
    func drawingPaths(in size: CGSize, inset: CGFloat = 8, minimumShare: Double = 0.08) -> [[CGPoint]] {
        let measured = segments.map { ($0, WalkTrail.distance(ofSegment: $0)) }
        guard let longest = measured.map(\.1).max(), longest > 0 else { return [] }
        let kept = measured.filter { $0.1 >= longest * minimumShare }.map(\.0)
        guard !kept.isEmpty else { return [] }

        // 눕히는 자는 남은 구간 전부를 합쳐서 잰다. 구간마다 따로 재면 저마다
        // 제 칸을 꽉 채워, 멀리 떨어진 두 동네가 나란히 붙어 있는 것처럼 보인다.
        let all = kept.flatMap { $0 }
        let latitudes = all.map(\.coordinate.latitude)
        let longitudes = all.map(\.coordinate.longitude)
        let minLat = latitudes.min()!, maxLat = latitudes.max()!
        let minLon = longitudes.min()!, maxLon = longitudes.max()!
        let midLat = (minLat + maxLat) / 2
        let lonScale = max(cos(midLat * .pi / 180), 0.01)

        let width = max((maxLon - minLon) * lonScale, 0.00005)
        let height = max(maxLat - minLat, 0.00005)

        let canvas = CGSize(
            width: max(size.width - inset * 2, 1),
            height: max(size.height - inset * 2, 1)
        )
        let scale = min(canvas.width / width, canvas.height / height)
        let originX = inset + (canvas.width - width * scale) / 2
        let originY = inset + (canvas.height - height * scale) / 2

        return kept.map { segment in
            segment.map { point in
                CGPoint(
                    x: originX + (point.coordinate.longitude - minLon) * lonScale * scale,
                    // 북쪽이 위로 오도록 y를 뒤집는다
                    y: originY + (maxLat - point.coordinate.latitude) * scale
                )
            }
        }
    }

    /// 대표 구간을 주어진 크기 안에 꽉 차게 눕힌다.
    ///
    /// 경도 1도는 위도 1도보다 짧으므로(위도에 따라 cos배) 그대로 그리면 그림이
    /// 옆으로 늘어난다. 실제 걸은 모양을 지키려고 경도를 보정한 뒤 비율을 유지한다.
    func drawingPath(in size: CGSize, inset: CGFloat = 16) -> [CGPoint] {
        guard let segment = primarySegment, segment.count >= 2 else { return [] }

        let latitudes = segment.map(\.coordinate.latitude)
        let longitudes = segment.map(\.coordinate.longitude)
        let minLat = latitudes.min()!, maxLat = latitudes.max()!
        let minLon = longitudes.min()!, maxLon = longitudes.max()!
        let midLat = (minLat + maxLat) / 2
        let lonScale = max(cos(midLat * .pi / 180), 0.01)

        // 한 방향으로만 걸었어도 납작해지지 않도록 최소 폭을 준다
        let width = max((maxLon - minLon) * lonScale, 0.00005)
        let height = max(maxLat - minLat, 0.00005)

        let canvas = CGSize(
            width: max(size.width - inset * 2, 1),
            height: max(size.height - inset * 2, 1)
        )
        let scale = min(canvas.width / width, canvas.height / height)
        let originX = inset + (canvas.width - width * scale) / 2
        let originY = inset + (canvas.height - height * scale) / 2

        return segment.map { point in
            CGPoint(
                x: originX + (point.coordinate.longitude - minLon) * lonScale * scale,
                // 북쪽이 위로 오도록 y를 뒤집는다
                y: originY + (maxLat - point.coordinate.latitude) * scale
            )
        }
    }
}
