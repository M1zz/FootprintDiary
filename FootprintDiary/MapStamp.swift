//
//  MapStamp.swift
//  FootprintDiary
//
//  내 지도에만 있는 표시 — 스탬프.
//
//  무엇을 새길지는 세 가지로 걸렀다.
//   1. 걸어야만 알 수 있는가 — 차나 항공사진, 거리뷰로 알 수 있으면 뺀다
//   2. 한 손으로 한 번에 찍을 수 있는가 — 걷는 중에는 손이 하나뿐이다
//   3. 나중에 내가 실제로 다시 찾아볼 것인가
//
//  세 번째가 가장 많이 걸러 냈다. "여기 예뻤다" 같은 건 남기기는 쉬운데 다시 찾아보지
//  않는다. 그래서 감상이 아니라 쓸모로 골랐다 — 옛 지도가 그랬듯이.
//
//  종류는 StampCatalog에 값의 목록으로 두었다 (200가지가 넘는다).
//
//  찍는 자리는 두 가지다. 걷는 중에는 지금 선 자리에 바로 찍고, 지도를 길게 눌러
//  원하는 지점에 찍을 수도 있다. 찍은 뒤에도 끌어서 자리를 고칠 수 있다.
//  걸을 때는 한 손뿐이라 정확히 짚을 수 없고, 돌아와서 다듬는 편이 실제로 더 정확하다.
//

import Foundation
import SwiftData
import CoreLocation

@Model
final class MapStamp {
    /// StampKind.id. 나중에 종류가 늘거나 줄어도 저장된 값이 깨지지 않도록 문자열로 둔다.
    var kindID: String = "other"
    var latitude: Double = 0
    var longitude: Double = 0
    var createdAt: Date = Date.now
    /// 덧붙인 한 줄 (없어도 된다)
    var note: String = ""

    init(kind: StampKind, coordinate: CLLocationCoordinate2D, createdAt: Date = .now, note: String = "") {
        self.kindID = kind.id
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.createdAt = createdAt
        self.note = note
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// 저장된 값이 알 수 없는 종류이면 '그 밖'으로 떨어뜨린다 (앱이 깨지지 않게)
    var kind: StampKind {
        StampCatalog.kind(id: kindID)
    }
}
