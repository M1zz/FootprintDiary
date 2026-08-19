//
//  FootprintDiaryApp.swift
//  FootprintDiary
//
//  발자국일기 — 하루의 이동을 지도에 발자국으로 기록하고 일기를 쓰는 앱
//

import SwiftUI
import SwiftData
import LeeoKit

@main
struct FootprintDiaryApp: App {

    let container: ModelContainer
    @StateObject private var locationManager: LocationManager

    init() {
        do {
            // 피드백 허브용 CloudKit entitlement 때문에 SwiftData가 로컬 스토어까지
            // 자동으로 CloudKit 동기화 대상으로 삼으려 한다. 현재 스키마는 CloudKit
            // 요구사항(모든 속성 기본값/옵셔널, 관계의 inverse)을 만족하지 않으므로
            // 앱 데이터 스토어는 명시적으로 CloudKit을 끈다.
            let schema = Schema([
                Visit.self, DiaryEntry.self, DiaryPhoto.self, PhotoSpot.self, TrackPoint.self,
                MapStamp.self
            ])
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: configuration)
            self.container = container
            let manager = LocationManager()
            manager.modelContainer = container
            // 백그라운드에서 위치 이벤트로 앱이 다시 실행됐을 때도
            // 모니터링이 즉시 재개되도록 초기화 시점에 시작한다.
            manager.startMonitoringIfAuthorized()
            _locationManager = StateObject(wrappedValue: manager)
            LeeoEngagement.shared.registerLaunch()
        } catch {
            fatalError("SwiftData 컨테이너 생성 실패: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationManager)
                .leeoSatisfactionCheck(FootprintDiarySpec.self)
        }
        .modelContainer(container)
    }
}
