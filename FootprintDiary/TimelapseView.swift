//
//  TimelapseView.swift
//  FootprintDiary
//
//  기간을 정해 하루씩 발자국을 재생하는 타임랩스.
//  로토스코프처럼 지난 며칠의 발자국이 잔상으로 옅게 남으면서
//  날짜가 넘어갈 때마다 이동 패턴의 변화가 보인다.
//

import SwiftUI
import SwiftData
import MapKit

struct TimelapseView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var startDate: Date
    @State private var endDate: Date

    init() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        _endDate = State(initialValue: today)
        _startDate = State(initialValue: calendar.date(byAdding: .day, value: -29, to: today) ?? today)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                rangePicker
                TimelapsePlayerView(startDate: startDate, endDate: endDate)
            }
            .navigationTitle("발자국 타임랩스")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 8) {
            DatePicker("시작", selection: $startDate, in: ...endDate, displayedComponents: .date)
                .labelsHidden()
            Text("~")
                .foregroundStyle(.secondary)
            DatePicker("끝", selection: $endDate, in: startDate..., displayedComponents: .date)
                .labelsHidden()
        }
        .environment(\.locale, Locale(identifier: "ko_KR"))
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// 기간 내 발자국을 하루 단위 프레임으로 재생하는 플레이어.
/// 기간이 바뀌면 SwiftData 쿼리째 다시 만들어진다.
private struct TimelapsePlayerView: View {
    @Query private var visits: [Visit]

    @State private var frameIndex = 0
    @State private var isPlaying = false
    @State private var speed: Double = 1.0
    @State private var cameraPosition: MapCameraPosition = .automatic

    private let days: [Date]
    private let calendar = Calendar.current

    /// 잔상으로 남길 지난 일수 (로토스코프 프레임 수)
    private static let ghostDays = 6
    /// 1배속에서 프레임(하루) 하나가 머무는 시간
    private static let baseFrameDuration: TimeInterval = 0.9

