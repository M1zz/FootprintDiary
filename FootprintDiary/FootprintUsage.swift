//
//  FootprintUsage.swift
//  FootprintDiary
//
//  이 앱이 실제로 어떻게 쓰이는지 익명으로 셈해 둔다 (LeeoKit의 LeeoUsageReporter).
//
//  셈하는 까닭은 하나다 — 만든 사람이 쓰는 법과 쓰는 사람이 쓰는 법이 다르기 때문이다.
//  영상을 만드는 사람이 백에 하나뿐이라면 그 화면에 더 손대는 것은 헛일이고, 도장은
//  찍는데 일기를 아무도 안 쓴다면 일기가 어렵거나 눈에 안 띄는 것이다. 그런 것은
//  물어봐서는 알 수 없고, 물어볼 수 있는 사람은 이미 피드백을 보내는 사람뿐이다.
//
//  무엇을 보내지 '않는가'가 더 중요하다.
//
//  - 좌표는 한 톨도 보내지 않는다. 이 앱이 들고 있는 것 가운데 가장 사적인 것이 그것이고,
//    '어디를 걸었나'는 통계로 알 필요가 전혀 없다. 얼마나 걸었는지만 보낸다.
//  - 일기 글, 장소 이름, 사진은 보내지 않는다. 몇 편을 썼는지만 센다.
//  - 누구인지는 보내지 않는다. 설치할 때 뽑은 무작위 UUID 하나가 전부이고, 지웠다
//    다시 깔면 남남이 된다 (LeeoUsageReporter가 UserDefaults에 들고 있다).
//
//  보내는 곳은 피드백과 같은 아이클라우드 그릇(iCloud.com.Ysoup.FeedbackHub)이다.
//  개인 아이클라우드가 아니라 공용(public) 쪽이므로, 걸음 기록이 저장되는 곳과는
//  아예 다른 그릇이다. 두 그릇이 섞이지 않는 것이 이 설계의 요점이다.
//

import Foundation
import CoreLocation
import LeeoKit

enum FootprintUsage {

    /// 남길 만한 행동들.
    ///
    /// 글자를 직접 적지 않고 여기 모아 둔 까닭은, 부르는 자리마다 다르게 적으면
    /// 나중에 세어 볼 때 같은 행동이 두세 갈래로 흩어지기 때문이다. 오타 하나가
    /// 몇 달치 셈을 조용히 반토막 낸다.
    ///
    /// 자주 일어나는 것은 여기 두지 않는다 — 걸음 한 점마다 이벤트를 남기면 하루에
    /// 수백 건이 되어 셈이 아니라 짐이 된다. 그런 것은 아래 metrics로 한 번에 보낸다.
    enum Event: String {
        /// 지도에 낙관을 찍었다
        case stampPlaced = "stamp_placed"
        /// 하루를 영상으로 내보냈다
        case filmExported = "film_exported"
        /// 일기를 남겼다 (그날 처음 저장할 때만)
        case diaryWritten = "diary_written"
        /// 다녀온 자리에 이름을 붙였다
        case placeNamed = "place_named"
        /// 카메라로 찍어 그 자리만의 심볼을 만들었다
        case stickerMade = "sticker_made"
        /// 달력으로 지난 날들을 들춰 봤다
        case calendarOpened = "calendar_opened"
    }

    private static var reporter: LeeoUsageReporter {
        LeeoUsageReporter(spec: FootprintDiarySpec.self)
    }

    /// 행동 하나를 남긴다. 아이클라우드에 닿지 못하면 조용히 지나간다 —
    /// 통계 때문에 앱이 멎거나 사용자를 기다리게 하는 일은 없어야 한다.
    ///
    /// 리뷰를 물어볼 때를 재는 눈금(LeeoEngagement)도 여기서 함께 올린다. 둘 다
    /// '의미 있는 행동'을 세는 일이라, 부르는 자리를 하나로 두어야 어긋나지 않는다.
    static func log(_ event: Event) {
        _ = LeeoEngagement.shared.registerSignificantEvent()
        reporter.logEventInBackground(event.rawValue)
    }

    /// 이 설치가 지금 어디까지 왔는지 한 장으로 갱신한다.
    ///
    /// 설치마다 한 줄이고 덮어쓰기라, 몇 번을 불러도 줄이 늘지 않는다. 실제로 보내는
    /// 것은 열두 시간에 한 번뿐이고 나머지는 LeeoUsageReporter가 걸러 낸다.
    ///
    /// 값은 모두 '얼마나'다. 어디인지는 하나도 들어가지 않는다.
    static func report(
        atlasMeters: CLLocationDistance,
        walkedDays: Int,
        stamps: Int,
        places: Int,
        diaries: Int
    ) {
        reporter.reportInBackground(metrics: [
            // km로 보낸다. m로 보내면 자릿수가 커서 통계 화면에서 읽기 어렵다.
            "atlas_km": (atlasMeters / 1_000).rounded(),
            "walked_days": Double(walkedDays),
            "stamps": Double(stamps),
            "places": Double(places),
            "diaries": Double(diaries)
        ])
    }
}
