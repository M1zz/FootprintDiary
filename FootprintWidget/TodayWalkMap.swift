//
//  TodayWalkMap.swift
//  FootprintWidget
//
//  손톱만 한 칸에 그리는 오늘 지도.
//
//  앱의 지도와 같은 규칙으로 그린다 — 오늘 걸은 자리는 주묵, 지난 걸음은 남빛,
//  종이는 닥종이빛. 배경 지도는 없다. 위젯 칸에서 지형지물은 어차피 읽히지 않고,
//  무엇보다 잠금화면에 내가 사는 동네의 지명이 박혀 있게 하고 싶지 않다.
//
//  Canvas로 그린다. 점이 수백 개인데 Circle 뷰를 수백 개 쌓으면 위젯이 그림을
//  내주기 전에 시간이 다한다.
//

import SwiftUI

struct TodayWalkMap: View {
    let snapshot: WalkSnapshot
    /// 점 하나의 반지름(pt). 칸이 클수록 굵게 그려야 길로 보인다.
    var dotRadius: CGFloat = 1.6

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let placed = WalkSnapshotLayout.lay(snapshot, in: size, inset: dotRadius * 2)
            let dark = colorScheme == .dark

            // 지난 걸음을 먼저 깔고 오늘 걸음을 위에 얹는다. 앱의 지도와 같은 차례다 —
            // 뒤바꾸면 오늘 걸은 자리가 어제 점에 반쯤 덮인다.
            //
            // 지난 걸음은 반쯤 바랜 것으로 그린다. 위젯이 말하려는 것은 오늘 하나이고,
            // 배경은 '여기가 어디쯤인지'만 알려 주면 된다.
            draw(placed.past, in: &context,
                 color: DotPalette.color(isToday: false, freshness: 0.45, dark: dark),
                 radius: dotRadius * 0.8, opacity: 0.55)

            draw(placed.today, in: &context,
                 color: DotPalette.color(isToday: true, freshness: 1, dark: dark),
                 radius: dotRadius, opacity: 1)
        }
    }

    private func draw(
        _ points: [CGPoint],
        in context: inout GraphicsContext,
        color: UIColor,
        radius: CGFloat,
        opacity: Double
    ) {
        guard !points.isEmpty else { return }
        // 한 색으로 한 번에 칠한다. 점마다 색을 새로 만들면 수백 번 같은 일을 되풀이한다.
        var path = Path()
        for point in points {
            path.addEllipse(in: CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
        }
        context.fill(path, with: .color(Color(color).opacity(opacity)))
    }
}
