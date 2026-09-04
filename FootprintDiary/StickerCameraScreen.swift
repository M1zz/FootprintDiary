//
//  StickerCameraScreen.swift
//  FootprintDiary
//
//  카메라로 스티커를 찍어 지도에 쓸 심볼로 만드는 화면.
//
//  화면은 두 걸음뿐이다 — 창 안에 넣고 누른다, 그리고 이걸 쓸지 정한다.
//
//  걸음을 둘로 나눈 까닭이 있다. 카메라는 손이 흔들리고 빛이 어긋나는 물건이라 한 번에
//  마음에 드는 것이 나오는 일이 드물다. 찍자마자 지도에 박아 버리면 마음에 안 드는
//  심볼을 지우고 다시 찍는 데 세 번을 눌러야 한다. '다시 찍기'가 그 자리에 있어야 한다.
//
//  창은 정사각이다. 지도에 얹히는 자리가 정사각이라 여기서 가로로 길게 잡아 두면
//  나중에 눌려서 다른 그림이 된다. 겨눈 것이 곧 얹히는 것이어야 한다.
//
//  창이 화면의 일부뿐이라, 멀리 있는 것은 창 안에서 점이 된다. 다가갈 수 있으면
//  다가가는 것이 낫지만 길 건너 간판이나 유리 너머 물건은 그럴 수가 없어, 겨누는 동안
//  배율을 바꿀 길을 둔다 — 손가락을 벌리거나, 아래에 선 배수를 누르거나. 배율은 기기에
//  걸리므로(StickerCamera) 창에서 겨눈 것이 그대로 찍히는 것은 달라지지 않는다.
//
//  창에 톱니(우표 모양)를 두었다가 걷어 냈다. 찍고 나면 배경이 지워져 안에 든 것만
//  남으므로, 테두리 모양은 결과에 아무 자국도 남기지 않는다. 남는 것은 겨누는 동안의
//  성가심뿐이라 네모로 되돌렸다 — 창은 '여기까지 담긴다'만 말하면 된다.
//
//  시뮬레이터에는 카메라가 없어 미리보기가 까맣게 나온다. 실기기에서 봐야 한다.
//

import SwiftUI
import AVFoundation

struct StickerCameraScreen: View {
    /// 만든 심볼을 건넨다 (PNG). 화면은 스스로 닫힌다.
    let onUse: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = StickerCamera()

    /// 찍어서 오려 낸 것. 정해지면 '이걸 쓸까' 화면으로 넘어간다.
    @State private var sticker: UIImage?
    /// 배경을 실제로 지웠는지. 못 지웠으면 그 까닭을 한 줄 적어 준다.
    @State private var liftedSubject = true
    /// 미리보기가 실제로 차지한 크기. 오려 낼 자리를 되짚는 데 쓴다.
    @State private var previewSize: CGSize = .zero
    /// 창이 놓인 자리 (미리보기 안에서의 좌표)
    @State private var windowRect: CGRect = .zero

    /// 집게질을 시작할 때의 배율. 손가락이 벌어진 몫을 여기에 곱한다.
    /// 매번 지금 배율에 곱하면 조금만 벌려도 끝까지 튀어 오른다.
    @State private var pinchAnchor: CGFloat = 1
    @State private var pinching = false

    /// 날아가는 중인지 (0: 제자리, 1: 단추 속)
    @State private var flight: Flight = .idle

    /// 잰 자리들. 심볼이 어디서 어디로 날아갈지는 화면 크기마다 달라진다.
    @State private var cardFrame: CGRect = .zero
    @State private var buttonFrame: CGRect = .zero

    private enum Flight { case idle, popped, gone }

