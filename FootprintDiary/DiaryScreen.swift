//
//  DiaryScreen.swift
//  FootprintDiary
//
//  하루 단위 일기 목록과 편집 화면 (텍스트 + 사진)
//

import SwiftUI
import SwiftData
import PhotosUI

struct DiaryScreen: View {
    @Query(sort: \Visit.arrivalDate, order: .reverse) private var allVisits: [Visit]
    @Query(sort: \DiaryEntry.dayStart, order: .reverse) private var entries: [DiaryEntry]

    private var calendar: Calendar { .current }

    /// 발자국이 있거나 일기가 있는 날짜들 (최신순)
    private var days: [Date] {
        var set = Set<Date>()
        for visit in allVisits { set.insert(calendar.startOfDay(for: visit.arrivalDate)) }
        for entry in entries { set.insert(calendar.startOfDay(for: entry.dayStart)) }
        set.insert(calendar.startOfDay(for: .now))
        return set.sorted(by: >)
    }

    var body: some View {
        NavigationStack {
            List(days, id: \.self) { day in
                NavigationLink {
                    DiaryDayView(day: day)
                } label: {
                    dayRow(day)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("일기")
        }
    }

    @ViewBuilder
    private func dayRow(_ day: Date) -> some View {
        let entry = entries.first { calendar.isDate($0.dayStart, inSameDayAs: day) }
        let visitCount = allVisits.filter { calendar.isDate($0.arrivalDate, inSameDayAs: day) }.count

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(dayTitle(day))
                    .font(.headline)
                Spacer()
                if visitCount > 0 {
                    Label("\(visitCount)", systemImage: "shoeprints.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let entry, !entry.photos.isEmpty {
                    Label("\(entry.photos.count)", systemImage: "photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let entry, !entry.text.isEmpty {
                Text(entry.text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("아직 일기가 없어요")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
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
                Section("오늘의 발자국") {
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

            Section("일기") {
                TextEditor(text: $text)
                    .frame(minHeight: 160)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("오늘 하루는 어땠나요?")
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
                    Self.downscaledJPEG(from: data) ?? data
                }.value
                entry.photos.append(DiaryPhoto(data: stored))
            }
        }
        entry.updatedAt = .now
        try? modelContext.save()
        selectedPhotos = []
    }

    /// 긴 변이 maxDimension을 넘는 사진을 JPEG으로 줄여 저장 용량과 디코딩 비용을 낮춘다
    private static func downscaledJPEG(from data: Data, maxDimension: CGFloat = 1600) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longSide = max(image.size.width, image.size.height)
        guard longSide > maxDimension else { return data }
        let scale = maxDimension / longSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }

    private func deletePhoto(_ photo: DiaryPhoto) {
        if let entry {
            entry.photos.removeAll { $0.persistentModelID == photo.persistentModelID }
        }
        modelContext.delete(photo)
        try? modelContext.save()
    }
}