    init(startDate: Date, endDate: Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)) ?? start

        _visits = Query(
            filter: #Predicate<Visit> { $0.arrivalDate >= start && $0.arrivalDate < endExclusive },
            sort: \Visit.arrivalDate
        )

        var days: [Date] = []
        var cursor = start
        while cursor < endExclusive {
            days.append(cursor)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? endExclusive
        }
        self.days = days
    }

    /// 하루 단위로 묶은 방문 기록 (렌더마다 다시 묶지 않도록 body 진입 전 한 번만 계산)
    private var visitsByDay: [Date: [Visit]] {
        Dictionary(grouping: visits) { calendar.startOfDay(for: $0.arrivalDate) }
    }

    /// 발자국이 있는 날만 추린 프레임 목록 (발자국 없는 날은 타임랩스에서 제외)
    private var activeDays: [Date] {
        let frames = visitsByDay
        return days.filter { frames[$0]?.isEmpty == false }
    }

    var body: some View {
        let frames = visitsByDay
        let activeDays = activeDays
        let currentDay = activeDays.indices.contains(frameIndex) ? activeDays[frameIndex] : activeDays.first ?? .now

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // 과거 기록 재생 화면이라 UserAnnotation(현재 위치)을 넣지 않는다.
                // 넣으면 지도가 떠 있는 내내 GPS가 켜져 배터리를 소모한다.
                Map(position: $cameraPosition) {
                    // 로토스코프 잔상: 지난 ghostDays개 프레임의 발자국이 옅어지며 남는다
                    ForEach(ghostRange(dayCount: activeDays.count), id: \.self) { dayIndex in
                        let age = frameIndex - dayIndex
                        let opacity = pow(0.55, Double(age))
                        if let dayVisits = frames[activeDays[dayIndex]], !dayVisits.isEmpty {
                            ForEach(FootprintTrail.steps(along: dayVisits.map(\.coordinate))) { step in
                                Annotation("", coordinate: step.coordinate, anchor: .center) {
                                    FootprintTrail.mark(heading: step.heading, opacity: opacity)
                                }
                            }
                            ForEach(Array(dayVisits.enumerated()), id: \.element.persistentModelID) { index, visit in
                                if age == 0 {
                                    Annotation(visit.displayName, coordinate: visit.coordinate) {
                                        Text("👣")
                                            .font(.title3)
                                            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                                            .rotationEffect(.degrees(FootprintTrail.heading(through: dayVisits.map(\.coordinate), at: index)))
                                    }
                                } else {
                                    Annotation("", coordinate: visit.coordinate) {
                                        Circle()
                                            .fill(Color.accentColor.opacity(opacity))
                                            .frame(width: 8, height: 8)
                                    }
                                }
                            }
                        }
                    }
                }

                dateBadge(for: currentDay, count: frames[currentDay]?.count ?? 0)
            }

            controlsView(activeDays: activeDays)
        }
        .onAppear { fitCamera() }
        .onChange(of: visits.map(\.persistentModelID)) {
            frameIndex = 0
            fitCamera()
        }
        .task(id: playbackToken) {
            guard isPlaying else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.baseFrameDuration / speed * 1_000_000_000))
                guard !Task.isCancelled else { return }
                if frameIndex < activeDays.count - 1 {
                    withAnimation(.easeInOut(duration: 0.25)) { frameIndex += 1 }
                } else {
                    isPlaying = false
                    return
                }
            }
        }
    }

    /// 재생 상태/배속이 바뀔 때마다 재생 태스크를 새로 시작하기 위한 키
    private var playbackToken: String { "\(isPlaying)-\(speed)" }

    private func ghostRange(dayCount: Int) -> Range<Int> {
        guard dayCount > 0 else { return 0..<0 }
        let clamped = min(frameIndex, dayCount - 1)
        return max(0, clamped - Self.ghostDays)..<(clamped + 1)
    }

    // MARK: - 하위 뷰

    private func dateBadge(for day: Date, count: Int) -> some View {
        VStack(spacing: 2) {
            Text(Self.dayFormatter.string(from: day))
                .font(.headline)
            Text(count > 0 ? "발자국 \(count)개" : "발자국 없음")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Capsule().fill(.thinMaterial))
        .padding(.top, 12)
    }

    @ViewBuilder
    private func controlsView(activeDays: [Date]) -> some View {
        if activeDays.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "film")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("이 기간에는 발자국이 없어요")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(height: 120)
        } else {
            VStack(spacing: 12) {
                Slider(
                    value: Binding(
                        get: { Double(frameIndex) },
                        set: { frameIndex = Int($0.rounded()) }
                    ),
                    in: 0...Double(max(activeDays.count - 1, 1)),
                    step: 1
                )

                HStack {
                    Text(Self.shortDayFormatter.string(from: activeDays.first ?? .now))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        if !isPlaying && frameIndex >= activeDays.count - 1 {
                            frameIndex = 0
                        }
                        isPlaying.toggle()
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                    }

                    Spacer()

                    Menu {
                        ForEach([0.5, 1.0, 2.0, 4.0], id: \.self) { value in
                            Button {
                                speed = value
                            } label: {
                                if speed == value {
                                    Label(speedLabel(value), systemImage: "checkmark")
                                } else {
                                    Text(speedLabel(value))
                                }
                            }
                        }
                    } label: {
                        Text(speedLabel(speed))
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }

    // MARK: - 헬퍼

    private func speedLabel(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))x" : "\(value)x"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E)"
        return formatter
    }()

    private static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M/d"
        return formatter
    }()

    private func fitCamera() {
        guard !visits.isEmpty else { return }
        let coords = visits.map(\.coordinate)
        let minLat = coords.map(\.latitude).min()!
        let maxLat = coords.map(\.latitude).max()!
        let minLon = coords.map(\.longitude).min()!
        let maxLon = coords.map(\.longitude).max()!
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.5, 0.02),
            longitudeDelta: max((maxLon - minLon) * 1.5, 0.02)
        )
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }
}
