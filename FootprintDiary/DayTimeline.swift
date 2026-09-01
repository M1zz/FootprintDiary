//
//  DayTimeline.swift
//  FootprintDiary
//
//  오늘 하루를 '들른 곳'의 차례로 세우는 셈.
//
//  지도는 하루를 한 장의 그림으로 보여 주고, 필름(WalkFilm)은 그것이 그려지는 차례를
//  보여 준다. 둘 다 답하지 못하는 물음이 하나 남는다 — 오늘 어디어디를 갔더라.
//  선의 모양은 어디를 지났는지 말해 주지만, 어디에 '머물렀는지'는 말해 주지 않는다.
//  하루를 되짚을 때 사람이 기억하는 단위는 지나온 길이 아니라 들른 곳이다.
//
//  머문 자리는 두 갈래에서 온다.
//
//   1. 머무름 기록(Visit) — 아이오에스가 알려 주는 것. 앱이 꺼져 있어도, 건물 안에
//      들어가 있어도 잡힌다. 대신 언제 어디에 있었는지만 알려 주고 그 사이는 비어 있다.
//   2. 걸음(TrackPoint) — 앱이 직접 쌓은 것. 걷는 동안의 일은 촘촘히 알지만,
//      앉아서 쉬는 동안에는 점이 아예 들어오지 않는다.
//
//  둘을 합치는 편이 어느 한쪽보다 낫다. 겹치는 자리는 머무름 기록 쪽을 남긴다 —
//  그쪽에 이름과 주소가 붙어 있다.
//
//  걸음에서 머무름을 짚어 내는 방법은 하나다. 어느 점을 붙박이로 두고 그 둘레
//  dwellRadius 안에 머무는 동안을 이어 본다. 그 동안이 minimumDwell을 넘으면
//  한 자리로 센다. 점이 촘촘히 뭉쳐 있어도 잡히고(가게 앞을 서성였다), 점 두 개
//  사이가 한 시간씩 비어 있어도 잡힌다(들어가 앉아 있었다). 두 번째가 더 흔하다 —
//  이 앱은 걷는 동안에만 점을 쌓으므로, 머무름은 대개 '점이 없는 시간'으로 나타난다.
//

import Foundation
import CoreLocation

enum DayTimeline {

    // MARK: - 자

    /// 한 자리에 머문 것으로 치는 반경(m).
    ///
    /// 80m로 잡았다. 도시에서 위치는 건물 사이에서 수십 미터씩 튀므로 그보다 좁게 잡으면
    /// 한자리에 앉아 있는 동안에도 자리가 둘로 갈라진다. 반대로 더 넓히면 골목 하나를
    /// 오가며 들른 두 가게가 한 자리로 뭉친다.
    /// (스탬프에 붙이는 100m보다 좁은 것은, 저쪽이 '거기 있다고 쳐 주는 너그러움'인 데 비해
    ///  이쪽은 '여기와 저기를 가르는 금'이기 때문이다)
    static let dwellRadius: CLLocationDistance = 80

    /// 이만큼 머물러야 한 자리로 센다.
    ///
    /// 12분. 신호를 기다리거나 가게 앞에서 들여다본 것까지 세면 하루가 스무 줄이 되어
    /// 정작 어디를 갔었는지가 묻힌다. 반대로 30분으로 올리면 잠깐 들른 편의점과 우체국이
    /// 통째로 빠져, 하루가 집과 일터 둘로만 남는다.
    static let minimumDwell: TimeInterval = 12 * 60

    /// 머무름 기록과 걸음이 이 거리 안에서 같은 시간을 가리키면 한 자리로 본다.
    ///
    /// 둘은 다른 눈으로 잰 같은 자리라, 좌표가 딱 맞아떨어지지 않는다.
    /// 머무름 기록은 한동안의 한가운데를 찍고 걸음은 문 앞을 찍으므로 백 미터쯤 어긋난다.
    static let mergeRadius: CLLocationDistance = 150

