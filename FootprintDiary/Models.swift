//
//  Models.swift
//  FootprintDiary
//
//  SwiftData 모델 정의
//
//  모든 속성에 기본값이 있고, 관계에는 반드시 짝(inverse)이 있다. 이것은 취향이 아니라
//  아이클라우드에 얹기 위한 조건이다 — CloudKit은 기기마다 스키마가 어긋날 수 있다고 보고,
//  값이 비어 오는 경우와 관계를 거꾸로 되짚는 길을 모두 요구한다. 새 속성을 더할 때도
//  기본값을 반드시 주어야 한다. 안 그러면 저장소가 아예 열리지 않는다.
//

import Foundation
import SwiftData
import CoreLocation

/// 한 번의 "머무름"(방문)을 나타내는 발자국 하나
@Model
final class Visit {
    var arrivalDate: Date = Date.now
    var departureDate: Date?
    var latitude: Double = 0
    var longitude: Double = 0
    /// 사용자가 붙인 장소 이름 (예: "회사", "단골 카페")
    var placeName: String?
    /// 역지오코딩으로 얻은 주소 (참고용)
    var address: String?
    /// 사용자에게 "여기는 어디였나요?"를 이미 물어봤는지 여부
    var isNamed: Bool = false

    // MARK: 발견 (수집 요소)
    // 기존 저장소와의 호환을 위해 모두 기본값을 가진다 (경량 마이그레이션).

    /// 기존 어떤 발자국과도 떨어진 '처음 밟은 자리'인지
    var isFirstVisit: Bool = false
    /// 몇 번째 발견인지 (첫 방문에만 1부터 부여, 재방문은 0)
    var discoveryIndex: Int = 0

    /// '여기는 기록 안 해도 괜찮냐'고 이미 물어본 자리인지.
    ///
    /// 한 번 물어본 자리는 다시 묻지 않는다. 같은 것을 두 번 묻는 것이 가장 성가시고,
    /// 성가신 물음은 한 번 겪으면 그 다음부터는 읽지도 않고 지워 버리게 된다.
    var askedAboutStamp: Bool = false

    // MARK: 행정구역 (도감 집계용)

    /// 시·도 (예: 서울특별시, 경기도)
    var administrativeArea: String?
    /// 시·군 (예: 성남시) — 광역시에서는 비어 있을 수 있다
    var subAdministrativeArea: String?
    /// 시·군·구 (예: 강남구)
    var locality: String?
    /// 읍·면·동 (예: 역삼동)
    var subLocality: String?
    var country: String?
    var isoCountryCode: String?

    init(
        arrivalDate: Date,
        departureDate: Date? = nil,
        latitude: Double,
        longitude: Double,
        placeName: String? = nil,
        address: String? = nil,
        isNamed: Bool = false,
        isFirstVisit: Bool = false,
        discoveryIndex: Int = 0
    ) {
        self.arrivalDate = arrivalDate
        self.departureDate = departureDate
        self.latitude = latitude
        self.longitude = longitude
        self.placeName = placeName
        self.address = address
        self.isNamed = isNamed
        self.isFirstVisit = isFirstVisit
        self.discoveryIndex = discoveryIndex
    }

    /// 행정구역 정보가 아직 채워지지 않았는지 (역지오코딩 대상 판별용)
    var needsRegionLookup: Bool {
        administrativeArea == nil && country == nil
    }

    /// 도감에서 쓰는 광역 지역 (한국은 시·도 축약형, 해외는 국가명)
    var provinceKey: String? {
        RegionCatalog.provinceKey(
            administrativeArea: administrativeArea,
            isoCountryCode: isoCountryCode,
            country: country
        )
    }

