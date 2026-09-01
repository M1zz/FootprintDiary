//
//  DayTimelineScreen.swift
//  FootprintDiary
//
//  오늘의 발자취 — 오늘 들른 곳을 차례대로 세운 화면.
//
//  하루를 되짚을 때 사람이 기억하는 단위는 지나온 길이 아니라 들른 곳이다. 지도는
//  '어디를 지났나'를 한 장으로 보여 주지만, 저녁에 하루를 돌아보며 묻는 것은 대개
//  '오늘 어디어디를 갔더라'이다. 선의 모양으로는 그 답이 나오지 않는다.
//
//  그래서 이 화면의 뼈대는 자리다. 들른 곳이 위에서부터 서고, 그 사이를 '얼마를
//  걸어서 왔다'가 잇는다. 시각은 왼쪽 기둥에 세워 두어, 훑어 내리는 것만으로 하루가
//  아침에서 저녁으로 흐른다.
//
//  여기서 한 가지를 더 한다 — 물어보기.
//
//  스탬프의 '다녀왔다'는 이제껏 그 자리에 서 있을 때만 누를 수 있었다(StampPicker).
//  그것이 옳다. 손가락이 아니라 발걸음을 세는 숫자여야 하니까. 그런데 그 탓에 정작
//  다녀온 날에는 앱을 꺼내 들지 않아 아무것도 안 남고, 나중에 지도를 열면 '한 번
//  갔던 자리'로 그대로 있다.
//
//  걸음은 이미 알고 있다. 그 자리에서 한 시간을 머물렀다는 것을. 그래서 셈이 짚어
//  내고, 사람이 답한다. 셈이 혼자 남기지 않는 까닭은 짚어 낸 것이 틀릴 수 있기
//  때문이다 — 카페 위층 사무실에 앉아 있었을 수도 있고, 그 앞 정류장에서 버스를
//  기다렸을 수도 있다. 틀린 채로 쌓인 숫자는 없는 것보다 나쁘다.
//
//  한 번 물어본 자리는 그날 다시 묻지 않는다(MapStamp.visitAskedAt). '아니에요'를
//  듣고도 또 묻는 것이 가장 성가시다.
//

import SwiftUI
import SwiftData
import CoreLocation

struct DayTimelineScreen: View {

    /// 오늘 찍힌 걸음만 읽는다. 전부 읽어 와 걸러도 답은 같지만, 쌓인 날이 길어질수록
    /// 화면 하나 여는 데 몇 만 개를 깨우게 된다.
    @Query private var track: [TrackPoint]
    @Query private var visits: [Visit]
    @Query(sort: \MapStamp.createdAt) private var stamps: [MapStamp]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [Entry] = []
    /// 오늘 걸은 총 거리(m). 화면을 그릴 때마다 다시 재지 않도록 세울 때 함께 담는다.
    @State private var walkedToday: CLLocationDistance = 0
    /// 아직 스탬프가 없는 자리에 찍으려고 골라 둔 좌표
    @State private var pendingCoordinate: StampSpot?

    init(now: Date = .now) {
        let start = Calendar.current.startOfDay(for: now)
        _track = Query(
            filter: #Predicate<TrackPoint> { $0.timestamp >= start },
            sort: \TrackPoint.timestamp
        )
        _visits = Query(
            filter: #Predicate<Visit> { $0.arrivalDate >= start },
            sort: \Visit.arrivalDate
        )
    }

    /// 타임라인 한 줄과, 그 자리에 이미 찍혀 있는 스탬프.
    ///
    /// 셈(DayTimeline)은 저장소를 모르게 두었으므로 자리와 스탬프를 맞붙이는 일은
    /// 여기서 한다. 화면을 그릴 때마다 다시 맞추면 스탬프 수만큼 거리를 재게 되어,
    /// 한 번 맞춰 두고 들고 있는다.
    private struct Entry: Identifiable {
        let id: UUID
        let row: DayTimeline.Row
        let stamp: MapStamp?
    }

    private var calendar: Calendar { .current }

    /// 시각을 세우는 왼쪽 기둥의 너비.
    ///
    /// '오전 9:11'이 접히지 않는 폭이다. 자리 줄과 걸음 줄이 같은 자를 써야
    /// 표시와 점선이 한 줄로 내려온다.
    private static let timeColumnWidth: CGFloat = 72

