//
//  FootprintWidgetBundle.swift
//  FootprintWidget
//
//  홈 화면과 잠금화면에 내거는 오늘 한 칸.
//
//  이 앱을 여는 까닭은 거의 언제나 하나다 — '오늘 어디를 걸었나'. 그 하나를 위해
//  앱을 켜고 지도가 그려지기를 기다려야 한다면, 걷는 도중에는 아무도 확인하지 않는다.
//  위젯은 그 한 물음만 떼어 내어 손이 닿는 자리에 둔다.
//
//  두 벌을 내건다. 홈 화면 것은 오늘 그린 모양을 보여 주고, 잠금화면 것은 숫자만
//  말한다. 잠금화면은 색을 쓸 수 없고 칸도 손톱만 해서 그림이 뭉개지기 때문이다.
//

import WidgetKit
import SwiftUI

@main
struct FootprintWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWalkWidget()
        TodayWalkAccessoryWidget()
    }
}
