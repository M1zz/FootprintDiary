//
//  MapStamp.swift
//  FootprintDiary
//
//  내 지도에만 있는 표시 — 스탬프.
//
//  무엇을 새길지는 세 가지로 걸렀다.
//   1. 걸어야만 알 수 있는가 — 차나 항공사진, 거리뷰로 알 수 있으면 뺀다
//   2. 한 손으로 한 번에 찍을 수 있는가 — 걷는 중에는 손이 하나뿐이다
//   3. 나중에 내가 실제로 다시 찾아볼 것인가
//
//  세 번째가 가장 많이 걸러 냈다. "여기 예뻤다" 같은 건 남기기는 쉬운데 다시 찾아보지
//  않는다. 그래서 감상이 아니라 쓸모로 골랐다 — 옛 지도가 그랬듯이.
//
//  종류는 StampCatalog에 값의 목록으로 두었다 (200가지가 넘는다).
//
//  한 번 찍은 자리에는 다시 다녀온 것도 셀 수 있다. 근처에 서 있을 때만, 하루에 한 번만
//  센다 — 손가락이 아니라 발걸음을 세는 숫자여야 한다. 횟수와 함께 언제 갔는지도 남는다.
//
//  찍는 자리는 두 가지다. 걷는 중에는 지금 선 자리에 바로 찍고, 지도를 길게 눌러
//  원하는 지점에 찍을 수도 있다. 찍은 뒤에도 끌어서 자리를 고칠 수 있다.
//  걸을 때는 한 손뿐이라 정확히 짚을 수 없고, 돌아와서 다듬는 편이 실제로 더 정확하다.
//

import Foundation
import SwiftData
import CoreLocation

@Model
final class MapStamp {
    /// StampKind.id. 나중에 종류가 늘거나 줄어도 저장된 값이 깨지지 않도록 문자열로 둔다.
    var kindID: String = "other"
    var latitude: Double = 0
    var longitude: Double = 0
    var createdAt: Date = Date.now
    /// 덧붙인 한 줄 (없어도 된다)
    var note: String = ""
    /// 내가 붙인 이름 (없으면 종류 이름으로 부른다).
    ///
    /// 종류는 '카페'까지밖에 말해 주지 못한다. 그런데 몇 달 뒤에 지도를 열어 그 자리가
    /// 무엇이었는지 되살리는 것은 늘 '퇴근길 카페' 쪽이다. 그래서 부르던 이름을
    /// 따로 받아 둔다 — 값이 없던 시절에 찍힌 스탬프도 깨지지 않도록 기본값을 준다.
    var placeName: String = ""

    /// 다시 다녀왔다고 남긴 기록들.
    ///
    /// 처음 찍은 날은 여기 들어 있지 않다 — createdAt이 곧 첫 방문이다. 그래야 이 속성이
    /// 생기기 전에 찍힌 스탬프도 '한 번 다녀온 자리'로 제대로 셈해진다.
    ///
    /// 옵셔널 배열인 것은 취향이 아니다 — CloudKit은 여럿을 거느리는 관계가 비어 오는 것을
    /// 허용해야 한다고 못 박는다. 다루기 번거로운 것은 아래 셈틀들이 대신 받아 준다.
    @Relationship(deleteRule: .cascade, inverse: \StampVisit.stamp)
    var revisits: [StampVisit]?

    /// 이 자리에서 찍은 사진.
    ///
    /// 하루치로 묶는 일기 사진과 달리 자리에 붙는다. '그날 어땠나'가 아니라
    /// '거기가 어땠나'를 남기는 것이라, 몇 달 뒤에 그 자리를 다시 찾을 때 쓰인다.
    @Relationship(deleteRule: .cascade, inverse: \StampPhoto.stamp)
    var photos: [StampPhoto]?

