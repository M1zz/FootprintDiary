//
//  DiaryScreen.swift
//  FootprintDiary
//
//  하루 단위 일기 목록과 편집 화면 (텍스트 + 사진)
//

import SwiftUI
import SwiftData
import PhotosUI

/// 카드에 필요한 계산을 한 번만 해서 들고 있는 상자.
/// 걸음이 쌓일수록 무거워지므로 본문에서 매번 하지 않고 백그라운드에서 만든다.
@MainActor
final class DiaryFeedState: ObservableObject {
    @Published private(set) var entries: [DayEntry] = []
    private var signature: Int?

    func rebuild(track: [TrackPoint], calendar: Calendar) {
        guard signature != track.count else { return }
        signature = track.count

        let points = DayWalk.values(of: track)
        Task.detached(priority: .userInitiated) {
            let walks = DayWalk.build(from: points, calendar: calendar)
            let novelty = WalkNovelty.newDistances(for: walks)
            let built = walks.map { DayEntry(walk: $0, newDistance: novelty[$0.day] ?? 0) }
            await MainActor.run { self.entries = built }
        }
    }
}

struct DiaryScreen: View {
    @Query(sort: \DiaryEntry.dayStart, order: .reverse) private var diaryEntries: [DiaryEntry]
    @Query(sort: \TrackPoint.timestamp) private var track: [TrackPoint]

    @StateObject private var feed = DiaryFeedState()
    @State private var showSupport = false

    private var calendar: Calendar { .current }

    /// 걸음이 남은 날들 (최신순). 오늘은 걷지 않았어도 늘 맨 위에 둔다.
    private var days: [DayEntry] {
        var built = feed.entries
        let today = calendar.startOfDay(for: .now)
        if !built.contains(where: { calendar.isDate($0.walk.day, inSameDayAs: today) }) {
            built.insert(DayEntry(walk: .empty(on: today), newDistance: 0), at: 0)
        }
        return built
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(days) { entry in
                        NavigationLink {
                            DiaryDayView(day: entry.walk.day)
                        } label: {
                            WalkDayCard(
                                entry: entry,
                                title: dayTitle(entry.walk.day),
                                note: note(for: entry.walk.day),
                                photo: photo(for: entry.walk.day)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("탐험 일지")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSupport = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSupport) {
                FootprintDiarySupportView()
            }
            .onAppear { feed.rebuild(track: track, calendar: calendar) }
            .onChange(of: track.count) { feed.rebuild(track: track, calendar: calendar) }
        }
    }

    private func entry(for day: Date) -> DiaryEntry? {
        diaryEntries.first { calendar.isDate($0.dayStart, inSameDayAs: day) }
    }

    private func note(for day: Date) -> String {
        entry(for: day)?.text ?? ""
    }

    private func photo(for day: Date) -> UIImage? {
        guard let data = entry(for: day)?
            .photos
            .sorted(by: { $0.createdAt < $1.createdAt })
            .first?
            .data else { return nil }
        return UIImage(data: data)
    }

    private func dayTitle(_ day: Date) -> String {
        if calendar.isDateInToday(day) { return "오늘" }
        if calendar.isDateInYesterday(day) { return "어제" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E)"
        return formatter.string(from: day)
    }
}

// MARK: - 하루 일기 편집

struct DiaryDayView: View {
    let day: Date

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Visit.arrivalDate) private var allVisits: [Visit]
    @Query private var entries: [DiaryEntry]

    @State private var text: String = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var loaded = false
    @State private var pendingSave: Task<Void, Never>?

    private var calendar: Calendar { .current }

    private var dayVisits: [Visit] {
        allVisits.filter { calendar.isDate($0.arrivalDate, inSameDayAs: day) }
    }

    private var entry: DiaryEntry? {
        entries.first { calendar.isDate($0.dayStart, inSameDayAs: day) }
    }

    var body: some View {
        Form {
            // 그날의 발자국 요약
            if !dayVisits.isEmpty {
                Section("걸어서 닿은 곳") {
                    ForEach(Array(dayVisits.enumerated()), id: \.element.persistentModelID) { index, visit in
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Color.accentColor.opacity(0.2)))
                            Text(visit.displayName)
                            Spacer()
                            Text(timeText(visit.arrivalDate))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("오늘의 탐험") {
                TextEditor(text: $text)
                    .frame(minHeight: 160)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("오늘은 어디를 탐험했나요?")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                    }
            }

            Section("사진") {
                if let entry, !entry.photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(entry.photos.sorted(by: { $0.createdAt < $1.createdAt }),
                                    id: \.persistentModelID) { photo in
                                photoThumbnail(photo)
                            }
                        }
                    }
                    .frame(height: 96)
                }
                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 10, matching: .images) {
                    Label("사진 추가", systemImage: "photo.badge.plus")
                }
            }
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            text = entry?.text ?? ""
            loaded = true
        }
        .onChange(of: text) {
            // 키 입력마다 디스크에 쓰지 않도록 입력이 멎은 뒤 저장한다
            pendingSave?.cancel()
            pendingSave = Task {
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard !Task.isCancelled else { return }
                saveText()
            }
        }
        .onDisappear {
            pendingSave?.cancel()
            saveText()
        }
        .onChange(of: selectedPhotos) {
            Task { await addPhotos() }
        }
    }

    // MARK: - 하위 뷰

    @ViewBuilder
    private func photoThumbnail(_ photo: DiaryPhoto) -> some View {
        if let uiImage = UIImage(data: photo.data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contextMenu {
                    Button("삭제", role: .destructive) {
                        deletePhoto(photo)
                    }
                }
        }
    }

    private var navTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E)"
        return formatter.string(from: day)
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h:mm"
        return formatter.string(from: date)
    }

    // MARK: - 저장

    /// 일기 엔트리를 가져오거나 새로 만든다.
    private func fetchOrCreateEntry() -> DiaryEntry {
        if let entry { return entry }
        let newEntry = DiaryEntry(dayStart: calendar.startOfDay(for: day))
        modelContext.insert(newEntry)
        return newEntry
    }

    private func saveText() {
        guard loaded else { return }
        // 내용이 그대로면 저장하지 않는다 (빈 일기 생성 방지 포함)
        guard text != (entry?.text ?? "") else { return }
        let entry = fetchOrCreateEntry()
        entry.text = text
        entry.updatedAt = .now
        try? modelContext.save()
    }

    private func addPhotos() async {
        guard !selectedPhotos.isEmpty else { return }
        let entry = fetchOrCreateEntry()
        for item in selectedPhotos {
            if let data = try? await item.loadTransferable(type: Data.self) {
                // 원본(수 MB~수십 MB)을 그대로 저장하지 않고 화면 표시에 충분한 크기로 줄인다
                let stored = await Task.detached(priority: .userInitiated) {
                    PhotoStore.downscaledJPEG(from: data) ?? data
                }.value
                entry.photos.append(DiaryPhoto(data: stored))
            }
        }
        entry.updatedAt = .now
        try? modelContext.save()
        selectedPhotos = []
    }

    private func deletePhoto(_ photo: DiaryPhoto) {
        if let entry {
            entry.photos.removeAll { $0.persistentModelID == photo.persistentModelID }
        }
        modelContext.delete(photo)
        try? modelContext.save()
    }
}
