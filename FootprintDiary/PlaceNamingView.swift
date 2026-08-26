//
//  PlaceNamingView.swift
//  FootprintDiary
//
//  [보관] 앱을 열 때 뜨던 '새로운 발견' 카드와 장소 이름 붙이기.
//
//  앱이 '탐험 일지' 한 화면으로 정리되면서 쓰이지 않는다.
//  지우지 않고 통째로 주석 처리해 둔다 — 되살리려면 아래 주석을 벗기고
//  ContentView에서 다시 연결하면 된다. (동작하던 마지막 상태: 커밋 a0de097)
//

/*
//
//  PlaceNamingView.swift
//  FootprintDiary
//
//  앱을 열었을 때 뜨는 '발견 카드'.
//  예전에는 이름 입력 폼부터 보여줬지만, 그러면 앱을 여는 순간이 숙제가 된다.
//  먼저 무엇을 발견했는지 보여주고, 이름 짓기는 그 위에 얹는다.
//

import SwiftUI
import SwiftData
import MapKit

struct DiscoveryReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// 아직 확인하지 않은 발자국. 새로 발견한 자리(발견 번호가 큰 쪽)를 먼저 보여준다.
    @Query(
        filter: #Predicate<Visit> { $0.isNamed == false },
        sort: \Visit.discoveryIndex,
        order: .reverse
    )
    private var pendingVisits: [Visit]

    @State private var name: String = ""
    @State private var namedCount = 0

    private var current: Visit? { pendingVisits.first }

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

    private var discoveryCount: Int {
        pendingVisits.filter(\.isFirstVisit).count
    }

    var body: some View {
        NavigationStack {
            if let visit = current {
                ScrollView {
                    VStack(spacing: 16) {
                        headline(for: visit)
                        miniMap(for: visit)
                        detail(for: visit)
                        nameField
                        if !suggestions.isEmpty { suggestionChips }
                        actions(for: visit)
                    }
                    .padding()
                }
                .navigationTitle(visit.isFirstVisit ? "새로운 발견" : "장소 확인")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("나중에") { dismiss() }
                    }
                }
            } else {
                completionCard
            }
        }
    }

    // MARK: - 하위 뷰

    /// 보상이 먼저 온다 — 몇 번째 발견인지, 몇 군데가 남았는지
    @ViewBuilder
    private func headline(for visit: Visit) -> some View {
        VStack(spacing: 10) {
            if visit.isFirstVisit {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.yellow.opacity(0.55), .yellow.opacity(0)],
                                center: .center,
                                startRadius: 4,
                                endRadius: 52
                            )
                        )
                        .frame(width: 104, height: 104)
                    Text("👣")
                        .font(.system(size: 46))
                }
                Text("\(visit.discoveryIndex)번째 발견")
                    .font(.title2.bold())
                    .foregroundStyle(.orange)
                Text("처음 밟아 본 자리예요")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("👣").font(.system(size: 40))
                Text("다시 찾은 자리")
                    .font(.title3.bold())
            }

            if discoveryCount > 1 || pendingVisits.count > 1 {
                Text(remainingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var remainingText: String {
        if discoveryCount > 1 {
            return "새로 발견한 곳 \(discoveryCount)군데 · 확인할 곳 \(pendingVisits.count)곳"
        }
        return "확인할 곳 \(pendingVisits.count)곳"
    }

    private func miniMap(for visit: Visit) -> some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: visit.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
        ))) {
            Annotation("", coordinate: visit.coordinate) {
                FootprintMarker(number: max(visit.discoveryIndex, 1), isDiscovery: visit.isFirstVisit)
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    visit.isFirstVisit ? Color.yellow.opacity(0.7) : Color.clear,
                    lineWidth: 2
                )
        )
        .allowsHitTesting(false)
        .id(visit.persistentModelID)
    }

    private func detail(for visit: Visit) -> some View {
        VStack(spacing: 4) {
            Text("여기는 어디였나요?")
                .font(.headline)
            Text(visitDescription(visit))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var nameField: some View {
        TextField("예: 집, 회사, 단골 카페", text: $name)
            .textFieldStyle(.roundedBorder)
            .submitLabel(.done)
            .onSubmit { saveCurrent() }
    }

    private var suggestionChips: some View {
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

    private func actions(for visit: Visit) -> some View {
        HStack {
            Button("건너뛰기") { skipCurrent(visit) }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

            Button("이름 붙이기") { saveCurrent() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    /// 다 확인했을 때 — 무엇을 모았는지 한 번 더 보여주고 닫는다
    private var completionCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
            Text(namedCount > 0 ? "\(namedCount)곳에 이름을 붙였어요" : "모든 장소를 확인했어요!")
                .font(.headline)
            Text("도감에서 지금까지 모은 발자국을 볼 수 있어요")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { dismiss() }
        }
    }

    // MARK: - 동작

    private func saveCurrent() {
        guard let visit = current else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        visit.placeName = trimmed
        visit.isNamed = true
        namedCount += 1

        // 같은 자리로 추정되는 다른 미확인 발자국에도 같은 이름 적용
        for other in pendingVisits where other !== visit {
            if other.distance(latitude: visit.latitude, longitude: visit.longitude) < LocationManager.sameSpotThreshold {
                other.placeName = trimmed
                other.isNamed = true
            }
        }
        try? modelContext.save()
        // 이름만 셈하고 이름 자체는 보내지 않는다. '몇 곳에 이름을 붙였나'가 알고
        // 싶은 것이지 그곳이 어디인지는 알 필요가 없다. (FootprintUsage.swift)
        FootprintUsage.log(.placeNamed)
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
*/
