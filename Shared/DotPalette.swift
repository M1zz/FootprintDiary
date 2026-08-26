//
//  DotPalette.swift
//  FootprintDiary
//
//  걸은 자리에 찍는 점의 빛깔.
//
//  지도(WalkHeatmap)와 위젯이 함께 쓰므로 Shared에 둔다. 위젯이 제 빛깔을 따로 들고
//  있으면 잠금화면에 뜬 오늘 걸음과 앱을 열어 본 오늘 걸음이 서로 다른 붉은색이 된다.
//
//  먹·종이·물·산처럼 '그려진 것'의 빛깔은 InkStyle.swift에 있다. 이쪽은 '걸어서 채운
//  것'의 빛깔이라, 언제 밟았느냐에 따라 셈으로 달라진다는 점이 다르다.
//

import UIKit

// MARK: - 오늘과 지난날, 그리고 잿빛

/// 걸은 자리에 찍을 빛깔을 고른다.
///
/// 고르는 것은 둘뿐이다 — 오늘 밟았으면 주묵, 아니면 남빛. 그 다음은 얼마나 바랬는지만 남는다.
///
/// 날마다 다른 색을 뽑던 때가 있었다. 지도는 알록달록했지만 어느 색이 무슨 날인지
/// 아무도 읽어 내지 못했고, 게다가 어제와 오늘이 이웃한 빛깔로 뽑히면 둘이 아예
/// 구별되지 않았다. 빛깔이 뜻을 하나만 지고 있어야 그 뜻이 눈에 들어온다.
enum DotPalette {

    /// 오늘 걸은 자리의 빛깔 (주묵, 붉은 먹). 색상환에서의 자리.
    ///
    /// 날마다 똑같다. 옛 지도가 길을 붉은 선으로 표시하던 것과 같은 자리에 두어,
    /// 지도의 다른 붉은 것들(낙관·오늘 자취)과 한 식구로 보인다.
    static let todayHue: CGFloat = 0.02

    /// 지난 걸음의 빛깔 (남빛).
    ///
    /// 색상환에서 주묵의 건너편이다. 이웃한 빛깔을 쓰면 오늘과 어제가 붙어 보여
    /// 색을 둘로 줄인 보람이 없다. 물빛(InkStyle.water)보다는 한참 짙어,
    /// 종이에 미리 인쇄된 무늬와 걸어서 채운 자리가 섞이지 않는다.
    static let pastHue: CGFloat = 0.58

    /// 갓 밟았을 때의 채도. 원색이라 부를 만큼은 올리되, 종이 위에서 눈이 아프지 않은 선.
    static let vividSaturation: CGFloat = 0.88

    /// 갓 밟은 점의 밝기. 종이 위에서 원색이 원색답게 보이는 자리.
    static let freshBrightness: (light: CGFloat, dark: CGFloat) = (0.78, 0.95)

    /// 온전히 바랜 점의 밝기. 그 자리에서 채도가 0이 되므로 이 값이 곧 잿빛의 농도다.
    ///
    /// 밝은 종이에서는 어둡게, 어두운 종이에서는 밝게 잡는다. 한쪽에 맞춰 두면
    /// 다른 쪽에서 옛 발자국이 배경에 묻혀 아예 없는 것처럼 보인다.
    static let fadedBrightness: (light: CGFloat, dark: CGFloat) = (0.42, 0.70)

    /// 한 점의 빛깔.
    ///
    /// 바래는 것은 '색이 빠지는 것'이다. 채도를 0으로 끌면 그 자리가 곧 잿빛이라,
    /// 원색과 잿빛을 따로 섞을 것 없이 한 줄로 이어진다. 석 달이 지난 자리는
    /// freshness가 0이므로 주묵이든 남빛이든 똑같은 잿빛으로 만난다.
    ///
    /// - Parameter dark: 어두운 종이인지. 그리는 중에는 화면 설정을 물어볼 수 없어 미리 받는다.
    static func color(isToday: Bool, freshness: Double, dark: Bool) -> UIColor {
        let alive = CGFloat(min(max(freshness, 0), 1))
        let fresh = dark ? freshBrightness.dark : freshBrightness.light
        let faded = dark ? fadedBrightness.dark : fadedBrightness.light
        return UIColor(
            hue: isToday ? todayHue : pastHue,
            saturation: vividSaturation * alive,
            brightness: faded + (fresh - faded) * alive,
            alpha: 1
        )
    }

    /// 오늘 걸은 자리의 빛깔. 지도의 갓 찍은 점과 같은 빛이라 글과 지도가 이어진다.
    static let today = UIColor { traits in
        color(isToday: true, freshness: 1, dark: traits.userInterfaceStyle == .dark)
    }

    /// 지난 걸음의 빛깔, 바래기 전 그대로.
    static let past = UIColor { traits in
        color(isToday: false, freshness: 1, dark: traits.userInterfaceStyle == .dark)
    }
}
