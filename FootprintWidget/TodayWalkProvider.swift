//
//  TodayWalkProvider.swift
//  FootprintWidget
//
//  위젯이 무엇을 언제 다시 그릴지.
//
//  위젯은 스스로 셈하지 않는다. 앱이 적어 둔 꾸러미(WalkSnapshot)를 읽어 그대로 내건다.
//  걷는 동안에는 앱이 경로 점을 저장할 때마다 꾸러미를 고쳐 쓰고 위젯에 알리므로,
//  여기서 시각을 재어 새로 고칠 일은 사실상 자정 한 번뿐이다.
//

import WidgetKit
import SwiftUI

struct TodayWalkEntry: TimelineEntry {
    let date: Date
    let snapshot: WalkSnapshot
    /// 앱 그룹 그릇조차 열리지 않았는지. 참이면 '걸음이 없다'가 아니라 '읽지 못했다'다.
    let isUnavailable: Bool
}

struct TodayWalkProvider: TimelineProvider {

    func placeholder(in context: Context) -> TodayWalkEntry {
        TodayWalkEntry(date: .now, snapshot: .preview, isUnavailable: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayWalkEntry) -> Void) {
        // 위젯 갤러리에서 고르는 중일 때는 빈 칸 대신 예시를 보여 준다.
        // 빈 칸을 내걸면 '이 위젯은 아무것도 안 보여 주는구나' 하고 지나친다.
        if context.isPreview, WalkSnapshotStore.load()?.isEmpty ?? true {
            completion(TodayWalkEntry(date: .now, snapshot: .preview, isUnavailable: false))
        } else {
            completion(current())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayWalkEntry>) -> Void) {
        let entry = current()

        // 다음에 스스로 깨어날 때는 자정이다. 그때 오늘 걸음이 0으로 돌아가야 하고,
        // 어제 그린 모양은 '지난 걸음'으로 물러나야 한다.
        //
        // 그 사이의 갱신은 앱이 맡는다. 걷는 동안 몇 분마다 위젯이 제 발로 깨어나 봐야
        // 시스템이 하루에 내주는 횟수만 축내고, 정작 걸음이 쌓이는 순간과는 어긋난다.
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }

    private func current() -> TodayWalkEntry {
        guard let stored = WalkSnapshotStore.load() else {
            return TodayWalkEntry(date: .now, snapshot: WalkSnapshot(), isUnavailable: true)
        }
        // 자정을 넘겼는데 앱이 아직 고쳐 쓰지 못했을 수 있다. 읽는 쪽에서 한 번 더 본다.
        return TodayWalkEntry(date: .now, snapshot: stored.rolledOver(), isUnavailable: false)
    }
}

// MARK: - 갤러리에서 보여 줄 예시

extension WalkSnapshot {
    /// 위젯 갤러리와 미리보기에서만 쓰는 걸음.
    /// 실제로 걸은 것처럼 굽이가 있어야 이 위젯이 무엇을 그리는지 한눈에 전해진다.
    static var preview: WalkSnapshot {
        var snapshot = WalkSnapshot()
        snapshot.updatedAt = .now
        snapshot.day = Calendar.current.startOfDay(for: .now)
        snapshot.newMeters = 1_240
        snapshot.walkedMeters = 2_430
        snapshot.newPlaces = 3

        // 한 바퀴 돌아 나오는 길. 사인 곡선 하나면 걸음처럼 굽는다.
        let base = (lat: 37.5665, lon: 126.9780)
        snapshot.past = (0..<120).map { index in
            let t = Double(index) / 120
            return Point(
                lat: base.lat + sin(t * .pi * 2) * 0.0035,
                lon: base.lon + t * 0.006 - 0.001
            )
        }
        snapshot.today = (0..<80).map { index in
            let t = Double(index) / 80
            return Point(
                lat: base.lat + 0.0012 + sin(t * .pi * 3) * 0.0018,
                lon: base.lon + 0.0005 + t * 0.0034
            )
        }
        return snapshot
    }
}
