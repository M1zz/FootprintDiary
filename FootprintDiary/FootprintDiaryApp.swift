//
//  FootprintDiaryApp.swift
//  FootprintDiary
//
//  발자국일기 — 하루의 이동을 지도에 발자국으로 기록하고 일기를 쓰는 앱
//

import SwiftUI
import SwiftData

@main
struct FootprintDiaryApp: App {

    let container: ModelContainer
    @StateObject private var locationManager: LocationManager

    init() {
        do {
            let container = try ModelContainer(
                for: Visit.self, DiaryEntry.self, DiaryPhoto.self
            )
            self.container = container
            let manager = LocationManager()
            manager.modelContainer = container
            // 백그라운드에서 위치 이벤트로 앱이 다시 실행됐을 때도
            // 모니터링이 즉시 재개되도록 초기화 시점에 시작한다.
            manager.startMonitoringIfAuthorized()
            _locationManager = StateObject(wrappedValue: manager)
        } catch {
            fatalError("SwiftData 컨테이너 생성 실패: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationManager)
        }
        .modelContainer(container)
    }
}
