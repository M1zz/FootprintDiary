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

    /// 일지를 보는 두 가지 방법.
    ///
    /// 목록은 걸은 날만 위에서부터 늘어놓아 '그날 무엇을 했나'를 읽게 하고,
    /// 달력은 걷지 않은 날까지 빈칸으로 남겨 '얼마나 자주 걸었나'를 보게 한다.
    /// 한 화면에 둘을 함께 담아 봤더니 어느 쪽도 제 몫을 못 했다.
    private enum Layout: String, CaseIterable {
        case list = "목록"
        case calendar = "달력"
    }

    @Query(sort: \DiaryEntry.dayStart, order: .reverse) private var diaryEntries: [DiaryEntry]
    @Query(sort: \TrackPoint.timestamp) private var track: [TrackPoint]
    /// 찍어 둔 자리들. 달력 칸에 '그날 어디에 갔었나'를 얹는 데 쓴다.
    @Query(sort: \MapStamp.createdAt) private var stamps: [MapStamp]

    @StateObject private var feed = DiaryFeedState()
    @State private var showSupport = false
    /// 마지막으로 보던 방식을 기억한다. 달력으로 보는 사람은 늘 달력으로 본다.
    @AppStorage("footprint.diaryLayout") private var layoutRaw = Layout.list.rawValue
    /// 달력에서 고른 날. 정해지면 그날 화면으로 넘어간다.
    @State private var pickedDay: Date?

    private var layout: Layout { Layout(rawValue: layoutRaw) ?? .list }

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
            Group {
                switch layout {
                case .list: listBody
                case .calendar: calendarBody
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("탐험 일지")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("보기", selection: $layoutRaw) {
                        ForEach(Layout.allCases, id: \.rawValue) { option in
                            Text(option.rawValue).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSupport = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .navigationDestination(item: $pickedDay) { day in
                DiaryDayView(day: day, walk: walk(on: day))
            }
            .sheet(isPresented: $showSupport) {
                FootprintDiarySupportView()
            }
            .onAppear { feed.rebuild(track: track, calendar: calendar) }
            .onChange(of: track.count) { feed.rebuild(track: track, calendar: calendar) }
        }
    }

    private var listBody: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(days) { entry in
                    NavigationLink {
                        DiaryDayView(day: entry.walk.day, walk: entry.walk)
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
    }

    private var calendarBody: some View {
        WalkCalendarScreen(entries: feed.entries, stampsByDay: stampsByDay) { day in
            pickedDay = calendar.startOfDay(for: day)
        }
        // 달력을 열어 본 것 자체를 센다. 화면을 새로 만들 때 가장 알고 싶은 것이
        // '이걸 아예 안 쓰는가'인데, 그 답은 이 한 줄로만 나온다.
        .task { FootprintUsage.log(.calendarOpened) }
    }

    /// 찍은 자리를 날짜별로 묶어 둔다.
    ///
    /// 칸마다 목록을 훑으면 한 달에 마흔두 번, 달을 넘길 때마다 다시 마흔두 번 훑는다.
    /// 도장이 몇 백 개가 되면 그것만으로 넘기는 것이 뻑뻑해진다.
    private var stampsByDay: [Date: [MapStamp]] {
        Dictionary(grouping: stamps.filter { !$0.isDeleted }) {
            calendar.startOfDay(for: $0.createdAt)
        }
    }

    /// 그날의 걸음. 이미 셈해 둔 것에서 찾아 쓴다 —
    /// 하루 화면에서 다시 셈하면 경로 점 전부를 또 훑게 된다.
    private func walk(on day: Date) -> DayWalk? {
        feed.entries.first { calendar.isDate($0.walk.day, inSameDayAs: day) }?.walk
    }

    private func entry(for day: Date) -> DiaryEntry? {
        diaryEntries.first { calendar.isDate($0.dayStart, inSameDayAs: day) }
    }

    private func note(for day: Date) -> String {
        entry(for: day)?.text ?? ""
    }

    private func photo(for day: Date) -> UIImage? {
        guard let data = entry(for: day)?.photosInOrder.first?.data else { return nil }
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
    /// 그날 그린 지도. 목록에서든 달력에서든 이미 셈해 둔 것을 받아 온다.
    var walk: DayWalk? = nil

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Visit.arrivalDate) private var allVisits: [Visit]
    @Query(sort: \MapStamp.createdAt) private var allStamps: [MapStamp]
    @Query private var entries: [DiaryEntry]

    @State private var text: String = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var loaded = false
    @State private var pendingSave: Task<Void, Never>?

    private var calendar: Calendar { .current }

    private var dayVisits: [Visit] {
        allVisits.filter { calendar.isDate($0.arrivalDate, inSameDayAs: day) }
    }

    /// 그날 내 손으로 찍은 자리들.
    ///
    /// 걸어서 닿은 곳(dayVisits)과 따로 둔다. 저쪽은 기기가 알아서 남긴 것이고 이쪽은
    /// 내가 '여기는 남겨 둘 만하다'고 정한 것이라, 몇 달 뒤에 되짚을 때 값이 다르다.
    private var dayStamps: [MapStamp] {
        allStamps.filter { !$0.isDeleted && calendar.isDate($0.createdAt, inSameDayAs: day) }
    }

    private var entry: DiaryEntry? {
        entries.first { calendar.isDate($0.dayStart, inSameDayAs: day) }
    }

    var body: some View {
        Form {
            // 그날 그린 지도. 배경 지도 없이 궤적만 남기므로 어디였는지는 드러나지
            // 않고 그날의 모양만 남는다. 달력 칸에서 본 것과 같은 그림이다.
            if let walk, walk.hasDrawing {
                Section {
                    DayWalkShape(
                        walk: walk,
                        freshness: WalkHeatmap.freshness(lastVisit: calendar.startOfDay(for: day), now: .now),
                        isToday: calendar.isDateInToday(day),
                        lineWidth: 3.2,
                        inset: 18
                    )
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color(InkStyle.paper))
                } footer: {
                    Text(walkSummary(walk))
                }
            }

            // 그날 찍은 자리. 달력 칸에 도장으로 얹힌 것들의 온전한 이름이 여기 있다.
            if !dayStamps.isEmpty {
                Section("이 날 찍은 자리") {
                    ForEach(dayStamps, id: \.persistentModelID) { stamp in
                        HStack(spacing: 10) {
                            StampSymbolBadge(stamp: stamp, side: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(stamp.displayName)
                                if !stamp.note.isEmpty {
                                    Text(stamp.note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Text(timeText(stamp.createdAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

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
                if let entry, entry.photoCount > 0 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(entry.photosInOrder, id: \.persistentModelID) { photo in
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

    private func walkSummary(_ walk: DayWalk) -> String {
        let distance = walk.distance < 1_000
            ? "\(Int(walk.distance))m"
            : String(format: "%.1fkm", walk.distance / 1_000)
        let minutes = Int(walk.duration / 60)
        guard minutes >= 1 else { return "이 날 걸은 길 \(distance)" }
        return "이 날 걸은 길 \(distance) · \(minutes)분"
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
        // 그날 처음 글이 생긴 순간만 센다. 글자를 고칠 때마다 세면 한 편이 수십 건이 된다.
        let wasEmpty = (entry?.text ?? "").isEmpty
        let entry = fetchOrCreateEntry()
        entry.text = text
        entry.updatedAt = .now
        try? modelContext.save()
        if wasEmpty, !text.isEmpty { FootprintUsage.log(.diaryWritten) }
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
                entry.addPhoto(DiaryPhoto(data: stored))
            }
        }
        entry.updatedAt = .now
        try? modelContext.save()
        selectedPhotos = []
    }

    private func deletePhoto(_ photo: DiaryPhoto) {
        if let entry {
            entry.removePhoto(photo)
        }
        modelContext.delete(photo)
        try? modelContext.save()
    }
}
