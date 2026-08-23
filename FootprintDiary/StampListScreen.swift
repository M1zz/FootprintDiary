//
//  StampListScreen.swift
//  FootprintDiary
//
//  내가 찍어 둔 자리를 모아 보는 화면. 보는 길이 둘이다 — 갈래별과 오늘.
//
//  지도는 '어디'를 잘 보여 주지만 '무엇을 모았는지'는 보여 주지 못한다. 스탬프가 늘면
//  화면 밖으로 흩어져 버려서, 내가 카페를 몇 군데 찍었는지조차 지도를 훑어야 안다.
//  그래서 같은 기록을 한 번 더, 이번에는 세로로 세워 보여 준다.
//
//  갈래별은 '무엇을 모았나'를, 오늘은 '어디를 다녀왔나'를 답한다. 둘은 묻는 것이 달라
//  차례도 다르다. 갈래별은 최근에 찍은 것이 위로 오고, 오늘은 아침이 위다 — 하루는
//  아침부터 읽어야 이야기가 된다.
//
//  오늘 줄에는 내가 찍은 스탬프뿐 아니라 저절로 남은 머무름도 함께 세운다. 스탬프는
//  손으로 찍어야 남지만, 다녀온 곳은 찍지 않아도 다녀온 것이기 때문이다.
//

import SwiftUI
import SwiftData
import CoreLocation

