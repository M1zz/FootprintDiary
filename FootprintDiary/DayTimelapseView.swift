//
//  DayTimelapseView.swift
//  FootprintDiary
//
//  하루의 이동을 발자국이 찍히는 순서대로 재생하는 타임랩스.
//  발자국이 시간 순서대로 하나씩 나타나므로
//  같은 곳을 왕복한 경로도 오간 순서와 방향이 그대로 보인다.
//

import SwiftUI
import SwiftData
import MapKit

struct DayTimelapseView: View {
    @Environment(\.dismiss) private var dismiss

    let date: Date

    var body: some View {
        NavigationStack {
            DayTimelapsePlayerView(date: date)
                .navigationTitle("하루 타임랩스")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("닫기") { dismiss() }
                    }
                }
        }
    }
}

/// 하루치 방문 기록을 발자국 단위 프레임으로 재생하는 플레이어
private struct DayTimelapsePlayerView: View {
    @Query private var visits: [Visit]

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var cursor = 0
    @State private var isPlaying = false
    @State private var speed: Double = 1.0

    /// 1배속에서 발자국 하나가 찍히는 간격(초)
    private static let baseFrameDuration: TimeInterval = 0.25

    private let day: Date

    init(date: Date) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        self.day = dayStart
        _visits = Query(
            filter: #Predicate<Visit> { $0.arrivalDate >= dayStart && $0.arrivalDate < dayEnd },
            sort: \Visit.arrivalDate
        )
    }

    // MARK: - 프레임

    /// 재생 프레임 하나: 방문 지점 도착 또는 경로 위 자취 발자국
    private enum Frame {
        case visit(number: Int, visit: Visit, heading: Double)
        case trail(FootprintTrail.Step, time: Date)

        var coordinate: CLLocationCoordinate2D {
            switch self {
            case .visit(_, let visit, _): visit.coordinate
            case .trail(let step, _): step.coordinate
            }
        }

        var time: Date {
            switch self {
            case .visit(_, let visit, _): visit.arrivalDate
            case .trail(_, let time): time
            }
        }
    }

    /// 방문 지점과 그 사이 자취 발자국을 시간 순서대로 한 줄로 펼친다.
    /// 자취 발자국의 시각은 출발/도착 시각 사이를 거리 비율로 보간한다.
    private var frames: [Frame] {
        let coords = visits.map(\.coordinate)
        var frames: [Frame] = []
        for (index, visit) in visits.enumerated() {
            frames.append(.visit(
                number: index + 1,
                visit: visit,
                heading: FootprintTrail.heading(through: coords, at: index)
            ))
            guard index + 1 < visits.count else { break }
            let next = visits[index + 1]
            let segmentSteps = FootprintTrail.steps(along: [visit.coordinate, next.coordinate])
            let departure = visit.departureDate ?? visit.arrivalDate
            let travelTime = next.arrivalDate.timeIntervalSince(departure)
            for (order, step) in segmentSteps.enumerated() {
                let fraction = Double(order + 1) / Double(segmentSteps.count + 1)
                frames.append(.trail(step, time: departure.addingTimeInterval(travelTime * fraction)))
            }
        }
        return frames
    }

    // MARK: - 본문

    var body: some View {
        if visits.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "figure.walk")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("이 날의 발자국이 없어요")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            player
        }
    }

    private var player: some View {
        let frames = frames
        let clampedCursor = min(cursor, frames.count - 1)

        return VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Map(position: $cameraPosition) {
                    // 지금까지 찍힌 발자국들
                    ForEach(Array(frames.prefix(clampedCursor + 1).enumerated()), id: \.offset) { _, frame in
                        switch frame {
                        case .visit(let number, let visit, let heading):
                            Annotation(visit.displayName, coordinate: visit.coordinate) {
                                FootprintMarker(number: number, heading: heading)
                            }
                        case .trail(let step, _):
                            Annotation("", coordinate: step.coordinate, anchor: .center) {
                                FootprintTrail.mark(heading: step.heading)
                            }
                        }
                    }
                    // 현재 위치
                    Annotation("", coordinate: frames[clampedCursor].coordinate, anchor: .center) {
                        Text("🚶")
                            .font(.title3)
                            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                    }
                }

                timeBadge(for: frames, at: clampedCursor)
            }

            controls(frameCount: frames.count)
        }
        .onAppear {
            fitCamera()
            isPlaying = true
        }
        .onChange(of: visits.map(\.persistentModelID)) {
            cursor = 0
            fitCamera()
        }
        .task(id: playbackToken) {
            guard isPlaying else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.baseFrameDuration / speed * 1_000_000_000))
                guard !Task.isCancelled else { return }
                if cursor < self.frames.count - 1 {
                    withAnimation(.easeInOut(duration: 0.2)) { cursor += 1 }
                } else {
                    isPlaying = false
                    return
                }
            }
        }
    }

    /// 재생 상태/배속이 바뀔 때마다 재생 태스크를 새로 시작하기 위한 키
    private var playbackToken: String { "\(isPlaying)-\(speed)" }

    // MARK: - 하위 뷰

    private func timeBadge(for frames: [Frame], at index: Int) -> some View {
        let visitedCount = frames.prefix(index + 1).reduce(0) { count, frame in
            if case .visit = frame { return count + 1 }
            return count
        }
        return VStack(spacing: 2) {
            Text(Self.dayFormatter.string(from: day))
                .font(.headline)
            Text("\(Self.timeFormatter.string(from: frames[index].time)) · 발자국 \(visitedCount)/\(visits.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Capsule().fill(.thinMaterial))
        .padding(.top, 12)
    }

    private func controls(frameCount: Int) -> some View {
        VStack(spacing: 12) {
            Slider(
                value: Binding(
                    get: { Double(min(cursor, frameCount - 1)) },
                    set: { cursor = Int($0.rounded()) }
                ),
                in: 0...Double(max(frameCount - 1, 1)),
                step: 1
            )

            HStack {
                Text(Self.timeFormatter.string(from: visits.first?.arrivalDate ?? day))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    if !isPlaying && cursor >= frameCount - 1 {
                        cursor = 0
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

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h:mm"
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
            latitudeDelta: max((maxLat - minLat) * 1.5, 0.01),
            longitudeDelta: max((maxLon - minLon) * 1.5, 0.01)
        )
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }
}
