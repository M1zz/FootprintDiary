//
//  ContentView.swift
//  FootprintDiary
//
//  앱은 화면 하나다 — 걸어서 그리는 내 지도.
//

import SwiftUI
import SwiftData
import LeeoKit

struct ContentView: View {
    @EnvironmentObject private var locationManager: LocationManager

    /// 안내를 받은 적이 있는지. 받지 않았다면 지도를 열기 전에 반드시 거친다.
    @AppStorage("footprint.hasOnboarded") private var hasOnboarded = false

    var body: some View {
        Group {
            if hasOnboarded {
                // 아이폰 듀오를 펴면 지도는 왼쪽(세로면 아래), 오늘의 발자취는 오른쪽(위)에 선다.
                // 손은 지도에서 걷고 찍고, 눈은 옆 판에서 오늘 들른 곳을 본다.
                // 접혀 있거나 보통 아이폰이면 지도만 그린다. 지금 화면 그대로다.
                FoldSplitView {
                    AtlasScreen()
                } result: {
                    FoldTodayPane()
                }
            } else {
                // 안내는 지도 '위에 띄우는' 것이 아니라 지도를 '대신한다'.
                // 반드시 거쳐야 하는 관문이라 덮개로 두면 뒤의 지도가 비치고,
                // 한 화면에 시트와 덮개를 여럿 걸면 SwiftUI가 서로를 닫아 버린다.
                OnboardingView {
                    // 막 시작한 사람에게는 모든 것이 새것이라 '새로 생긴 것'을 따로 띄우지 않는다.
                    WhatsNew.markSeen()
                    hasOnboarded = true
                }
                .foldConfined()
            }
        }
        // 시트 · 알림창이 접힌 선을 비킨다. 접혀 있으면 아무것도 바뀌지 않는다.
        .foldAware()
        .onAppear {
            locationManager.requestPermission()
            // 걷기가 시작되면 경로를 남기기 시작한다
            locationManager.startMonitoringIfAuthorized()
        }
    }
}

/// 펼친 화면의 옆 판: 오늘의 발자취. 날이 바뀌면 새 날로 다시 세운다.
private struct FoldTodayPane: View {
    @State private var today = Calendar.current.startOfDay(for: .now)

    var body: some View {
        DayTimelineScreen(now: today, isSheet: false)
            .id(today)
            .environment(\.foldLayout, .single)
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                today = Calendar.current.startOfDay(for: .now)
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
