//
//  WalkIntents.swift
//  FootprintDiary
//
//  "벅뚜벅뚜, 오늘 얼마나 걸었어?" — 오늘 걸은 거리와 그중 처음 걷는 길을 알려 준다.
//  지도 화면과 같은 계산(DayWalk · WalkNovelty)을 쓴다.
//
//  남긴 일기는 Spotlight 에 싣는다(iOS 18+). Siri · Spotlight 에서 누르면 그날의 일지가 열린다.
//  일기는 하루에 하나라, 그날 자정을 id 로 쓴다.
//

import AppIntents
import CoreLocation
import CoreSpotlight
import Foundation
import SwiftData

struct TodayWalkIntent: AppIntent {
    static let title = LocalizedStringResource("오늘 걸은 길", comment: "Siri: how far I walked today")
    static let description = IntentDescription(
        LocalizedStringResource("오늘 걸은 거리와 처음 걷는 길을 알려 줍니다.", comment: "Siri: today's walk description")
    )

    @Dependency private var container: ModelContainer

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let points = (try? ModelContext(container).fetch(FetchDescriptor<TrackPoint>())) ?? []
        let walks = DayWalk.build(from: DayWalk.values(of: points))
        let today = Calendar.current.startOfDay(for: .now)
        guard let walk = walks.first(where: { $0.day == today }), walk.distance >= 10 else {
            return .result(dialog: IntentDialog(LocalizedStringResource("오늘은 아직 걸은 길이 없어요.", comment: "Siri: no walk today yet")))
        }
        let fresh = WalkNovelty.newDistances(for: walks)[today] ?? 0
        let total = Self.spoken(walk.distance)
        guard fresh >= 10 else {
            return .result(dialog: IntentDialog(LocalizedStringResource("오늘 \(total) 걸었어요.", comment: "Siri: walked today. Argument is the distance")))
        }
        return .result(dialog: IntentDialog(LocalizedStringResource("오늘 \(total) 걸었고, 그중 \(Self.spoken(fresh))는 처음 걷는 길이에요.", comment: "Siri: walked today with new roads. Arguments: total, new distance")))
    }

    private static func spoken(_ meters: CLLocationDistance) -> String {
        Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .wide, usage: .road))
    }
}

// MARK: - 일기

/// Siri · Spotlight 가 열어 달라는 날. AtlasScreen 이 일지를 열고, DiaryScreen 이 그날로 넘어간 뒤 비운다.
@MainActor @Observable
final class FootprintRouter {
    static let shared = FootprintRouter()
    var diaryDay: Date?
}

struct DiaryEntryEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("일기", comment: "Siri/Spotlight: the diary written for one day")
    )
    static let defaultQuery = DiaryEntryQuery()

    let id: String
    let day: Date
    let text: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(day.formatted(date: .long, time: .omitted))", subtitle: "\(String(text.prefix(80)))")
    }

    init(_ entry: DiaryEntry) {
        day = entry.dayStart
        id = String(Int(day.timeIntervalSince1970))
        text = entry.text
    }
}

@available(iOS 18.0, *)
extension DiaryEntryEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let set = defaultAttributeSet
        set.textContent = text
        return set
    }
}

struct DiaryEntryQuery: EntityStringQuery {
    @Dependency private var container: ModelContainer

    func entities(for identifiers: [String]) async throws -> [DiaryEntryEntity] {
        let wanted = Set(identifiers)
        return DiaryLibrary.entries(in: container).map(DiaryEntryEntity.init).filter { wanted.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [DiaryEntryEntity] {
        DiaryLibrary.entries(in: container)
            .filter { $0.text.range(of: string, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            .map(DiaryEntryEntity.init)
    }

    func suggestedEntities() async throws -> [DiaryEntryEntity] {
        Array(DiaryLibrary.entries(in: container).prefix(20)).map(DiaryEntryEntity.init)
    }
}

/// 그날의 일지를 연다. Spotlight · Siri 결과를 누르면 여기로 온다.
struct OpenDiaryIntent: OpenIntent {
    static let title = LocalizedStringResource("일기 열기", comment: "Siri/Spotlight: open the diary of a day")
    static let description = IntentDescription(
        LocalizedStringResource("그날 남긴 일기와 걸은 길을 엽니다.", comment: "Siri: open diary description")
    )

    @Parameter(title: LocalizedStringResource("일기", comment: "Siri/Spotlight: the diary written for one day"),
               description: LocalizedStringResource("열어 볼 날의 일기", comment: "Siri: diary parameter description"))
    var target: DiaryEntryEntity

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        FootprintRouter.shared.diaryDay = target.day
        return .result()
    }
}

enum DiaryLibrary {
    /// 글이 있는 일기만, 최근 날부터.
    static func entries(in container: ModelContainer) -> [DiaryEntry] {
        let descriptor = FetchDescriptor<DiaryEntry>(sortBy: [SortDescriptor(\.dayStart, order: .reverse)])
        return ((try? ModelContext(container).fetch(descriptor)) ?? []).filter { !$0.text.isEmpty }
    }

    /// Spotlight 에 싣는 일기를 지금 것에 맞춘다. 앱을 열 때와 뒤로 보낼 때 부른다.
    static func reindex(_ container: ModelContainer) async {
        guard #available(iOS 18.0, *) else { return }
        let index = CSSearchableIndex.default()
        try? await index.deleteAppEntities(ofType: DiaryEntryEntity.self)
        try? await index.indexAppEntities(entries(in: container).map(DiaryEntryEntity.init))
    }
}

// MARK: - Siri 문구

struct FootprintShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TodayWalkIntent(),
            phrases: [
                "How far did I walk today in \(.applicationName)",
                "\(.applicationName) today"
            ],
            shortTitle: "Today’s Walk",
            systemImageName: "figure.walk"
        )
    }
}
