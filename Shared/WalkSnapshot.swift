//
//  WalkSnapshot.swift
//  FootprintDiary
//
//  위젯에 건네는 오늘 한 장.
//
//  위젯은 앱의 저장소를 열지 못한다. 열 수 있다 해도 열면 안 된다 — 위젯은 몇 십 MB
//  안에서 몇 초 만에 그림을 그려 내야 하는데, 몇 만 개의 경로 점을 읽어 격자로 세고
//  날짜별로 묶는 일은 앱에서도 백그라운드로 미루는 셈이다. 잠금화면을 켤 때마다
//  그 셈을 돌리면 위젯은 그냥 빈 칸으로 남는다.
//
//  그래서 앱이 이미 셈해 둔 것을 작은 꾸러미 하나로 적어 두고, 위젯은 그것만 읽는다.
//  앱 그룹 그릇에 파일 하나로 둔다. UserDefaults에 넣지 않는 까닭은 점 목록이
//  수백 개라 값이 제법 크고, 그런 것을 기본값 저장소에 넣으면 앱을 켤 때마다 통째로
//  메모리에 올라오기 때문이다.
//

import Foundation
import CoreLocation
import CoreGraphics

/// 위젯이 읽는 하루치 요약
struct WalkSnapshot: Codable, Equatable {

    /// 지도에 찍을 자리 하나.
    ///
    /// 이름을 짧게 둔 것은 취향이 아니다. 이 이름이 그대로 JSON의 열쇠가 되는데,
    /// 점이 수백 개면 "latitude"와 "lat"의 차이가 꾸러미 크기의 몇 할이 된다.
    struct Point: Codable, Equatable {
        var lat: Double
        var lon: Double

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }

    /// 이 꾸러미를 적은 때
    var updatedAt: Date = .distantPast
    /// 어느 날의 것인지 (그날의 첫 시각)
    var day: Date = .distantPast
    /// 오늘 새로 그은 길이(m) — 앱의 '오늘 그은 길'과 같은 값
    var newMeters: Double = 0
    /// 오늘 걸은 총 거리(m)
    var walkedMeters: Double = 0
    /// 오늘 처음 밟은 자리 수
    var newPlaces: Int = 0
    /// 오늘 걸은 자리
    var today: [Point] = []
    /// 지난 걸음 (오늘 걸음의 뒤에 옅게 깔아 '어디쯤인지'를 알려 준다)
    var past: [Point] = []

    /// 아직 아무것도 적히지 않은 꾸러미인지
    var isEmpty: Bool { today.isEmpty && past.isEmpty }

    /// 이 꾸러미가 오늘 것인지.
    ///
    /// 자정을 넘기면 어제 것이 된다. 위젯이 하루에 몇 번이나 다시 그려질지는 시스템
    /// 마음이라, 어제 꾸러미를 그대로 '오늘 2.4km'라고 내걸 수 있다. 그리기 전에 묻는다.
    func isCurrent(on now: Date = .now, calendar: Calendar = .current) -> Bool {
        calendar.isDate(day, inSameDayAs: now)
    }

    /// 날이 바뀌었으면 걸음만 지운 빈 하루로 바꾼다. 지난 걸음은 그대로 둔다 —
    /// 어제 걸은 자리는 오늘 아침에 이미 '지난 걸음'이다.
    func rolledOver(to now: Date = .now, calendar: Calendar = .current) -> WalkSnapshot {
        guard !isCurrent(on: now, calendar: calendar) else { return self }
        var rolled = WalkSnapshot()
        rolled.updatedAt = updatedAt
        rolled.day = calendar.startOfDay(for: now)
        rolled.past = (past + today).suffix(WalkSnapshotStore.maxPastPoints)
        return rolled
    }
}

// MARK: - 주고받는 자리

/// 앱이 적고 위젯이 읽는 곳.
enum WalkSnapshotStore {

    /// 앱과 위젯이 함께 쓰는 그릇.
    ///
    /// 프로비저닝에 이 그룹이 없으면 그릇 주소가 비어 온다. 그때는 아무 일도 하지 않는다 —
    /// 위젯 하나 때문에 앱이 죽는 것보다 위젯이 빈 칸으로 남는 편이 낫다.
    static let appGroup = "group.com.leeo.FootprintDiary"