    init(
        kind: StampKind,
        coordinate: CLLocationCoordinate2D,
        createdAt: Date = .now,
        note: String = "",
        placeName: String = ""
    ) {
        self.kindID = kind.id
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.createdAt = createdAt
        self.note = note
        self.placeName = placeName
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// 저장된 값이 알 수 없는 종류이면 '그 밖'으로 떨어뜨린다 (앱이 깨지지 않게)
    var kind: StampKind {
        StampCatalog.kind(id: kindID)
    }

    /// 지도와 화면에서 이 스탬프를 부르는 이름
    var displayName: String {
        placeName.isEmpty ? kind.title : placeName
    }

    /// 찍은 차례대로 (붙인 차례가 아니라 찍은 때가 이야기의 차례다)
    var photosInOrder: [StampPhoto] {
        (photos ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var photoCount: Int { photos?.count ?? 0 }

    /// 옵셔널 배열은 append로 넣으면 비어 있을 때 조용히 아무 일도 일어나지 않는다.
    /// 그래서 넣고 빼는 길을 여기 하나로 두고, 바깥에서는 배열을 만지지 않는다.
    func addPhoto(_ photo: StampPhoto) {
        photos = (photos ?? []) + [photo]
    }

    func removePhoto(_ photo: StampPhoto) {
        photos = (photos ?? []).filter { $0.persistentModelID != photo.persistentModelID }
    }

    // MARK: - 다시 다녀오기

    /// 이 안에 들어와 있어야 '다녀왔다'고 남길 수 있는 거리(m).
    ///
    /// 100m로 잡았다. 도시에서 위치는 건물 사이에서 수십 미터씩 튀는데, 그보다 좁게
    /// 잡으면 정작 그 가게 안에 서 있는데도 단추가 잠긴다. 반대로 더 넓히면 앞 블록을
    /// 지나가기만 해도 다녀온 것이 되어, 이 기록이 아무 말도 하지 않게 된다.
    /// (사진 스팟과 같은 자다 — 이 앱에서 '거기 있다'고 치는 거리는 하나로 둔다)
    static let visitRadius: CLLocationDistance = 100

    /// 다시 다녀온 차례대로
    var revisitsInOrder: [StampVisit] {
        (revisits ?? []).sorted { $0.date < $1.date }
    }

    /// 처음 찍은 때부터 차례대로 늘어놓은 모든 방문
    var visitDates: [Date] {
        [createdAt] + revisitsInOrder.map(\.date)
    }

    /// 몇 번 다녀온 자리인지 (처음 찍은 날을 첫 번째로 센다)
    var visitCount: Int {
        (revisits?.count ?? 0) + 1
    }

    /// 마지막으로 다녀온 때
    var lastVisitedAt: Date {
        revisitsInOrder.last?.date ?? createdAt
    }

    /// 그날 이미 다녀온 것으로 남아 있는지
    func hasVisited(on date: Date, calendar: Calendar = .current) -> Bool {
        visitDates.contains { calendar.isDate($0, inSameDayAs: date) }
    }

    /// 오늘 한 번 더 남길 수 있는지.
    ///
    /// 하루에 한 번만 받는다. 단골 가게에 앉아 있는 동안 눌리는 대로 올라가면 '몇 번
    /// 다녀왔나'가 아니라 '몇 번 눌렀나'가 되어 버린다. 하루 한 번으로 끊어야 그 숫자가
    /// 며칠 동안의 발걸음으로 읽힌다.
    func canAddVisit(now: Date = .now, calendar: Calendar = .current) -> Bool {
        !hasVisited(on: now, calendar: calendar)
    }

    /// 지금 선 자리에서 이 스탬프까지의 거리(m)
    func distance(from location: CLLocation) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude).distance(from: location)
    }

    /// 남길 수 있을 만큼 가까이 와 있는지
    func isNearby(_ location: CLLocation) -> Bool {
        distance(from: location) <= Self.visitRadius
    }

    /// 다녀온 것으로 한 번 센다. 셀 수 있는 자리인지는 부르는 쪽에서 먼저 본다.
    func addVisit(at date: Date = .now) {
        revisits = (revisits ?? []) + [StampVisit(date: date)]
    }
}

/// 스탬프를 찍은 뒤에 다시 다녀왔다고 남긴 한 번.
///
/// 횟수만 세지 않고 때를 남기는 까닭이 있다. '열두 번 갔다'는 것보다 '지난주에도 갔다'가
/// 나중에 훨씬 쓸모 있고, 언제 갔는지가 남아야 한동안 발길이 끊긴 자리도 눈에 띈다.
///
/// 스탬프가 지워지면 함께 지워진다.
@Model
final class StampVisit {
    var date: Date = Date.now
    /// 어느 자리의 방문인지 (MapStamp.revisits의 짝)
    var stamp: MapStamp?

    init(date: Date = .now) {
        self.date = date
    }
}

/// 스탬프 한 자리에 붙는 사진.
///
/// 스탬프가 지워지면 함께 지워진다 (자리가 없으면 그 사진도 갈 곳이 없다).
@Model
final class StampPhoto {
    @Attribute(.externalStorage)
    var data: Data = Data()
    var createdAt: Date = Date.now
    /// 어느 자리의 사진인지 (MapStamp.photos의 짝)
    var stamp: MapStamp?

    init(data: Data, createdAt: Date = .now) {
        self.data = data
        self.createdAt = createdAt
    }
}