    /// 창 한 변이 화면 너비에서 차지하는 몫.
    /// 너무 크면 손이 프레임 밖으로 나가고, 너무 작으면 무엇을 겨누는지 안 보인다.
    private let windowFraction: CGFloat = 0.72
    private let windowCorner: CGFloat = 16

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let sticker {
                    result(sticker)
                } else {
                    viewfinder
                }
            }
            .coordinateSpace(name: "sticker")
            .navigationTitle(sticker == nil ? "스티커 찍기" : "이 심볼을 쓸까요?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
                }
                if sticker == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            camera.flip()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                        }
                        .disabled(!camera.isAuthorized)
                    }
                }
            }
        }
        .task { await camera.requestAccess() }
        .onDisappear { camera.stop() }
        // 셔터를 누르면 온전한 사진이 먼저 온다. 그것을 화면에서 겨눈 창으로 오려 내고
        // 안에 든 것만 떼어 낸다. (StickerMaker)
        .onChange(of: camera.captured) { _, image in
            guard let image else { return }
            let made = StickerMaker.makeSticker(
                from: image,
                previewSize: previewSize,
                windowRect: windowRect,
                mirrored: camera.isMirrored
            )
            sticker = made?.image
            liftedSubject = made?.liftedSubject ?? false
            camera.captured = nil
            // 결과를 보는 동안에는 카메라를 멈춘다. 다시 찍기를 누르면 되살린다.
            camera.stop()
        }
    }

    // MARK: - 겨누는 화면

    private var viewfinder: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let size = geometry.size
                let rect = window(in: size)
                ZStack {
                    if camera.isAuthorized {
                        StickerCameraPreview(session: camera.session)
                    } else {
                        permissionNotice
                    }

                    // 창 바깥을 덮는다. 어디까지 담기는지가 눈에 보여야 손이 그 안에
                    // 물건을 넣는다. 덮지 않고 테두리만 그으면 어느 쪽이 안인지 헷갈린다.
                    Color.black.opacity(0.55)
                        .reverseMask {
                            RoundedRectangle(cornerRadius: windowCorner)
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                        }
                        .allowsHitTesting(false)

                    RoundedRectangle(cornerRadius: windowCorner)
                        .stroke(Color.white.opacity(0.9), lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)

                    if camera.isAuthorized && camera.canZoom {
                        VStack {
                            Spacer()
                            zoomBar
                                .padding(.bottom, 18)
                        }
                    }
                }
                // 집게질은 창 안팎을 가리지 않고 화면 어디서나 받는다. 창 안에서만 받으면
                // 정작 손가락이 겨누는 것을 가리게 된다.
                .contentShape(Rectangle())
                .gesture(pinch)
                .onAppear {
                    previewSize = size
                    windowRect = rect
                }
                .onChange(of: size) { _, new in
                    previewSize = new
                    windowRect = window(in: new)
                }
            }

            shutterBar
        }
    }

    // MARK: - 배율

    /// 손가락을 벌린 만큼 배율을 옮긴다.
    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if !pinching {
                    pinching = true
                    pinchAnchor = camera.zoom
                }
                camera.setZoom(pinchAnchor * value.magnification)
            }
            .onEnded { _ in pinching = false }
    }

    /// 아래에 서는 배수 단추. 지금 서 있는 자리는 실제 값을 그대로 적는다 —
    /// 1.7배로 벌려 놓고 단추에는 '1'이 적혀 있으면 어디쯤인지 알 수 없다.
    private var zoomBar: some View {
        HStack(spacing: 6) {
            ForEach(camera.zoomStops, id: \.self) { stop in
                let isCurrent = stop == currentStop
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { camera.setZoom(stop) }
                } label: {
                    Text(isCurrent ? zoomLabel(camera.zoom) : shortLabel(stop))
                        .font(.caption.weight(isCurrent ? .bold : .medium))
                        .monospacedDigit()
                        .foregroundStyle(isCurrent ? .white : .white.opacity(0.6))
                        .frame(minWidth: isCurrent ? 44 : 34, minHeight: 34)
                        .background {
                            Circle()
                                .fill(.white.opacity(isCurrent ? 0.22 : 0))
                                .frame(width: 34, height: 34)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(shortLabel(stop))배")
                .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(.black.opacity(0.4)))
    }

    /// 지금 배율이 어느 단추 자리에 서 있는지. 그 아래로는 못 내려가면 첫 단추다.
    private var currentStop: CGFloat? {
        camera.zoomStops.last { $0 <= camera.zoom + 0.0001 } ?? camera.zoomStops.first
    }

    private func zoomLabel(_ value: CGFloat) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? "\(Int(rounded))×"
            : String(format: "%.1f×", rounded)
    }

    private func shortLabel(_ value: CGFloat) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }

    private func window(in size: CGSize) -> CGRect {
        let side = min(size.width * windowFraction, size.height * 0.62)
        return CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
    }

    private var shutterBar: some View {
        VStack(spacing: 10) {
            Text("창 안에 담긴 것만 남고 배경은 지워져요")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))

            Button {
                camera.capture()
            } label: {
                ZStack {
                    Circle().stroke(Color.white, lineWidth: 4).frame(width: 74, height: 74)
                    Circle().fill(Color.white).frame(width: 60, height: 60)
                }
            }
            .disabled(!camera.isAuthorized)
            .opacity(camera.isAuthorized ? 1 : 0.3)
            .accessibilityLabel("찍기")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(Color.black)
    }

    private var permissionNotice: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.5))
            Text(camera.permissionDenied ? "카메라를 쓸 수 없어요" : "카메라를 준비하는 중")
                .font(.headline)
                .foregroundStyle(.white)
            if camera.permissionDenied {
                Text("설정 앱 > 벅뚜벅뚜 > 카메라를 켜 주세요.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                Button("설정 열기") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
        .padding(30)
    }

    // MARK: - 쓸지 정하는 화면

    private func result(_ image: UIImage) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            Text("지도에서는 이렇게 보여요")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))

            // 지도 위에 실제로 얹힌 모습 그대로 보여 준다.
            //
            // 떼어 낸 그림만 크게 보여 주고 말면, 지도에 얹었을 때 무엇인지 알아볼 수
            // 없는 일이 잦다. 종이 위에 도장 크기로 앉혀 놓고 봐야 '이게 지도에서 읽히나'를
            // 정할 수 있다. 크게 한 장 더 두는 것은 무엇이 떼어졌는지 확인하는 몫이다.
            mapPreview(image)
                .background {
                    GeometryReader { geometry in
                        Color.clear.onAppear {
                            cardFrame = geometry.frame(in: .named("sticker"))
                        }
                    }
                }
                // '통 튀어서 날아간다' — 먼저 살짝 부풀었다가 단추 속으로 빨려 들어간다.
                // 곧바로 줄어들기만 하면 사라진 것처럼 보이지, 어디로 들어갔는지 안 보인다.
                .scaleEffect(flightScale, anchor: .center)
                .offset(flightOffset)
                .opacity(flight == .gone ? 0 : 1)

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 190, maxHeight: 190)
                .opacity(flight == .idle ? 1 : 0)

            if !liftedSubject {
                Text("또렷한 것이 없어 배경을 지우지 못했어요. 물건에 가까이 대고 다시 찍어 보세요.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 32)
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button {
                    use(image)
                } label: {
                    Text("이 심볼 쓰기")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(InkStyle.sealRed))
                .scaleEffect(flight == .gone ? 1.06 : 1)
                .background {
                    GeometryReader { geometry in
                        Color.clear.onAppear {
                            buttonFrame = geometry.frame(in: .named("sticker"))
                        }
                    }
                }

                Button {
                    sticker = nil
                    flight = .idle
                    camera.start()
                } label: {
                    Text("다시 찍기")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .opacity(flight == .idle ? 1 : 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    /// 지도에 얹힌 그대로 — 종이를 깔고 도장 크기로 앉힌다.
    private func mapPreview(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: StampSeal.size.width, height: StampSeal.size.height)
            .padding(14)
            .background(Color(InkStyle.paper))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }

    // MARK: - 날려 보내기

    private var flightScale: CGFloat {
        switch flight {
        case .idle: return 1
        case .popped: return 1.18
        case .gone: return 0.2
        }
    }

    /// 단추 한가운데까지의 거리. 자리를 못 쟀으면 그냥 아래로 내려보낸다 —
    /// 어디로 갔는지는 덜 또렷해도, 멈춰 서서 아무 일도 안 하는 것보다 낫다.
    private var flightOffset: CGSize {
        guard flight == .gone else { return .zero }
        guard !cardFrame.isEmpty, !buttonFrame.isEmpty else { return CGSize(width: 0, height: 220) }
        return CGSize(width: buttonFrame.midX - cardFrame.midX,
                      height: buttonFrame.midY - cardFrame.midY)
    }

    private func use(_ image: UIImage) {
        guard flight == .idle, let data = StickerMaker.pngData(for: image) else { return }

        // 통 — 손끝에서 튀어 오르는 만큼만.
        withAnimation(.spring(response: 0.16, dampingFraction: 0.45)) { flight = .popped }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 160_000_000)
            // 쏙 — 단추 속으로.
            withAnimation(.easeIn(duration: 0.32)) { flight = .gone }
            // 들어가 앉는 소리 대신 손끝에 한 번.
            try? await Task.sleep(nanoseconds: 300_000_000)
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            try? await Task.sleep(nanoseconds: 90_000_000)
            onUse(data)
            dismiss()
        }
    }
}

// MARK: - 구멍 뚫린 덮개

extension View {
    /// 준 모양만큼 뚫린 채로 덮는다.
    ///
    /// mask는 '남길 곳'을 받는데 여기서 필요한 것은 그 반대다. 뒤집힌 마스크를 만들어
    /// 창 바깥만 덮으면, 덮개 하나로 '바깥은 어둡고 창은 그대로'가 된다.
    /// 사각형 넷을 이어 붙여 흉내 낼 수도 있으나 모서리가 둥근 창에서는 어긋난다.
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle()
                .overlay {
                    mask().blendMode(.destinationOut)
                }
                .compositingGroup()
        }
    }
}
