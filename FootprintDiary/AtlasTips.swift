//
//  AtlasTips.swift
//  FootprintDiary
//
//  지도 위 단추에 한 번씩 붙는 작은 안내 (TipKit).
//
//  단추를 줄이고 나니 남은 단추가 무슨 일을 하는지가 더 중요해졌다. 특히 비춰보기는
//  눌러야 아는 것이 아니라 '누르고 있어야' 아는 것이라, 한 번 톡 눌러 보고 아무 일도
//  없다고 여기기 쉽다.
//
//  하루에 하나만 뜬다(FootprintDiaryApp의 Tips.configure). 걷는 중에 안내가 줄줄이
//  나오면 그건 안내가 아니라 방해다. 그리고 지도가 비어 있는 동안에는 띄우지 않는다 —
//  그때는 빈 지도 안내가 이미 한가운데 서 있다.
//

import SwiftUI
import TipKit

enum AtlasTips {
    /// 지도가 다 그려졌고, 가운데 안내나 다른 장이 떠 있지 않은지.
    /// 이 값이 참일 때만 안내가 뜬다.
    @Parameter static var isMapIdle: Bool = false
}

struct PeekTip: Tip {
    var title: Text { Text("누르면 지도가 비쳐요") }
    var message: Text? { Text("다시 누르면 종이로 돌아가요. 지금 어디쯤인지 확인할 때 써 보세요.") }
    var image: Image? { Image(systemName: "map") }

    var rules: [Rule] {
        #Rule(AtlasTips.$isMapIdle) { $0 == true }
    }
}

struct MapControlsTip: Tip {
    var title: Text { Text("지도 단추는 설정에서 골라요") }
    var message: Text? { Text("지도에 띄워 둘 단추를 고르고, 꺼 둔 화면도 설정에서 바로 열 수 있어요.") }
    var image: Image? { Image(systemName: "slider.horizontal.3") }

    var rules: [Rule] {
        #Rule(AtlasTips.$isMapIdle) { $0 == true }
    }
}
