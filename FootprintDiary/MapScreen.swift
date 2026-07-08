//
//  MapScreen.swift
//  FootprintDiary
//
//  선택한 날짜의 이동 경로를 지도 위 발자국으로 보여준다.
//

import SwiftUI
import SwiftData
import MapKit

struct MapScreen: View {
    @EnvironmentObject private var locationManager: LocationManager

    @State private var selectedDate: Date = .now
    @State private var showTimelapse = false

    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                dayPicker
                DayMapView(date: selectedDate)
            }
            .navigationTitle("발자국")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showTimelapse = true
                    } label: {
                        Label("타임랩스", systemImage: "film")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        locationManager.recordCurrentLocation()
                    } label: {
                        if locationManager.isRecordingManually {
                            ProgressView()
                        } else {
                            Label("현재 위치 기록", systemImage: "plus.circle.fill")
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showTimelapse) {
                TimelapseView()
            }
        }
    }

    // MARK: - 하위 뷰

    private var dayPicker: some View {
        HStack {
            Button {
                selectedDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.left")
            }

            Spacer()

            DatePicker("날짜", selection: $selectedDate, displayedComponents: .date)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "ko_KR"))

            Spacer()

            Button {
                selectedDate = calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(calendar.isDateInToday(selectedDate))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// 하루치 발자국 지도 + 목록.
/// 날짜별 필터링을 SwiftData 쿼리(저장소 레벨)로 내려서
/// 전체 기록을 메모리로 가져와 매 렌더마다 거르던 비용을 없앤다.
struct DayMapView: View {
    @Query private var dayVisits: [Visit]

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedVisit: Visit?

    init(date: Date) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        _dayVisits = Query(
            filter: #Predicate<Visit> { $0.arrivalDate >= dayStart && $0.arrivalDate < dayEnd },
            sort: \Visit.arrivalDate
        )
    }

    var body: some View {
        Map(position: $cameraPosition) {
            // 현재 내 위치
            UserAnnotation()

            // 이동 경로 선
            if dayVisits.count >= 2 {
                MapPolyline(coordinates: dayVisits.map(\.coordinate))
                    .stroke(
                        Color.accentColor.opacity(0.7),
                        style: StrokeStyle(lineWidth: 3, dash: [6, 6])
                    )
            }
            // 발자국 마커
            ForEach(Array(dayVisits.enumerated()), id: \.element.persistentModelID) { index, visit in
                Annotation(visit.displayName, coordinate: visit.coordinate) {
                    FootprintMarker(number: index + 1)
                        .onTapGesture { selectedVisit = visit }
                }
            }
        }
        .mapControls {
            MapUserLocationButton()
        }
        .frame(maxHeight: .infinity)

        visitList
            .sheet(item: $selectedVisit) { visit in
                VisitEditView(visit: visit)
                    .presentationDetents([.medium])
            }
            .onAppear { fitCamera() }
            .onChange(of: dayVisits.map(\.persistentModelID)) { fitCamera() }
    }

    @ViewBuilder
    private var visitList: some View {
        if dayVisits.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "figure.walk")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("이 날의 발자국이 아직 없어요")
                    .foregroundStyle(.secondary)
                Text("걷거나 뛰어서 이동하면 자동으로 기록되고, + 버튼으로 지금 위치를 바로 남길 수도 있어요.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(height: 160)
        } else {
            List {
                ForEach(Array(dayVisits.enumerated()), id: \.element.persistentModelID) { index, visit in
                    Button {
                        selectedVisit = visit
                    } label: {
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.accentColor.opacity(0.2)))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(visit.displayName)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Text(timeRange(for: visit))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if !visit.isNamed {
                                Text("이름 없음")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.orange.opacity(0.2)))
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .frame(height: 200)
        }
    }

    // MARK: - 헬퍼

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h:mm"
        return formatter
    }()

    private func timeRange(for visit: Visit) -> String {
        var text = Self.timeFormatter.string(from: visit.arrivalDate)
        if let departure = visit.departureDate {
            text += " ~ " + Self.timeFormatter.string(from: departure)
        }
        return text
    }

    private func fitCamera() {
        guard !dayVisits.isEmpty else { return }
        let coords = dayVisits.map(\.coordinate)
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

/// 지도 위 발자국 마커
struct FootprintMarker: View {
    let number: Int

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Text("👣")
                    .font(.title2)
                    .padding(6)
                    .background(Circle().fill(.background).shadow(radius: 2))
                Text("\(number)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.accentColor))
                    .offset(x: 4, y: -4)
            }
        }
    }
}

/// 발자국(방문) 이름/정보 수정 시트
struct VisitEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let visit: Visit
    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("장소 이름") {
                    TextField("예: 회사, 단골 카페", text: $name)
                }
                if let address = visit.address, !address.isEmpty {
                    Section("주소") {
                        Text(address).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button("이 발자국 삭제", role: .destructive) {
                        modelContext.delete(visit)
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .navigationTitle("발자국 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        visit.placeName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        visit.isNamed = true
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .onAppear { name = visit.placeName ?? "" }
        }
    }
}
