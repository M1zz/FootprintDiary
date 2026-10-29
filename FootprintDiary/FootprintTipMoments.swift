//
//  FootprintTipMoments.swift
//  FootprintDiary
//
//  개발자 응원(팁)을 부탁할 순간. 이 앱이 그 사람에게 도움이 됐다는 것이 숫자로 보일 때만 묻는다.
//
//  숫자는 이미 쌓여 있는 것만 쓴다 — 걸은 날 수(탐험 일지의 날 카드 수)와 글을 남긴 일기 편 수.
//  카드는 탐험 일지 목록 맨 위에 선다. 얼마나 드물게 물을지는 LeeoKit 의 규칙(`LeeoTipAskPolicy`)이 정한다.
//

import Foundation
import LeeoKit

enum FootprintTipMoments {
    /// 걸은 날 수. 큰 것부터.
    static let walkedDays = [365, 100, 30]
    /// 글이 한 자라도 있는 일기 편 수. 큰 것부터.
    static let diaries = [100, 30, 10]

    /// 넘어선 순간, **인상적인 것부터**. 걸은 날이 앞이다(이 앱이 함께한 시간이 가장 분명하다).
    static func reached(walkedDays days: Int, diaries count: Int) -> [LeeoTipMoment] {
        let byDays = walkedDays.filter { days >= $0 }.map { threshold in
            LeeoTipMoment(id: "days.\(threshold)",
                          message: String(localized: "지금까지 \(days)일을 걸으며 지도를 그렸어요",
                                          comment: "Tip ask card: how many days the person has walked with the app"))
        }
        let byDiaries = diaries.filter { count >= $0 }.map { threshold in
            LeeoTipMoment(id: "diary.\(threshold)",
                          message: String(localized: "지금까지 일기 \(count)편을 남겼어요",
                                          comment: "Tip ask card: how many diary entries the person has written"))
        }
        return byDays + byDiaries
    }
}
