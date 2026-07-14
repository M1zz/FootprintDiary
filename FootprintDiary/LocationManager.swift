//
//  LocationManager.swift
//  FootprintDiary
//
//  CLVisit(방문 감지)만으로 이동을 자동 기록한다.
//  방문 감지는 백그라운드 모드 없이도 앱을 깨워 주기 때문에
//  배터리를 거의 쓰지 않으면서 "장소를 옮길 때마다" 발자국이 쌓인다.
//  기록 직전에 CoreMotion으로 이동 수단을 판별해
//  걷기/뛰기로 온 발자국만 남기고 차량 이동은 버린다.
//

import Foundation
import CoreLocation
import CoreMotion
import SwiftData

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let activityManager = CMMotionActivityManager()

    /// 앱에서 주입해 주는 SwiftData 컨테이너
    var modelContainer: ModelContainer?

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var lastKnownLocation: CLLocation?
    @Published var isRecordingManually = false
    @Published var manualRecordError: ManualRecordError?

    /// 권한 요청 응답을 기다렸다가 수동 기록을 이어서 진행하기 위한 플래그
    private var pendingManualRecord = false

    enum ManualRecordError: Identifiable {
        case permissionDenied
        case locationUnavailable

        var id: Self { self }

        var message: String {
            switch self {
            case .permissionDenied:
                return "위치 권한이 꺼져 있어요. 설정에서 위치 접근을 허용해주세요."
            case .locationUnavailable:
                return "현재 위치를 가져오지 못했어요. 잠시 후 다시 시도해주세요.\n(시뮬레이터라면 Features > Location에서 위치를 설정해주세요.)"
            }
        }
    }

    /// 이 거리(m) 안에 이미 이름 붙은 장소가 있으면 이름을 자동으로 재사용한다.
    static let sameSpotThreshold: CLLocationDistance = 150
    /// 직전 발자국이 이 거리(m) 안이면 같은 장소로 보고 새로 저장하지 않는다.
    /// 한 장소에 머물며 방문 이벤트가 반복해서 들어와도 발자국이 쌓이지 않게 한다.
    static let repeatSuppressionRadius: CLLocationDistance = 500
    /// 도착 직전 이 시간(초) 동안의 모션 활동으로 이동 수단을 판별한다.
    static let arrivalLookback: TimeInterval = 20 * 60

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.pausesLocationUpdatesAutomatically = true
    }

    // MARK: - 권한

    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            // 백그라운드 방문 감지를 위해 '항상 허용'으로 승급 요청
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    func startMonitoringIfAuthorized() {
        let status = manager.authorizationStatus
        authorizationStatus = status
        guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
        manager.startMonitoringVisits()
        // 과거 버전이 켜 둔 큰 위치 변화 감지를 끈다.
        // 운전 중에도 셀 타워가 바뀔 때마다 앱을 깨워 배터리를 소모하는데,
        // 방문 기록에는 CLVisit만으로 충분하다.
        manager.stopMonitoringSignificantLocationChanges()
    }

    // MARK: - 수동 기록 (시뮬레이터 테스트 및 즉시 기록용)

    func recordCurrentLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            // 권한을 먼저 받고, 응답이 오면 이어서 기록한다.
            pendingManualRecord = true
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            manualRecordError = .permissionDenied
        default:
            isRecordingManually = true
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
        }
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            startMonitoringIfAuthorized()
        }

        // 수동 기록 도중 권한 요청이 끼어들었으면 응답에 따라 이어간다.
        guard pendingManualRecord, status != .notDetermined else { return }
        pendingManualRecord = false
        Task { @MainActor in
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                self.recordCurrentLocation()
            } else {
                self.manualRecordError = .permissionDenied
            }
        }
    }

    /// 방문 감지 — 한 장소에 머물다 떠나거나 도착했을 때 호출된다.
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let lat = visit.coordinate.latitude
        let lon = visit.coordinate.longitude
        let arrival = visit.arrivalDate == .distantPast ? Date() : visit.arrivalDate
        let departure = visit.departureDate == .distantFuture ? nil : visit.departureDate

        classifyArrivalMovement(endingAt: arrival) { [weak self] arrivedByVehicle in
            guard let self, !arrivedByVehicle else { return }
            Task { @MainActor in
                self.saveVisit(latitude: lat, longitude: lon, arrival: arrival, departure: departure)
            }
        }
    }

    /// 큰 위치 변화 / 수동 기록 위치 수신
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let wasManual = isRecordingManually
        Task { @MainActor in
            self.lastKnownLocation = location
            self.isRecordingManually = false
            if wasManual {
                // 사용자가 직접 + 버튼을 눌렀을 때는 이동 수단을 따지지 않는다.
                self.saveVisit(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    arrival: Date(),
                    departure: nil,
                    // 사용자가 직접 남긴 발자국은 근처라도 그대로 저장한다.
                    suppressNearby: false
                )
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if self.isRecordingManually {
                self.manualRecordError = .locationUnavailable
            }
            self.isRecordingManually = false
        }
    }

    // MARK: - 이동 수단 판별

    /// 도착 직전 구간의 모션 활동을 조회해 차량(자동차/자전거) 이동인지 판별한다.
    /// 걷기·뛰기 시간이 차량 시간보다 길면 도보 도착으로 본다.
    /// 모션 데이터를 쓸 수 없으면(권한 거부, 시뮬레이터 등) 기록을 막지 않는다.
    private func classifyArrivalMovement(endingAt arrival: Date, completion: @escaping (Bool) -> Void) {
        guard CMMotionActivityManager.isActivityAvailable() else {
            completion(false)
            return
        }
        let windowStart = arrival.addingTimeInterval(-Self.arrivalLookback)
        activityManager.queryActivityStarting(from: windowStart, to: arrival, to: .main) { activities, error in
            guard error == nil, let activities, !activities.isEmpty else {
                completion(false)
                return
            }

            var vehicleTime: TimeInterval = 0
            var onFootTime: TimeInterval = 0
            for (index, activity) in activities.enumerated() {
                guard activity.confidence != .low else { continue }
                let end = index + 1 < activities.count ? activities[index + 1].startDate : arrival
                let duration = max(0, end.timeIntervalSince(activity.startDate))
                if activity.automotive || activity.cycling {
                    vehicleTime += duration
                } else if activity.walking || activity.running {
                    onFootTime += duration
                }
            }

            // 차량 이동이 1분 이상이고 걷기/뛰기보다 길면 차로 온 것으로 판단
            completion(vehicleTime > 60 && vehicleTime > onFootTime)
        }
    }

    // MARK: - 저장

    @MainActor
    private func saveVisit(
        latitude: Double,
        longitude: Double,
        arrival: Date,
        departure: Date?,
        suppressNearby: Bool = true
    ) {
        guard let modelContainer else { return }
        let context = modelContainer.mainContext

        // 최근 발자국 1건을 확인해 같은 장소면 새로 저장하지 않고 갱신만 한다.
        var lastDescriptor = FetchDescriptor<Visit>(sortBy: [SortDescriptor(\.arrivalDate, order: .reverse)])
        lastDescriptor.fetchLimit = 1
        if let last = (try? context.fetch(lastDescriptor))?.first {
            let distance = last.distance(latitude: latitude, longitude: longitude)
            // 같은 방문 이벤트가 도착/출발로 두 번 오는 경우: 출발 시각만 갱신
            if distance < 50, abs(last.arrivalDate.timeIntervalSince(arrival)) < 60 * 5 {
                last.departureDate = departure ?? last.departureDate
                try? context.save()
                return
            }
            // 자동 기록에서, 직전 장소 500m 이내면 반복 저장하지 않는다.
            if suppressNearby, distance < Self.repeatSuppressionRadius {
                if let departure { last.departureDate = departure }
                try? context.save()
                return
            }
        }

        let visit = Visit(
            arrivalDate: arrival,
            departureDate: departure,
            latitude: latitude,
            longitude: longitude
        )

        // 이미 이름 붙인 근처 장소가 있으면 이름을 자동으로 재사용
        // (전체가 아니라 이름 붙은 기록만 가져와서 거리 비교)
        let namedDescriptor = FetchDescriptor<Visit>(
            predicate: #Predicate<Visit> { $0.isNamed == true && $0.placeName != nil }
        )
        let named = (try? context.fetch(namedDescriptor)) ?? []
        if let known = named.first(where: {
            ($0.placeName?.isEmpty == false)
            && $0.distance(latitude: latitude, longitude: longitude) < Self.sameSpotThreshold
        }) {
            visit.placeName = known.placeName
            visit.address = known.address
            visit.isNamed = true
        }

        context.insert(visit)
        try? context.save()

        // 주소는 참고용으로 비동기 채움 — 근처 장소에서 재사용했으면 네트워크 요청을 생략
        if visit.address?.isEmpty != false {
            reverseGeocode(visit: visit)
        }
    }

    @MainActor
    private func reverseGeocode(visit: Visit) {
        // CLGeocoder는 동시 요청을 지원하지 않아 겹치면 요청만 낭비된다.
        guard !geocoder.isGeocoding else { return }
        let location = CLLocation(latitude: visit.latitude, longitude: visit.longitude)
        geocoder.reverseGeocodeLocation(location) { placemarks, _ in
            guard let placemark = placemarks?.first else { return }
            let parts = [
                placemark.locality,
                placemark.subLocality,
                placemark.thoroughfare,
                placemark.name
            ].compactMap { $0 }
            var seen = Set<String>()
            let address = parts.filter { seen.insert($0).inserted }.joined(separator: " ")
            Task { @MainActor in
                visit.address = address
                try? visit.modelContext?.save()
            }
        }
    }
}
