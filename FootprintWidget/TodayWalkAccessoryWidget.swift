//
//  TodayWalkAccessoryWidget.swift
//  FootprintWidget
//
//  잠금화면에 내거는 오늘 한 줄.
//
//  여기서는 그림을 그리지 않는다. 잠금화면 위젯은 빛깔을 쓸 수 없고(시스템이 한 색으로
//  칠해 버린다) 칸도 손톱만 해서, 오늘 걸음과 지난 걸음을 갈라 보여 줄 방법이 없다.
//  색으로 말하던 것을 색 없이 말하려 들면 결국 아무 말도 못 한다. 그래서 숫자만 말한다.
//
//  걷다가 주머니에서 꺼내 화면만 켜도 오늘 얼마나 그었는지 보이는 것 — 이 위젯이 하는
//  일은 그 하나다.
//

import WidgetKit
import SwiftUI

struct TodayWalkAccessoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWalkAccessory", provider: TodayWalkProvider()) { entry in
            TodayWalkAccessoryView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("오늘 걸음")
        .description("오늘 그은 길이를 잠금화면에 보여 줍니다.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct TodayWalkAccessoryView: View {
    let entry: TodayWalkEntry

    @Environment(\.widgetFamily) private var family

    private var snapshot: WalkSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .accessoryInline:
            // 인라인은 한 줄에 아이콘 하나와 글씨 몇 자가 전부다. 시간 옆에 붙으므로
            // '오늘'이라는 말을 넣어야 무엇의 거리인지 알 수 있다.
            Label("오늘 \(WalkFormat.distance(snapshot.newMeters))", systemImage: "shoeprints.fill")

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("오늘 그은 길", systemImage: "shoeprints.fill")
                    .font(.caption2)
                    .widgetAccentable()
                Text(WalkFormat.distance(snapshot.newMeters))
                    .font(.title2.weight(.semibold))
                Text(snapshot.newPlaces > 0 ? "처음 밟은 자리 \(snapshot.newPlaces)곳" : "걸은 거리 \(WalkFormat.distance(snapshot.walkedMeters))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -1) {
                    Image(systemName: "shoeprints.fill")
                        .font(.system(size: 11))
                        .widgetAccentable()
                    // 원형 칸은 지름이 작아 'km'까지 넣으면 숫자가 뭉갠다.
                    // 숫자와 단위를 위아래로 나눠 둘 다 읽히게 한다.
                    Text(WalkFormat.circularValue(snapshot.newMeters))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(WalkFormat.circularUnit(snapshot.newMeters))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - 거리를 글씨로

/// 거리를 어떻게 적을지 한곳에서 정한다.
/// 앱의 지도 화면과 같은 규칙이라, 위젯을 보고 앱을 열어도 숫자가 달라 보이지 않는다.
enum WalkFormat {
    static func distance(_ meters: Double) -> String {
        meters < 1_000 ? "\(Int(meters))m" : String(format: "%.1fkm", meters / 1_000)
    }

    /// 원형 칸의 숫자만
    static func circularValue(_ meters: Double) -> String {
        meters < 1_000 ? "\(Int(meters))" : String(format: "%.1f", meters / 1_000)
    }

    /// 원형 칸의 단위만
    static func circularUnit(_ meters: Double) -> String {
        meters < 1_000 ? "m" : "km"
    }
}
