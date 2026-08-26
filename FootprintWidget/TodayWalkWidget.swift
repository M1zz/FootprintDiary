//
//  TodayWalkWidget.swift
//  FootprintWidget
//
//  홈 화면에 내거는 오늘 한 칸 — 오늘 그린 모양과 그 길이.
//
//  앞세우는 숫자는 '걸은 거리'가 아니라 '오늘 그은 길'이다. 앱이 재는 것이 그것이기
//  때문이다 — 같은 길을 백 번 걸어도 지도는 자라지 않는다. 위젯에 걸은 거리를 크게
//  내걸면 위젯과 앱이 서로 다른 말을 하게 되고, 늘 다니던 길만 걸은 날 앱을 열었을 때
//  숫자가 줄어든 것처럼 보인다.
//

import WidgetKit
import SwiftUI

struct TodayWalkWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWalk", provider: TodayWalkProvider()) { entry in
            TodayWalkView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(InkStyle.paper)
                }
        }
        .configurationDisplayName("오늘 걸음")
        .description("오늘 그린 길과 그 길이를 보여 줍니다.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodayWalkView: View {
    let entry: TodayWalkEntry

    @Environment(\.widgetFamily) private var family

    private var snapshot: WalkSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .systemMedium: medium
        default: small
        }
    }

    // MARK: 소형 — 그림이 거의 전부고 숫자는 한 귀퉁이에 얹는다

    private var small: some View {
        ZStack(alignment: .bottomLeading) {
            map(dotRadius: 1.7)

            if !entry.isUnavailable {
                VStack(alignment: .leading, spacing: 0) {
                    Text(WalkFormat.distance(snapshot.newMeters))
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundStyle(Color(DotPalette.today))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                // 그림 위에 글씨가 바로 얹히면 점과 획이 섞여 둘 다 안 읽힌다.
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color(InkStyle.paper).opacity(0.82), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: 중형 — 그림과 숫자를 나란히

    private var medium: some View {
        HStack(spacing: 14) {
            map(dotRadius: 1.9)
                .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 0) {
                Text("오늘 그은 길")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(WalkFormat.distance(snapshot.newMeters))
                    .font(.system(size: 30, weight: .bold, design: .serif))
                    .foregroundStyle(Color(DotPalette.today))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Spacer(minLength: 6)

                if entry.isUnavailable {
                    Text("앱을 한 번 열어 주세요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    detail("걸은 거리", WalkFormat.distance(snapshot.walkedMeters))
                    detail("처음 밟은 자리", "\(snapshot.newPlaces)곳")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(InkStyle.ink))
        }
    }

    // MARK: 함께 쓰는 것

    /// 그림 자리. 걸음이 하나도 없으면 그릴 것이 없으므로 대신 한 줄로 말한다.
    @ViewBuilder
    private func map(dotRadius: CGFloat) -> some View {
        if snapshot.isEmpty {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(InkStyle.hill))
                Text(entry.isUnavailable ? "앱을 한 번 열어 주세요" : "아직 오늘 걸음이 없어요")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
        } else {
            TodayWalkMap(snapshot: snapshot, dotRadius: dotRadius)
        }
    }

    /// 그림 아래 한 줄. 처음 밟은 자리가 있는 날에는 그것을 앞세운다 —
    /// 새 길로 갔다는 것이 이 앱에서 가장 값진 소식이라서다.
    private var subtitle: String {
        snapshot.newPlaces > 0 ? "처음 \(snapshot.newPlaces)곳" : "오늘 그은 길"
    }
}
