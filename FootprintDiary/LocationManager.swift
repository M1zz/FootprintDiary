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
    /// 걸음 수 계측기. 모션 활동 판정보다 훨씬 빨리 '지금 걷는 중'을 알려 준다.
    private let pedometer = CMPedometer()
    private var isCountingSteps = false
    /// 마지막으로 걸음이 늘어난 시각
    private var lastStepAt: Date?
    /// 모션이 한 번이라도 대답했는지
    private var didReceiveMotion = false

    /// 앱에서 주입해 주는 SwiftData 컨테이너
    var modelContainer: ModelContainer?

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var lastKnownLocation: CLLocation?
    @Published var isRecordingManually = false
    @Published var manualRecordError: ManualRecordError?

    /// 어느 관문에서 점이 버려지는지 세는 계기판
    let diagnostics = TrackingDiagnostics()

    /// 얼마나 촘촘히 기록할지 (사용자 설정 — 재실행에도 유지)
    @Published var trackingMode: TrackingMode = .thorough {
        didSet {
            guard oldValue != trackingMode else { return }
            UserDefaults.standard.set(trackingMode.rawValue, forKey: Self.trackingModeKey)
            // 바꾼 즉시 반영한다 (다음 산책까지 기다리지 않게)
            applyUpdateReasons()
            if isTrackingEnabled { startMonitoringIfAuthorized() }
        }
    }

    /// 자동 위치 추적 켜짐/꺼짐 (사용자 설정 — 재실행·백그라운드 깨어남에도 유지)
    @Published var isTrackingEnabled: Bool = true {
        didSet {
            guard oldValue != isTrackingEnabled else { return }
            UserDefaults.standard.set(isTrackingEnabled, forKey: Self.trackingEnabledKey)
            if isTrackingEnabled {
                startMonitoringIfAuthorized()
            } else {
                stopMonitoring()
            }
        }
    }

    private static let trackingEnabledKey = "footprint.isTrackingEnabled"
    private static let trackingModeKey = "footprint.trackingMode"
    private static let discoveryBackfillKey = "footprint.discoveryBackfillDone"

    /// 역지오코딩 대기열 (CLGeocoder는 한 번에 한 건만 처리한다)
    private var geocodeQueue: [Visit] = []
    private var isProcessingGeocode = false

    /// 지금 위치를 계속 받고 있는 이유들
    private var updateReasons: Set<UpdateReason> = []
    private var isDetectingActivity = false

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
    /// 이 거리(m) 밖이면 '처음 밟은 자리'로 보고 새 발견으로 센다.
    /// GPS 오차로 같은 자리가 새 발견이 되지 않도록 넉넉히 잡는다.
    static let discoveryRadius: CLLocationDistance = 300

    override init() {
        // 저장된 설정이 없으면 기본값은 켜짐(기존 동작 유지).
        // init 안에서의 대입은 didSet을 호출하지 않으므로 모니터링을 조기 시작하지 않는다.
        if UserDefaults.standard.object(forKey: Self.trackingEnabledKey) != nil {
            isTrackingEnabled = UserDefaults.standard.bool(forKey: Self.trackingEnabledKey)
        }
        if let saved = UserDefaults.standard.string(forKey: Self.trackingModeKey),
           let mode = TrackingMode(rawValue: saved) {
            trackingMode = mode
        }
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.pausesLocationUpdatesAutomatically = true
    }

    /// 시스템이 들고 있는 최근 위치. 지도를 처음 열 때 화면을 어디에 맞출지 정하는 데 쓴다.
    var currentLocation: CLLocation? {
        manager.location ?? lastKnownLocation
    }

    /// 스팟을 찾아가는 동안에만 위치를 계속 받는다. (AR 화면에서 거리·방향을 갱신하려면 필요)
    /// 배터리를 쓰므로 화면을 닫으면 반드시 stopLiveUpdates()로 되돌린다.
    func startLiveUpdates() {
        addUpdateReason(.guiding)
    }

    func stopLiveUpdates() {
        removeUpdateReason(.guiding)
    }

    // MARK: - 걷기 감지와 경로 기록

    /// 위치를 계속 받아야 하는 이유들. 하나라도 남아 있으면 켜 둔다.
    private enum UpdateReason: Hashable {
        case walking   // 걷는 중 — 경로를 남긴다
        case guiding   // AR로 스팟을 찾아가는 중
    }

    /// 이 속도(m/s)를 넘으면 걷기·뛰기로 보지 않는다 (약 21km/h)
    static let maxWalkingSpeed: CLLocationDistance = 6

    /// Info.plist에 백그라운드 위치 모드가 선언돼 있는지
    static let hasBackgroundLocationMode: Bool = {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        return modes?.contains("location") ?? false
    }()
    /// 경로 점 사이의 최소 간격(m)
    static let trackPointSpacing: CLLocationDistance = 12

    /// 지도에 그릴 때 믿는 수평 정확도 상한(m).
    /// 이보다 밀린 점을 직선으로 이으면 선이 건물 안을 가로지른다.
    static let maxDrawAccuracy: CLLocationDistance = 25

    /// 저장까지 받아들이는 상한(m).
    /// 그리기 기준을 넘겨도 일단 남긴다 — 오늘 안 남긴 점은 나중에 어떤 방법으로도
    /// 되살릴 수 없지만, 그리는 방법은 앞으로 얼마든지 나아질 수 있기 때문이다.
    static let maxStoredAccuracy: CLLocationDistance = 60

    /// 예전 이름 (진단 화면이 그리기 기준을 보여 줄 때 쓴다)
    static var maxTrackAccuracy: CLLocationDistance { maxDrawAccuracy }
    /// 위치를 켠 직후 정확도가 자리 잡을 때까지 기다리는 시간(초).
    /// 이 동안에는 아주 정확한 점만 받는다.
    static let warmupInterval: TimeInterval = 8
    /// 워밍업 동안 요구하는 정확도(m)
    static let warmupAccuracy: CLLocationDistance = 15
    /// 이 시간(초)보다 오래된 점은 버린다.
    /// startUpdatingLocation() 직후 iOS는 들고 있던 지난 위치부터 돌려주는데,
    /// 실내에서 잡힌 Wi-Fi 기반 위치는 정확도를 낙관적으로 보고하면서도 수백 m 밀려 있다.
    static let maxTrackAge: TimeInterval = 10
    /// 걸음이 멎은 뒤 이 시간(초) 안에는 '멈춤' 판정이 와도 기록을 이어 간다.
    /// 신호 대기·가게 구경처럼 잠깐 서는 일은 산책의 일부다.
    static let stepGracePeriod: TimeInterval = 90

    /// 점프로 판정해 연속으로 버릴 수 있는 최대 개수.
    /// 잘못 저장된 점 하나 때문에 그 뒤의 멀쩡한 점이 영원히 막히는 걸 막는다.
    static let maxConsecutiveJumpRejections = 3

    /// 위치 갱신을 켠 시각. 그 이전에 찍힌(=iOS가 들고 있던) 점을 걸러내는 기준이 된다.
    private var trackingStartedAt: Date?
    /// 점프로 판정해 연달아 버린 횟수
    private var jumpRejectionCount = 0

    /// 걷는 동안에만 경로를 남긴다. 모션 판정으로 걷기가 시작되면 켜고, 멈추거나 차를 타면 끈다.
    func startWalkDetection() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            // 모션을 쓸 수 없는 기기면 기록 자체가 멈춰 버린다.
            // 그럴 때는 위치를 받되 걷기 속도를 넘는 점을 버리는 것으로 규칙을 지킨다.
            addUpdateReason(.walking)
            return
        }

        // 권한이 막혀 있으면 startActivityUpdates가 오류도 없이 조용히 아무것도 보내지 않는다.
        // 그대로 두면 '걷기로 판정되지 않음' 상태로 굳어 한 점도 남지 않는다.
        // 기다리지 말고 기록하되, 걷기 규칙은 저장 단계의 속도 필터가 지킨다.
        switch CMMotionActivityManager.authorizationStatus() {
        case .denied, .restricted:
            addUpdateReason(.walking)
            return
        default:
            break
        }

        guard !isDetectingActivity else { return }
        isDetectingActivity = true
        startStepDetection()
        startMotionTimeout()
        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            Task { @MainActor in
                self.didReceiveMotion = true
                self.diagnostics.motionState = Self.describe(activity)
            }
            guard activity.confidence != .low else { return }
            if activity.walking || activity.running {
                self.addUpdateReason(.walking)
            } else if activity.automotive || activity.cycling {
                // 차·자전거는 곧바로 끈다 — 이 앱의 기록은 걷기에서만 나온다
                self.removeUpdateReason(.walking)
            } else if activity.stationary {
                // 방금까지 걸음이 있었다면 신호 대기일 뿐이다. 그때마다 끄면
                // 다시 켜질 때의 첫 위치 지연이 쌓여 산책이 조각난다.
                if let lastStepAt = self.lastStepAt,
                   Date().timeIntervalSince(lastStepAt) < Self.stepGracePeriod {
                    return
                }
                self.removeUpdateReason(.walking)
            }
        }
    }

    /// 모션이 이 시간(초) 안에 한 번도 대답하지 않으면 기다리기를 그만둔다.
    ///
    /// 권한이 '아직 묻지 않음'인 채로 프롬프트가 뜨지 않거나, 기기 사정으로 판정이
    /// 오지 않는 경우가 있다. 그때 잠자코 기다리면 걷는 내내 한 점도 남지 않는다.
    /// 기록을 막느니 받아 두고 속도로 거르는 편이 낫다.
    static let motionSilenceTimeout: TimeInterval = 25

    private func startMotionTimeout() {
        let deadline = Self.motionSilenceTimeout
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(deadline * 1_000_000_000))
            guard let self, !self.didReceiveMotion, self.isDetectingActivity else { return }
            self.diagnostics.motionState = "대답 없음 — 걷기 판정 없이 기록"
            self.addUpdateReason(.walking)
        }
    }

    /// 걸음 수로 걷기를 알아챈다.
    ///
    /// 모션 활동(CMMotionActivity)은 걷기를 확정하는 데 수십 초가 걸린다. 그동안 위치를
    /// 받지 않으니 집에서 나와 처음 100~200m가 매번 통째로 빠진다. 걸음 수는 몇 초 안에
    /// 늘기 시작하므로 훨씬 빨리 켤 수 있다.
    ///
    /// 켜는 것만 걸음 수로 하고, 차·자전거를 가려내는 일은 그대로 모션 활동에 맡긴다.
    /// '걸어야만 기록된다'는 규칙은 저장 단계의 속도 필터가 이미 지키고 있다.
    private func startStepDetection() {
        guard trackingMode.usesPedometer else { return }
        guard CMPedometer.isStepCountingAvailable(), !isCountingSteps else { return }
        isCountingSteps = true
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            guard let self, let data, data.numberOfSteps.intValue > 0 else { return }
            Task { @MainActor in
                self.lastStepAt = Date()
                self.addUpdateReason(.walking)
            }
        }
    }

    private func stopStepDetection() {
        guard isCountingSteps else { return }
        isCountingSteps = false
        pedometer.stopUpdates()
    }

    /// 모션이 알려 준 상태를 사람 말로 (계기판에 그대로 보여 준다)
    private static func describe(_ activity: CMMotionActivity) -> String {
        var names: [String] = []
        if activity.walking { names.append("걷기") }
        if activity.running { names.append("뛰기") }
        if activity.cycling { names.append("자전거") }
        if activity.automotive { names.append("차량") }
        if activity.stationary { names.append("멈춤") }
        if activity.unknown || names.isEmpty { names.append("알 수 없음") }
        let confidence = switch activity.confidence {
        case .high: "확실"
        case .medium: "보통"
        default: "낮음(무시됨)"
        }
        return names.joined(separator: "·") + " · " + confidence
    }

    func stopWalkDetection() {
        stopStepDetection()
        guard isDetectingActivity else { return }
        isDetectingActivity = false
        didReceiveMotion = false
        activityManager.stopActivityUpdates()
        removeUpdateReason(.walking)
    }

    private func addUpdateReason(_ reason: UpdateReason) {
        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
        guard updateReasons.insert(reason).inserted else { return }
        applyUpdateReasons()
    }

    private func removeUpdateReason(_ reason: UpdateReason) {
        guard updateReasons.remove(reason) != nil else { return }
        applyUpdateReasons()
    }

    private func applyUpdateReasons() {
        guard !updateReasons.isEmpty else {
            manager.stopUpdatingLocation()
            // trackingStartedAt은 여기서 지우지 않는다.
            // 신호 대기처럼 잠깐 멈출 때마다 걷기 판정이 껐다 켜지는데,
            // 그때마다 8초짜리 엄한 워밍업이 다시 열리면 걷는 내내 점이 거의 안 남는다.
            // 묵은 위치를 걸러 내는 기준으로는 처음 켠 시각 하나면 충분하다.
            manager.allowsBackgroundLocationUpdates = false
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.distanceFilter = kCLDistanceFilterNone
            Task { @MainActor in self.diagnostics.isWalking = false }
            return
        }

        if updateReasons.contains(.guiding) {
            // 방향을 알려 줘야 하므로 가장 정확하게
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.distanceFilter = kCLDistanceFilterNone
        } else {
            // 지도가 곧 결과물이라 경로는 최대한 정확해야 한다.
            // 걷는 시간은 하루 30~60분이라 이 구간만 정확도를 올려도 배터리 부담이 크지 않다.
            manager.desiredAccuracy = trackingMode.desiredAccuracy
            // iOS가 raw 위치로 잘라 내게 두면 튄 점이 간격을 넘겨 통과하고
            // 정확한 점이 대신 버려질 수 있다. 전부 받아서 직접 고른다.
            manager.distanceFilter = kCLDistanceFilterNone
        }
        manager.activityType = .fitness
        // iOS가 '멈췄다'고 보고 스스로 꺼 버리면 다시 켜 줄 신호가 마땅치 않다.
        // 벤치에 앉았다 일어난 뒤의 산책이 통째로 사라질 수 있어, 빠짐없이 기록할 때는 맡기지 않는다.
        manager.pausesLocationUpdatesAutomatically = trackingMode.allowsAutomaticPause
        // 백그라운드 위치 모드가 없는데 이 값을 켜면 앱이 그 자리에서 죽는다.
        // 설정이 빠졌을 때 크래시 대신 '앱이 떠 있을 때만 기록'으로 물러난다.
        //
        // '앱 사용 중' 권한에서도 켠다. 이 권한만으로도 앱이 떠 있을 때 시작한 갱신은
        // 주머니에 넣은 뒤까지 이어진다. 이걸 '항상 허용'에만 걸어 두면, 승급 프롬프트를
        // 놓친 사람은 화면을 켜 둔 채 걷지 않는 한 한 점도 남지 않는다.
        // ('항상 허용'이라야 앱을 켜지 않고 걸어도 기록되는 건 그대로다)
        let status = manager.authorizationStatus
        if Self.hasBackgroundLocationMode, status == .authorizedAlways || status == .authorizedWhenInUse {
            manager.allowsBackgroundLocationUpdates = true
        }
        // 여기서부터 들어오는 점만 믿는다 (이미 켜져 있었다면 기준을 흔들지 않는다)
        if trackingStartedAt == nil {
            trackingStartedAt = Date()
            jumpRejectionCount = 0
        }
        Task { @MainActor in self.diagnostics.isWalking = self.updateReasons.contains(.walking) }
        manager.startUpdatingLocation()
    }

    /// 걷는 동안 들어온 위치를 경로로 남긴다.
    /// 정확도가 나쁘거나 차량 속도인 점은 버려서 '걸어야만 기록된다'는 규칙을 지킨다.
    @MainActor
    private func appendTrackPoint(_ location: CLLocation) {
        diagnostics.noteFix(location)

        guard updateReasons.contains(.walking) else { diagnostics.note(.notWalking); return }
        guard let modelContainer else { return }
        guard location.horizontalAccuracy > 0 else { diagnostics.note(.accuracy); return }

        // 켜기 이전에 찍힌 점은 iOS가 들고 있던 지난 위치다. 지금 내가 선 자리가 아니다.
        if let trackingStartedAt, location.timestamp < trackingStartedAt {
            diagnostics.note(.beforeStart); return
        }
        guard abs(location.timestamp.timeIntervalSinceNow) < Self.maxTrackAge else {
            diagnostics.note(.staleFix); return
        }

        // 켠 직후에는 정확도가 자리를 잡을 때까지 아주 정확한 점만 받는다.
        // 실내에서 출발하면 첫 몇 점이 Wi-Fi 기반이라 수백 m 밀려 있다.
        let isWarmingUp = trackingStartedAt.map { Date().timeIntervalSince($0) < Self.warmupInterval } ?? false
        let accuracyLimit = isWarmingUp ? Self.warmupAccuracy : Self.maxStoredAccuracy
        guard location.horizontalAccuracy <= accuracyLimit else {
            diagnostics.note(isWarmingUp ? .warmupAccuracy : .accuracy); return
        }

        if location.speed >= 0, location.speed > Self.maxWalkingSpeed {
            diagnostics.note(.tooFast); return
        }

        let context = modelContainer.mainContext
        var descriptor = FetchDescriptor<TrackPoint>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        if let last = (try? context.fetch(descriptor))?.first {
            let previous = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let gap = previous.distance(from: location)
            let interval = location.timestamp.timeIntervalSince(last.timestamp)

            // 걸어서 닿을 수 없는 자리로 튀었으면 버린다.
            // 기기가 보고하는 speed는 -1일 수 있어서 직전 점과의 실제 이동으로 다시 잰다.
            // 간격이 길면 그 사이 앱이 꺼져 있었을 수 있으므로 판정하지 않는다.
            if interval > 0, interval < 60, gap / interval > Self.maxWalkingSpeed {
                jumpRejectionCount += 1
                // 잘못 저장된 점 하나가 그 뒤를 계속 막을 수 있다. 몇 번 이어지면 여기서부터 다시 잇는다.
                if jumpRejectionCount <= Self.maxConsecutiveJumpRejections {
                    diagnostics.note(.jump); return
                }
            }
            jumpRejectionCount = 0

            guard gap >= trackingMode.pointSpacing else { diagnostics.note(.tooClose); return }
        }

        context.insert(TrackPoint(
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            speed: location.speed,
            horizontalAccuracy: location.horizontalAccuracy
        ))
        try? context.save()
        diagnostics.noteAccepted()
    }

    /// 현재 위치를 한 번만 받아 온다. (발자국을 남기지 않고 지도 화면을 맞추는 용도)
    /// 앱이 막 켜진 직후에는 시스템이 들고 있는 위치가 비어 있을 수 있다.
    func refreshCurrentLocation() {
        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
        guard !isRecordingManually else { return }
        manager.requestLocation()
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
        // 사용자가 추적을 꺼 두었으면 백그라운드 깨어남에도 다시 시작하지 않는다.
        guard isTrackingEnabled else { return }
        guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
        // 걷기가 시작되면 경로를 남기기 시작한다 (이 앱의 기록은 걷기에서 나온다)
        startWalkDetection()
        // 앱이 꺼져 있어도 다시 깨워 주는 장치. 걸어서 도착한 자리를 '장소'로 남긴다.
        manager.startMonitoringVisits()

        // CLVisit은 '머문 뒤'에 오는 이벤트라 걷는 중에는 오지 않는다.
        // 그래서 앱이 종료된 채 산책을 나가면 깨워 줄 것이 아무것도 없다.
        // 큰 위치 변화 감지가 그 구멍을 메운다. 예전에 이걸 끈 까닭은 운전 중에도
        // 셀 타워마다 깨어나 배터리를 쓴다는 것이었는데, 그건 깨어난 '뒤'에
        // 걷는 중일 때만 정밀 추적을 켜는 것으로 해결한다 (차 안이면 곧바로 다시 잠든다).
        if trackingMode.wakesOnSignificantChange {
            manager.startMonitoringSignificantLocationChanges()
        } else {
            manager.stopMonitoringSignificantLocationChanges()
        }
    }

    /// 자동 위치 추적을 멈춘다. (수동 + 기록은 계속 사용할 수 있다)
    func stopMonitoring() {
        stopWalkDetection()
        manager.stopMonitoringVisits()
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
            // 걷는 중이면 지나온 점들을 모두 경로로 남긴다
            for point in locations {
                self.appendTrackPoint(point)
            }
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

    /// iOS가 '멈췄다'고 보고 스스로 위치 갱신을 멈췄을 때.
    ///
    /// 이 뒤로는 시스템이 알아서 되살려 주지 않는다. 그냥 두면 벤치에 앉았다 일어난 뒤의
    /// 산책이 통째로 사라진다. 큰 위치 변화 감지로 넘겨 두었다가, 다시 움직이면 되살린다.
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.diagnostics.note(.systemPaused)
            guard self.updateReasons.contains(.walking) else { return }
            manager.startMonitoringSignificantLocationChanges()
            // 걸음이 다시 잡히면 startStepDetection의 콜백이 정밀 추적을 되살린다
            manager.startUpdatingLocation()
        }
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        Task { @MainActor in
            if !self.trackingMode.wakesOnSignificantChange {
                manager.stopMonitoringSignificantLocationChanges()
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

        // 처음 밟은 자리면 발견 번호를 붙인다 (수집의 단위)
        if Self.isNewGround(latitude: latitude, longitude: longitude, in: context) {
            visit.isFirstVisit = true
            visit.discoveryIndex = Self.nextDiscoveryIndex(in: context)
        }

        context.insert(visit)
        try? context.save()

        // 주소·행정구역은 참고용으로 비동기 채움.
        // 이름을 물려받았더라도 행정구역이 없으면 도감 집계를 위해 조회한다.
        if visit.address?.isEmpty != false || visit.needsRegionLookup {
            reverseGeocode(visit: visit)
        }
    }

    // MARK: - 발견 판정

    /// 이 좌표가 기존 어떤 발자국과도 discoveryRadius 밖인지.
    /// 전체를 훑지 않도록 위경도 사각형으로 먼저 좁힌 뒤 실제 거리를 잰다.
    @MainActor
    static func isNewGround(latitude: Double, longitude: Double, in context: ModelContext) -> Bool {
        let latDelta = discoveryRadius / 111_320
        // 고위도에서 경도 간격이 좁아지는 것을 보정한다 (극지방에서 0으로 나누지 않도록 하한을 둔다)
        let lonDelta = discoveryRadius / (111_320 * max(cos(latitude * .pi / 180), 0.01))
        let minLat = latitude - latDelta, maxLat = latitude + latDelta
        let minLon = longitude - lonDelta, maxLon = longitude + lonDelta

        let descriptor = FetchDescriptor<Visit>(
            predicate: #Predicate<Visit> {
                $0.latitude >= minLat && $0.latitude <= maxLat
                && $0.longitude >= minLon && $0.longitude <= maxLon
            }
        )
        let nearby = (try? context.fetch(descriptor)) ?? []
        return !nearby.contains {
            $0.distance(latitude: latitude, longitude: longitude) < discoveryRadius
        }
    }

    /// 다음 발견 번호 (기존 최댓값 + 1)
    @MainActor
    static func nextDiscoveryIndex(in context: ModelContext) -> Int {
        var descriptor = FetchDescriptor<Visit>(
            sortBy: [SortDescriptor(\.discoveryIndex, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let highest = (try? context.fetch(descriptor))?.first?.discoveryIndex ?? 0
        return highest + 1
    }

    /// CLGeocoder는 동시 요청을 지원하지 않는다. 요청을 버리지 않고 한 건씩 차례로 처리한다.
    @MainActor
    private func reverseGeocode(visit: Visit) {
        guard !geocodeQueue.contains(where: { $0.persistentModelID == visit.persistentModelID }) else { return }
        geocodeQueue.append(visit)
        processGeocodeQueue()
    }

    @MainActor
    private func processGeocodeQueue() {
        guard !isProcessingGeocode, !geocodeQueue.isEmpty else { return }
        isProcessingGeocode = true
        let visit = geocodeQueue.removeFirst()
        Task { @MainActor in
            await lookUpPlacemark(for: visit)
            // 애플 지오코더 호출 제한에 걸리지 않도록 간격을 둔다
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            isProcessingGeocode = false
            processGeocodeQueue()
        }
    }

    @MainActor
    private func lookUpPlacemark(for visit: Visit) async {
        // 큐에 있는 동안 삭제됐을 수 있다
        guard visit.modelContext != nil else { return }
        let location = CLLocation(latitude: visit.latitude, longitude: visit.longitude)
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else { return }
        guard visit.modelContext != nil else { return }

        let parts = [
            placemark.locality,
            placemark.subLocality,
            placemark.thoroughfare,
            placemark.name
        ].compactMap { $0 }
        var seen = Set<String>()
        let address = parts.filter { seen.insert($0).inserted }.joined(separator: " ")
        if !address.isEmpty { visit.address = address }

        // 도감 집계에 쓰는 행정구역
        visit.administrativeArea = placemark.administrativeArea
        visit.subAdministrativeArea = placemark.subAdministrativeArea
        visit.locality = placemark.locality
        visit.subLocality = placemark.subLocality
        visit.country = placemark.country
        visit.isoCountryCode = placemark.isoCountryCode

        try? visit.modelContext?.save()
    }

    // MARK: - 기존 기록 보정

    /// 도감·발견 기능이 생기기 전에 쌓인 발자국에 발견 번호를 채워 넣는다. (앱당 1회)
    @MainActor
    func backfillDiscoveriesIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.discoveryBackfillKey) else { return }
        guard let modelContainer else { return }
        let context = modelContainer.mainContext
        let all = (try? context.fetch(
            FetchDescriptor<Visit>(sortBy: [SortDescriptor(\.arrivalDate)])
        )) ?? []

        let radius = Self.discoveryRadius
        let step = SpatialGrid.step(meters: radius)
        var anchors: [CLLocation] = []
        var index: [GridCell: [Int]] = [:]
        var discovered = 0

        for visit in all {
            let location = CLLocation(latitude: visit.latitude, longitude: visit.longitude)
            let candidates = SpatialGrid
                .neighbors(latitude: visit.latitude, longitude: visit.longitude, step: step, meters: radius)
                .flatMap { index[$0] ?? [] }
            let isNewGround = !candidates.contains { anchors[$0].distance(from: location) < radius }

            if isNewGround {
                discovered += 1
                visit.isFirstVisit = true
                visit.discoveryIndex = discovered
                anchors.append(location)
                let cell = SpatialGrid.cell(latitude: visit.latitude, longitude: visit.longitude, step: step)
                index[cell, default: []].append(anchors.count - 1)
            } else if visit.discoveryIndex != 0 || visit.isFirstVisit {
                visit.isFirstVisit = false
                visit.discoveryIndex = 0
            }
        }

        try? context.save()
        UserDefaults.standard.set(true, forKey: Self.discoveryBackfillKey)
    }

    /// 행정구역이 비어 있는 기록을 조금씩 채운다. (지오코더 제한 때문에 한 번에 조금씩)
    @MainActor
    func backfillRegions(limit: Int = 25) {
        guard let modelContainer else { return }
        let context = modelContainer.mainContext
        var descriptor = FetchDescriptor<Visit>(sortBy: [SortDescriptor(\.arrivalDate, order: .reverse)])
        descriptor.fetchLimit = 500
        let visits = (try? context.fetch(descriptor)) ?? []
        for visit in visits.filter({ $0.needsRegionLookup }).prefix(limit) {
            reverseGeocode(visit: visit)
        }
    }
}
