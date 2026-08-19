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
    @State private var showDiagnostics = false

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

                Section {
                    LeeoSupportSection<FootprintDiarySpec>()
                } header: {
                    Text("지원")
                }
            }
            .sheet(isPresented: $showDiagnostics) {
                TrackingDiagnosticsView()
            }
            .navigationTitle("설정")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
