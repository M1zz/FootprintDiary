//
//  StampPicker.swift
//  FootprintDiary
//
//  스탬프를 고르는 화면과, 찍힌 스탬프를 들여다보는 화면.
//
//  걷다가 한 손으로 쓰는 화면이라 한 번 눌러 고르면 바로 찍히고 닫힌다.
//  이름을 적게 하거나 확인을 한 번 더 받으면 걷는 중에는 쓰지 않게 된다.
//

import SwiftUI
import CoreLocation

struct StampPicker: View {
    /// 고른 스탬프를 찍는다
    let onPick: (StampKind) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    /// 최근에 쓴 스탬프 id (자주 쓰는 몇 가지를 맨 위에 둔다)
    @AppStorage("footprint.recentStamps") private var recentIDs = ""

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                    if query.isEmpty {
                        if !recent.isEmpty {
                            section("최근", recent)
                        }
                        ForEach(StampCatalog.groups, id: \.self) { group in
                            section(group, StampCatalog.kinds(in: group))
                        }
                    } else {
                        let found = StampCatalog.search(query)
                        if found.isEmpty {
                            Text("‘\(query)’에 맞는 스탬프가 없어요")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else {
                            section("찾은 것 \(found.count)개", found)
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
        }
    }

    // MARK: - 조각

    @ViewBuilder
    private func section(_ title: String, _ kinds: [StampKind]) -> some View {
        Section {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(kinds) { kind in
                    button(for: kind)
                }
            }
        } header: {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .background(Color(.systemGroupedBackground))
        }
    }

    private func button(for kind: StampKind) -> some View {
        Button {
            remember(kind)
            onPick(kind)
            dismiss()
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

// MARK: - 찍힌 스탬프 들여다보기

struct StampDetailView: View {
    let stamp: MapStamp
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: stamp.kind.symbolName)
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(RoundedRectangle(cornerRadius: 11).fill(Color(InkStyle.sealRed)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stamp.kind.title).font(.headline)
                            Text("\(stamp.kind.group) · \(dateText)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("메모") {
                    TextField("덧붙일 말 (없어도 됩니다)", text: $note, axis: .vertical)
                        .lineLimit(1...4)
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") {
                        stamp.note = note
                        dismiss()
                    }
                }
            }
            .onAppear { note = stamp.note }
        }
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E) a h:mm"
        return formatter.string(from: stamp.createdAt)
    }
}
