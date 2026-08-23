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

    /// 내가 붙일 이름. 비워 두면 종류 이름으로 부른다.
    @State private var name: String = ""
    @State private var note: String = ""
    @State private var loaded = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var isAddingPhotos = false

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
                    onDelete()
                    dismiss()
                }
            }
        }
        .navigationTitle("스탬프")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            name = stamp.placeName
            note = stamp.note
            loaded = true
        }
        .onDisappear { save() }
        .onChange(of: picked) {
            Task { await addPhotos() }
        }
    }

    // MARK: - 사진

    @ViewBuilder
    private var photos: some View {
        Section("사진") {
            if !stamp.photos.isEmpty {
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
                Label(stamp.photos.isEmpty ? "이 자리의 사진 넣기" : "사진 더 넣기", systemImage: "photo.badge.plus")
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
                stamp.photos.append(StampPhoto(data: stored))
            }
        }
        try? modelContext.save()
        picked = []
        isAddingPhotos = false
    }

    private func delete(_ photo: StampPhoto) {
        stamp.photos.removeAll { $0.persistentModelID == photo.persistentModelID }
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
        guard loaded else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != stamp.placeName || note != stamp.note else { return }
        stamp.placeName = trimmed
        stamp.note = note
        try? modelContext.save()
    }
}
