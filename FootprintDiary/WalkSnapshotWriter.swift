//
//  WalkSnapshotWriter.swift
//  FootprintDiary
//
//  위젯에 건넬 오늘 한 장을 적는다.
//
//  적는 때가 둘이다.
//
//  하나는 지도를 다시 셈했을 때(AtlasState). 여기서는 오늘 그은 길이·걸은 거리·처음
//  밟은 자리까지 온전히 다 안다. 다만 앱을 열어야만 돌아간다.
//
//  또 하나는 걷는 중에 경로 점이 하나 쌓였을 때(LocationManager). 걷는 동안에는 앱이
//  뒤에 가 있으므로 지도를 다시 셈하지 않는다. 그런데 위젯을 보는 때는 하필 그때다 —
//  주머니에서 꺼내 화면만 켜는 순간. 그래서 그때는 온전한 셈 대신 '점 하나 붙이고
//  걸은 거리만 늘리는' 값싼 갱신을 한다. '오늘 그은 길'은 과거 기록 전체를 훑어야
//  나오는 값이라 여기서 늘릴 수 없고, 앱을 다음에 열 때 제 값으로 맞춰진다.
//

import Foundation
import CoreLocation
import WidgetKit

enum WalkSnapshotWriter {

    /// 지난 걸음을 오늘 걸음에서 이만큼 떨어진 데까지만 담는다.
    ///
    /// 위젯의 그림은 담긴 점 전부가 들어가도록 배율을 맞춘다. 지난달 부산에 다녀온
    /// 점이 한 톨이라도 섞이면 오늘 동네 한 바퀴가 화면에서 티끌만 해진다.
    static let pastRadius: CLLocationDistance = 3_000

    /// 걷는 중에 위젯을 다시 그리라고 이르는 사이 간격.
    ///
    /// 경로 점은 12m마다 쌓이므로 한 시간을 걸으면 삼백 번 가까이 들어온다. 그때마다
    /// 파일을 다시 쓰고 위젯을 깨우면, 아이오에스가 하루치 갱신 몫을 오전에 다 써 버려
    /// 정작 오후에는 위젯이 멈춘다. 점은 그때그때 메모리에 쌓아 두고, 실제로 적어
    /// 내보내는 것은 이 간격으로 한다.
    ///
    /// 3분으로 잡았다. 걷는 속도로 200m쯤이라 위젯의 그림이 눈에 띄게 자라고,
    /// 한 시간을 내리 걸어도 스무 번이면 끝난다.
    static let liveInterval: TimeInterval = 3 * 60

    /// 아직 적어 내보내지 않은 꾸러미. 걷는 동안 여기에 점이 쌓인다.
    private static var pending: WalkSnapshot?
    /// 마지막으로 적어 내보낸 때
    private static var lastCommit: Date = .distantPast

    /// 적는 이가 둘이라 자물쇠를 채운다 — 지도를 다시 셈하는 쪽은 백그라운드에서,
    /// 걷는 중에 점을 붙이는 쪽은 메인에서 온다. 둘이 겹치면 쌓아 둔 점이 어긋나고,
    /// 무엇보다 같은 파일에 동시에 쓰게 된다.
    private static let lock = NSLock()

    /// 지도를 다시 셈한 뒤 온전한 꾸러미를 적는다.
    ///
    /// - Parameters:
    ///   - todayPoints: 오늘 걸은 자리 (시간순)
    ///   - pastPoints: 지난 걸음 가운데 오늘 근처의 것들 (시간순)
    static func write(
        todayPoints: [CLLocationCoordinate2D],
        pastPoints: [CLLocationCoordinate2D],
        newMeters: CLLocationDistance,
        walkedMeters: CLLocationDistance,
        newPlaces: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        var snapshot = WalkSnapshot()
        snapshot.updatedAt = now
        snapshot.day = calendar.startOfDay(for: now)
        snapshot.newMeters = newMeters
        snapshot.walkedMeters = walkedMeters
        snapshot.newPlaces = newPlaces
        snapshot.today = WalkSnapshotStore.thinned(
            todayPoints.map { WalkSnapshot.Point(lat: $0.latitude, lon: $0.longitude) },
            to: WalkSnapshotStore.maxTodayPoints
        )
        snapshot.past = WalkSnapshotStore.thinned(
            nearby(pastPoints, of: todayPoints).map { WalkSnapshot.Point(lat: $0.latitude, lon: $0.longitude) },
            to: WalkSnapshotStore.maxPastPoints
        )
        lock.lock()
        defer { lock.unlock() }
        // 온전히 셈한 것이 걷는 중에 쌓아 둔 것을 이긴다. 여기서 나온 값이 참이다.
        pending = snapshot
        commit(snapshot, at: now, force: true)
    }

    /// 걷는 중에 점 하나가 쌓였을 때의 값싼 갱신.
    ///
    /// 앞선 점과의 거리만큼 '걸은 거리'를 늘리고 점 하나를 붙인다. 저장소를 다시 읽지
    /// 않으므로 백그라운드에서도 부담이 없다.
    static func append(_ coordinate: CLLocationCoordinate2D, movedMeters: CLLocationDistance, now: Date = .now) {
        lock.lock()
        defer { lock.unlock() }
        // 앱을 켠 뒤 첫 점이면 적혀 있던 것을 불러와 이어 쌓는다.
        guard var snapshot = (pending ?? WalkSnapshotStore.load())?.rolledOver(to: now) else { return }
        snapshot.updatedAt = now
        snapshot.walkedMeters += max(0, movedMeters)
        snapshot.today.append(WalkSnapshot.Point(lat: coordinate.latitude, lon: coordinate.longitude))
        // 한도를 넘으면 그 자리에서 솎아 낸다. 하루 종일 걸으면 점이 수천 개까지 간다.
        if snapshot.today.count > WalkSnapshotStore.maxTodayPoints {
            snapshot.today = WalkSnapshotStore.thinned(snapshot.today, to: WalkSnapshotStore.maxTodayPoints)
        }
        pending = snapshot
        commit(snapshot, at: now, force: false)
    }

    /// 오늘 걸은 자리 언저리의 지난 걸음만 골라 낸다.
    /// 오늘 한 걸음도 걷지 않았으면 고를 기준이 없으므로 그대로 둔다 — 그때는 지난
    /// 걸음이 그림의 전부라, 넓게 잡혀도 볼 것이 그것뿐이다.
    private static func nearby(
        _ pastPoints: [CLLocationCoordinate2D],
        of todayPoints: [CLLocationCoordinate2D]
    ) -> [CLLocationCoordinate2D] {
        guard !todayPoints.isEmpty else { return pastPoints }
        let lats = todayPoints.map(\.latitude), lons = todayPoints.map(\.longitude)
        let center = CLLocation(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        return pastPoints.filter {
            center.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <= pastRadius
        }
    }

    /// 자물쇠를 쥔 채로만 부른다.
    private static func commit(_ snapshot: WalkSnapshot, at now: Date, force: Bool) {
        guard force || now.timeIntervalSince(lastCommit) >= liveInterval else { return }
        // 앱 그룹이 없으면 적히지 않는다. 그때 위젯을 깨워 봐야 읽을 것이 없다.
        guard WalkSnapshotStore.save(snapshot) else { return }
        lastCommit = now
        WidgetCenter.shared.reloadAllTimelines()
    }
}
