//
//  WalkDrawing.swift
//  FootprintDiary
//
//  일지에 하루 한 장씩 쌓이는 카드.
//  그날 걸은 것 중 '처음 걷는 길'이 얼마였는지를 보여준다.
//

import SwiftUI
import CoreLocation

/*
 [보관] 걸은 궤적을 선으로 그리던 뷰.
 경로를 선으로 남기는 표현은 다른 걷기 앱들이 이미 하는 것이라,
 카드는 '처음 걷는 길의 비율'로 바꿨다. 되살리려면 주석을 벗기고
 WalkDayCard 안의 NoveltyGauge 자리에 넣으면 된다.

struct WalkDrawing: View {
    let walk: DayWalk
    /// 선 굵기
    var lineWidth: CGFloat = 3

    /// 시작 색에서 끝 색으로 흐른다
    private let startColor = Color(red: 0.35, green: 0.85, blue: 0.72)
    private let endColor = Color(red: 1.0, green: 0.66, blue: 0.28)

    var body: some View {
        Canvas { context, size in
            let path = walk.drawingPath(in: size)
            guard path.count >= 2 else { return }

            let total = max(path.count - 1, 1)
            // 조각마다 색을 조금씩 옮겨 가며 그린다 (한 번에 그리면 그라데이션이 안 생긴다)
            for (index, pair) in zip(path, path.dropFirst()).enumerated() {
                var line = Path()
                line.move(to: pair.0)
                line.addLine(to: pair.1)
                context.stroke(
                    line,
                    with: .color(color(at: Double(index) / Double(total))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
            }

            // 출발점과 도착점
            if let first = path.first {
                context.fill(dot(at: first, radius: lineWidth * 1.6), with: .color(startColor))
            }
            if let last = path.last {
                context.fill(dot(at: last, radius: lineWidth * 1.9), with: .color(endColor))
                context.stroke(
                    dot(at: last, radius: lineWidth * 1.9),
                    with: .color(.white.opacity(0.9)),
                    lineWidth: 1.5
                )
            }
        }
        .drawingGroup()
    }

    /// 시작 색에서 끝 색으로 섞는다 (Color.mix는 iOS 18부터라 직접 계산한다)
    private func color(at progress: Double) -> Color {
        let t = min(max(progress, 0), 1)
        return Color(
            red: 0.35 + (1.0 - 0.35) * t,
            green: 0.85 + (0.66 - 0.85) * t,
            blue: 0.72 + (0.28 - 0.72) * t
        )
    }

    private func dot(at point: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
    }
}
*/

// MARK: - 하루 카드

/// 일지에 한 장씩 쌓이는 그날의 걸음.
/// 경로를 그리는 대신 '오늘 처음 걷는 길이 얼마였나'를 보여준다.
struct WalkDayCard: View {
    let entry: DayEntry
    let title: String
    /// 그날 쓴 한 줄 (없으면 비어 있다)
    let note: String
    let photo: UIImage?

    private var walk: DayWalk { entry.walk }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ZStack {
                if walk.distance > 0 {
                    NoveltyGauge(entry: entry)
                } else {
                    emptyDrawing
                }
            }
            .frame(height: 210)
            .frame(maxWidth: .infinity)

            footer
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer()
            if walk.distance > 0 {
                Text(timeRangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: 새로움 게이지

    /// 그날 걸은 것 중 처음 걷는 길이 차지한 몫
    private struct NoveltyGauge: View {
        let entry: DayEntry

        private var novelty: Double { entry.novelty }

        var body: some View {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 14)

                Circle()
                    .trim(from: 0, to: max(novelty, 0.004))
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(red: 0.35, green: 0.85, blue: 0.72),
                                Color(red: 0.55, green: 0.86, blue: 0.45),
                                Color(red: 1.0, green: 0.72, blue: 0.28)
                            ],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    // 12시 방향에서 시작하도록 돌린다
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(Int((novelty * 100).rounded()))%")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("처음 걷는 길")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 150, height: 150)
            .overlay(alignment: .bottom) {
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .offset(y: 26)
            }
        }

        private var summaryText: String {
            guard entry.newDistance >= 1 else { return "늘 걷던 길만 걸었어요" }
            return "\(distanceText(entry.walk.distance)) 중 \(distanceText(entry.newDistance))가 처음"
        }

        private func distanceText(_ meters: CLLocationDistance) -> String {
            meters < 1_000 ? "\(Int(meters))m" : String(format: "%.1fkm", meters / 1_000)
        }
    }

    private var emptyDrawing: some View {
        VStack(spacing: 6) {
            Image(systemName: "figure.walk")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("이 날은 걸음이 남지 않았어요")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if walk.distance > 0 {
                HStack(spacing: 16) {
                    stat(value: distanceText, label: "걸음")
                    if walk.duration > 60 {
                        stat(value: durationText, label: "시간")
                    }
                    if walk.walkCount > 1 {
                        Text("\(walk.walkCount)번 나갔어요")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            Text(note.isEmpty ? "한 줄 남겨보세요" : note)
                .font(.subheadline)
                .foregroundStyle(note.isEmpty ? .tertiary : .secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func stat(value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(value).font(.subheadline.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var distanceText: String {
        walk.distance < 1_000
        ? "\(Int(walk.distance))m"
        : String(format: "%.1fkm", walk.distance / 1_000)
    }

    private var durationText: String {
        let minutes = Int(walk.duration / 60)
        if minutes < 60 { return "\(minutes)분" }
        return "\(minutes / 60)시간 \(minutes % 60)분"
    }

    private var timeRangeText: String {
        guard let start = walk.startTime, let end = walk.endTime else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h:mm"
        return formatter.string(from: start) + " ~ " + formatter.string(from: end)
    }
}
