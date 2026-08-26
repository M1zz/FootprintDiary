//
//  StickerMaker.swift
//  FootprintDiary
//
//  찍은 사진을 창 그대로 오려 내고, 그 안의 것만 남기고 배경을 지운다.
//
//  오려 내는 셈은 StampCamera(펀칭)의 StampCompositor에서 가져왔다. 어려운 곳은 딱
//  한 군데다 — 화면에 보인 자리를 사진의 픽셀 자리로 되짚는 셈.
//
//  미리보기는 aspect-fill이라 사진의 위아래(또는 좌우)가 화면 밖으로 잘려 나가 있다.
//  그런데 사진은 제 해상도와 제 비율로 따로 들어온다. 그래서 화면 좌표를 그대로 쓰면
//  겨눈 것과 다른 자리가 잘린다 — 대개 조금씩 위로 밀린다. 채우느라 넘친 만큼을
//  되돌려 빼야(coverScale 역산) 겨눈 자리가 나온다.
//
//  배경을 지우는 것은 여기서 한 걸음 더 나간 것이다. 네모로 오려 놓으면 지도 위에
//  창문이 뚫린 것처럼 보여 배경 지도와 구별되지 않는다. 안에 든 것만 떼어 내면 그때부터
//  '그 자리에 붙여 놓은 것'이 되고, 종이도 테두리도 없이 지도에 바로 설 수 있다.
//  떼어 낸 뒤에는 흰 테두리를 두른다 — 아이오에스 스티커가 하는 것과 같은 까닭이다.
//  어두운 지도에서든 밝은 종이에서든 실루엣이 배경에 먹히지 않게 잡아 준다.
//

import UIKit
import Vision

enum StickerMaker {

    /// 지도에 얹을 심볼의 한 변 (픽셀).
    ///
    /// 지도의 도장은 30pt 남짓이고 3배 화면에서 90px이다. 360px이면 네 배 여유가 있어
    /// 나중에 크게 보여 줄 일이 생겨도 버티고, 아이클라우드에 실어 나르기에도 가볍다.
    /// 원본을 그대로 담으면 한 장에 수 MB가 되어 스탬프 몇 십 개만으로 동기화가 무거워진다.
    static let outputSide: CGFloat = 360

    /// 떼어 낸 것 둘레에 두르는 흰 테두리의 두께 (출력 픽셀 기준).
    /// 얇으면 어두운 지도에서 실루엣이 먹히고, 두꺼우면 무엇을 찍었는지보다
    /// 흰 덩어리가 먼저 보인다.
    static let outlineWidth: CGFloat = 9

    /// 화면에서 겨눈 창을 사진에서 오려 내고, 그 안의 것만 남긴다.
    ///
    /// - Parameters:
    ///   - image: 카메라가 건네준 온전한 사진
    ///   - previewSize: 화면에 보이던 미리보기 크기 (pt)
    ///   - windowRect: 그 안에서 창이 놓였던 자리 (pt)
    ///   - mirrored: 앞면 카메라인지
    /// - Returns: 배경이 지워진 심볼과, 배경을 실제로 지웠는지 여부.
    ///   못 지웠으면 네모 그대로 돌려준다 — 아무것도 못 내놓는 것보다 낫다.
    static func makeSticker(from image: UIImage,
                            previewSize: CGSize,
                            windowRect: CGRect,
                            mirrored: Bool) -> (image: UIImage, liftedSubject: Bool)? {

        guard let square = crop(image, previewSize: previewSize,
                                windowRect: windowRect, mirrored: mirrored) else { return nil }

        // 안에 든 것만 떼어 낸다. 사람·물건·간판처럼 또렷한 것이 있으면 잡히고,
        // 하늘이나 벽처럼 배경뿐인 사진에서는 잡히지 않는다.
        guard let lifted = liftSubject(from: square) else {
            return (square, false)
        }
        return (outlined(lifted), true)
    }

    // MARK: - 오려 내기

