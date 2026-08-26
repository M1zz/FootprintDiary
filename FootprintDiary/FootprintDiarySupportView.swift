//
//  FootprintDiarySupportView.swift
//  FootprintDiary
//
//  지원 화면 — 피드백/리뷰/버전 정보 (LeeoKit 제공)
//

import SwiftUI
import LeeoKit

struct FootprintDiarySupportView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var cloudSync: CloudSync
    @State private var showDiagnostics = false
    /// 개발자 모드. 버전 줄을 일곱 번 두드리면 켜진다 (LeeoSupportSection이 맡는다).
    /// 여기서는 그 값을 읽어 통계 화면 입구만 함께 연다.
    @AppStorage("dev.masterMode") private var devMode = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(TrackingMode.allCases) { mode in
                        Button {
                            locationManager.trackingMode = mode
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: locationManager.trackingMode == mode
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(locationManager.trackingMode == mode
                                                     ? Color.accentColor : .secondary)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(mode.title).font(.body.weight(.medium))
                                    Text(mode.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if locationManager.trackingMode == mode {
                                        VStack(alignment: .leading, spacing: 2) {
                                            ForEach(mode.details, id: \.self) { detail in
                                                Label(detail, systemImage: "circle.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .labelStyle(BulletLabelStyle())
                                            }
                                        }
                                        .padding(.top, 2)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text("기록 방식")
                } footer: {
                    Text("어느 쪽이든 받은 위치는 모두 저장합니다. 정확도가 낮은 점은 지도에 그리지 않을 뿐이에요.")
                }

                Section {
                    Button {
                        showDiagnostics = true
                    } label: {
                        HStack {
                            Label("기록 상태 보기", systemImage: "waveform.path.ecg")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                } header: {
                    Text("걷기 기록")
                } footer: {
                    Text("걸었는데 지도에 선이 그어지지 않으면 여기서 까닭을 볼 수 있어요.")
                }

                cloud

                Section {
                    LeeoSupportSection<FootprintDiarySpec>()
                    if devMode {
                        NavigationLink {
                            LeeoUsageStatsView<FootprintDiarySpec>()
                        } label: {
                            Label("사용 통계 (개발자)", systemImage: "chart.bar")
                        }
                    }
                } header: {
                    Text("지원")
                } footer: {
                    Text("어떤 화면이 쓰이는지 익명으로만 셉니다. 걸은 자리와 일기 글은 보내지 않아요.")
                }
            }
            .sheet(isPresented: $showDiagnostics) {
                TrackingDiagnosticsView()
            }
            .task { await cloudSync.refresh() }
            .navigationTitle("설정")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    /// 아이클라우드가 지금 어떤지.
    ///
    /// 켜져 있다는 말만 적어 두면 정작 로그아웃된 채로 몇 달이 지나도 모른다.
    /// 그래서 상태를 그대로 적고, 안 되고 있으면 그 까닭까지 적는다.
    private var cloud: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: cloudSync.symbolName)
                    .font(.title3)
                    .foregroundStyle(cloudSync.isHealthy ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(cloudSync.title).font(.body.weight(.medium))
                    Text(cloudSync.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        } header: {
            Text("아이클라우드")
        } footer: {
            Text("내 개인 아이클라우드에만 담깁니다. 다른 사람에게 보이지 않아요.")
        }
    }
}


/// 앞에 작은 점을 찍는 목록 표시
struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            configuration.icon.font(.system(size: 3))
            configuration.title
        }
    }
}
