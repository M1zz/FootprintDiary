//
//  FootprintDiaryApp.swift
//  FootprintDiary
//
//  벅터벅터 — 하루의 이동을 지도에 발자국으로 기록하고 일기를 쓰는 앱
//

import SwiftUI
import SwiftData
import LeeoKit

@main
struct FootprintDiaryApp: App {

    let container: ModelContainer
    @StateObject private var locationManager: LocationManager
    @StateObject private var cloudSync = CloudSync()

    init() {
        // 걸음·스탬프·일기를 내 아이클라우드(개인 데이터베이스)에 함께 둔다.
        // 이 스키마의 모든 속성에 기본값이 있고 관계마다 짝이 있는 것은 그 조건을 맞추기
        // 위해서다 — 까닭은 Models.swift 머리말에 적어 두었다.
        let schema = Schema([
            Visit.self, DiaryEntry.self, DiaryPhoto.self, PhotoSpot.self, TrackPoint.self,
            MapStamp.self, StampPhoto.self, StampVisit.self
        ])

        // 아이클라우드를 붙이지 못하는 날이 있다 — 그릇이 아직 안 만들어졌거나, 기기가
        // 막고 있거나, 알 수 없는 까닭으로. 그때 앱이 아예 안 켜지면 기기 안에 멀쩡히 있는
        // 기록까지 못 보게 된다. 붙여 보고, 안 되면 같은 파일을 기기 안에서만 연다.
        // (저장 자리가 같으므로 되돌아와도 기록은 그대로다)
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    cloudKitDatabase: .private(CloudSync.containerID)
                )
            )
            CloudSync.isAttached = true
        } catch {
            do {
                container = try ModelContainer(
                    for: schema,
                    configurations: ModelConfiguration(
                        schema: schema,
                        isStoredInMemoryOnly: false,
                        cloudKitDatabase: .none
                    )
                )
                CloudSync.isAttached = false
            } catch {
                fatalError("SwiftData 컨테이너 생성 실패: \(error)")
            }
        }

        self.container = container
        let manager = LocationManager()
        manager.modelContainer = container
        // 백그라운드에서 위치 이벤트로 앱이 다시 실행됐을 때도
        // 모니터링이 즉시 재개되도록 초기화 시점에 시작한다.
        manager.startMonitoringIfAuthorized()
        _locationManager = StateObject(wrappedValue: manager)
        LeeoEngagement.shared.registerLaunch()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationManager)
                .environmentObject(cloudSync)
                .leeoSatisfactionCheck(FootprintDiarySpec.self)
                .task { await cloudSync.refresh() }
        }
        .modelContainer(container)
    }
}
