//
//  StampPicker.swift
//  FootprintDiary
//
//  스탬프를 고르는 화면과, 찍힌 스탬프를 들여다보는 화면.
//
//  걷다가 한 손으로 쓰는 화면이라 한 번 눌러 고르면 바로 찍히고 닫힌다.
//  이름을 적게 하거나 확인을 한 번 더 받으면 걷는 중에는 쓰지 않게 된다.
//
//  고르는 길은 갈래부터다. 200가지를 한 판에 늘어놓으면 훑는 것만으로 지치고,
//  정작 찾는 것은 "먹을 곳 중에 무엇"처럼 갈래를 먼저 떠올리게 마련이다.
//  대신 자주 쓰는 것과 이름으로 찾는 길은 갈래를 거치지 않고 첫 화면에 그대로 둔다 —
//  걷는 중에 쓰는 손은 늘 한 번이라도 덜 누르는 쪽을 고른다.
//

import SwiftUI
import SwiftData
import PhotosUI
import CoreLocation

struct StampPicker: View {
    /// 고른 스탬프를 찍는다
    let onPick: (StampKind) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    /// 최근에 쓴 스탬프 id (자주 쓰는 몇 가지를 맨 위에 둔다)
    @AppStorage("footprint.recentStamps") private var recentIDs = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if query.isEmpty {
                        if !recent.isEmpty {
                            StampGrid(title: "최근", kinds: recent, onPick: pick)
                        }
                        groupList
                    } else {
                        let found = StampCatalog.search(query)
                        if found.isEmpty {
                            Text("‘\(query)’에 맞는 스탬프가 없어요")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else {
                            StampGrid(title: "찾은 것 \(found.count)개", kinds: found, onPick: pick)
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("여기에 무엇이 있나요?")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "스탬프 찾기")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
                }
            }
            .navigationDestination(for: StampGroup.self) { group in
                StampGroupScreen(group: group, onPick: pick)
            }
        }
    }

    // MARK: - 갈래

    private var groupList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("갈래")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(StampCatalog.groups.enumerated()), id: \.element) { index, group in
                    NavigationLink(value: group) {
                        groupRow(group)
                    }
                    .buttonStyle(.plain)

                    if index < StampCatalog.groups.count - 1 {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func groupRow(_ group: StampGroup) -> some View {
        HStack(spacing: 12) {
            Image(systemName: group.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color(InkStyle.sealRed)))

            Text(group.name)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Text("\(StampCatalog.kinds(in: group).count)가지")
                .font(.caption)
                .foregroundStyle(.secondary)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.name), \(StampCatalog.kinds(in: group).count)가지")
    }

    // MARK: - 고르기

    /// 갈래 안에서 고르든 최근에서 고르든 여기 한 곳으로 모인다.
    /// 밀고 들어간 화면에서 dismiss를 부르면 시트가 아니라 그 화면만 물러난다.
    private func pick(_ kind: StampKind) {
        remember(kind)
        onPick(kind)
        dismiss()
    }

    // MARK: - 최근 쓴 것

    private var recent: [StampKind] {
        recentIDs.split(separator: ",").prefix(8).map { StampCatalog.kind(id: String($0)) }
    }

    /// 방금 쓴 것을 맨 앞으로. 200가지를 매번 훑게 하지 않으려는 장치다.
    private func remember(_ kind: StampKind) {
        var ids = recentIDs.split(separator: ",").map(String.init)
        ids.removeAll { $0 == kind.id }
        ids.insert(kind.id, at: 0)
        recentIDs = ids.prefix(8).joined(separator: ",")
    }
}

// MARK: - 갈래 하나

private struct StampGroupScreen: View {
    let group: StampGroup
    let onPick: (StampKind) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                StampGrid(title: nil, kinds: StampCatalog.kinds(in: group), onPick: onPick)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 스탬프 한 판

private struct StampGrid: View {
    let title: String?
    let kinds: [StampKind]
    let onPick: (StampKind) -> Void

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(kinds) { kind in
                    button(for: kind)
                }
            }
        }
    }

    private func button(for kind: StampKind) -> some View {
        Button {
            onPick(kind)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: kind.symbolName)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(InkStyle.sealRed)))
                Text(kind.title)
                    .font(.caption2.bold())
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.title)
    }
}

// MARK: - 찍힌 스탬프 들여다보기

/// 시트로 띄우는 겉옷. 지도에서 스탬프를 바로 두드렸을 때 쓴다.
struct StampDetailView: View {
    let stamp: MapStamp
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            StampEditor(stamp: stamp, onDelete: onDelete)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("완료") { dismiss() }
                    }
                }
        }
    }
}

