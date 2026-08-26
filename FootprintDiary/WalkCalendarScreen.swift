//
//  WalkCalendarScreen.swift
//  FootprintDiary
//
//  달력 한 장에 그날그날 그린 지도를 한 칸씩 담는다.
//
//  일지의 목록은 걸은 날만 위에서부터 늘어놓는다. 그것으로는 '이번 달에 며칠이나
//  걸었나', '어느 주에 발길이 뜸했나'를 볼 수 없다. 걷지 않은 날이 빈칸으로 남아
//  있어야 걸은 날이 무슨 뜻인지 보이기 때문이다. 달력은 그 빈칸을 보여 준다.
//
//  칸마다 숫자 대신 그날의 모양을 그린다. 숫자는 아무 날에나 있지만 모양은 그날
//  걸은 사람만 가진 것이다. 한 달을 펼쳐 놓으면 같은 골목을 도는 날들 사이에
//  어느 날 하루만 낯선 모양이 섞여 있는 것이 눈에 들어온다.
//
//  빛깔은 지도와 같은 규칙이다 — 오늘은 주묵, 지난 걸음은 남빛, 석 달이 지나면
//  잿빛. 그래서 달을 거슬러 넘길수록 달력이 통째로 빛이 빠진다.
//
//  그날 찍은 자리가 있으면 칸 귀퉁이에 도장을 하나 얹는다. 걸음의 모양만으로는
//  '어디를 걸었나'까지밖에 말하지 못하는데, 달력을 넘기며 찾는 것은 대개 '그날 어디에
//  갔었나'다. 그 답은 스스로 찍어 둔 자리에만 있다.
//

import SwiftUI

// MARK: - 그날의 모양

/// 하루치 걸음을 배경 지도 없이 궤적만으로 그린다.
///
/// 달력 칸에서도 하루 화면에서도 같은 것을 그린다. 작은 칸에서 본 모양과 눌러서
/// 크게 본 모양이 다르면, 눌러 보고 나서야 '내가 찾던 그날이 아니었네' 하게 된다.
struct DayWalkShape: View {
    let walk: DayWalk
    /// 이 그림이 그려진 날로부터 오늘까지의 싱싱함 (1이면 오늘, 0이면 석 달 넘음)
    let freshness: Double
    let isToday: Bool
    var lineWidth: CGFloat = 2.4
    var inset: CGFloat = 5

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let paths = walk.drawingPaths(in: size, inset: inset)
            guard !paths.isEmpty else { return }

            let color = Color(DotPalette.color(
                isToday: isToday,
                freshness: freshness,
                dark: colorScheme == .dark
            ))

            for points in paths {
                guard points.count >= 2 else {
                    // 한자리에서만 서성인 날. 선이 될 수 없으니 점 하나로 남긴다.
                    if let only = points.first {
                        context.fill(
                            Path(ellipseIn: CGRect(x: only.x - lineWidth, y: only.y - lineWidth,
                                                   width: lineWidth * 2, height: lineWidth * 2)),
                            with: .color(color)
                        )
                    }
                    continue
                }
                var path = Path()
                path.move(to: points[0])
                for point in points.dropFirst() { path.addLine(to: point) }
                context.stroke(
                    path,
                    with: .color(color),
                    // 모서리를 둥글게 깎아야 골목이 꺾이는 자리가 뾰족하게 튀지 않는다
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }
}

// MARK: - 달력

struct WalkCalendarScreen: View {
    /// 걸음이 남은 날들 (일지가 이미 셈해 둔 것을 받아 쓴다)
    let entries: [DayEntry]
    /// 그날 찍은 자리들 (날의 첫 시각으로 묶여 있다)
    let stampsByDay: [Date: [MapStamp]]
    /// 날을 눌렀을 때
    let onPick: (Date) -> Void

    @State private var month: Date = Calendar.current.startOfMonth(for: .now)

    private var calendar: Calendar { .current }

    /// 날짜로 바로 찾을 수 있게 묶어 둔다. 칸마다 목록을 훑으면 한 달에 마흔두 번 훑는다.
    private var byDay: [Date: DayEntry] {
        Dictionary(entries.map { (calendar.startOfDay(for: $0.walk.day), $0) },
                   uniquingKeysWith: { first, _ in first })
    }

