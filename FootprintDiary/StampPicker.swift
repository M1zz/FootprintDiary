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
    /// 지금 그 자리에 서서 찍는 것인지. 거짓이면 아직 가보지 않은 자리에 미리 찍는 것이다.
    ///
    /// 고르는 것은 똑같지만 묻는 말이 달라야 한다. 안 가본 자리를 두고 "여기에 무엇이
    /// 있나요"라고 물으면 없는 것을 아는 척 답하게 되고, 무엇보다 지금 남기는 것이
    /// 다녀온 기록이 아니라는 것을 고르기 전에 알아야 한다.
    var isHere: Bool = true
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
            .navigationTitle(isHere ? "여기에 무엇이 있나요?" : "저기에 무엇이 있나요?")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                if !isHere { plannedNotice }
            }
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

    /// 아직 안 가본 자리에 찍는 중이라는 알림.
    ///
    /// 고르고 난 뒤에 알려 주면 늦다 — 다 찍고 나서야 다녀온 기록이 아니라는 것을
    /// 알게 되면, 되돌리려고 지우는 수밖에 없다.
    private var plannedNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "signpost.right.and.left")
                .foregroundStyle(Color(InkStyle.sealRed))
            Text("아직 가보지 않은 자리예요. ‘가볼 곳’으로 남고, 그 자리에 닿으면 다녀온 곳이 됩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
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
    /// 스티커를 찍는 카메라를 띄우고 있는지
    @State private var isMakingSticker = false
    /// 찍어 둔 스티커를 크게 들여다보고 있는지
    @State private var isViewingSticker = false
    /// 다녀온 날을 다 펼쳐 볼지 (여러 해 다닌 자리는 목록이 길어진다)
    @State private var showsAllVisits = false
    /// 이 화면에서 지웠는지. 지운 뒤에는 떠나면서 다시 쓰지 않는다.
    @State private var isGone = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    // 지도의 도장은 30pt 남짓으로 작게 서므로(그래야 자리마다 무게가
                    // 같다), 무엇을 찍었는지 확인하는 일은 이 화면이 맡는다.
                    // 갈래 그림도 같은 크기로 선다 — 한 화면 안에서 둘의 크기가 갈리면
                    // 심볼을 넣은 자리가 더 대단한 것처럼 보인다.
                    //
                    // 56pt로도 모자라면 두드려서 화면 가득 펼친다. 찍어 놓고 무엇이
                    // 찍혔는지 못 보는 일이 없어야 한다. 두드릴 것이 있다는 표는
                    // 아래 '심볼' 칸의 '크게 보기'가 대신 세운다 — 딱지에 돋보기를
                    // 얹으면 정작 심볼이 가려진다.
                    stickerBadge
                    VStack(alignment: .leading, spacing: 2) {
                        Text(headline).font(.headline)
                        Text(subtitle)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            visiting

            symbol

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
        .fullScreenCover(isPresented: $isViewingSticker) {
            if let data = stamp.sticker, let image = StickerMaker.displayImage(from: data) {
                StickerViewer(image: image, title: headline)
            } else {
                // 열려는 사이에 스티커가 지워졌으면 빈 창만 남는다. 닫을 것이 없는
                // 검은 화면에 갇히지 않도록 그대로 물러선다.
                Color.clear.onAppear { isViewingSticker = false }
            }
        }
        .fullScreenCover(isPresented: $isMakingSticker) {
            // 전체 화면으로 띄운다. 카메라는 눈앞의 것을 겨누는 일이라 시트로 반쯤
            // 올라오면 창이 좁아 무엇을 담을지 가늠할 수 없다.
            StickerCameraScreen { data in
                stamp.stickerData = data
                try? modelContext.save()
                FootprintUsage.log(.stickerMade)
            }
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
            if stamp.isUnvisited {
                // 횟수도 마지막 방문도 적을 것이 없다. 0번이라고 적어 두면 다녀온
                // 자리와 같은 칸에서 견주게 되어, 성격이 다른 기록이 '덜 간 곳'으로 읽힌다.
                LabeledContent("아직") {
                    Text("가보지 않은 곳")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color(InkStyle.sealRed))
                }
                LabeledContent("찍어 둔 날") {
                    Text(visitDayText(stamp.createdAt))
                }
            } else {
                LabeledContent("다녀온 횟수") {
                    Text("\(stamp.visitCount)번")
                        .font(.body.weight(.semibold))
                        .contentTransition(.numericText())
                }
                if let last = stamp.lastVisitedAt {
                    LabeledContent("마지막 방문") {
                        Text(visitDayText(last))
                    }
                }
                // 가볼 곳으로 찍어 두었다가 정말로 간 자리는 그 이야기를 남긴다.
                if stamp.isPlanned {
                    LabeledContent("처음") {
                        Text("가볼 곳으로 찍어 뒀던 자리")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            visitButton
            visitHistory
        } header: {
            Text(stamp.isUnvisited ? "가볼 곳" : "방문")
        } footer: {
            Text(visitFooter)
        }
    }

    private var visitButton: some View {
        Button {
            addVisit()
        } label: {
            Label(visitButtonTitle, systemImage: alreadyToday ? "checkmark.seal.fill" : "seal")
        }
        .disabled(alreadyToday || !isHere)
        .accessibilityHint(visitFooter)
    }

    private var visitButtonTitle: String {
        if alreadyToday { return "오늘은 이미 남겼어요" }
        // 안 가본 자리의 첫 걸음은 '한 번 더'가 아니라 '가본 곳이 되는' 일이다.
        return stamp.isUnvisited ? "여기 왔어요 — 가본 곳으로" : "여기 다녀왔어요"
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
                    // 마지막 칸이 곧 처음 간 날이다 (visitDates의 첫 자리를 뒤집어 놓은 것).
                    // '찍은 날'이라 하지 않는 까닭은, 가볼 곳으로 미리 찍어 둔 자리는
                    // 찍은 날과 처음 간 날이 다르기 때문이다.
                    Text(index == days.count - 1 ? "처음 간 날" : "\(days.count - index)번째")
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
        let planned = stamp.isUnvisited
        guard let distanceFromHere else {
            return planned
                ? "아직 가보지 않은 자리라 다녀온 횟수를 세지 않습니다. 위치를 켜고 이 자리에 닿으면 가본 곳이 됩니다."
                : "현재 위치를 찾는 중이에요. 위치를 켜고 이 자리 근처에 오면 남길 수 있습니다."
        }
        if distanceFromHere <= MapStamp.visitRadius {
            return planned
                ? "지금 이 자리에 있어요. 눌러서 가본 곳으로 굳히세요."
                : "지금 이 자리에 있어요. 눌러서 다녀온 것으로 남기세요."
        }
        let gap = "여기서 \(distanceText(distanceFromHere)) 떨어져 있어요. \(Int(MapStamp.visitRadius))m 안에 들어가면 "
        return gap + (planned ? "가본 곳이 됩니다." : "남길 수 있습니다.")
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

    // MARK: - 심볼

    /// 머리에 서는 딱지. 스티커가 있으면 두드려서 크게 볼 수 있다.
    ///
    /// 갈래 그림뿐일 때는 두드려도 나올 것이 없다 — 이미 다 보이는 그림을 화면 가득
    /// 펼쳐 봐야 그 그림 그대로다. 그때는 단추로 만들지 않는다. 눌리는데 아무 일도
    /// 일어나지 않는 자리는, 눌리지 않는 자리보다 더 고장 난 것처럼 보인다.
    @ViewBuilder
    private var stickerBadge: some View {
        if stamp.sticker != nil {
            Button {
                isViewingSticker = true
            } label: {
                StampSymbolBadge(stamp: stamp, side: 56, corner: 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("심볼 크게 보기")
        } else {
            StampSymbolBadge(stamp: stamp, side: 56, corner: 14)
        }
    }

    /// 지도에 얹히는 그림 한 장.
    ///
    /// 사진과 갈라 둔 까닭은 하는 일이 다르기 때문이다. 사진은 '거기가 어땠나'를 남기는
    /// 것이라 여러 장이어도 되고 들춰 봐야 보이지만, 심볼은 지도에서 '어느 자리인가'를
    /// 알아보게 하는 것이라 딱 한 장이고 늘 보인다. 한 섹션에 같이 두면 사진을 넣다가
    /// 지도가 바뀌어 놀라게 된다.
    @ViewBuilder
    private var symbol: some View {
        Section {
            if stamp.sticker != nil {
                Button {
                    isViewingSticker = true
                } label: {
                    Label("크게 보기", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .foregroundStyle(.primary)
            }

            Button {
                isMakingSticker = true
            } label: {
                Label(stamp.sticker == nil ? "스티커 추가하기" : "스티커 다시 찍기",
                      systemImage: "camera.viewfinder")
            }
            .foregroundStyle(.primary)

            if stamp.sticker != nil {
                Button("기본 그림으로 되돌리기", role: .destructive) {
                    stamp.stickerData = nil
                    try? modelContext.save()
                }
            }
        } header: {
            Text("심볼")
        } footer: {
            Text(stamp.sticker == nil
                 ? "카메라로 찍어 이 자리만의 심볼을 만들 수 있어요. 지도에 그 그림이 찍힙니다."
                 : "지도에는 이 스티커가 찍혀요.")
        }
    }

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
                Label("이미지 추가하기", systemImage: "photo.badge.plus")
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
