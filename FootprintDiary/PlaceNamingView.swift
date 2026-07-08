//
//  PlaceNamingView.swift
//  FootprintDiary
//
//  앱을 열었을 때 아직 이름이 없는 장소들을 한꺼번에 물어보는 화면.
//  "여기는 어디였나요?"
//

import SwiftUI
import SwiftData
import MapKit

struct PlaceNamingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Visit> { $0.isNamed == false }, sort: \Visit.arrivalDate)
    private var unnamedVisits: [Visit]

    @State private var name: String = ""
    @FocusState private var nameFieldFocused: Bool

    private var current: Visit? { unnamedVisits.first }

    /// 최근에 사용한 장소 이름 제안
    @Query(sort: \Visit.arrivalDate, order: .reverse)
    private var allVisits: [Visit]

    private var suggestions: [String] {
        var seen = Set<String>()
        return allVisits
            .compactMap(\.placeName)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            if let visit = current {
                VStack(spacing: 16) {
                    // 진행 상황
                    if unnamedVisits.count > 1 {
                        Text("남은 장소 \(unnamedVisits.count)곳")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // 미니 지도
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: visit.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                    ))) {
                        Annotation("", coordinate: visit.coordinate) {
                            Text("👣").font(.title)
                        }
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .allowsHitTesting(false)
                    .id(visit.persistentModelID)

                    VStack(spacing: 4) {
                        Text("여기는 어디였나요?")
                            .font(.title2.bold())
                        Text(visitDescription(visit))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    TextField("예: 집, 회사, 단골 카페", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { saveCurrent() }

                    // 최근 이름 제안 칩
                    if !suggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(suggestions, id: \.self) { suggestion in
                                    Button(suggestion) {
                                        name = suggestion
                                        saveCurrent()
                                    }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                                }
                            }
                        }
                    }

                    HStack {
                        Button("건너뛰기") { skipCurrent(visit) }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)

                        Button("저장") { saveCurrent() }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Spacer()
                }
                .padding()
                .navigationTitle("장소 확인")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("나중에") { dismiss() }
                    }
                }
            } else {
                // 모두 답하면 자동으로 닫힘
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("모든 장소를 확인했어요!")
                        .font(.headline)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { dismiss() }
                }
            }
        }
    }

    // MARK: - 동작

    private func saveCurrent() {
        guard let visit = current else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        visit.placeName = trimmed
        visit.isNamed = true

        // 같은 자리로 추정되는 다른 미확인 발자국에도 같은 이름 적용
        for other in unnamedVisits where other !== visit {
            if other.distance(latitude: visit.latitude, longitude: visit.longitude) < LocationManager.sameSpotThreshold {
                other.placeName = trimmed
                other.isNamed = true
            }
        }
        try? modelContext.save()
        name = ""
    }

    private func skipCurrent(_ visit: Visit) {
        visit.isNamed = true // 다시 묻지 않음 (주소/좌표로 표시)
        try? modelContext.save()
        name = ""
    }

    private func visitDescription(_ visit: Visit) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 a h:mm"
        var text = formatter.string(from: visit.arrivalDate) + "에 머물렀던 곳"
        if let address = visit.address, !address.isEmpty {
            text += "\n" + address
        }
        return text
    }
}