    /// 걸음이 남은 가장 이른 달. 그보다 앞으로는 넘길 것이 없다.
    private var earliestMonth: Date? {
        entries.map(\.walk.day).min().map { calendar.startOfMonth(for: $0) }
    }

    private var thisMonth: Date { calendar.startOfMonth(for: .now) }

    var body: some View {
        VStack(spacing: 12) {
            header
            weekdayRow
            grid
            legend
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: 달 넘기기

    private var header: some View {
        HStack {
            Button {
                step(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            // 눌리지 않는 것은 눌리지 않아 보여야 한다. plain 단추는 못 쓰게 막아도
            // 겉모습이 그대로라, 눌러 보고서야 끝인 줄 알게 된다.
            .opacity(canStep(-1) ? 1 : 0.25)
            .disabled(!canStep(-1))

            Spacer()

            Text(monthTitle)
                .font(.headline)
                .contentTransition(.numericText())

            Spacer()

            Button {
                step(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .opacity(canStep(1) ? 1 : 0.25)
            .disabled(!canStep(1))
        }
        .buttonStyle(.plain)
        .font(.body.weight(.semibold))
    }

    private func step(_ months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: month) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { month = next }
    }

    /// 앞뒤로 더 넘길 곳이 있는지.
    /// 걸음이 하나도 없는 달을 끝없이 넘기게 두면 넘겨도 넘겨도 빈칸만 나온다.
    private func canStep(_ months: Int) -> Bool {
        guard let next = calendar.date(byAdding: .month, value: months, to: month) else { return false }
        if months > 0 { return next <= thisMonth }
        guard let earliest = earliestMonth else { return false }
        return next >= earliest
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = calendar.isDate(month, equalTo: thisMonth, toGranularity: .year)
            ? "M월"
            : "yyyy년 M월"
        return formatter.string(from: month)
    }

    // MARK: 칸

    /// 요일 머리글. 한 주가 무슨 요일부터인지는 지역 설정을 따르고,
    /// 글자는 앱의 다른 곳과 같이 우리말로 적는다 — 기기 언어가 영어라도
    /// 이 앱의 글은 전부 우리말이라 거기만 S M T가 서면 남의 화면 같다.
    private var weekdayRow: some View {
        let symbols = ["일", "월", "화", "수", "목", "금", "토"]
        return HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { column in
                // firstWeekday는 1이 일요일이다. 월요일부터 시작하는 지역이면 2로 온다.
                let weekday = (calendar.firstWeekday - 1 + column) % 7
                Text(symbols[weekday])
                    .font(.caption2)
                    .foregroundStyle(weekday == 0 ? Color.red.opacity(0.7) : .secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        let days = calendar.monthGrid(of: month)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            // 자리 번호를 이름표로 쓴다. 날짜를 이름표로 쓰면 달의 앞뒤를 메우는 빈 칸이
            // 모두 nil이라 이름표가 겹치고, 이름표가 겹치면 스위프트UI가 어느 칸에
            // 무엇을 그릴지 헷갈려 엉뚱한 칸이 비어 버린다. 실제로 그렇게 되어,
            // 오늘 걸은 그림이 그려졌다 안 그려졌다 했다.
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                cell(for: day)
            }
        }
    }

    @ViewBuilder
    private func cell(for day: Date?) -> some View {
        if let day {
            let entry = byDay[calendar.startOfDay(for: day)]
            let isFuture = day > Date.now
            Button {
                onPick(day)
            } label: {
                DayCell(
                    day: day,
                    walk: entry?.walk,
                    stamps: stampsByDay[calendar.startOfDay(for: day)] ?? [],
                    isToday: calendar.isDateInToday(day),
                    isFuture: isFuture
                )
            }
            .buttonStyle(.plain)
            .disabled(isFuture)
        } else {
            // 달의 앞뒤를 메우는 빈 칸. 이웃 달의 날짜를 흐리게 채우지 않는다 —
            // 이 화면은 '이 달에 며칠 걸었나'를 세는 자리라, 남의 달 숫자가 끼면 잘못 센다.
            Color.clear.aspectRatio(1, contentMode: .fit)
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            swatch(Color(DotPalette.today), "오늘")
            swatch(Color(DotPalette.past), "지난 걸음")
            swatch(Color(DotPalette.color(isToday: false, freshness: 0, dark: false)), "석 달 넘음")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    private func swatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(color).frame(width: 14, height: 3)
            Text(label)
        }
    }
}

// MARK: - 한 칸

private struct DayCell: View {
    let day: Date
    let walk: DayWalk?
    /// 그날 찍은 자리들 (찍은 차례)
    let stamps: [MapStamp]
    let isToday: Bool
    let isFuture: Bool

    private var calendar: Calendar { .current }

    /// 오늘로부터 얼마나 안 바랬는지. 지도의 자(WalkHeatmap.fadingSpan)와 같다.
    private var freshness: Double {
        WalkHeatmap.freshness(lastVisit: calendar.startOfDay(for: day), now: .now)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(InkStyle.paper).opacity(isFuture ? 0.35 : 1))

            if let walk, walk.hasDrawing {
                DayWalkShape(walk: walk, freshness: freshness, isToday: isToday)
            }

            // 날짜는 그림 위 왼쪽 위 귀퉁이에 작게 얹는다. 가운데에 두면 그림과
            // 겹쳐 둘 다 안 읽히고, 크게 두면 달력이 숫자판이 되어 버린다.
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 10, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color(DotPalette.today) : Color(InkStyle.ink).opacity(0.45))
                .padding(3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // 도장은 날짜의 대각선 반대편에 앉힌다. 같은 귀퉁이에 두면 한 자리 숫자와
            // 두 자리 숫자에서 겹치는 정도가 달라져 달력이 들쭉날쭉해 보인다.
            if let first = stamps.first {
                stampMark(first)
                    .padding(2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isToday ? Color(DotPalette.today).opacity(0.55) : Color(InkStyle.ink).opacity(0.07),
                    lineWidth: isToday ? 1.4 : 0.7
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// 칸 귀퉁이의 도장 하나.
    ///
    /// 여럿이어도 하나만 얹고 나머지는 숫자로 센다. 40pt 남짓한 칸에 도장을 여러 개
    /// 늘어놓으면 저마다 알아볼 수 없을 만큼 작아져, 있다는 것 말고는 아무것도 말하지
    /// 못한다. 그럴 바에는 하나를 알아볼 수 있게 얹고 '몇 곳 더'라고 적는 편이 낫다.
    @ViewBuilder
    private func stampMark(_ stamp: MapStamp) -> some View {
        HStack(spacing: 1) {
            if stamps.count > 1 {
                Text("+\(stamps.count - 1)")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color(InkStyle.ink).opacity(0.5))
            }
            StampSymbolBadge(stamp: stamp, side: 13, corner: 4)
        }
        .opacity(isFuture ? 0.4 : 1)
    }

    private var accessibilityLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일"
        let date = formatter.string(from: day)

        var parts: [String] = [date]
        if let walk, walk.distance >= 1 {
            parts.append(walk.distance < 1_000
                         ? "\(Int(walk.distance))미터"
                         : String(format: "%.1f킬로미터", walk.distance / 1_000))
        }
        // 도장은 이름으로 읽어 준다. '도장 2개'로는 어디였는지 알 수 없는데,
        // 눈으로 훑을 수 없는 사람에게는 그 이름이 이 칸의 거의 전부다.
        if !stamps.isEmpty {
            parts.append(stamps.prefix(3).map(\.displayName).joined(separator: ", "))
            if stamps.count > 3 { parts.append("외 \(stamps.count - 3)곳") }
        }
        if parts.count == 1 { return "\(date), 걸음 없음" }
        return parts.joined(separator: ", ")
    }
}

// MARK: - 달력 셈

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }

    /// 한 달을 주 단위로 채운 칸들. 달의 앞뒤를 메우는 자리는 비워 둔다.
    func monthGrid(of month: Date) -> [Date?] {
        let start = startOfMonth(for: month)
        guard let range = self.range(of: .day, in: .month, for: start) else { return [] }
        // 첫날이 무슨 요일인지에 따라 앞을 비운다 (firstWeekday는 지역마다 다르다)
        let leading = (component(.weekday, from: start) - firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<range.count {
            cells.append(date(byAdding: .day, value: offset, to: start))
        }
        // 마지막 주를 이레로 채운다. 남는 칸이 없으면 마지막 줄만 짧아져 격자가 어긋난다.
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }
}
