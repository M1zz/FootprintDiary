//
//  StayPrompt.swift
//  FootprintDiary
//
//  오래 머문 자리를 두고 "여기는 기록 안 해도 괜찮을까요?" 하고 묻는 규칙.
//
//  머무름은 저절로 쌓이지만 스탬프는 손으로 찍어야 남는다. 그래서 가만두면 정작 오래
//  앉아 있던 자리가 지도에 하나도 안 남는 일이 생긴다. 그런 자리만 골라 한 번 짚어 준다.
//
//  묻는 일은 쉽게 성가셔지므로 문턱을 두 겹으로 뒀다.
//
//   1. 절대 기준 — 오래 머문 자리만. 잠깐 들른 곳까지 물으면 하루에 열 번을 묻게 된다.
//   2. 그 기준을 넘은 것도 다 묻지 않는다 — 하루에 많아야 두 곳, 오래 머문 순으로.
//
//  여기에 더해, 이미 스탬프를 찍어 둔 자리와 이름을 아는 자리(집·일터처럼 늘 가는 곳)는
//  아예 후보에서 뺀다. 이미 아는 것을 묻는 것이 가장 성가시다.
//  한 번 "괜찮아요"를 들은 자리도 다시 묻지 않는다 (Visit.askedAboutStamp).
//

import Foundation
import CoreLocation

enum StayPrompt {

    /// 이만큼은 머물러야 물어본다 (절대 기준)
    static let minimumStay: TimeInterval = 45 * 60

    /// 하루에 많아야 이만큼만 묻는다
    static let dailyLimit = 2

    /// 이 거리 안에 이미 스탬프가 있으면 묻지 않는다 — 이미 기록한 자리다
    static let alreadyMarkedRadius: CLLocationDistance = 80

    /// 오늘 머문 자리 가운데 물어볼 만한 것. 오래 머문 순으로 최대 `dailyLimit`곳.
    static func candidates(
        visits: [Visit],
        stamps: [MapStamp],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [Visit] {
        visits
            .filter { calendar.isDate($0.arrivalDate, inSameDayAs: now) }
            .filter { !$0.askedAboutStamp }
            // 이름을 아는 자리는 이미 내 지도 안에 있는 셈이다 (집·일터처럼 늘 가는 곳)
            .filter { ($0.placeName ?? "").isEmpty }
            .filter { stay($0, now: now) >= minimumStay }
            .filter { !isMarked($0, stamps: stamps) }
            .sorted { stay($0, now: now) > stay($1, now: now) }
            .prefix(dailyLimit)
            .map { $0 }
    }

    /// 얼마나 머물렀는지. 아직 떠나지 않았으면 지금까지로 센다.
    static func stay(_ visit: Visit, now: Date = .now) -> TimeInterval {
        let end = visit.departureDate ?? now
        return max(0, end.timeIntervalSince(visit.arrivalDate))
    }

    /// 그 자리 가까이에 이미 찍어 둔 스탬프가 있는지
    static func isMarked(_ visit: Visit, stamps: [MapStamp]) -> Bool {
        let here = CLLocation(latitude: visit.latitude, longitude: visit.longitude)
        return stamps.contains { stamp in
            here.distance(from: CLLocation(latitude: stamp.latitude, longitude: stamp.longitude))
                < alreadyMarkedRadius
        }
    }

    /// "2시간 10분"처럼 읽히게
    static func stayText(_ visit: Visit, now: Date = .now) -> String {
        let minutes = Int(stay(visit, now: now) / 60)
        if minutes < 60 { return "\(minutes)분" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)시간" : "\(hours)시간 \(rest)분"
    }
}
