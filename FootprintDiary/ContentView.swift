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

    var body: some View {
        AtlasScreen()
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
