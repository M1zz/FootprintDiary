//
//  ContentView.swift
//  FootprintDiary
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.scenePhase) private var scenePhase

    @Query(filter: #Predicate<Visit> { $0.isNamed == false })
    private var unnamedVisits: [Visit]

    @State private var showNamingSheet = false

    var body: some View {
        TabView {
            MapScreen()
                .tabItem {
                    Label("발자국", systemImage: "map.fill")
                }

            DiaryScreen()
                .tabItem {
                    Label("일기", systemImage: "book.fill")
                }
        }
        .onAppear {
            locationManager.requestPermission()
            locationManager.startMonitoringIfAuthorized()
            askIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                askIfNeeded()
            }
        }
        .sheet(isPresented: $showNamingSheet) {
            PlaceNamingView()
        }
    }

    /// 앱을 열었을 때 아직 이름을 묻지 않은 장소가 있으면 한꺼번에 묻는다.
    private func askIfNeeded() {
        if !unnamedVisits.isEmpty {
            showNamingSheet = true
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(LocationManager())
        .modelContainer(for: [Visit.self, DiaryEntry.self, DiaryPhoto.self], inMemory: true)
}
