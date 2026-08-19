//
//  TrackingDiagnostics.swift
//  FootprintDiary
//
//  "왜 선이 안 그어지지?"에 답하기 위한 계기판.
//
//  경로 한 점이 저장되기까지 관문이 여럿이라(걷기 판정·권한·정확도·간격),
//  어디서 막혔는지 밖에서는 알 길이 없다. 그래서 관문마다 버려진 횟수를 센다.
//  숫자를 보면 무엇을 풀어야 할지가 바로 나온다.
//

import Foundation
import CoreLocation
import CoreMotion

/// 점이 버려진 까닭
enum TrackRejection: String, CaseIterable, Identifiable {
    case notWalking = "걷기로 판정되지 않음"
    case staleFix = "너무 오래된 위치"
    case beforeStart = "추적 시작 이전의 위치"
    case warmupAccuracy = "켠 직후라 정확도 부족"
    case accuracy = "정확도 부족"
    case tooFast = "걷기보다 빠름"
    case jump = "걸어서 닿을 수 없는 점프"
    case tooClose = "직전 점과 너무 가까움"
    case systemPaused = "iOS가 갱신을 멈춤"

    var id: String { rawValue }

    /// 이 까닭으로 자주 막힌다면 무엇을 손봐야 하는지
    var hint: String {
        switch self {
        case .notWalking: return "모션 권한이 꺼져 있거나 걷기 판정이 안 되고 있어요"
        case .staleFix: return "위치가 늦게 들어오고 있어요"
        case .beforeStart: return "정상 — 켜기 직전의 묵은 위치를 버린 것"
        case .warmupAccuracy: return "켠 직후 기준이 너무 엄해요"
        case .accuracy: return "정확도 기준(25m)이 이 동네엔 너무 엄해요"
        case .tooFast: return "차·자전거로 판정됐어요"
        case .jump: return "위치가 크게 튀고 있어요"
        case .tooClose: return "정상 — 정해진 간격마다 한 점만 남긴다"
        case .systemPaused: return "iOS가 '멈췄다'고 보고 껐어요. 되살리기를 시도했습니다"
        }
    }
}

/// LocationManager가 격리되지 않은 클래스라 여기도 @MainActor를 걸지 않는다.
/// 값을 고치는 곳은 모두 메인에서 불린다 — 위치 델리게이트와 모션 콜백 모두 메인 큐로 온다.
final class TrackingDiagnostics: ObservableObject {
    /// 관문별로 버린 횟수
    @Published private(set) var rejections: [TrackRejection: Int] = [:]
    /// 실제로 저장한 점의 수 (앱을 켠 뒤로)
    @Published private(set) var accepted = 0
    /// 마지막으로 들어온 위치의 정확도(m)
    @Published private(set) var lastAccuracy: CLLocationDistance?
    /// 마지막으로 위치가 들어온 시각
    @Published private(set) var lastFixAt: Date?
    /// 지금 걷기로 보고 기록 중인지
    @Published var isWalking = false
    /// 마지막으로 모션이 알려 준 상태
    @Published var motionState = "아직 없음"

    func note(_ rejection: TrackRejection) {
        rejections[rejection, default: 0] += 1
    }

    func noteAccepted() {
        accepted += 1
    }

    func noteFix(_ location: CLLocation) {
        lastAccuracy = location.horizontalAccuracy
        lastFixAt = location.timestamp
    }

    func reset() {
        rejections = [:]
        accepted = 0
    }

    /// 가장 많이 막힌 관문
    var topRejection: (TrackRejection, Int)? {
        rejections.max { $0.value < $1.value }.map { ($0.key, $0.value) }
    }

    /// 모션 권한 상태를 사람 말로
    static var motionAuthorizationText: String {
        guard CMMotionActivityManager.isActivityAvailable() else {
            return "이 기기에서는 쓸 수 없음 (걷기 판정 없이 기록)"
        }
        switch CMMotionActivityManager.authorizationStatus() {
        case .authorized: return "허용됨"
        case .denied: return "거부됨 — 설정에서 켜야 기록됩니다"
        case .restricted: return "제한됨"
        case .notDetermined: return "아직 묻지 않음"
        @unknown default: return "알 수 없음"
        }
    }
}
