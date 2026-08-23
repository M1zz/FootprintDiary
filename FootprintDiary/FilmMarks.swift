//
//  FilmMarks.swift
//  FootprintDiary
//
//  필름 도중에 '탕' 하고 찍힐 자리를 고른다.
//
//  거르는 잣대는 하나다 — 그때 그 자리가 나에게 처음이었는가.
//  늘 지나는 길목은 필름에서도 그냥 지나가야 한다. 하루에 스무 번 도장이 찍히면
//  그 도장은 아무것도 뜻하지 않게 되고, 정작 처음 간 곳이 묻힌다.
//
//  두 갈래를 모은다. 하나는 앱이 스스로 알아본 '발견'(처음 밟은 자리)이고,
//  다른 하나는 내가 손으로 찍은 스탬프다. 뒤엣것은 내가 직접 이름까지 붙인 자리라
//  같은 자리에서 둘이 겹치면 스탬프 쪽을 남긴다.
//
//  WalkFilm은 '그리는 법'만 안다. 무엇을 찍을지는 기록을 아는 이쪽에서 정해 넘긴다.
//

import Foundation
import CoreLocation

enum FilmMarks {

    /// 발견과 스탬프가 이 거리(m) 안에 있으면 같은 자리로 본다.
    /// 스탬프는 걷는 중에 한 손으로 찍으므로 실제 자리와 조금 어긋나 있다.
    static let sameSpot: CLLocationDistance = 150

    /// 앱이 알아본 발견에 새기는 그림 (도감에서 발견을 부를 때 쓰는 것과 같다)
    static let discoverySymbol = "sparkles"

    /// 이 기간의 필름에 찍을 자리들 (찍히는 차례대로)
    static func arrivals(
        visits: [Visit],
        stamps: [MapStamp],
        from start: Date,
        to end: Date
    ) -> [WalkFilm.Arrival] {
        let stamped = stamps.filter { $0.createdAt >= start && $0.createdAt <= end }

        let byHand = stamped.map {
            WalkFilm.Arrival(
                coordinate: $0.coordinate,
                name: $0.displayName,
                symbolName: $0.kind.symbolName,
                time: $0.createdAt
            )
        }

        let discovered = visits
            .filter { $0.isFirstVisit && $0.arrivalDate >= start && $0.arrivalDate <= end }
            .filter { visit in
                !stamped.contains {
                    visit.distance(latitude: $0.latitude, longitude: $0.longitude) < sameSpot
                }
            }
            .map {
                WalkFilm.Arrival(
                    coordinate: $0.coordinate,
                    name: name(of: $0),
                    symbolName: discoverySymbol,
                    time: $0.arrivalDate
                )
            }

        return (byHand + discovered).sorted { $0.time < $1.time }
    }

    /// 발견을 부를 이름.
    ///
    /// 내가 붙인 이름이 있으면 그것이 첫째다. 아직 이름을 안 붙였으면 동네 이름으로 부르고,
    /// 그마저 없으면 몇 번째 발견인지로 부른다 — 좌표를 적어 두면 읽는 사람이 아무것도 못 읽는다.
    private static func name(of visit: Visit) -> String {
        if let placeName = visit.placeName, !placeName.isEmpty { return placeName }
        if let district = visit.districtName, !district.isEmpty { return district }
        if visit.discoveryIndex > 0 { return "\(visit.discoveryIndex)번째 발견" }
        return "처음 온 자리"
    }
}
