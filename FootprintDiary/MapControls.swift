//
//  MapControls.swift
//  FootprintDiary
//
//  지도에서 여는 화면들의 이름.
//
//  기능이 하나 늘 때마다 지도 위에 단추가 하나씩 붙었고, 그다음에는 단추마다 켜고 끄는
//  스위치가 붙었다. 둘 다 걷어 냈다. 지도에는 일지·내가 찍은 곳·설정, 비춰보기·도장만
//  고정으로 두고, 나머지 화면은 설정의 '모아 보기'에서 연다. 고를 것이 없는 편이
//  고를 것이 열 개인 것보다 덜 헤맨다.
//

import Foundation

/// 지도 화면에서 여는 화면들. 설정이나 새 기능 안내에서도 같은 화면을 열 수 있게 이름을 붙였다.
enum AtlasDestination: String, CaseIterable, Identifiable {
    case diary
    case stampList
    case timeline
    case compass
    case film
    case period

    var id: String { rawValue }

    /// 지도 위에 단추가 늘 있는 화면인지. 설정의 '모아 보기'에는 이것이 아닌 것만 둔다.
    var isOnMap: Bool { self == .diary || self == .stampList }

    var title: String {
        switch self {
        case .diary: return String(localized: "일지")
        case .stampList: return String(localized: "내가 찍은 곳")
        case .timeline: return String(localized: "오늘의 발자취")
        case .compass: return String(localized: "개척 나침반")
        case .film: return String(localized: "그려지는 것 보기")
        case .period: return String(localized: "기간으로 좁혀 보기")
        }
    }

    var summary: String {
        switch self {
        case .diary: return String(localized: "날마다 쓴 일기와 사진")
        case .stampList: return String(localized: "찍은 자리를 갈래별로, 오늘 것만 따로")
        case .timeline: return String(localized: "오늘 들른 곳을 차례대로")
        case .compass: return String(localized: "어느 쪽으로 걸어야 새 자리가 나오는지")
        case .film: return String(localized: "내 지도가 그려지는 과정을 영상으로")
        case .period: return String(localized: "이번 주, 이번 달, 올해만 골라서")
        }
    }

    var symbol: String {
        switch self {
        case .diary: return "book.closed"
        case .stampList: return "list.bullet"
        case .timeline: return "clock"
        case .compass: return "location.north.line"
        case .film: return "play.rectangle"
        case .period: return "calendar"
        }
    }
}
