//
//  AtlasPeriod.swift
//  FootprintDiary
//
//  지도를 한 기간으로 좁혀 보는 거름망.
//
//  지도는 처음부터 지금까지를 한 장에 겹쳐 그린다. 오래 쓸수록 그 한 장이 짙어져서
//  "올여름에는 어디를 걸었지"를 물으면 답이 묻힌다. 그래서 기간을 하나 고르면 그 사이에
//  걸은 길과 그 사이에 찍은 도장만 남긴다.
//
//  날 단위로 끊는다. 걸음은 하루치(DayWalk)로 묶여 있고, '처음 그은 길'도 날마다 센다.
//  시각까지 자르면 하루치 산책이 반토막 나고 그은 길이도 어긋난다.
//

import SwiftUI

enum AtlasPeriod: Hashable {
    case all
    case thisWeek
    case thisMonth
    case thisYear
    /// 직접 고른 날짜. 두 날 모두 그날 하루를 통째로 넣는다.
    case custom(start: Date, end: Date)

    static let presets: [AtlasPeriod] = [.all, .thisWeek, .thisMonth, .thisYear]

    var title: LocalizedStringKey {
        switch self {
        case .all: return "전체"
        case .thisWeek: return "이번 주"
        case .thisMonth: return "이번 달"
        case .thisYear: return "올해"
        case .custom: return "직접 정한 기간"
        }
    }

    var isAll: Bool { self == .all }

    /// 이 기간이 덮는 시간. 전체면 nil — 거를 것이 없다.
    func interval(now: Date = .now, calendar: Calendar = .current) -> DateInterval? {
        switch self {
        case .all:
            return nil
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now)
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now)
        case .thisYear:
            return calendar.dateInterval(of: .year, for: now)
        case let .custom(start, end):
            let first = calendar.startOfDay(for: min(start, end))
            let last = calendar.startOfDay(for: max(start, end))
            // 끝 날도 하루를 통째로 넣는다
            let after = calendar.date(byAdding: .day, value: 1, to: last) ?? last
            return DateInterval(start: first, end: after)
        }
    }

    /// 사람이 읽는 날짜 범위. 예) 10월 1일 ~ 10월 31일
    func rangeText(now: Date = .now, calendar: Calendar = .current) -> String? {
        guard let interval = interval(now: now, calendar: calendar) else { return nil }
        let lastDay = interval.end.addingTimeInterval(-1)
        let sameYear = calendar.isDate(interval.start, equalTo: lastDay, toGranularity: .year)
            && calendar.isDate(lastDay, equalTo: now, toGranularity: .year)
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        let format = sameYear ? style : style.year()
        if calendar.isDate(interval.start, inSameDayAs: lastDay) {
            return interval.start.formatted(format)
        }
        return "\(interval.start.formatted(format)) ~ \(lastDay.formatted(format))"
    }
}

/// 기간을 고르는 시트
struct AtlasPeriodPicker: View {
    @Binding var period: AtlasPeriod
    @Environment(\.dismiss) private var dismiss

    @State private var customStart: Date
    @State private var customEnd: Date
    @State private var isCustom: Bool

    init(period: Binding<AtlasPeriod>) {
        _period = period
        let calendar = Calendar.current
        if case let .custom(start, end) = period.wrappedValue {
            _customStart = State(initialValue: start)
            _customEnd = State(initialValue: end)
            _isCustom = State(initialValue: true)
        } else {
            // 처음 직접 고를 때는 지난 30일을 펼쳐 둔다. 오늘 하루만 잡혀 있으면
            // 날짜 두 개를 다 손대야 해서 번거롭다.
            let today = calendar.startOfDay(for: .now)
            _customStart = State(initialValue: calendar.date(byAdding: .day, value: -29, to: today) ?? today)
            _customEnd = State(initialValue: today)
            _isCustom = State(initialValue: false)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(AtlasPeriod.presets, id: \.self) { preset in
                        Button {
                            period = preset
                            dismiss()
                        } label: {
                            row(title: preset.title,
                                detail: preset.rangeText(),
                                isSelected: !isCustom && period == preset)
                        }
                    }
                    Button {
                        withAnimation { isCustom = true }
                    } label: {
                        row(title: AtlasPeriod.custom(start: customStart, end: customEnd).title,
                            detail: nil,
                            isSelected: isCustom)
                    }
                } footer: {
                    Text("고른 기간에 걸은 길과 그 기간에 찍은 도장만 지도에 남습니다.")
                        .font(.body)
                }

                if isCustom {
                    Section {
                        DatePicker("시작", selection: $customStart, in: ...Date.now, displayedComponents: .date)
                        DatePicker("끝", selection: $customEnd, in: customStart...Date.now, displayedComponents: .date)
                        Button {
                            period = .custom(start: customStart, end: customEnd)
                            dismiss()
                        } label: {
                            Text("이 기간으로 보기")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .font(.body)
                }
            }
            .navigationTitle("기간으로 보기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .onChange(of: customStart) {
                if customEnd < customStart { customEnd = customStart }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(title: LocalizedStringKey, detail: String?, isSelected: Bool) -> some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(InkStyle.sealRed))
                .opacity(isSelected ? 1 : 0)
        }
        .contentShape(Rectangle())
    }
}
