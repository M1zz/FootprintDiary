//
//  OnboardingView.swift
//  FootprintDiary
//
//  처음 여는 사람에게 반드시 한 번 보여 주는 안내.
//
//  이 앱의 지도는 백지에서 시작한다. 아무것도 없는 종이는 그 자체로는 어디가 어딘지
//  알 수 없어서, 첫 화면이 '빈 화면'이 아니라 '고장 난 화면'처럼 보인다.
//  그래서 기준이 될 스탬프를 하나 찍고 나서야 지도를 열어 준다.
//
//  여기서 받는 것은 딱 하나, '지금 있는 곳'이다. 사람은 한 번에 두 곳에 있을 수 없으므로
//  두 번째 기준점을 여기서 달라고 하면 같은 자리를 두 번 찍게 만드는 셈이 된다.
//  두 번째는 그곳에 가서 찍으라고 일러 주고 내보낸다.
//
//  건너뛸 수 있게 두지 않는 까닭은 따로 있다. 건너뛴 사람은 백지를 보고 앱을 지운다.
//

import SwiftUI
import SwiftData
import CoreLocation

struct OnboardingView: View {
    /// 여기서 받는 스탬프. 지금 있는 곳 하나뿐이다.
    /// 방향을 잡으려면 결국 둘이 있어야 하지만, 두 번째는 그 자리에 가서 찍어야 한다.
    static let requiredStamps = 1

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var locationManager: LocationManager
    @Query private var stamps: [MapStamp]

    /// 안내를 다 마쳤을 때
    let onFinish: () -> Void

    @State private var step = 0
    @State private var showPicker = false

    private var placed: Int { stamps.count }
    private var isSatisfied: Bool { placed >= Self.requiredStamps }
    private var hasLocation: Bool { locationManager.currentLocation != nil }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            content
                .padding(.horizontal, 28)
            Spacer(minLength: 0)
            footer
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .background(Color(InkStyle.paper))
        .interactiveDismissDisabled()
        .sheet(isPresented: $showPicker) {
            StampPicker { kind in
                guard let coordinate = locationManager.currentLocation?.coordinate else { return }
                modelContext.insert(MapStamp(kind: kind, coordinate: coordinate))
                try? modelContext.save()
            }
        }
        .onChange(of: placed) {
            // 첫 기준점이 찍히면 바로 다음 쪽으로 (같은 자리를 또 찍게 두지 않는다)
            if step == 1, isSatisfied { step = 2 }
        }
        .onAppear {
            locationManager.requestPermission()
            // 자리를 찍으려면 지금 위치가 필요하다
            locationManager.refreshCurrentLocation()
        }
    }

    // MARK: - 쪽

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: intro
        case 1: anchorStep
        default: doneStep
        }
    }

    private var intro: some View {
        VStack(spacing: 22) {
            Image(systemName: "map")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(Color(InkStyle.ink))

            Text("빈 종이에서 시작합니다")
                .font(.title2.bold())

            VStack(spacing: 14) {
                Text("세상은 이미 다른 지도가 다 그려 두었어요.\n여기에는 **당신이 두 발로 지난 자리만** 남습니다.")
                Text("차나 지하철로 지난 길은 그려지지 않아요.\n걸어야만 한 점씩 찍힙니다.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
        }
    }

    private var anchorStep: some View {
        VStack(spacing: 22) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(Color(InkStyle.sealRed))

            Text("지금 있는 곳을 찍어 주세요")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text("빈 종이는 그것만으로는 어디가 어딘지 알 수 없어요.\n지금 계신 자리가 **첫 기준점**이 됩니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            if !hasLocation {
                Label("지금 위치를 찾고 있어요", systemImage: "location.magnifyingglass")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 첫 기준점을 찍고 난 뒤. 두 번째는 여기서 받지 않는다 — 그 자리에 가야 찍을 수 있다.
    private var doneStep: some View {
        VStack(spacing: 22) {
            Image(systemName: "figure.walk")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(Color(InkStyle.ink))

            Text("첫 기준점이 생겼어요")
                .font(.title2.bold())

            VStack(spacing: 14) {
                Text("이제 걸어 보세요.\n지나온 자리가 한 점씩 찍힙니다.")
                Text("자주 가는 곳에 **도착하면 그 자리에서 한 번 더** 찍어 주세요.\n기준이 둘이 되면 백지에서도 방향이 잡힙니다.")
                Text("지도를 길게 눌러도 찍을 수 있어요.")
                    .font(.footnote)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
        }
    }

    // MARK: - 아래 단추

    @ViewBuilder
    private var footer: some View {
        switch step {
        case 0:
            primaryButton("시작하기") { step = 1 }
        case 1:
            VStack(spacing: 10) {
                primaryButton("지금 자리에 찍기", enabled: hasLocation) { showPicker = true }
                Text("집·일터처럼 기준이 될 만한 것으로 골라 주세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        default:
            primaryButton("내 지도 열기") { finish() }
        }
    }

    private func primaryButton(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(enabled ? Color(InkStyle.sealRed) : Color.secondary.opacity(0.4))
                )
        }
        .disabled(!enabled)
    }

    private func finish() {
        onFinish()
    }
}