    private static func crop(_ image: UIImage,
                             previewSize: CGSize,
                             windowRect: CGRect,
                             mirrored: Bool) -> UIImage? {
        // 방향을 .up으로 구워 둔다. 그러지 않으면 픽셀 좌표가 사진마다 다른 뜻이 된다.
        let normalized = image.stickerNormalizedUp()
        guard let source = normalized.cgImage else { return nil }

        let imgW = CGFloat(source.width)
        let imgH = CGFloat(source.height)
        guard imgW > 0, imgH > 0, previewSize.width > 0, previewSize.height > 0 else { return nil }

        // aspect-fill 되짚기 — 미리보기를 채우려고 얼마나 키웠는지
        let coverScale = max(previewSize.width / imgW, previewSize.height / imgH)
        let dispW = imgW * coverScale
        let dispH = imgH * coverScale
        let dispX = (previewSize.width - dispW) / 2
        let dispY = (previewSize.height - dispH) / 2

        var sx = (windowRect.minX - dispX) / coverScale
        let sy = (windowRect.minY - dispY) / coverScale
        let sw = windowRect.width / coverScale
        let sh = windowRect.height / coverScale
        if mirrored { sx = imgW - sx - sw }

        // 사진 밖으로 나가는 일은 없어야 한다. 창이 미리보기 안에 있으면 셈만으로도
        // 안에 들어오지만, 소수점이 몇 픽셀 넘칠 수 있어 잘라 둔다.
        let srcRect = CGRect(x: sx, y: sy, width: sw, height: sh)
            .intersection(CGRect(x: 0, y: 0, width: imgW, height: imgH))
        guard !srcRect.isNull, srcRect.width >= 1, srcRect.height >= 1,
              let cropped = source.cropping(to: srcRect) else { return nil }

        let outSize = CGSize(width: outputSide, height: outputSide)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        return UIGraphicsImageRenderer(size: outSize, format: format).image { ctx in
            if mirrored {
                ctx.cgContext.translateBy(x: outSize.width, y: 0)
                ctx.cgContext.scaleBy(x: -1, y: 1)
            }
            UIImage(cgImage: cropped).draw(in: CGRect(origin: .zero, size: outSize))
        }
    }

    // MARK: - 배경 지우기

    /// 사진 안의 '주인공'만 남기고 나머지를 지운다 (iOS 17의 피사체 떼어 내기).
    ///
    /// 여러 개가 잡히면 전부 남긴다. 하나만 고르면 나란히 선 두 사람 중 하나가 잘리는데,
    /// 찍은 사람은 둘을 다 담을 셈이었을 것이다. 아무것도 못 잡으면 nil을 준다 —
    /// 그때는 부르는 쪽이 네모 그대로 쓴다.
    private static func liftSubject(from image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }
            let masked = try result.generateMaskedImage(
                ofInstances: result.allInstances,
                from: handler,
                croppedToInstancesExtent: false
            )
            return UIImage(cgImage: CGImage.fromPixelBuffer(masked) ?? cgImage)
        } catch {
            return nil
        }
    }

    /// 떼어 낸 것 둘레에 흰 테두리를 두른다.
    ///
    /// 실루엣을 흰색으로 한 장 구워 두고, 그것을 여러 방향으로 조금씩 옮겨 찍은 뒤
    /// 원본을 위에 얹는다. 제대로 하려면 알파 채널을 부풀려야 하지만(모폴로지 팽창),
    /// 그것 하나로 CoreImage 파이프라인을 들이는 것보다 이 방식이 읽기도 고치기도 쉽고
    /// 360px에서는 눈으로 구별되지 않는다.
    ///
    /// 실루엣은 .sourceAtop으로 만든다 — 이미 그려진 자리(알파가 있는 곳)에만 흰색을
    /// 덮으므로 모양은 그대로고 색만 희어진다. CGContext.clip(to:mask:)로 하려다
    /// 접었다: 그쪽은 마스크가 회색조여야 한다고 못 박혀 있어, 색이 든 그림을 넘기면
    /// 아무 말 없이 엉뚱하게 잘린다.
    private static func outlined(_ image: UIImage) -> UIImage {
        let size = image.size
        let rect = CGRect(origin: .zero, size: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let silhouette = renderer.image { ctx in
            image.draw(in: rect)
            ctx.cgContext.setBlendMode(.sourceAtop)
            UIColor.white.setFill()
            ctx.cgContext.fill(rect)
        }

        return renderer.image { _ in
            // 방향을 촘촘히 돌수록 테두리가 매끈해진다. 16이면 9px 두께에서
            // 이가 빠진 자리가 보이지 않는다.
            let steps = 16
            for step in 0..<steps {
                let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
                silhouette.draw(in: rect.offsetBy(dx: cos(angle) * outlineWidth,
                                                  dy: sin(angle) * outlineWidth))
            }
            image.draw(in: rect)
        }
    }

    /// 심볼로 담을 PNG. 배경이 지워진 자리를 살려야 하므로 JPEG는 쓸 수 없다.
    static func pngData(for sticker: UIImage) -> Data? {
        sticker.pngData()
    }
}

// MARK: - 거들

extension CGImage {
    /// Vision이 돌려주는 픽셀 버퍼를 CGImage로 옮긴다.
    static func fromPixelBuffer(_ buffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        return CIContext().createCGImage(ciImage, from: ciImage.extent)
    }
}

extension UIImage {
    /// 방향을 .up으로 구운 사본.
    ///
    /// 이름을 길게 둔 것은 다른 곳(PhotoStore)에도 비슷한 것이 있을 수 있어서다.
    /// 같은 이름의 확장이 두 벌 있으면 어느 쪽이 불리는지 읽는 사람이 알 수 없다.
    func stickerNormalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