    /// 도감에서 쓰는 시·군·구 이름
    var districtName: String? {
        RegionCatalog.districtName(
            administrativeArea: administrativeArea,
            subAdministrativeArea: subAdministrativeArea,
            locality: locality,
            subLocality: subLocality
        )
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// 화면에 보여줄 이름 (이름 > 주소 > 좌표 순서로 대체)
    var displayName: String {
        if let placeName, !placeName.isEmpty { return placeName }
        if let address, !address.isEmpty { return address }
        return String(format: "%.4f, %.4f", latitude, longitude)
    }

    /// 다른 좌표와의 거리(미터)
    func distance(latitude otherLat: Double, longitude otherLon: Double) -> CLLocationDistance {
        let a = CLLocation(latitude: latitude, longitude: longitude)
        let b = CLLocation(latitude: otherLat, longitude: otherLon)
        return a.distance(from: b)
    }
}

extension CLLocationCoordinate2D {
    /// 이 좌표에서 다른 좌표를 향한 방위각(도, 북쪽 0° 기준 시계 방향)
    func bearing(to other: CLLocationCoordinate2D) -> Double {
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLon = (other.longitude - longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        return atan2(y, x) * 180 / .pi
    }
}

/// 걸어서 지나간 한 점.
///
/// 이 앱은 '머문 곳'이 아니라 '걸은 길'을 기록한다.
/// 걷기·뛰기로 판정된 동안에만 쌓이고, 차량 속도로 움직인 구간은 들어오지 않는다.
@Model
final class TrackPoint {
    var timestamp: Date = Date.now
    var latitude: Double = 0
    var longitude: Double = 0
    /// 그때의 속도(m/s). 음수면 알 수 없음.
    var speed: Double = -1
    /// 그때 보고된 수평 정확도(m). 음수면 알 수 없음.
    ///
    /// 선을 다듬을 때 '이 점을 얼마나 믿을지'의 근거가 된다. 정확도를 남기지 않으면
    /// 나중에 알고리즘을 고쳐도 지난 기록은 손댈 수 없으므로 값으로 함께 저장한다.
    /// (이 속성이 생기기 전에 쌓인 점은 -1이 들어간다)
    var horizontalAccuracy: Double = -1

    init(
        timestamp: Date = .now,
        latitude: Double,
        longitude: Double,
        speed: Double = -1,
        horizontalAccuracy: Double = -1
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.speed = speed
        self.horizontalAccuracy = horizontalAccuracy
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// 지도에 뿌려지는 사진 스팟.
/// 아직 밟지 않은 자리에만 생기고, 그 자리에 가서 사진을 찍으면 수집된다.
@Model
final class PhotoSpot {
    var latitude: Double = 0
    var longitude: Double = 0
    var name: String = ""
    /// MKPointOfInterestCategory의 rawValue (표시할 아이콘을 고르는 데 쓴다)
    var category: String?
    var createdAt: Date = Date.now
    /// 사진을 찍은 시각 (nil이면 아직 안 간 곳)
    var collectedAt: Date?

    @Attribute(.externalStorage)
    var photoData: Data?

    init(
        latitude: Double,
        longitude: Double,
        name: String,
        category: String? = nil,
        createdAt: Date = .now
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.name = name
        self.category = category
        self.createdAt = createdAt
    }

    /// 이 거리(m) 안에 들어와야 사진을 찍을 수 있다
    static let captureRadius: CLLocationDistance = 100

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isCollected: Bool { collectedAt != nil }

    func distance(from location: CLLocation) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude).distance(from: location)
    }

    /// 지도에 쓰는 아이콘. AR에 세워질 랜드마크와 같은 성격을 쓴다.
    var symbolName: String {
        landmarkKind.symbolName
    }
}

/// 하루 단위 일기
@Model
final class DiaryEntry {
    /// 해당 날짜의 자정 (하루를 식별하는 키)
    var dayStart: Date = Date.now
    var text: String = ""
    var updatedAt: Date = Date.now

    /// 그날 붙인 사진들.
    /// 옵셔널 배열인 것은 CloudKit이 여럿을 거느리는 관계에 요구하는 조건이다.
    @Relationship(deleteRule: .cascade, inverse: \DiaryPhoto.entry)
    var photos: [DiaryPhoto]?

    init(dayStart: Date, text: String = "", photos: [DiaryPhoto] = []) {
        self.dayStart = dayStart
        self.text = text
        self.updatedAt = .now
        self.photos = photos
    }

    /// 붙인 차례대로
    var photosInOrder: [DiaryPhoto] {
        (photos ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var photoCount: Int { photos?.count ?? 0 }

    /// 옵셔널 배열은 append로 넣으면 비어 있을 때 조용히 아무 일도 일어나지 않는다.
    /// 그래서 넣고 빼는 길을 여기 하나로 둔다.
    func addPhoto(_ photo: DiaryPhoto) {
        photos = (photos ?? []) + [photo]
    }

    func removePhoto(_ photo: DiaryPhoto) {
        photos = (photos ?? []).filter { $0.persistentModelID != photo.persistentModelID }
    }
}

/// 일기에 첨부된 사진
@Model
final class DiaryPhoto {
    @Attribute(.externalStorage)
    var data: Data = Data()
    var createdAt: Date = Date.now
    /// 어느 날의 일기에 붙은 사진인지 (DiaryEntry.photos의 짝)
    var entry: DiaryEntry?

    init(data: Data, createdAt: Date = .now) {
        self.data = data
        self.createdAt = createdAt
    }
}
