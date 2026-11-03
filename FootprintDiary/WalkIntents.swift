//
//  WalkIntents.swift
//  FootprintDiary
//
//  "벅뚜벅뚜, 오늘 얼마나 걸었어?" — 오늘 걸은 거리와 그중 처음 걷는 길을 알려 준다.
//  지도 화면과 같은 계산(DayWalk · WalkNovelty)을 쓴다.
//

import AppIntents
import CoreLocation
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
