//
//  FootprintDiarySupportView.swift
//  FootprintDiary
//
//  지원 화면 — 피드백/리뷰/버전 정보 (LeeoKit 제공)
//

import SwiftUI
import LeeoKit

struct FootprintDiarySupportView: View {
    /// 지금까지 그린 길이. 지도 위에 늘 띄워 두던 것을 여기로 옮겼다.
    struct Record {
        let atlasMeters: Double
        let todayMeters: Double
    }

    /// 지도에서 열었을 때만 있다
    var record: Record? = nil
    /// 모아 보기에서 고른 화면을 연다. 설정은 먼저 닫힌다 (AtlasScreen이 닫힌 뒤에 연다).
    var onOpen: (AtlasDestination) -> Void = { _ in }

    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var cloudSync: CloudSync
    @Environment(\.dismiss) private var dismiss
    @State private var showDiagnostics = false
    @State private var showWhatsNew = false
    /// 지도 모양. 지도 위 그림지도 단추와 같은 열쇠다 (단추를 꺼 둔 사람도 여기서 바꾼다)
    @AppStorage("footprint.terrainSkin") private var terrainSkinRaw = TerrainSkin.ink.rawValue
    /// 개발자 모드. 버전 줄을 일곱 번 두드리면 켜진다 (LeeoSupportSection이 맡는다).
    /// 여기서는 그 값을 읽어 통계 화면 입구만 함께 연다.
    @AppStorage("dev.masterMode") private var devMode = false

    var body: some View {
        NavigationStack {
            List {
                gallery

                mapControls

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
                    Button {
                        showWhatsNew = true
                    } label: {
                        HStack {
                            Label("새로 생긴 것", systemImage: "sparkles")
                            Spacer()
                            Text("버전 \(WhatsNew.version)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                } header: {
                    Text("안내")
                }

                Section {
                    LeeoSupportSection<FootprintDiarySpec>()
                    NavigationLink(LeeoRoadmapText.entry) { RoadmapScreen() }
                    LeeoShareAppLink<FootprintDiarySpec>()
                    LeeoTipJarLink<FootprintDiarySpec>(tipJar: FootprintDiarySpec.tipJar)
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
            .sheet(isPresented: $showWhatsNew) {
                WhatsNewView { destination in open(destination) }
            }
            .task { await cloudSync.refresh() }
            .navigationTitle("설정")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    /// 지도에서 내려온 화면들. 지도에 단추가 없어도 여기서는 늘 열 수 있다.
    private var gallery: some View {
        Section {
            if let record {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DayTimeline.distanceText(record.atlasMeters))
                            .font(.title2.weight(.bold).monospacedDigit())
                            .fontDesign(.serif)
                        Text("내가 그린 길")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(record.todayMeters >= 1 ? "+\(DayTimeline.distanceText(record.todayMeters))" : "—")
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .foregroundStyle(record.todayMeters >= 1 ? Color(DotPalette.today) : .secondary)
                        Text("오늘 그은 길")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
            ForEach(AtlasDestination.allCases) { destination in
                Button {
                    open(destination)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: destination.symbol)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(destination.title)
                            Text(destination.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
            }
        } header: {
            Text("모아 보기")
        }
    }

    /// 지도 위에 띄워 둘 것 고르기
    private var mapControls: some View {
        Section {
            Picker(selection: $terrainSkinRaw) {
                Text("먹 지도").tag(TerrainSkin.ink.rawValue)
                Text("그림지도").tag(TerrainSkin.picture.rawValue)
            } label: {
                Label("지도 모양", systemImage: "mountain.2")
            }
            ForEach(MapControl.allCases) { control in
                MapControlToggle(control: control)
            }
        } header: {
            Text("지도에 보이기")
        } footer: {
            Text("꺼 둔 화면도 위 '모아 보기'에서 언제든 열 수 있어요. 도장과 설정 단추는 늘 보여요.")
        }
    }

    private func open(_ destination: AtlasDestination) {
        onOpen(destination)
        dismiss()
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


/// 지도 위 하나를 켜고 끄는 줄. 열쇠가 줄마다 달라 @AppStorage를 줄 안에 둔다.
private struct MapControlToggle: View {
    let control: MapControl
    @AppStorage private var isOn: Bool

    init(control: MapControl) {
        self.control = control
        _isOn = AppStorage(wrappedValue: control.isVisibleByDefault, control.storageKey)
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(systemName: control.symbol)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(control.title)
                    Text(control.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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
