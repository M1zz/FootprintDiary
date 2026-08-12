//
//  SpotViews.swift
//  FootprintDiary
//
//  지도 위의 스팟 표시와, 스팟을 눌렀을 때 뜨는 화면.
//

import SwiftUI
import SwiftData
import MapKit

// MARK: - 지도 마커

/// 지도 위 스팟 하나. 아직 안 간 곳은 점선 테두리로 '비어 있음'을 보여 준다.
struct SpotMarker: View {
    let spot: PhotoSpot

    var body: some View {
        ZStack {
            Circle()
                .fill(spot.isCollected ? Color.green.opacity(0.9) : Color.white)
                .frame(width: 34, height: 34)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)

            Circle()
                .strokeBorder(
                    spot.isCollected ? Color.green : Color.orange,
                    style: StrokeStyle(
                        lineWidth: 2,
                        dash: spot.isCollected ? [] : [3, 3]
                    )
                )
                .frame(width: 34, height: 34)

            Image(systemName: spot.isCollected ? "checkmark" : spot.symbolName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(spot.isCollected ? .white : .orange)
        }
    }
}

// MARK: - 상세 시트

struct SpotDetailSheet: View {
    let spot: PhotoSpot

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var locationManager: LocationManager

    @State private var showAR = false

    private var distance: CLLocationDistance? {
        guard let location = locationManager.currentLocation else { return nil }
        return spot.distance(from: location)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let data = spot.photoData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    Image(systemName: spot.symbolName)
                        .font(.system(size: 46))
                        .foregroundStyle(.orange)
                        .frame(height: 100)
                }

                VStack(spacing: 4) {
                    Text(spot.name)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if spot.isCollected {
                    Label("수집한 스팟", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        showAR = true
                    } label: {
                        Label("AR로 찾아가기", systemImage: "arkit")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Text("걸어서 도착하면 그 자리에서 사진을 남길 수 있어요")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                if !spot.isCollected {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("관심 없어요") {
                            modelContext.delete(spot)
                            try? modelContext.save()
                            dismiss()
                        }
                        .font(.caption)
                    }
                }
            }
            .fullScreenCover(isPresented: $showAR) {
                SpotARScreen(spot: spot)
            }
        }
    }

    private var statusText: String {
        if let collectedAt = spot.collectedAt {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ko_KR")
            formatter.dateFormat = "yyyy년 M월 d일"
            return formatter.string(from: collectedAt) + "에 다녀왔어요"
        }
        guard let distance else { return "아직 탐험하지 않은 곳" }
        if distance < 1_000 { return "여기서 \(Int(distance))m" }
        return String(format: "여기서 %.1fkm", distance / 1_000)
    }
}

// MARK: - 스팟 채우기

/// 주변에 갈 곳이 모자라면 자동으로 채운다.
/// 지도를 열 때마다 검색하지 않도록 조금 텀을 둔다.
@MainActor
final class SpotReplenisher: ObservableObject {
    @Published private(set) var isSearching = false
    private var lastSearchLocation: CLLocation?

    /// 이만큼 움직였을 때만 다시 찾는다
    private static let researchDistance: CLLocationDistance = 500

    func replenishIfNeeded(near location: CLLocation?, context: ModelContext) {
        guard let location, !isSearching else { return }
        if let last = lastSearchLocation, last.distance(from: location) < Self.researchDistance {
            return
        }
        lastSearchLocation = location
        isSearching = true
        Task {
            _ = await SpotFinder.replenish(near: location, context: context)
            isSearching = false
        }
    }
}
