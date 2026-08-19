//
//  ContentView.swift
//  FootprintDiary
//
//  앱은 화면 하나다 — 걸어서 그리는 내 지도.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var locationManager: LocationManager

    /// 안내를 받은 적이 있는지. 받지 않았다면 지도를 열기 전에 반드시 거친다.
    @AppStorage("footprint.hasOnboarded") private var hasOnboarded = false

    var body: some View {
        Group {
            if hasOnboarded {
                AtlasScreen()
            } else {
                // 안내는 지도 '위에 띄우는' 것이 아니라 지도를 '대신한다'.
                // 반드시 거쳐야 하는 관문이라 덮개로 두면 뒤의 지도가 비치고,
                // 한 화면에 시트와 덮개를 여럿 걸면 SwiftUI가 서로를 닫아 버린다.
                OnboardingView { hasOnboarded = true }
            }
        }
        .onAppear {
            locationManager.requestPermission()
            // 걷기가 시작되면 경로를 남기기 시작한다
            locationManager.startMonitoringIfAuthorized()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(LocationManager())
        .modelContainer(
            for: [Visit.self, DiaryEntry.self, DiaryPhoto.self, TrackPoint.self],
            inMemory: true
        )
}