    /// 아직 답하지 않은 물음이 몇 개인지
    private var pendingCount: Int {
        entries.filter { asks($0) }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    emptyState
                } else {
                    timeline
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("오늘의 발자취")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
            .sheet(item: $pendingCoordinate) { spot in
                StampPicker { kind in
                    modelContext.insert(MapStamp(kind: kind, coordinate: spot.coordinate))
                    try? modelContext.save()
                    FootprintUsage.log(.stampPlaced)
                }
            }
        }
        .task { FootprintUsage.log(.timelineOpened) }
        // 걸음이 늘거나 자리가 늘면 다시 세운다. 스탬프 수를 함께 보는 까닭은, 없던
        // 자리에 스탬프를 찍고 돌아왔을 때 그 줄이 여전히 '이름 없는 자리'로 남아
        // 있으면 방금 한 일이 아무 일도 아닌 것처럼 보이기 때문이다.
        // (답을 하고 난 뒤에는 답한 자리에서 곧바로 다시 세운다)
        .task(id: "\(track.count)-\(visits.count)-\(stamps.count)") { rebuild() }
    }

    // MARK: - 세우기

    private func rebuild() {
        let points = DayWalk.values(of: track)
        let stays = visits.map {
            DayTimeline.Stay(
                coordinate: $0.coordinate,
                arrival: $0.arrivalDate,
                departure: $0.departureDate,
                name: name(of: $0)
            )
        }
        entries = DayTimeline.rows(track: points, stays: stays).map { row in
            Entry(id: row.id, row: row, stamp: nearestStamp(to: row.stop.coordinate))
        }
        // 자리와 자리 사이를 이은 것만이 아니라 하루 전체를 잰다.
        // 어디에도 들르지 않고 한 바퀴 돌고 온 걸음도 오늘 걸은 것이다.
        walkedToday = WalkTrail.distance(of: points)
    }

    /// 머무름 기록이 들고 있는 이름. 좌표밖에 없으면 이름이 없는 것으로 친다 —
    /// 소수점 여섯 자리는 사람이 읽는 이름이 아니다.
    private func name(of visit: Visit) -> String? {
        if let placeName = visit.placeName, !placeName.isEmpty { return placeName }
        if let address = visit.address, !address.isEmpty { return address }
        return nil
    }

    /// 그 자리에 이미 찍혀 있는 스탬프 가운데 가장 가까운 것
    private func nearestStamp(to coordinate: CLLocationCoordinate2D) -> MapStamp? {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return stamps
            .map { ($0, $0.distance(from: here)) }
            .filter { $0.1 <= MapStamp.visitRadius }
            .min { $0.1 < $1.1 }?
            .0
    }

    /// 이 줄에 물어볼 것이 있는지
    private func asks(_ entry: Entry) -> Bool {
        guard let stamp = entry.stamp else { return false }
        return stamp.canAskAboutVisit(now: .now, calendar: calendar)
    }

    // MARK: - 답

    /// 다녀온 것으로 남긴다.
    ///
    /// 남기는 때는 '지금'이 아니라 그 자리에 닿았던 때다. 저녁에 몰아서 답해도
    /// 기록은 낮에 다녀온 것으로 남아야, 나중에 '언제 갔더라'가 맞는 답을 준다.
    private func confirm(_ entry: Entry) {
        guard let stamp = entry.stamp, stamp.canAddVisit(now: .now, calendar: calendar) else { return }
        stamp.addVisit(at: entry.row.stop.arrival)
        stamp.visitAskedAt = .now
        try? modelContext.save()
        FootprintUsage.log(.visitConfirmed)
        rebuild()
    }

    /// 아니라고 답한 자리. 오늘은 다시 묻지 않는다.
    private func decline(_ entry: Entry) {
        guard let stamp = entry.stamp else { return }
        stamp.visitAskedAt = .now
        try? modelContext.save()
        rebuild()
    }

    // MARK: - 화면

    private var timeline: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                ForEach(entries) { entry in
                    if let approach = entry.row.approach {
                        legRow(approach)
                    }
                    stopRow(entry)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Date.now, format: .dateTime.month().day().weekday(.wide))
                .font(.system(size: 22, weight: .bold, design: .serif))
            HStack(spacing: 6) {
                Text("들른 곳 \(entries.count)곳")
                if walkedToday >= 1 {
                    Text("·")
                    Text("\(DayTimeline.distanceText(walkedToday)) 걸음")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if pendingCount > 0 {
                // 물음이 몇 개인지 위에서 한 번 알린다. 줄 사이에 흩어져 있으면
                // 아래까지 내려가 보기 전에는 답할 것이 남았는지 알 수 없다.
                Label("다녀오신 게 맞는지 \(pendingCount)곳 여쭤볼게요",
                      systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(Color(InkStyle.sealRed))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    /// 들른 곳 한 줄
    private func stopRow(_ entry: Entry) -> some View {
        let stop = entry.row.stop
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .trailing, spacing: 2) {
                // 한 줄로 세운다. '오전 9:11'이 두 줄로 접히면 옆의 표시와 높이가
                // 어긋나, 훑어 내릴 때 시각과 자리가 짝지어 보이지 않는다.
                Text(stop.arrival, format: .dateTime.hour().minute())
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(DayTimeline.durationText(stop.duration))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: Self.timeColumnWidth, alignment: .trailing)

            rail(for: entry, isLast: entries.last?.id == entry.id)

            VStack(alignment: .leading, spacing: 8) {
                Text(title(of: entry))
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle = subtitle(of: entry) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if asks(entry) {
                    askButtons(entry)
                } else if entry.stamp == nil {
                    markButton(stop.coordinate)
                }
            }
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    /// 자리 옆에 서는 기둥과 표시.
    ///
    /// 표시는 그 자리의 심볼이다. 지도에서 보던 그림이 여기서도 같아야 같은 곳인 줄
    /// 알아본다 — 목록과 지도가 다른 그림을 쓰면 그때부터 둘은 다른 물건이 된다.
    private func rail(for entry: Entry, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            Group {
                if let stamp = entry.stamp {
                    StampSymbolBadge(stamp: stamp, side: 28, corner: 7)
                } else {
                    Circle()
                        .strokeBorder(Color(InkStyle.ink).opacity(0.35), lineWidth: 2)
                        .frame(width: 14, height: 14)
                        .frame(width: 28, height: 28)
                }
            }
            // 마지막 자리 아래로는 잇지 않는다. 이 기둥은 '다음 자리로 이어진다'는
            // 말이라, 이어질 것이 없는데도 뻗어 있으면 아직 못 읽은 줄이 남은 것처럼
            // 보인다.
            if !isLast {
                Rectangle()
                    .fill(Color(InkStyle.ink).opacity(0.14))
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 28)
    }

    /// 자리와 자리 사이 — 얼마를 걸어서 왔는지
    private func legRow(_ leg: DayTimeline.Leg) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Spacer().frame(width: Self.timeColumnWidth)
            VStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color(InkStyle.ink).opacity(0.22))
                        .frame(width: 3, height: 3)
                }
            }
            .frame(width: 28)

            Text("\(DayTimeline.distanceText(leg.distance)) 걸어서 \(DayTimeline.durationText(leg.duration))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 20)
    }

    private func askButtons(_ entry: Entry) -> some View {
        HStack(spacing: 8) {
            Button("다녀왔어요") { confirm(entry) }
                .buttonStyle(.borderedProminent)
                .tint(Color(InkStyle.sealRed))
            Button("아니에요") { decline(entry) }
                .buttonStyle(.bordered)
        }
        .font(.caption)
        .controlSize(.small)
    }

    /// 아직 스탬프가 없는 자리는 물어볼 것이 없다 — 셀 자리가 없으므로.
    /// 대신 여기서 바로 찍을 수 있게 둔다.
    private func markButton(_ coordinate: CLLocationCoordinate2D) -> some View {
        Button {
            pendingCoordinate = StampSpot(coordinate: coordinate)
        } label: {
            Label("여기 찍어 두기", systemImage: "plus.circle")
        }
        .buttonStyle(.bordered)
        .font(.caption)
        .controlSize(.small)
    }

    private func title(of entry: Entry) -> String {
        if let stamp = entry.stamp { return stamp.displayName }
        if let name = entry.row.stop.name { return name }
        return "이름 없는 자리"
    }

    /// 이름 아래 한 줄.
    ///
    /// 스탬프가 있는 자리에는 몇 번째 걸음인지를 적는다. 그 숫자가 이 자리를 단골로
    /// 만들어 가는 눈금이라, 오늘 한 번을 더한 보람이 곧바로 눈에 보여야 한다.
    /// 그 밖의 자리에는 아무것도 적지 않는다 — 좌표를 적어 두면 읽히지도 않으면서
    /// 줄만 길어진다.
    private func subtitle(of entry: Entry) -> String? {
        guard let stamp = entry.stamp, stamp.visitCount > 1 else { return nil }
        return "\(stamp.visitCount)번째 다녀온 자리"
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("오늘은 아직 머문 자리가 없어요")
                .font(.headline)
            Text("한 곳에 \(Int(DayTimeline.minimumDwell / 60))분 넘게 머물면\n그 자리가 오늘의 발자취에 섭니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
