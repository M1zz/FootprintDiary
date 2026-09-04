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
//  찍는 자리부터는 진짜 종이를 띄워 놓고 그 위에서 한다. 글로 "첫 기준점이 생겼어요"라고
//  알려 주기만 하면, 정작 무슨 일이 일어났는지는 못 본 채로 지도를 열게 된다. 이 앱에서
//  가장 중요한 한 장면이 도장이 종이에 내려앉는 순간인데 그것을 글로 때우는 셈이다.
//  그래서 종이는 찍기 전부터 떠 있고, 고른 도장은 보고 있던 그 종이 위에 내려앉는다.
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
    /// 종이가 붙들고 있을 자리. 한 번 잡으면 흔들리지 않게 붙들어 둔다 —
    /// 위치는 몇 초마다 몇 미터씩 고쳐지는데, 그때마다 종이가 미끄러지면 멀미가 난다.
    @State private var anchor: CLLocationCoordinate2D?
    /// 도장이 이미 내려앉았는지. 자국이 한 번만 번지도록 붙든다.
    @State private var didPress = false
    @StateObject private var paperProxy = MapProxy()

    private var placed: Int { stamps.count }
    private var isSatisfied: Bool { placed >= Self.requiredStamps }
    private var hasLocation: Bool { locationManager.currentLocation != nil }

    /// 방금 찍은 첫 도장
    private var firstStamp: MapStamp? {
        stamps.min { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            // 종이는 찍기 전부터 떠 있다. 이 자리에서 뷰가 바뀌지 않아야 고른 도장이
            // '새 화면에 그려지는' 것이 아니라 '보고 있던 종이에 내려앉는' 것으로 보인다.
            if step > 0 {
                paper
                    .padding(.horizontal, 28)
                    .padding(.bottom, 22)
            }
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
            guard step == 1, isSatisfied else { return }
            step = 2
            // 도장이 종이에 닿는 자국. 시트가 닫히면서 종이가 드러나기를 기다렸다 번진다.
            Task {
                try? await Task.sleep(for: .milliseconds(320))
                withAnimation(.easeOut(duration: 0.7)) { didPress = true }
            }
        }
        .onChange(of: hasLocation) { captureAnchor() }
        .onAppear {
            locationManager.requestPermission()
            // 자리를 찍으려면 지금 위치가 필요하다
            locationManager.refreshCurrentLocation()
            captureAnchor()
        }
    }

    /// 종이가 설 자리를 한 번만 잡는다
    private func captureAnchor() {
        guard anchor == nil, let coordinate = locationManager.currentLocation?.coordinate else { return }
        anchor = coordinate
    }

    // MARK: - 종이

    /// 안내 안에 띄우는 진짜 종이 한 조각.
    ///
    /// 그림으로 흉내 내지 않고 지도 본체를 그대로 쓴다. 안내에서 본 종이와 열고 나서
    /// 보는 종이가 다르면, 첫 도장이 어디로 갔는지 되짚느라 지도를 다시 배워야 한다.
    private var paper: some View {
        ZStack {
            AtlasMapView(
                cells: [],
                trails: [],
                showsBasemap: false,
                stamps: firstStamp.map { [$0] } ?? [],
                proxy: paperProxy,
                focus: anchor,
                showsTrackingButton: false,
                // 도장을 찍기 전에는 '여기가 나'를 점으로 보여 주고, 찍고 나서는 물린다.
                // 도장이 바로 그 점 자리에 내려앉기 때문에, 켜 두면 무엇을 찍었는지가
                // 점에 통째로 덮여 정작 보여 주려던 장면이 사라진다.
                showsUserLocation: step == 1
            )
            // 만질 수 없게 둔다. 여기서 할 일은 하나뿐인데 종이를 끌 수 있으면
            // 자기 자리를 잃어버리고, 그러면 도장이 어디에 찍혔는지 볼 수 없다.
            .allowsHitTesting(false)

            if step == 1 {
                // 아직 아무것도 없는 종이라는 것을 한 줄로 짚어 준다.
                // 빈 화면은 그것만으로는 '아직'인지 '고장'인지 갈리지 않는다.
                //
                // 한가운데를 비켜 위에 붙인다. 가운데는 지금 내가 선 점이 서 있고
                // 곧 도장이 내려앉을 자리다 — 안내가 그 위를 덮으면 정작 보여 주려던
                // 장면을 안내가 가린다.
                Text(hasLocation ? "아직 아무것도 없는 종이" : "지금 있는 곳을 찾는 중")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 10)
            }

            // 도장이 눌린 자국. 한 번 크게 번졌다가 도장 크기로 오므라들며 사라진다.
            if step == 2 {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(InkStyle.sealRed), lineWidth: 2)
                    .frame(width: StampSeal.size.width, height: StampSeal.size.height)
                    .scaleEffect(didPress ? 1 : 3.2)
                    .opacity(didPress ? 0 : 0.9)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(InkStyle.ink).opacity(0.15), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(step == 2 ? "종이에 첫 도장이 찍혔습니다" : "아직 아무것도 없는 종이")
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

    /// 종이가 이미 위에 떠 있으므로 그림은 두지 않는다.
    /// 큰 그림을 또 얹으면 정작 보아야 할 종이가 화면 밖으로 밀려난다.
    private var anchorStep: some View {
        VStack(spacing: 12) {
            Text("이 종이에 첫 도장을 찍어 주세요")
                .font(.title3.bold())
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
        VStack(spacing: 12) {
            Text("찍혔어요")
                .font(.title3.bold())

            VStack(spacing: 10) {
                Text("이제 걸어 보세요.\n지나온 자리가 한 점씩 이 종이에 찍힙니다.")
                Text("자주 가는 곳에 **도착하면 그 자리에서 한 번 더** 찍어 주세요.\n기준이 둘이 되면 백지에서도 방향이 잡힙니다.")
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
