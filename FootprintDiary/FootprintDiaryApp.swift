//
//  FootprintDiaryApp.swift
//  FootprintDiary
//
//  벅뚜벅뚜 — 하루의 이동을 지도에 발자국으로 기록하고 일기를 쓰는 앱
//

import SwiftUI
import SwiftData
import AppIntents
import LeeoKit
import TipKit

@main
struct FootprintDiaryApp: App {

    let container: ModelContainer
    @StateObject private var locationManager: LocationManager
    @StateObject private var cloudSync = CloudSync()

    init() {
        // 백업 금고 — 예약된 복원 적용 · 매일/업데이트 직전 백업. 저장소를 열기 전에 먼저.
        LeeoVault.start(FootprintDiarySpec.self)
        // 페이월이 생긴 버전을 처음 켤 때, 이미 쓰던 사람이면 적어 둔다(Pro 평생 → PurchaseManager).
        // 안내 화면을 거치기 전, 아무것도 묻기 전에 한 번.
        ProEntitlement.noteUseBeforePaywall()

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
        let demoContainer = Self.demoContainer(schema: schema)
        let demo = demoContainer != nil
        if let demoContainer {
            container = demoContainer
            CloudSync.isAttached = false
        } else {
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
                container = StoreFallback.memoryContainer(schema: schema, after: error)
                CloudSync.isAttached = false
            }
        }
        }

        self.container = container
        // Siri 인텐트가 같은 저장소를 읽게 한다 (→ WalkIntents.swift)
        AppDependencyManager.shared.add(dependency: container)
        let manager = LocationManager()
        manager.modelContainer = container
        // 백그라운드에서 위치 이벤트로 앱이 다시 실행됐을 때도
        // 모니터링이 즉시 재개되도록 초기화 시점에 시작한다.
        manager.startMonitoringIfAuthorized()
        _locationManager = StateObject(wrappedValue: manager)
        if !demo { LeeoEngagement.shared.registerLaunch() }
        // 지도 단추 안내는 하루에 하나만 (AtlasTips.swift)
        try? Tips.configure([.displayFrequency(.daily)])
    }

    /// 스토어 스크린샷용 가상 기록 (DEBUG 빌드에서 `-demoSeed` 로 켰을 때만). DemoSeed.swift
    private static func demoContainer(schema: Schema) -> ModelContainer? {
        #if DEBUG
        guard DemoSeed.isOn else { return nil }
        DemoSeed.prepareDefaults()
        return DemoSeed.makeContainer(schema: schema)
        #else
        return nil
        #endif
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationManager)
                .environmentObject(cloudSync)
                .leeoSatisfactionCheck(FootprintDiarySpec.self)
                // 개발자가 보낸 의견에 답장하면, 앱이 앞으로 올 때 답장을 시트로 보여 준다 (LeeoKit).
                .leeoFeedbackReplyNotice(FootprintDiarySpec.self)
                // App Store 이벤트 링크(<번들 ID>://paywall)로 열리면 요금제를 띄운다 (LeeoKit).
                .leeoPaywallLink { PaywallView() }
                .storeFallbackNotice()
                .task { await cloudSync.refresh() }
                // 영수증을 읽어 칸을 정한다. 팁 상품과 끝나지 않은 팁은 LeeoStore 가 함께 챙긴다.
                .task { await PurchaseManager.shared.refresh() }
                // 일기를 Spotlight · Siri 가 찾게 한다 (→ WalkIntents.swift)
                .task { await DiaryLibrary.reindex(container) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { Task { await DiaryLibrary.reindex(container) } }
                    if phase == .active { Task { await PurchaseManager.shared.refresh() } }
                }
        }
        .modelContainer(container)
    }
}
