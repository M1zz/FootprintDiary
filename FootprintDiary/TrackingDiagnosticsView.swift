//
//  TrackingDiagnosticsView.swift
//  FootprintDiary
//
//  기록이 왜 안 되는지 눈으로 보는 화면.
//  걷고 나서 여기를 열면 어느 관문에서 몇 번 막혔는지 그대로 나온다.
//

import SwiftUI
import SwiftData
import CoreLocation
import UIKit

struct TrackingDiagnosticsView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @Query private var track: [TrackPoint]
    @Environment(\.dismiss) private var dismiss

    @StateObject private var clock = Ticker()

    var body: some View {
        NavigationStack {
            List {
                Section("지금 상태") {
                    row("기록 방식", locationManager.trackingMode.title)
                    row("저전력 모드", isLowPower ? "켜짐 — 배경 기록이 줄어요" : "꺼짐", warn: isLowPower)
                    row("걷기로 보고 기록 중", locationManager.diagnostics.isWalking ? "예" : "아니오",
                        warn: !locationManager.diagnostics.isWalking)
                    row("모션이 알려 준 상태", locationManager.diagnostics.motionState)
                    row("모션 권한", TrackingDiagnostics.motionAuthorizationText,
                        warn: TrackingDiagnostics.motionAuthorizationText.contains("거부"))
                    row("위치 권한", locationText,
                        warn: !(locationManager.authorizationStatus == .authorizedAlways))
                    row("마지막 위치 정확도", accuracyText, warn: isAccuracyBad)
                    row("마지막 위치가 들어온 지", fixAgeText)
                }

                Section {
                    row("이번 실행에서 저장한 점", "\(locationManager.diagnostics.accepted)개")
                    row("지금까지 쌓인 점 전부", "\(track.count)개")
                    row("그리기엔 정확도가 모자란 점", "\(lowQualityCount)개")
                } header: {
                    Text("점 세기")
                } footer: {
                    Text("정확도가 모자란 점도 저장은 해 둡니다. 지금은 지도에 그리지 않지만, 보정이 나아지면 그때 쓸 수 있어요.")
                }

                Section {
                    let rejections = locationManager.diagnostics.rejections
                        .sorted { $0.value > $1.value }
                    if rejections.isEmpty {
                        Text("아직 버려진 점이 없어요")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(rejections, id: \.key) { rejection, count in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(rejection.rawValue)
                                    Spacer()
                                    Text("\(count)번")
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                Text(rejection.hint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    Text("버려진 까닭")
                } footer: {
                    if let (rejection, count) = locationManager.diagnostics.topRejection {
                        Text("가장 많이 막힌 곳: \(rejection.rawValue) (\(count)번). \(rejection.hint)")
                    }
                }

                if needsSettings {
                    Section {
                        Button {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        } label: {
                            Label("설정에서 권한 켜기", systemImage: "gear")
                        }
                    } footer: {
                        Text("위치를 '항상 허용'으로, 동작 및 피트니스를 켜 두면 앱을 열지 않고 걸어도 기록됩니다.")
                    }
                }

                Section {
                    Button("세기 초기화") { locationManager.diagnostics.reset() }
                }
            }
            .navigationTitle("기록 상태")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private var isLowPower: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// 저장은 됐지만 정확도가 모자라 지도에 그리지 않는 점
    private var lowQualityCount: Int {
        track.filter { $0.horizontalAccuracy > LocationManager.maxDrawAccuracy }.count
    }

    /// 권한이 모자라 기록이 막힐 수 있는 상태인가
    private var needsSettings: Bool {
        locationManager.authorizationStatus != .authorizedAlways
            || TrackingDiagnostics.motionAuthorizationText.contains("거부")
    }

    // MARK: - 줄

    private func row(_ title: String, _ value: String, warn: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(warn ? Color.orange : .secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var locationText: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways: return "항상 허용"
        case .authorizedWhenInUse: return "앱 사용 중만 — 배경 기록 안 됨"
        case .denied: return "거부됨"
        case .restricted: return "제한됨"
        default: return "아직 묻지 않음"
        }
    }

    private var accuracyText: String {
        guard let accuracy = locationManager.diagnostics.lastAccuracy else { return "아직 없음" }
        return String(format: "±%.0fm (그리기 기준 %.0fm)", accuracy, LocationManager.maxDrawAccuracy)
    }

    private var isAccuracyBad: Bool {
        guard let accuracy = locationManager.diagnostics.lastAccuracy else { return false }
        return accuracy > LocationManager.maxDrawAccuracy
    }

    private var fixAgeText: String {
        guard let at = locationManager.diagnostics.lastFixAt else { return "아직 없음" }
        let seconds = Int(max(0, clock.now.timeIntervalSince(at)))
        return seconds < 60 ? "\(seconds)초 전" : "\(seconds / 60)분 전"
    }
}

/// 화면에 떠 있는 동안 '몇 초 전'을 갱신하기 위한 시계
final class Ticker: ObservableObject {
    @Published var now = Date()
    private var timer: Timer?

    init() {
        // Timer는 메인 런루프에서 돈다 — 갱신이 메인에서 일어남이 보장된다
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.now = Date()
        }
    }

    deinit { timer?.invalidate() }
}