/// 스탬프 하나를 들여다보고 고치는 알맹이.
///
/// 시트로 띄우기도 하고(지도에서 두드렸을 때) 목록에서 밀고 들어가기도 한다. 두 자리에서
/// 같은 것을 보여 줘야 해서 겉옷과 알맹이를 갈라 두었다.
///
/// 갈무리는 '완료'가 아니라 화면을 떠날 때 한다. 옆으로 쓸어 닫아도 적던 것이 남아야 한다.
struct StampEditor: View {
    let stamp: MapStamp
    /// 있으면 '지도에서 보기' 줄이 생긴다 (지도 위에서 연 것이면 필요 없다)
    var onShowOnMap: (() -> Void)?
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var locationManager: LocationManager

    /// 내가 붙일 이름. 비워 두면 종류 이름으로 부른다.
    @State private var name: String = ""
    @State private var note: String = ""
    @State private var loaded = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var isAddingPhotos = false
    /// 다녀온 날을 다 펼쳐 볼지 (여러 해 다닌 자리는 목록이 길어진다)
    @State private var showsAllVisits = false
    /// 이 화면에서 지웠는지. 지운 뒤에는 떠나면서 다시 쓰지 않는다.
    @State private var isGone = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: stamp.kind.symbolName)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(RoundedRectangle(cornerRadius: 11).fill(Color(InkStyle.sealRed)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(headline).font(.headline)
                        Text(subtitle)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            visiting

            // 이름은 내가 부르는 대로 붙인다. '카페'가 아니라 '퇴근길 카페'여야
            // 몇 달 뒤 지도를 열었을 때 그 자리가 무엇이었는지 되살아난다.
            Section("이름") {
                TextField(stamp.kind.title, text: $name)
                    .submitLabel(.done)
            }

            Section("메모") {
                TextField("덧붙일 말 (없어도 됩니다)", text: $note, axis: .vertical)
                    .lineLimit(1...4)
            }

            photos

            if let onShowOnMap {
                Section {
                    Button {
                        save()
                        dismiss()
                        onShowOnMap()
                    } label: {
                        Label("지도에서 보기", systemImage: "map")
                    }
                }
            }

            Section {
                Button("이 스탬프 지우기", role: .destructive) {
                    // 떠나면서 도는 갈무리보다 먼저 못을 박는다.
                    // 이름을 고친 뒤 지우면 '적던 것과 다르다'는 셈이 서서, 지워진 자리에
                    // 이름을 다시 쓰고 저장하게 된다.
                    isGone = true
                    onDelete()
                    dismiss()
                }
            }
        }
        .navigationTitle("스탬프")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 여는 동안에는 위치를 계속 받는다. 한 번만 받아 두면 가게 앞까지 걸어 들어가도
            // 거리가 그대로라, 다 왔는데도 단추가 잠긴 채로 보인다.
            locationManager.startLiveUpdates()
            locationManager.refreshCurrentLocation()
            guard !loaded else { return }
            name = stamp.placeName
            note = stamp.note
            loaded = true
        }
        .onDisappear {
            locationManager.stopLiveUpdates()
            save()
        }
        .onChange(of: picked) {
            Task { await addPhotos() }
        }
    }

    // MARK: - 다시 다녀오기

    /// 같은 자리에 다시 온 것을 하루 한 번 세어 둔다.
    ///
    /// 스탬프는 '처음 찾은 자리'를 남기는 것인데, 정작 오래 남는 자리는 처음 간 곳이 아니라
    /// 자꾸 가는 곳이다. 그 둘을 한 화면에서 가르려면 횟수와 날이 함께 있어야 한다.
    ///
    /// 근처에 서 있을 때만 셀 수 있게 막아 둔다. 집에서 목록을 넘기다가 눌러 올릴 수 있으면
    /// 이 숫자는 발걸음이 아니라 손가락을 세는 것이 된다.
    @ViewBuilder
    private var visiting: some View {
        Section {
            LabeledContent("다녀온 횟수") {
                Text("\(stamp.visitCount)번")
                    .font(.body.weight(.semibold))
                    .contentTransition(.numericText())
            }
            LabeledContent("마지막 방문") {
                Text(visitDayText(stamp.lastVisitedAt))
            }
            visitButton
            visitHistory
        } header: {
            Text("방문")
        } footer: {
            Text(visitFooter)
        }
    }

    private var visitButton: some View {
        Button {
            addVisit()
        } label: {
            Label(
                alreadyToday ? "오늘은 이미 남겼어요" : "여기 다녀왔어요",
                systemImage: alreadyToday ? "checkmark.seal.fill" : "seal"
            )
        }
        .disabled(alreadyToday || !isHere)
        .accessibilityHint(visitFooter)
    }

    /// 다녀온 날들. 가장 나중에 온 날이 위다 — 되짚어 볼 때 궁금한 것은 늘 최근 쪽이다.
    @ViewBuilder
    private var visitHistory: some View {
        let days = stamp.visitDates.reversed().map { $0 }
        if days.count > 1 {
            let shown = showsAllVisits ? days : Array(days.prefix(3))
            ForEach(Array(shown.enumerated()), id: \.offset) { index, date in
                HStack {
                    Text(visitDayText(date))
                        .font(.subheadline)
                    Spacer()
                    // 마지막 칸이 곧 처음 찍은 날이다 (visitDates의 첫 자리를 뒤집어 놓은 것)
                    Text(index == days.count - 1 ? "처음 찍은 날" : "\(days.count - index)번째")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if days.count > 3 {
                Button(showsAllVisits ? "접기" : "\(days.count - 3)번 더 보기") {
                    showsAllVisits.toggle()
                }
                .font(.subheadline)
            }
        }
    }

    /// 오늘 몫을 이미 셌는지
    private var alreadyToday: Bool {
        !stamp.canAddVisit()
    }

    /// 지금 선 자리에서 이 스탬프까지의 거리(m). 위치를 아직 못 찾았으면 없다.
    private var distanceFromHere: CLLocationDistance? {
        locationManager.currentLocation.map { stamp.distance(from: $0) }
    }

    private var isHere: Bool {
        guard let distanceFromHere else { return false }
        return distanceFromHere <= MapStamp.visitRadius
    }

    private var visitFooter: String {
        if alreadyToday {
            return "하루에 한 번만 셉니다. 내일 다시 오면 또 남길 수 있어요."
        }
        guard let distanceFromHere else {
            return "현재 위치를 찾는 중이에요. 위치를 켜고 이 자리 근처에 오면 남길 수 있습니다."
        }
        if distanceFromHere <= MapStamp.visitRadius {
            return "지금 이 자리에 있어요. 눌러서 다녀온 것으로 남기세요."
        }
        return "여기서 \(distanceText(distanceFromHere)) 떨어져 있어요. \(Int(MapStamp.visitRadius))m 안에 들어가면 남길 수 있습니다."
    }

    private func addVisit() {
        // 화면이 그려진 뒤에 멀어졌거나 날이 넘어갔을 수 있으니 누르는 순간에 한 번 더 본다
        guard let location = locationManager.currentLocation,
              stamp.isNearby(location),
              stamp.canAddVisit() else { return }
        stamp.addVisit()
        try? modelContext.save()
    }

    private func distanceText(_ meters: CLLocationDistance) -> String {
        meters < 1_000 ? "\(Int(meters))m" : String(format: "%.1fkm", meters / 1_000)
    }

    /// 오늘·어제는 그렇게 부른다. 날짜로만 적으면 방금 남긴 것도 한눈에 안 들어온다.
    private func visitDayText(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = StampEditor.clock.string(from: date)
        if calendar.isDateInToday(date) { return "오늘 \(time)" }
        if calendar.isDateInYesterday(date) { return "어제 \(time)" }
        return StampEditor.day.string(from: date)
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h:mm"
        return formatter
    }()

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일 (E)"
        return formatter
    }()

    // MARK: - 사진

    @ViewBuilder
    private var photos: some View {
        Section("사진") {
            if stamp.photoCount > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(stamp.photosInOrder, id: \.persistentModelID) { photo in
                            thumbnail(photo)
                        }
                    }
                }
                .frame(height: 96)
            }
            PhotosPicker(selection: $picked, maxSelectionCount: 10, matching: .images) {
                Label(stamp.photoCount == 0 ? "이 자리의 사진 넣기" : "사진 더 넣기", systemImage: "photo.badge.plus")
            }
            .disabled(isAddingPhotos)
            if isAddingPhotos {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("사진을 넣는 중").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ photo: StampPhoto) -> some View {
        if let image = UIImage(data: photo.data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contextMenu {
                    Button("사진 지우기", role: .destructive) { delete(photo) }
                }
        }
    }

    private func addPhotos() async {
        guard !picked.isEmpty else { return }
        isAddingPhotos = true
        for item in picked {
            if let data = try? await item.loadTransferable(type: Data.self) {
                // 원본을 그대로 담으면 한 장에 수십 MB가 된다. 보여 줄 만한 크기로 줄인다.
                let stored = await Task.detached(priority: .userInitiated) {
                    PhotoStore.downscaledJPEG(from: data) ?? data
                }.value
                stamp.addPhoto(StampPhoto(data: stored))
            }
        }
        try? modelContext.save()
        picked = []
        isAddingPhotos = false
    }

    private func delete(_ photo: StampPhoto) {
        stamp.removePhoto(photo)
        modelContext.delete(photo)
        try? modelContext.save()
    }

    // MARK: - 글

    private var headline: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? stamp.kind.title : trimmed
    }

    /// 이름을 붙였으면 종류가 곁줄로 내려온다 — 무엇으로 찍었는지는 남아 있어야 한다
    private var subtitle: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "\(stamp.kind.group) · \(dateText)"
        }
        return "\(stamp.kind.title) · \(stamp.kind.group) · \(dateText)"
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E) a h:mm"
        return formatter.string(from: stamp.createdAt)
    }

    private func save() {
        guard loaded, !isGone, !stamp.isDeleted else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != stamp.placeName || note != stamp.note else { return }
        stamp.placeName = trimmed
        stamp.note = note
        try? modelContext.save()
    }
}