    /// 꾸러미에 담는 점의 최대 수.
    ///
    /// 위젯이 그리는 그림은 손톱만 하다. 소형 위젯의 지도 칸은 한 변이 150pt 남짓이라
    /// 점 300개면 이미 붓이 겹친다. 더 담아 봐야 읽는 시간과 메모리만 든다.
    static let maxTodayPoints = 300
    static let maxPastPoints = 400

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("walk-snapshot.json")
    }

    static func load() -> WalkSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WalkSnapshot.self, from: data)
    }

    @discardableResult
    static func save(_ snapshot: WalkSnapshot) -> Bool {
        guard let fileURL else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(snapshot) else { return false }
        // .atomic으로 쓴다. 위젯이 읽는 사이에 절반만 적힌 파일을 보면
        // 그날 걸음이 통째로 사라진 것처럼 보인다.
        do {
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// 점이 너무 많으면 고르게 솎아 낸다.
    ///
    /// 앞이나 뒤를 잘라 내지 않는다. 그러면 아침에 걸은 길이나 방금 걸은 길이 통째로
    /// 사라져, 오늘 그린 모양이 실제와 달라진다. 고르게 건너뛰면 모양은 남는다.
    static func thinned(_ points: [WalkSnapshot.Point], to limit: Int) -> [WalkSnapshot.Point] {
        guard points.count > limit, limit > 0 else { return points }
        let stride = Double(points.count) / Double(limit)
        var kept: [WalkSnapshot.Point] = []
        kept.reserveCapacity(limit)
        for index in 0..<limit {
            kept.append(points[min(Int(Double(index) * stride), points.count - 1)])
        }
        // 마지막 점은 '지금 내가 선 자리'다. 솎아 내다 놓치면 위젯이 늘 몇 분 뒤처져 보인다.
        if let last = points.last, kept.last != last { kept[kept.count - 1] = last }
        return kept
    }
}

// MARK: - 손톱만 한 지도에 눕히기

/// 점들을 주어진 칸 안에 꽉 차게 눕힌다.
///
/// 배경 지도가 없으므로 위도·경도의 절대값은 아무 뜻이 없다. 중요한 것은 '오늘 그린
/// 모양'이고, 그 모양이 칸을 꽉 채워야 손톱만 한 위젯에서도 읽힌다.
///
/// DayWalk.drawingPath와 하는 일이 같지만 한곳에 모으지 않았다. 저쪽은 한 구간만
/// 그리고 이쪽은 오늘과 지난날 두 벌을 '같은 자'로 눕혀야 한다 — 따로 눕히면 두 그림의
/// 배율이 달라져 오늘 걸음이 엉뚱한 자리에 놓인다.
enum WalkSnapshotLayout {

    struct Placed {
        var today: [CGPoint]
        var past: [CGPoint]
    }

    static func lay(_ snapshot: WalkSnapshot, in size: CGSize, inset: CGFloat) -> Placed {
        // 눕히는 자는 두 벌을 합쳐서 잰다. 그래야 오늘 걸음이 지난 걸음 위 제자리에 온다.
        let all = snapshot.today + snapshot.past
        guard !all.isEmpty else { return Placed(today: [], past: []) }

        let lats = all.map(\.lat), lons = all.map(\.lon)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        let midLat = (minLat + maxLat) / 2
        // 경도 1도는 위도 1도보다 짧다(위도에 따라 cos배). 보정하지 않으면 그림이 옆으로 늘어난다.
        let lonScale = max(cos(midLat * .pi / 180), 0.01)

        // 한자리에서만 서성였어도 납작해지지 않도록 최소 폭을 준다
        let width = max((maxLon - minLon) * lonScale, 0.00005)
        let height = max(maxLat - minLat, 0.00005)

        let canvas = CGSize(
            width: max(size.width - inset * 2, 1),
            height: max(size.height - inset * 2, 1)
        )
        let scale = min(canvas.width / width, canvas.height / height)
        let originX = inset + (canvas.width - width * scale) / 2
        let originY = inset + (canvas.height - height * scale) / 2

        func place(_ point: WalkSnapshot.Point) -> CGPoint {
            CGPoint(
                x: originX + (point.lon - minLon) * lonScale * scale,
                // 북쪽이 위로 오도록 y를 뒤집는다
                y: originY + (maxLat - point.lat) * scale
            )
        }

        return Placed(today: snapshot.today.map(place), past: snapshot.past.map(place))
    }
}