    // MARK: - 값

    /// 머무름 기록(Visit)에서 값만 뽑아 온 것.
    ///
    /// 저장소 객체를 그대로 받지 않는 까닭은 이 셈이 화면과 상관없이 서야 하기 때문이다.
    /// 여기서 SwiftData를 알면 미리보기도 시험도 저장소를 띄워야 돌아간다.
    struct Stay {
        let coordinate: CLLocationCoordinate2D
        let arrival: Date
        let departure: Date?
        /// 이름이나 주소 (아직 모르면 nil)
        let name: String?
    }

    /// 오늘 들른 한 자리
    struct Stop: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
        let arrival: Date
        let departure: Date
        /// 어디서 알아낸 자리인지
        let source: Source
        /// 머무름 기록이 들고 있던 이름 (걸음에서 짚어 낸 자리에는 없다)
        let name: String?

        enum Source {
            /// 아이오에스가 알려 준 머무름
            case stay
            /// 걸음이 끊긴 자리에서 짚어 낸 것
            case track
        }

        var duration: TimeInterval { max(0, departure.timeIntervalSince(arrival)) }
    }

    /// 앞 자리에서 이 자리까지 걸어온 것
    struct Leg {
        let distance: CLLocationDistance
        let duration: TimeInterval
    }

    /// 타임라인의 한 줄 — 들른 곳 하나와, 거기까지 걸어온 길.
    ///
    /// 길을 따로 줄로 두지 않고 자리에 딸려 붙인 까닭이 있다. 따로 두면 목록이
    /// '자리, 길, 자리, 길'로 번갈아 서서 어느 것이 이야기의 뼈대인지 흐려진다.
    /// 이 하루의 뼈대는 들른 곳이고, 길은 그 사이를 잇는 것이다.
    struct Row: Identifiable {
        let id = UUID()
        let stop: Stop
        /// 첫 자리에는 없다 (그 앞에 온 곳이 없으므로)
        let approach: Leg?
    }

    // MARK: - 세우기

    /// 하루치 걸음과 머무름 기록에서 타임라인을 세운다.
    ///
    /// - Parameters:
    ///   - track: 그날의 걸음 (시각 차례대로)
    ///   - stays: 그날의 머무름 기록
    ///   - now: 아직 떠나지 않은 자리를 어디까지로 셀지
    static func rows(track: [WalkTrail.Point],
                     stays: [Stay],
                     now: Date = .now) -> [Row] {
        let fromStays = stays.map { stay in
            Stop(coordinate: stay.coordinate,
                 arrival: stay.arrival,
                 // 아직 떠나지 않았으면 지금까지로 센다
                 departure: max(stay.departure ?? now, stay.arrival),
                 source: .stay,
                 name: stay.name)
        }

        // 걸음에서 짚어 낸 자리 가운데, 머무름 기록이 이미 말하고 있는 것은 뺀다.
        // 같은 자리가 두 줄로 서면 '두 번 갔다'로 읽힌다.
        let fromTrack = trackStops(from: track).filter { candidate in
            !fromStays.contains { overlaps(candidate, $0) }
        }

        let stops = (fromStays + fromTrack).sorted { $0.arrival < $1.arrival }

        return stops.enumerated().map { index, stop in
            guard index > 0 else { return Row(stop: stop, approach: nil) }
            let previous = stops[index - 1]
            return Row(stop: stop, approach: leg(in: track, from: previous.departure, to: stop.arrival))
        }
    }

    /// 두 자리가 같은 자리인지 — 가깝고, 같은 시간을 가리키면.
    ///
    /// 거리만으로 가르지 않는다. 아침에 들렀다 저녁에 다시 들른 단골 가게는 가깝지만
    /// 다른 자리이고, 그 둘을 합치면 '하루 종일 거기 있었다'가 되어 버린다.
    static func overlaps(_ a: Stop, _ b: Stop) -> Bool {
        let near = CLLocation(latitude: a.coordinate.latitude, longitude: a.coordinate.longitude)
            .distance(from: CLLocation(latitude: b.coordinate.latitude, longitude: b.coordinate.longitude))
        guard near <= mergeRadius else { return false }
        return a.arrival < b.departure && b.arrival < a.departure
    }

    /// 걸음에서 머문 자리를 짚어 낸다.
    ///
    /// 앞에서부터 한 점을 붙박이로 세우고, 그 둘레 dwellRadius를 벗어나지 않는 동안
    /// 이어 본다. 그 동안이 minimumDwell을 넘으면 한 자리로 센다.
    ///
    /// 자리는 뭉친 점들의 한가운데로 잡는다. 붙박이 점을 그대로 쓰면 자리가 늘 문 앞이나
    /// 길가로 치우친다 — 들어갈 때 마지막으로 찍힌 점이 붙박이가 되기 때문이다.
    static func trackStops(from points: [WalkTrail.Point]) -> [Stop] {
        guard points.count >= 2 else { return [] }
        var stops: [Stop] = []
        var index = 0

        while index < points.count - 1 {
            let anchor = points[index]
            let anchorLocation = CLLocation(latitude: anchor.coordinate.latitude,
                                            longitude: anchor.coordinate.longitude)
            var last = index
            var next = index + 1
            while next < points.count {
                let here = CLLocation(latitude: points[next].coordinate.latitude,
                                      longitude: points[next].coordinate.longitude)
                if anchorLocation.distance(from: here) > dwellRadius { break }
                last = next
                next += 1
            }

            let span = points[last].timestamp.timeIntervalSince(anchor.timestamp)
            if span >= minimumDwell {
                stops.append(Stop(
                    coordinate: centroid(of: points[index...last]),
                    arrival: anchor.timestamp,
                    departure: points[last].timestamp,
                    source: .track,
                    name: nil
                ))
                index = last + 1
            } else {
                index += 1
            }
        }
        return stops
    }

    /// 두 자리 사이에 걸은 것.
    ///
    /// 거리는 그 사이에 찍힌 점을 이어 잰다. 끊긴 곳은 WalkTrail이 알아서 건너뛰므로,
    /// 차를 타고 옮긴 구간이 걸은 거리로 들어가지 않는다.
    static func leg(in track: [WalkTrail.Point], from: Date, to: Date) -> Leg? {
        guard to > from else { return nil }
        let between = track.filter { $0.timestamp >= from && $0.timestamp <= to }
        let distance = WalkTrail.distance(of: between)
        // 걸은 것이 잡히지 않으면 줄을 세우지 않는다. 0m를 적어 두면 걷지 않았다는
        // 말인지 기록이 없다는 말인지 읽는 쪽에서 가릴 수 없다.
        guard distance >= 1 else { return nil }
        return Leg(distance: distance, duration: to.timeIntervalSince(from))
    }

    /// 점 무리의 한가운데. 도시 한 자리 안에서는 평균으로 충분하다.
    static func centroid(of points: ArraySlice<WalkTrail.Point>) -> CLLocationCoordinate2D {
        guard !points.isEmpty else { return CLLocationCoordinate2D() }
        let count = Double(points.count)
        return CLLocationCoordinate2D(
            latitude: points.reduce(0) { $0 + $1.coordinate.latitude } / count,
            longitude: points.reduce(0) { $0 + $1.coordinate.longitude } / count
        )
    }

    // MARK: - 읽히게

    /// "1시간 20분"처럼. 1분이 안 되면 "1분 미만".
    static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "1분 미만" }
        if minutes < 60 { return "\(minutes)분" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)시간" : "\(hours)시간 \(rest)분"
    }

    /// "820m", "1.2km"
    static func distanceText(_ meters: CLLocationDistance) -> String {
        meters < 1000
        ? "\(Int(meters.rounded()))m"
        : String(format: "%.1fkm", meters / 1000)
    }
}
