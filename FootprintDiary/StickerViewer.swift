//
//  StickerViewer.swift
//  FootprintDiary
//
//  찍어 둔 심볼 한 장을 화면 가득 들여다보는 창.
//
//  지도에서 심볼은 30pt 남짓으로 선다. 그래야 심볼을 넣은 자리와 갈래 도장만 찍은 자리가
//  같은 무게로 보이는데, 대신 무엇을 찍었는지 확인하려면 눈을 바짝 붙여야 한다.
//  '작게 서는 것'과 '들여다보는 것'은 다른 일이라, 크기를 키우는 대신 들여다보는 자리를
//  따로 낸다. 지도는 지도대로 고요하고, 궁금할 때는 한 번 두드려 크게 본다.
//
//  사진 뷰어를 따로 두지 않고 이것만 두는 까닭은 하는 일이 다르기 때문이다. 사진은
//  여러 장을 넘겨 보는 것이고, 심볼은 딱 한 장을 확인하는 것이다. 넘길 것이 없으니
//  좌우로 쓸어 넘기는 손짓도 없고, 대신 오므렸다 펴서 더 가까이 볼 수 있게 둔다.
//
//  바탕은 어둡게 깐다. 떼어 낸 심볼은 둘레에 흰 테두리를 두르고 있어(StickerMaker),
//  밝은 종이 위에 얹으면 테두리가 바탕에 녹아 실루엣이 헐렁해 보인다.
//

import SwiftUI

struct StickerViewer: View {
    let image: UIImage
    /// 아래에 적을 자리 이름 (없으면 갈래 이름)
    let title: String

    @Environment(\.dismiss) private var dismiss

    /// 지금 얼마나 키워 보고 있는지. settled는 손을 뗀 자리 — 다음 손짓은 여기서 이어진다.
    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var settledPan: CGSize = .zero

    private let minZoom: CGFloat = 1
    private let maxZoom: CGFloat = 5

    var body: some View {
        ZStack {
            backdrop
            picture
            controls
        }
        .statusBarHidden()
    }

    // MARK: - 바탕

    /// 바탕을 두드리면 닫힌다. 심볼 쪽의 '두 번 두드리기'와 부딪히지 않도록
    /// 그림이 아니라 바탕에만 건다.
    private var backdrop: some View {
        Color(red: 0.06, green: 0.06, blue: 0.07)
            .ignoresSafeArea()
            .onTapGesture { dismiss() }
    }

    // MARK: - 심볼

    private var picture: some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            // 화면 끝까지 붙이지 않는다. 흰 테두리가 화면 가장자리에 닿으면
            // 잘려 나간 것처럼 보인다.
            .padding(28)
            .scaleEffect(zoom)
            .offset(pan)
            .gesture(magnify)
            .simultaneousGesture(drag)
            .onTapGesture(count: 2) { toggleZoom() }
            .animation(.snappy(duration: 0.22), value: zoom)
            .animation(.snappy(duration: 0.22), value: pan)
            .accessibilityLabel("\(title) 심볼")
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = clampedZoom(settledZoom * value.magnification)
            }
            .onEnded { _ in
                settledZoom = zoom
                // 본디 크기로 돌아오면 자리도 가운데로 돌린다. 그러지 않으면
                // 작아진 심볼이 화면 구석에 치우친 채로 남는다.
                if zoom <= minZoom { resetPan() }
            }
    }

    /// 키워 본 뒤에만 끌어서 옮긴다. 본디 크기에서는 옮길 데가 없고,
    /// 옮겨지면 바탕을 두드려 닫으려다 심볼을 밀어 놓게 된다.
    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoom > minZoom else { return }
                pan = CGSize(width: settledPan.width + value.translation.width,
                             height: settledPan.height + value.translation.height)
            }
            .onEnded { _ in settledPan = pan }
    }

    private func toggleZoom() {
        if zoom > minZoom {
            zoom = minZoom
            settledZoom = minZoom
            resetPan()
        } else {
            zoom = 2.5
            settledZoom = 2.5
        }
    }

    private func resetPan() {
        pan = .zero
        settledPan = .zero
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, minZoom), maxZoom)
    }

    // MARK: - 단추와 글

    private var controls: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.16), in: Circle())
                }
                .accessibilityLabel("닫기")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                // 오므렸다 펼 수 있다는 것은 눈에 보이지 않는다. 아직 키워 보지 않은
                // 동안에만 한 줄 일러 두고, 한 번 키운 뒤에는 지운다.
                if zoom <= minZoom {
                    Text("두 번 두드리거나 오므렸다 펴면 더 크게 볼 수 있어요")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .animation(.easeInOut(duration: 0.2), value: zoom <= minZoom)
        }
    }
}
