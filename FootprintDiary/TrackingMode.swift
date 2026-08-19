//
//  TrackingMode.swift
//  FootprintDiary
//
//  기록을 얼마나 촘촘히 할지 고르는 두 갈래.
//
//  걸은 길을 빠짐없이 남기려면 위치를 더 자주, 더 오래 받아야 하고 그만큼 배터리를 쓴다.
//  어느 쪽이 나은지는 사람마다 다르므로 고르게 둔다.
//
//  다만 '데이터를 버리는 일'은 어느 쪽에서도 하지 않는다. 정확도가 낮은 점도 일단 저장하고
//  그릴 때만 걸러낸다 — 오늘 안 남긴 점은 나중에 어떤 방법으로도 되살릴 수 없기 때문이다.
//

import Foundation
import CoreLocation

enum TrackingMode: String, CaseIterable, Identifiable {
    /// 정확한 기록 우선 — 앱이 꺼져 있어도 되살아나 기록한다
    case thorough
    /// 배터리 우선 — 앱을 열고 걷기 시작할 때만 기록한다
    case thrifty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thorough: return "빠짐없이 기록"
        case .thrifty: return "배터리 아끼기"
        }
    }

    var summary: String {
        switch self {
        case .thorough: return "앱을 열지 않고 걸어도 남습니다. 배터리를 더 씁니다."
        case .thrifty: return "앱을 열고 걷기 시작해야 남습니다. 배터리를 덜 씁니다."
        }
    }

    /// 무엇이 달라지는지 — 고를 때 그대로 보여 준다
    var details: [String] {
        switch self {
        case .thorough:
            return [
                "앱이 꺼져 있어도 위치가 크게 바뀌면 되살아나 이어서 기록해요",
                "걸음 수로 걷기를 알아채서 산책 앞부분을 놓치지 않아요",
                "경로 점을 8m마다 남겨 굽은 길이 뭉개지지 않아요"
            ]
        case .thrifty:
            return [
                "앱을 열고 걷기 시작할 때만 기록해요",
                "걷기 판정이 확실해진 뒤 시작하므로 앞부분이 조금 빠질 수 있어요",
                "경로 점을 12m마다 남겨요"
            ]
        }
    }

    // MARK: - 모드에 따라 달라지는 값

    /// 경로 점 사이의 최소 간격(m)
    var pointSpacing: CLLocationDistance {
        switch self {
        case .thorough: return 8
        case .thrifty: return 12
        }
    }

    /// 위치를 얼마나 정밀하게 받을지
    var desiredAccuracy: CLLocationAccuracy {
        switch self {
        case .thorough: return kCLLocationAccuracyBest
        case .thrifty: return kCLLocationAccuracyNearestTenMeters
        }
    }

    /// 앱이 종료돼도 큰 위치 변화로 되살릴지
    var wakesOnSignificantChange: Bool {
        self == .thorough
    }

    /// 걸음 수로 걷기를 빨리 알아챌지.
    /// 모션 활동 판정은 걷기를 확정하는 데 수십 초가 걸려 산책 앞부분이 통째로 빠진다.
    var usesPedometer: Bool {
        self == .thorough
    }

    /// iOS가 '멈췄다'고 보고 위치 갱신을 스스로 멈추게 둘지.
    /// 멈추면 다시 켜 주는 신호가 마땅치 않아, 빠짐없이 기록할 때는 맡기지 않는다.
    var allowsAutomaticPause: Bool {
        self == .thrifty
    }
}
