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
//  좌우로 쓸어 넘겨 다음 장으로 가는 손짓이 남아, 그 손짓을 뒤집는 데 쓴다.
//
//  손짓은 셋이다. 오므렸다 펴면 커지고, 두 번 두드리면 오갔다 하고, 쓸면 뒤집힌다.
//  키워 본 뒤에는 쓸어서 옮긴다 — 키운 심볼은 화면 밖으로 나가 있으므로 그때 필요한
//  것은 뒤집는 것이 아니라 옮기는 것이다.
//
//  뒤집히는 것은 한 장짜리 카드다. 종이가 제자리에서 팽이처럼 도는 것이 아니라, 손끝에
//  걸려 앞뒤로 넘어간다. 심볼은 배경이 지워진 한 장이라 팽이처럼 돌면 그저 기울어진
//  그림이 되지만, 넘어가면 한 장의 두께가 생겨 정말 붙어 있던 것을 떼어 든 것 같다.
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
    /// 지금 얼마나 넘어가 있는지 (도). 한 바퀴를 넘겨도 되돌리지 않는다 —
    /// 720도는 '두 바퀴 넘어갔다'는 뜻이고, 애니메이션이 그 두 바퀴를 실제로 넘는다.
    @State private var flip: Double = 0
    @State private var settledFlip: Double = 0
    /// 넘어가는 축. 쓸어 넘긴 방향과 직각이다 — 좌우로 쓸면 세로축, 위아래로 쓸면 가로축.
    @State private var axis = CGVector(dx: 0, dy: 1)
    /// 이번 손짓이 향한 쪽 (길이 1). 손짓이 끝나면 비운다.
    ///
    /// 축을 손짓마다 한 번만 정하는 까닭은, 도중에 축이 흔들리면 카드가 넘어가다 말고
    /// 방향을 트는 탓이다. 한 번 걸린 카드는 튕긴 쪽으로 끝까지 넘어가야 한다.
    @State private var swipeDirection: CGVector?

    /// 한 번이라도 만져 봤는지. 일러두는 글을 언제 지울지 가른다.
    @State private var played = false

    private let minZoom: CGFloat = 1
    private let maxZoom: CGFloat = 5

    /// 쓴 거리 1pt를 몇 도로 셀지. 300pt쯤 쓸면 반 바퀴가 넘어간다 —
    /// 손끝을 그대로 따라오면서, 화면을 한 번 가로지르면 한 바퀴에 닿는 만큼.
    private let degreesPerPoint: Double = 0.8
    /// 손을 뗀 뒤 더 넘어가는 몫. 튕긴 세기(predictedEndTranslation)에 이만큼을 얹는다.
    ///
    /// 살살 쓸면 반 바퀴를 못 넘겨 도로 눕고, 여느 세기로 튕기면 한두 바퀴, 세게 튕기면
    /// 세 바퀴까지 넘어간다. 이 사이가 손끝에 힘을 준 만큼 돌아온다고 느껴지는 자리다.
    private let flingBoost: Double = 1.5
    /// 한 번 튕겨 넘어갈 수 있는 끝 (도). 세 바퀴를 넘기면 카드가 넘어가는 것이 아니라
    /// 화면이 고장 난 것처럼 보이고, 멎기를 기다리는 동안 정작 심볼을 못 본다.
    private let maxFling: Double = 1080
    /// 카드에 두께가 있어 보일 만큼만 원근을 준다. 0이면 그림자 인형처럼 납작하게
    /// 접히고, 1을 넘기면 가까운 쪽이 확 커져 손에서 튀어나온 것처럼 요란해진다.
    private let depth: CGFloat = 0.6

    var body: some View {
        ZStack {
            backdrop
            picture
            controls
        }
        // 손짓을 그림이 아니라 화면 전체에 건다. 넓적한 간판은 화면 가운데 좁은 띠로만
        // 서는데, 그 띠 위에서만 넘어가면 쓸어도 아무 일이 없는 자리가 화면의 대부분이 된다.
        //
        // 자리를 먼저 화면만큼 넓혀 둔다. 바탕이 화면을 다 덮는 것은 그리는 일이지
        // 자리를 차지하는 일이 아니라, 넓혀 두지 않으면 손이 닿는 자리가 글씨와 단추가
        // 놓인 만큼으로 쪼그라든다 — 쓸어도 아무 일이 없다.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(swipe())
        .simultaneousGesture(magnify)
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
            // 축은 한 겹만 건다. 가로축과 세로축을 잇달아 걸면 원근이 두 번 먹어,
            // 비스듬히 선 카드가 저 멀리 놓인 것처럼 쪼그라든다.
            .rotation3DEffect(.degrees(flip),
                              axis: (x: axis.dx, y: axis.dy, z: 0),
                              perspective: depth)
            .scaleEffect(zoom)
            .offset(pan)
            .onTapGesture(count: 2) { toggleZoom() }
            .animation(.snappy(duration: 0.22), value: zoom)
            .animation(.snappy(duration: 0.22), value: pan)
            .accessibilityLabel("\(title) 심볼")
    }

    // MARK: - 뒤집기와 옮기기

    /// 쓸면 그 방향으로 카드처럼 넘어간다. 키워 본 뒤에는 옮긴다.
    ///
    /// 쓴 방향이 그대로 넘어가는 방향이 된다. 오른쪽으로 쓸면 오른쪽 자락이 뒤로 넘어가고,
    /// 위로 쓸면 윗자락이 뒤로 넘어간다 — 책상에 놓인 카드를 손끝으로 튕겼을 때와 같다.
    ///
    /// 손을 떼면 튕긴 세기만큼 더 넘어가고 천천히 선다. 그 자리에 딱 멈추면 카드를 튕긴
    /// 것이 아니라 손잡이를 돌린 것처럼 뻣뻣하다.
    ///
    /// 멎는 자리는 늘 한 바퀴의 배수다. 반 바퀴에서 멎으면 심볼의 뒷면 — 좌우가 뒤집힌
    /// 간판이 남는데, 그것은 찍은 적 없는 그림이다. 힘이 모자라 반 바퀴를 못 넘기면
    /// 넘어가던 카드가 도로 제자리로 눕는다. 이것도 손끝에 익은 셈이다.
    private func swipe() -> some Gesture {
        DragGesture()
            .onChanged { value in
                played = true
                guard zoom <= minZoom else {
                    pan = CGSize(width: settledPan.width + value.translation.width,
                                 height: settledPan.height + value.translation.height)
                    return
                }
                guard let heading = heading(for: value.translation) else { return }
                flip = settledFlip + along(value.translation, heading) * degreesPerPoint
            }
            .onEnded { value in
                // 이번 손짓에 정해 둔 쪽을 먼저 집어 두고 비운다. 여기서 다시 재면
                // 손짓이 끝난 뒤에도 쪽이 남아, 다음 손짓이 지난번 쪽으로 넘어간다.
                let heading = swipeDirection
                swipeDirection = nil
                guard zoom <= minZoom else {
                    settledPan = pan
                    return
                }
                guard let heading else { return }

                // 튕긴 몫은 '손을 뗀 뒤에도 갈 거리'다. 여태 온 거리를 빼야
                // 이미 넘어간 만큼을 두 번 세지 않는다.
                let flung = CGSize(
                    width: value.predictedEndTranslation.width - value.translation.width,
                    height: value.predictedEndTranslation.height - value.translation.height
                )
                let target = landing(flip + fling(along(flung, heading)))

                // 빨리 넘어가기 시작해 천천히 서는 것이 넘어가는 것으로 보인다.
                // 많이 넘어갈수록 오래 돌되, 두 숨을 넘기지는 않는다.
                let turns = abs(target - flip) / 360
                withAnimation(.easeOut(duration: min(0.45 + turns * 0.5, 1.8))) {
                    flip = target
                }
                settledFlip = target
            }
    }

    /// 이번 손짓이 향한 쪽. 처음 한 번 정해 두고 손을 뗄 때까지 그대로 쓴다.
    /// 아직 방향이라 할 만큼 움직이지 않았으면 nil.
    private func heading(for translation: CGSize) -> CGVector? {
        if let swipeDirection { return swipeDirection }
        let length = (translation.width * translation.width
                      + translation.height * translation.height).squareRoot()
        guard length > 1 else { return nil }

        let heading = CGVector(dx: translation.width / length, dy: translation.height / length)
        swipeDirection = heading
        // 넘어가는 축은 쓴 쪽과 직각이다. 오른쪽으로 쓸면 세로축 둘레로 돌아
        // 오른쪽 자락이 뒤로 넘어가고, 위로 쓸면 가로축 둘레로 돌아 윗자락이 넘어간다.
        axis = CGVector(dx: -heading.dy, dy: heading.dx)
        return heading
    }

    /// 쓴 거리 가운데 넘어가는 데 쓰이는 몫 (손짓이 향한 쪽으로 잰 길이).
    /// 도중에 손이 옆으로 새도 카드는 처음 걸린 쪽으로만 넘어간다.
    private func along(_ translation: CGSize, _ heading: CGVector) -> Double {
        Double(translation.width * heading.dx + translation.height * heading.dy)
    }

    /// 튕긴 거리를 더 넘어갈 도로 셈한다 (한 번에 넘길 수 있는 끝까지).
    private func fling(_ distance: Double) -> Double {
        let degrees = distance * degreesPerPoint * flingBoost
        return min(max(degrees, -maxFling), maxFling)
    }

    /// 앞면이 보이는 가장 가까운 자리 (한 바퀴의 배수).
    private func landing(_ degrees: Double) -> Double {
        (degrees / 360).rounded() * 360
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                played = true
                zoom = clampedZoom(settledZoom * value.magnification)
            }
            .onEnded { _ in
                settledZoom = zoom
                // 본디 크기로 돌아오면 자리도 가운데로 돌린다. 그러지 않으면
                // 작아진 심볼이 화면 구석에 치우친 채로 남는다.
                if zoom <= minZoom { resetPan() }
            }
    }

    /// 두 번 두드리면 커졌다 작아졌다 한다.
    private func toggleZoom() {
        played = true
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
                // 쓸고 오므리는 손짓은 눈에 보이지 않는다. 아직 만져 보지 않은 동안에만
                // 한 줄 일러 두고, 한 번 만진 뒤에는 지운다.
                if !played {
                    Text("쓸면 카드처럼 넘어가고, 두 번 두드리면 크게 볼 수 있어요")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .transition(.opacity)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .animation(.easeInOut(duration: 0.25), value: played)
        }
    }
}
