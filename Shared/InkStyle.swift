//
//  InkStyle.swift
//  FootprintDiary
//
//  이 지도가 쓰는 먹과 종이의 빛깔.
//
//  앱과 위젯이 함께 쓰므로 Shared에 둔다. 위젯이 제 빛깔을 따로 들고 있으면
//  잠금화면에 뜬 오늘 걸음과 앱을 열어 본 오늘 걸음이 서로 다른 붉은색이 된다.
//
//  지도·산·물·도장·필름이 모두 같은 빛을 나눠 쓰므로 한곳에 모아 둔다. 어느 한 화면
//  안에 두면 그 화면을 고칠 때마다 온 앱의 빛깔이 함께 흔들리고, 무엇보다 빛깔 하나
//  고치자고 지도 전체를 열어야 한다.
//
//  걸은 자리에 찍는 점의 빛깔은 여기 없다. 그것은 '오늘인가'와 '얼마나 바랬는가'에 따라
//  셈으로 뽑히므로 DotPalette.swift가 맡는다.
//

import UIKit

/// 먹과 종이의 빛깔
enum InkStyle {
    /// 먹 — 밝은 배경에선 짙은 먹, 어두운 배경에선 종이빛으로 뒤집는다
    static let ink = UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.97, green: 0.94, blue: 0.87, alpha: 1)
        : UIColor(red: 0.11, green: 0.12, blue: 0.16, alpha: 1)
    }

    /// 배경 지도를 덮는 종이. 옛 지도의 닥종이처럼 아주 옅은 누런빛.
    static let paper = UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1)
        : UIColor(red: 0.96, green: 0.95, blue: 0.91, alpha: 1)
    }

    /// 오늘 지난 자리는 주묵(붉은 먹)으로 찍는다.
    /// 옛 지도가 길을 붉은 선으로 표시하던 것과 같고, 오늘 무엇을 더했는지 바로 보인다.
    static let vermilion = UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 1.0, green: 0.45, blue: 0.35, alpha: 1)
        : UIColor(red: 0.78, green: 0.20, blue: 0.13, alpha: 1)
    }

    /// 물빛. 종이에 미리 인쇄돼 있는 무늬라 먹보다 한참 옅다.
    /// 걸어서 채울 수 없는 곳이므로 눈에 먼저 들어오면 안 되고, 그저 뭍의 테두리를 잡아 준다.
    static let water = UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.13, green: 0.19, blue: 0.26, alpha: 1)
        : UIColor(red: 0.80, green: 0.86, blue: 0.89, alpha: 1)
    }

    /// 산·숲빛. 물보다 한참 옅다.
    ///
    /// 산자락에서는 화면의 거의 전부가 이 빛이 된다. 짙게 깔면 종이가 사라지고
    /// 발자국이 묻힌다. 게다가 산은 물과 달리 걸어서 갈 수 있는 곳이라,
    /// 여기는 '아직 채울 몫이 남은 자리'로 보여야 한다. 그래서 겨우 알아볼 만큼만 얹는다.
    static let hill = UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.12, green: 0.15, blue: 0.11, alpha: 1)
        : UIColor(red: 0.91, green: 0.92, blue: 0.85, alpha: 1)
    }

    /// 낙관을 찍는 인주 빛. 주묵보다 짙어 점과 도장이 섞이지 않는다.
    static let sealRed = UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.86, green: 0.30, blue: 0.24, alpha: 1)
        : UIColor(red: 0.66, green: 0.14, blue: 0.11, alpha: 1)
    }
}
