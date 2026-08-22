//
//  FilmScreen.swift
//  FootprintDiary
//
//  기간을 정해 내 지도가 그려지는 것을 보고, 영상으로 내보낸다.
//
//  완성된 지도는 남에게 보여 줘도 '그림 한 장'이지만, 그려지는 과정은 이야기가 된다.
//  어디서 시작해 어디까지 뻗어 나갔는지가 순서대로 드러나기 때문이다.
//  그래서 자랑할 만한 것은 지도가 아니라 이 필름 쪽이다.
//

import SwiftUI
import SwiftData
import MapKit

struct FilmScreen: View {
    @Query(sort: \TrackPoint.timestamp) private var track: [TrackPoint]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// 미리 골라 둘 만한 기간
    private enum Span: String, CaseIterable, Identifiable {
        case week = "최근 7일"
        case month = "최근 30일"
        case year = "최근 1년"
        case all = "전부"

        var id: String { rawValue }

        func start(from end: Date, calendar: Calendar, earliest: Date?) -> Date {
            switch self {
            case .week: return calendar.date(byAdding: .day, value: -6, to: end) ?? end
            case .month: return calendar.date(byAdding: .day, value: -29, to: end) ?? end
            case .year: return calendar.date(byAdding: .year, value: -1, to: end) ?? end
            case .all: return earliest ?? end
            }
        }
    }

    @State private var span: Span = .month
    @State private var reel: WalkFilm.Reel?
    @State private var terrain: TerrainMask?
    @State private var isFindingTerrain = false
    /// 필름을 돌리기 시작한 때. 지금 어디까지 그렸는지는 이 때부터 흐른 시간으로 셈한다.
    ///
    /// 그리는 자리를 상태로 들고 앉아 매 칸 고쳐 쓰면, 화면을 그리는 도중에 상태를 바꾸는 꼴이
    /// 되어 SwiftUI가 싫어한다. 시각에서 되짚어 내면 고쳐 쓸 상태가 아예 없다.
    @State private var startedAt = Date()
    @State private var pausedAt: Date?
    private var isPlaying: Bool { pausedAt == nil }

    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var movie: Movie?
    @State private var failure: String?

    @StateObject private var finder = FilmTerrainFinder()

