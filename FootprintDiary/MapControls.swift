//
//  MapControls.swift
//  FootprintDiary
//
//  지도 위에 무엇을 띄워 둘지.
//
//  기능이 하나 늘 때마다 지도 위에 단추가 하나씩 붙었다. 그러다 보니 백지도라고 부르는
//  화면이 정작 단추로 덮였다 — 도구 막대에 다섯, 아래에 셋, 오른쪽에 둘. 이 앱의 지도는
//  비어 있어야 걸은 자리가 보인다.
//
//  그래서 매일 쓰는 것만 지도에 남기고 나머지는 설정으로 옮겼다. 옮긴 것도 없어진 것이
//  아니라 설정의 '모아 보기'에서 바로 열 수 있고, 지도에 두고 싶으면 하나씩 다시 켤 수 있다.
//
//  도장과 설정 단추는 고를 수 없다. 도장은 이 앱에서 손으로 하는 단 하나의 일이고,
//  설정 단추가 사라지면 다시 켤 길이 없다.
//

import Foundation

/// 지도 위에 켜고 끌 수 있는 것들.
enum MapControl: String, CaseIterable, Identifiable {
    case diary
    case stampList
    case compass
    case film
    case period
    case peek
    case skin
    case neighborhood
    case scaleBar
    case zoom

    var id: String { rawValue }

    /// UserDefaults 열쇠. 화면과 설정이 같은 값을 보도록 여기 한 곳에서만 만든다.
    var storageKey: String { "map.show.\(rawValue)" }

    /// 처음 설치했을 때 지도에 보이는지.
    ///
    /// 나침반·필름은 가끔 꺼내 보는 화면이라 설정으로 보냈다. 배율과 확대·축소는 두 손가락으로
    /// 이미 되는 일을 단추로 한 번 더 둔 것이라 꺼 두었다.
    var isVisibleByDefault: Bool {
        switch self {
        // 기간·그림지도는 막 생긴 기능이라 우선 보이게 둔다
        case .diary, .stampList, .peek, .period, .skin, .neighborhood: return true
        case .compass, .film, .scaleBar, .zoom: return false
        }
    }

    var title: String {
        switch self {
        case .diary: return String(localized: "일지 단추")
        case .stampList: return String(localized: "내가 찍은 곳 단추")
        case .compass: return String(localized: "개척 나침반 단추")
        case .film: return String(localized: "그려지는 것 보기 단추")
        case .period: return String(localized: "기간 단추")
        case .skin: return String(localized: "그림지도 단추")
        case .neighborhood: return String(localized: "내 동네 테두리")
        case .peek: return String(localized: "비춰보기 단추")
        case .scaleBar: return String(localized: "배율 막대")
        case .zoom: return String(localized: "확대·축소 단추")
        }
    }

    var summary: String {
        switch self {
        case .diary: return String(localized: "왼쪽 위. 날마다 쓴 일기를 모아 봐요.")
        case .stampList: return String(localized: "왼쪽 위. 찍은 자리를 목록으로 봐요.")
        case .compass: return String(localized: "오른쪽 위. 어느 쪽이 아직 하얀지 가리켜요.")
        case .film: return String(localized: "오른쪽 위. 내 지도가 그려지는 것을 영상으로 봐요.")
        case .period: return String(localized: "왼쪽 아래. 이번 주, 이번 달처럼 기간으로 좁혀 봐요.")
        case .skin: return String(localized: "왼쪽 아래. 먹 지도와 그림지도를 오가요.")
        case .neighborhood: return String(localized: "걸은 자리로 내 동네가 어디까지인지 점선으로 그려요. 왼쪽 아래 단추로도 켜고 꺼요.")
        case .peek: return String(localized: "왼쪽 아래. 누르면 배경 지도가 비치고, 다시 누르면 종이로 돌아가요.")
        case .scaleBar: return String(localized: "왼쪽 아래. 지금 배율을 막대로 보여 줘요.")
        case .zoom: return String(localized: "오른쪽. 두 손가락 대신 눌러서 확대·축소해요.")
        }
    }

    var symbol: String {
        switch self {
        case .diary: return "book.closed"
        case .stampList: return "list.bullet"
        case .compass: return "location.north.line"
        case .film: return "play.rectangle"
        case .period: return "calendar"
        case .skin: return "mountain.2"
        case .neighborhood: return "circle.dashed"
        case .peek: return "map"
        case .scaleBar: return "ruler"
        case .zoom: return "plus.magnifyingglass"
        }
    }
}

/// 지도 화면에서 여는 화면들. 설정이나 새 기능 안내에서도 같은 화면을 열 수 있게 이름을 붙였다.
enum AtlasDestination: String, CaseIterable, Identifiable {
    case diary
    case stampList
    case timeline
    case compass
    case film
    case period

    var id: String { rawValue }

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