struct StampListScreen: View {
    /// 고른 자리를 지도에서 보여 준다 (이 화면은 닫힌다)
    let onShowOnMap: (CLLocationCoordinate2D) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \MapStamp.createdAt, order: .reverse) private var stamps: [MapStamp]
    @Query(sort: \Visit.arrivalDate) private var visits: [Visit]

    /// 보는 길
    private enum Mode: String, CaseIterable, Identifiable {
        case group = "갈래별"
        case today = "오늘"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .group
    @State private var query = ""
    /// 골라 놓은 갈래. 비어 있으면 전부 본다.
    @State private var onlyGroup: StampGroup?
    /// '여기 기록해 둘까요'에 그러겠다고 한 자리. 스탬프 고르는 화면이 열린다.
    @State private var marking: Visit?

    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                modePicker
                switch mode {
                case .group: groupSide
                case .today: TodayTimeline(
                    stamps: todayStamps,
                    visits: todayVisits,
                    asking: asking,
                    onShowOnMap: { coordinate in
                        dismiss()
                        onShowOnMap(coordinate)
                    },
                    onDelete: delete,
                    onMark: { marking = $0 },
                    onLetGo: letGo
                )
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("내가 찍은 곳")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
                }
            }
            .sheet(item: $marking) { visit in
                StampPicker { kind in
                    // 찍힌 때를 머무르기 시작한 때로 맞춘다 — 그래야 오늘 줄의 제자리에 선다
                    let stamp = MapStamp(kind: kind, coordinate: visit.coordinate, createdAt: visit.arrivalDate)
                    modelContext.insert(stamp)
                    visit.askedAboutStamp = true
                    try? modelContext.save()
                }
            }
            .navigationDestination(for: MapStamp.self) { stamp in
                StampEditor(
                    stamp: stamp,
                    onShowOnMap: {
                        dismiss()
                        onShowOnMap(stamp.coordinate)
                    },
                    onDelete: { delete(stamp) }
                )
            }
        }
    }

    private var modePicker: some View {
        Picker("보는 길", selection: $mode) {
            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - 갈래별

    @ViewBuilder
    private var groupSide: some View {
        if stamps.isEmpty {
            hint(
                symbol: "seal",
                title: "아직 찍은 곳이 없어요",
                detail: "지도에서 스탬프를 찍으면 여기에 갈래별로 모입니다."
            )
        } else {
            VStack(spacing: 0) {
                groupFilter
                list
            }
            .searchable(text: $query, prompt: "이름·종류로 찾기")
        }
    }

    /// 스탬프가 하나라도 있는 갈래만 내놓는다. 빈 갈래를 늘어놓으면 고를 것이 많아 보이기만 한다.
    private var presentGroups: [StampGroup] {
        let names = Set(stamps.map { $0.kind.group })
        return StampCatalog.groups.filter { names.contains($0.name) }
    }

    @ViewBuilder
    private var groupFilter: some View {
        let groups = presentGroups
        if groups.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(title: "전부", symbol: "seal", isOn: onlyGroup == nil) { onlyGroup = nil }
                    ForEach(groups) { group in
                        chip(
                            title: group.name,
                            symbol: group.symbolName,
                            isOn: onlyGroup == group
                        ) {
                            onlyGroup = (onlyGroup == group ? nil : group)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    private func chip(title: String, symbol: String, isOn: Bool, act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(isOn ? .semibold : .regular))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(isOn ? Color.white : Color(InkStyle.ink))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(isOn ? Color(InkStyle.sealRed) : Color(InkStyle.ink).opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    /// 갈래별로 묶은 것. 갈래의 차례는 스탬프를 고를 때와 같다.
    private var sections: [(group: StampGroup, stamps: [MapStamp])] {
        let shown = filtered
        return StampCatalog.groups.compactMap { group in
            let mine = shown.filter { $0.kind.group == group.name }
            return mine.isEmpty ? nil : (group, mine)
        }
    }

    /// 찾는 말과 고른 갈래로 거른 것. 이름으로도 종류로도 찾을 수 있게 둔다 —
    /// 이름을 안 붙인 자리는 '카페'로밖에 부를 수 없다.
    private var filtered: [MapStamp] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return stamps.filter { stamp in
            if let onlyGroup, stamp.kind.group != onlyGroup.name { return false }
            guard !text.isEmpty else { return true }
            return stamp.placeName.localizedCaseInsensitiveContains(text)
                || stamp.kind.title.localizedCaseInsensitiveContains(text)
                || stamp.note.localizedCaseInsensitiveContains(text)
        }
    }

    @ViewBuilder
    private var list: some View {
        let sections = sections
        if sections.isEmpty {
            hint(
                symbol: "magnifyingglass",
                title: "찾는 것이 없어요",
                detail: "다른 말로 찾거나 갈래를 바꿔 보세요."
            )
        } else {
            List {
                ForEach(sections, id: \.group) { section in
                    Section {
                        ForEach(section.stamps) { stamp in
                            NavigationLink(value: stamp) {
                                StampRow(stamp: stamp)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(stamp)
                                } label: {
                                    Label("지우기", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(section.group.name)
                            Spacer()
                            Text("\(section.stamps.count)곳")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - 오늘 것 고르기

    private var todayStamps: [MapStamp] {
        stamps.filter { calendar.isDateInToday($0.createdAt) }
    }

    private var todayVisits: [Visit] {
        visits.filter { calendar.isDateInToday($0.arrivalDate) }
    }

    /// 오늘 오래 머물렀는데 아직 지도에 남기지 않은 자리 (많아야 두 곳)
    private var asking: [Visit] {
        StayPrompt.candidates(visits: visits, stamps: stamps, calendar: calendar)
    }

    /// "괜찮아요" — 이 자리는 다시 묻지 않는다
    private func letGo(_ visit: Visit) {
        visit.askedAboutStamp = true
        try? modelContext.save()
    }

    // MARK: - 빈 화면

    private func hint(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 일

    private func delete(_ stamp: MapStamp) {
        modelContext.delete(stamp)
        try? modelContext.save()
    }
}

// MARK: - 목록 한 줄

private struct StampRow: View {
    let stamp: MapStamp

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: stamp.kind.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(InkStyle.sealRed)))

            VStack(alignment: .leading, spacing: 2) {
                Text(stamp.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(PlaceText.subtitle(for: stamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let first = stamp.photosInOrder.first, let image = UIImage(data: first.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(alignment: .bottomTrailing) {
                        if stamp.photos.count > 1 {
                            Text("\(stamp.photos.count)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 3)
                                .background(Color.black.opacity(0.55), in: Capsule())
                                .padding(2)
                        }
                    }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 오늘 줄

/// 오늘 하루를 아침부터 아래로 늘어놓는다.
///
/// 왼쪽에 시각, 가운데에 줄과 매듭, 오른쪽에 그 자리. 줄이 이어져 있어야 '하루'로 읽힌다.
/// 매듭 모양으로 내가 찍은 것과 저절로 남은 것을 가른다 — 붉은 도장은 내 손이 간 자리다.
private struct TodayTimeline: View {
    let stamps: [MapStamp]
    let visits: [Visit]
    /// 물어볼 자리 (오래 머물렀는데 아직 안 남긴 곳)
    let asking: [Visit]
    let onShowOnMap: (CLLocationCoordinate2D) -> Void
    let onDelete: (MapStamp) -> Void
    let onMark: (Visit) -> Void
    let onLetGo: (Visit) -> Void

    /// 오늘 지나온 자리 하나
    private enum Moment: Identifiable {
        case stamp(MapStamp)
        case visit(Visit)

        var id: PersistentIdentifier {
            switch self {
            case .stamp(let stamp): return stamp.persistentModelID
            case .visit(let visit): return visit.persistentModelID
            }
        }

        var time: Date {
            switch self {
            case .stamp(let stamp): return stamp.createdAt
            case .visit(let visit): return visit.arrivalDate
            }
        }
    }

    private var moments: [Moment] {
        (stamps.map(Moment.stamp) + visits.map(Moment.visit)).sorted { $0.time < $1.time }
    }

    var body: some View {
        let moments = moments
        if moments.isEmpty && asking.isEmpty {
            empty
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(asking) { visit in
                        askCard(visit)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, asking.isEmpty ? 0 : 6)

                LazyVStack(spacing: 0) {
                    ForEach(Array(moments.enumerated()), id: \.element.id) { index, moment in
                        row(moment, isFirst: index == 0, isLast: index == moments.count - 1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - 물음 카드

    /// 오래 머문 자리 하나를 짚어 준다.
    ///
    /// 묻는 말은 '남겨 두세요'가 아니라 '안 남겨도 괜찮냐'다. 시키는 쪽이 아니라 확인하는
    /// 쪽이라야, 그냥 지나가는 것도 떳떳한 답이 된다.
    private func askCard(_ visit: Visit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "clock.badge.questionmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(InkStyle.sealRed))
                Text("여기 \(StayPrompt.stayText(visit)) 머무셨어요")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }

            Text(visit.displayName)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text("여기는 기록 안 해도 괜찮을까요?")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    onMark(visit)
                } label: {
                    Text("여기 남기기")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color(InkStyle.sealRed)))
                }
                .buttonStyle(.plain)

                Button {
                    onLetGo(visit)
                } label: {
                    Text("괜찮아요")
                        .font(.subheadline)
                        .foregroundStyle(Color(InkStyle.ink))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color(InkStyle.ink).opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(InkStyle.sealRed).opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - 한 줄

    @ViewBuilder
    private func row(_ moment: Moment, isFirst: Bool, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(PlaceText.time(moment.time))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
                .padding(.top, 12)

            rail(for: moment, isFirst: isFirst, isLast: isLast)

            content(for: moment)
                .padding(.bottom, isLast ? 0 : 10)
        }
    }

    private func rail(for moment: Moment, isFirst: Bool, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            thread.opacity(isFirst ? 0 : 1).frame(height: 10)
            knot(for: moment)
            thread.opacity(isLast ? 0 : 1).frame(maxHeight: .infinity)
        }
        .frame(width: 28)
    }

    private var thread: some View {
        Rectangle()
            .fill(Color(InkStyle.ink).opacity(0.18))
            .frame(width: 1.5)
    }

    @ViewBuilder
    private func knot(for moment: Moment) -> some View {
        switch moment {
        case .stamp(let stamp):
            Image(systemName: stamp.kind.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(InkStyle.sealRed)))
        case .visit:
            Image(systemName: "figure.walk")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(InkStyle.ink).opacity(0.6))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color(InkStyle.ink).opacity(0.10)))
        }
    }

    @ViewBuilder
    private func content(for moment: Moment) -> some View {
        switch moment {
        case .stamp(let stamp):
            NavigationLink(value: stamp) {
                card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(stamp.displayName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(PlaceText.subtitle(for: stamp, includeDay: false))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        photoStrip(stamp)
                    }
                }
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    onShowOnMap(stamp.coordinate)
                } label: {
                    Label("지도에서 보기", systemImage: "map")
                }
                Button(role: .destructive) {
                    onDelete(stamp)
                } label: {
                    Label("이 스탬프 지우기", systemImage: "trash")
                }
            }

        case .visit(let visit):
            Button {
                onShowOnMap(visit.coordinate)
            } label: {
                card {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(visit.displayName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(PlaceText.stayed(visit))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func photoStrip(_ stamp: MapStamp) -> some View {
        let photos = stamp.photosInOrder
        if !photos.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(photos, id: \.persistentModelID) { photo in
                        if let image = UIImage(data: photo.data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .frame(height: 64)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("오늘은 아직 다녀온 곳이 없어요")
                .font(.headline)
            Text("걷다가 스탬프를 찍으면 여기에 시간 순서대로 쌓입니다.\n머문 자리는 찍지 않아도 저절로 남습니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 글 다듬기

/// 목록과 줄에서 같은 규칙으로 쓰기 위한 한 곳.
enum PlaceText {
    /// 이름을 붙였으면 무엇으로 찍었는지가 곁줄로 내려온다 (지도에서 쓰는 규칙과 같다)
    static func subtitle(for stamp: MapStamp, includeDay: Bool = true) -> String {
        var parts: [String] = []
        if !stamp.placeName.isEmpty { parts.append(stamp.kind.title) }
        parts.append(includeDay ? day.string(from: stamp.createdAt) : stamp.kind.group)
        if !stamp.note.isEmpty { parts.append(stamp.note) }
        return parts.joined(separator: " · ")
    }

    /// 얼마나 머물렀는지. 아직 떠나지 않았으면 그렇게 적는다.
    static func stayed(_ visit: Visit) -> String {
        guard let departure = visit.departureDate else { return "머무는 중" }
        let minutes = Int(departure.timeIntervalSince(visit.arrivalDate) / 60)
        if minutes < 1 { return "잠깐 들름" }
        if minutes < 60 { return "\(minutes)분 머무름" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)시간 머무름" : "\(hours)시간 \(rest)분 머무름"
    }

    static func time(_ date: Date) -> String {
        clock.string(from: date)
    }

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일"
        return formatter
    }()

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h:mm"
        return formatter
    }()
}
