//
//  Models.swift
//  FootprintDiary
//
//  SwiftData 모델 정의
//

import Foundation
import SwiftData
import CoreLocation

/// 한 번의 "머무름"(방문)을 나타내는 발자국 하나
@Model
final class Visit {
    var arrivalDate: Date
    var departureDate: Date?
    var latitude: Double
    var longitude: Double
    /// 사용자가 붙인 장소 이름 (예: "회사", "단골 카페")
    var placeName: String?
    /// 역지오코딩으로 얻은 주소 (참고용)
    var address: String?
    /// 사용자에게 "여기는 어디였나요?"를 이미 물어봤는지 여부
    var isNamed: Bool

    init(
        arrivalDate: Date,
        departureDate: Date? = nil,
        latitude: Double,
        longitude: Double,
        placeName: String? = nil,
        address: String? = nil,
        isNamed: Bool = false
    ) {
        self.arrivalDate = arrivalDate
        self.departureDate = departureDate
        self.latitude = latitude
        self.longitude = longitude
        self.placeName = placeName
        self.address = address
        self.isNamed = isNamed
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

/// 하루 단위 일기
@Model
final class DiaryEntry {
    /// 해당 날짜의 자정 (하루를 식별하는 키)
    var dayStart: Date
    var text: String
    var updatedAt: Date

    @Relationship(deleteRule: .cascade)
    var photos: [DiaryPhoto]

    init(dayStart: Date, text: String = "", photos: [DiaryPhoto] = []) {
        self.dayStart = dayStart
        self.text = text
        self.updatedAt = .now
        self.photos = photos
    }
}

/// 일기에 첨부된 사진
@Model
final class DiaryPhoto {
    @Attribute(.externalStorage)
    var data: Data
    var createdAt: Date

    init(data: Data, createdAt: Date = .now) {
        self.data = data
        self.createdAt = createdAt
    }
}