    /// 공유 시트에 넘길 영상. URL은 Identifiable이 아니라 감싸 둔다.
    private struct Movie: Identifiable {
        let id = UUID()
        let url: URL
    }

    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                spanPicker
                stage
                summary
                exportButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .background(Color(InkStyle.paper).ignoresSafeArea())
            .navigationTitle("내 지도가 그려지는 것")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .task(id: span) { rebuild() }
            .sheet(item: $movie) { movie in
                ShareSheet(items: [movie.url])
            }
            .alert(
                "영상을 만들지 못했어요",
                isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
            ) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
        }
    }

    // MARK: - 기간 고르기

    private var spanPicker: some View {
        Picker("기간", selection: $span) {
            ForEach(Span.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .disabled(isExporting)
    }

    // MARK: - 미리보기

    @ViewBuilder
    private var stage: some View {
        if let reel, !reel.isEmpty {
            // 내보낼 영상과 같은 비율로 보여 준다 — 본 대로 나가야 한다
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { timeline in
                let progress = Self.progress(at: timeline.date, since: startedAt)
                Canvas { context, size in
                    context.withCGContext { cgContext in
                        WalkFilm.draw(
                            reel,
                            terrain: terrain,
                            palette: palette,
                            progress: progress,
                            in: cgContext,
                            size: size
                        )
                    }
                }
                .overlay(alignment: .bottom) { dayLabel(for: reel, progress: progress) }
            }
            .aspectRatio(WalkFilmExporter.size.width / WalkFilmExporter.size.height, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                if isFindingTerrain { terrainHint }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(InkStyle.ink).opacity(0.12)))
            .onTapGesture { togglePlaying() }
            .accessibilityLabel("내 지도가 그려지는 미리보기")
            .accessibilityHint("두드리면 멈추거나 다시 재생합니다")
        } else {
            empty
        }
    }

    private func dayLabel(for reel: WalkFilm.Reel, progress: Double) -> some View {
        Text(WalkFilm.caption(reel, progress: progress))
            .font(.system(size: 15, weight: .semibold, design: .serif))
            .foregroundStyle(Color(InkStyle.ink).opacity(0.75))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 14)
            .contentTransition(.numericText())
    }

    private var terrainHint: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text("물과 산을 앉히는 중")
                .font(.caption2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(10)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.walk")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("이 기간에는 그린 길이 없어요")
                .font(.headline)
            Text("걸으면 지나온 길이 순서대로 쌓입니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 요약

    @ViewBuilder
    private var summary: some View {
        if let reel, !reel.isEmpty {
            HStack {
                Text(WalkFilm.dayFormatter.string(from: reel.start))
                Spacer(minLength: 8)
                Text("→").foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(WalkFilm.dayFormatter.string(from: reel.end))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - 내보내기

    @ViewBuilder
    private var exportButton: some View {
        if isExporting {
            VStack(spacing: 8) {
                ProgressView(value: exportProgress)
                    .tint(Color(InkStyle.sealRed))
                Text("영상을 만드는 중 \(Int(exportProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        } else {
            Button {
                export()
            } label: {
                Label("영상으로 내보내기", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(reel?.isEmpty == false ? Color(InkStyle.sealRed) : Color.secondary.opacity(0.4))
                    )
            }
            .disabled(reel?.isEmpty != false)
        }
    }

    // MARK: - 일

    private var uiStyle: UIUserInterfaceStyle {
        colorScheme == .dark ? .dark : .light
    }

    /// 화면에서 쓰는 빛깔 그대로 (영상에도 이걸 그대로 넘긴다)
    private var palette: WalkFilm.Palette {
        WalkFilm.Palette(traits: UITraitCollection(userInterfaceStyle: uiStyle))
    }

    /// 시작한 때부터 흐른 시간으로 어디까지 그렸는지 셈한다.
    /// 다 그린 뒤에는 잠깐 머물렀다가 처음으로 돌아간다 — 내보내는 영상과 같은 흐름이다.
    private static func progress(at now: Date, since start: Date) -> Double {
        let cycle = WalkFilmExporter.duration + WalkFilmExporter.holdAtEnd
        let elapsed = max(0, now.timeIntervalSince(start)).truncatingRemainder(dividingBy: cycle)
        return min(1, elapsed / WalkFilmExporter.duration)
    }

    /// 멈췄다 다시 돌릴 때 처음으로 되감기지 않도록, 쉰 만큼 시작한 때를 뒤로 민다
    private func togglePlaying() {
        if let pausedAt {
            startedAt += Date().timeIntervalSince(pausedAt)
            self.pausedAt = nil
        } else {
            pausedAt = Date()
        }
    }

    private func rebuild() {
        let end = Date()
        let earliest = track.first?.timestamp
        let start = span.start(from: end, calendar: calendar, earliest: earliest)
        let built = WalkFilm.reel(from: track, from: start, to: end)

        reel = built
        startedAt = Date()
        pausedAt = nil
        terrain = nil
        guard !built.isEmpty else { return }

        isFindingTerrain = true
        finder.find(in: built.rect) { mask in
            terrain = mask
            isFindingTerrain = false
        }
    }

    private func export() {
        guard let reel, !reel.isEmpty else { return }
        isExporting = true
        exportProgress = 0
        let palette = WalkFilm.Palette(traits: UITraitCollection(userInterfaceStyle: uiStyle))
        let terrain = terrain

        Task {
            do {
                let url = try await WalkFilmExporter.export(
                    reel: reel,
                    terrain: terrain,
                    palette: palette,
                    onProgress: { exportProgress = $0 }
                )
                isExporting = false
                movie = Movie(url: url)
            } catch {
                isExporting = false
                failure = error.localizedDescription
            }
        }
    }
}

// MARK: - 필름에 앉힐 무늬 찾기

/// TerrainFinder를 화면이 살아 있는 동안 붙들어 두기 위한 껍데기.
/// 찾는 도중에 화면이 닫히면 찍던 것을 접는다.
@MainActor
final class FilmTerrainFinder: ObservableObject {
    private let finder = TerrainFinder()

    func find(in rect: MKMapRect, then handle: @escaping (TerrainMask?) -> Void) {
        finder.find(in: rect) { result in
            switch result {
            case .found(let mask): handle(mask)
            case .bare, .failed: handle(nil)
            }
        }
    }

    deinit {
        finder.cancel()
    }
}

// MARK: - 공유

/// 영상을 다른 앱으로 넘긴다. SwiftUI의 ShareLink는 파일 URL을 그대로 넘길 때
/// 미리보기가 비어 보이는 일이 있어 UIKit 시트를 그대로 쓴다.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
