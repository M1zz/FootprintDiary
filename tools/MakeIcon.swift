//
//  앱 아이콘을 그린다 — 종이 위에 걸음이 쌓이는 그림.
//
//  만드는 법:
//    swiftc -O tools/MakeIcon.swift -o /tmp/makeicon
//    /tmp/makeicon FootprintDiary/Assets.xcassets/AppIcon.appiconset
//    (icon-light/dark/tinted.png이 나오면 AppIcon/AppIcon-Dark/AppIcon-Tinted.png로 옮긴다)
//
//  손으로 다시 그리지 않으려고 코드로 남겨 둔다. 빛깔이나 굽이를 고칠 일이 생기면
//  여기 숫자만 바꾸고 다시 돌리면 된다.
//
//  앱이 하는 일이 그대로 아이콘이 되어야 한다. 이 앱은 걸은 자리를 점으로 찍고,
//  오래된 자리는 빛이 빠져 잿빛이 되고 요즘 걸은 자리는 원색으로 남는다.
//  그래서 아이콘도 잿빛에서 시작해 원색으로 끝나는 점선 한 줄이다.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024

// MARK: - 빛깔 (InkStyle·DotPalette와 같은 값)

let paper = CGColor(red: 0.96, green: 0.95, blue: 0.91, alpha: 1)
let ink = CGColor(red: 0.11, green: 0.12, blue: 0.16, alpha: 1)
let sealRed = CGColor(red: 0.72, green: 0.16, blue: 0.13, alpha: 1)

/// HSB를 RGB로 (CoreGraphics에는 HSB 생성자가 없다)
func color(hue h: CGFloat, saturation s: CGFloat, brightness v: CGFloat, alpha: CGFloat = 1) -> CGColor {
    let i = floor(h * 6)
    let f = h * 6 - i
    let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
    let (r, g, b): (CGFloat, CGFloat, CGFloat)
    switch Int(i) % 6 {
    case 0: (r, g, b) = (v, t, p)
    case 1: (r, g, b) = (q, v, p)
    case 2: (r, g, b) = (p, v, t)
    case 3: (r, g, b) = (p, q, v)
    case 4: (r, g, b) = (t, p, v)
    default: (r, g, b) = (v, p, q)
    }
    return CGColor(red: r, green: g, blue: b, alpha: alpha)
}

// MARK: - 길

/// 걸어간 길의 뼈대. 모서리에서 모서리로 가로지르되 한 번 굽어야 '걸은 길'로 보인다.
let spine: [CGPoint] = [
    CGPoint(x: 0.12, y: 0.80),
    CGPoint(x: 0.26, y: 0.88),
    CGPoint(x: 0.40, y: 0.76),
    CGPoint(x: 0.36, y: 0.56),
    CGPoint(x: 0.48, y: 0.42),
    CGPoint(x: 0.66, y: 0.44),
    CGPoint(x: 0.74, y: 0.26),
    CGPoint(x: 0.88, y: 0.14),
].map { CGPoint(x: CGFloat($0.x) * size, y: (CGFloat(1) - CGFloat($0.y)) * size) }

/// 캣멀롬으로 매끈하게 이은 뒤 촘촘히 잘라 둔다
func smoothed(_ points: [CGPoint], per segment: Int = 60) -> [CGPoint] {
    guard points.count > 2 else { return points }
    var out: [CGPoint] = []
    let padded = [points[0]] + points + [points[points.count - 1]]
    for i in 1..<(padded.count - 2) {
        let p0 = padded[i - 1], p1 = padded[i], p2 = padded[i + 1], p3 = padded[i + 2]
        for step in 0..<segment {
            let t = CGFloat(step) / CGFloat(segment)
            let t2 = t * t, t3 = t2 * t
            let x = 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t
                + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2
                + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
            let y = 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t
                + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2
                + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
            out.append(CGPoint(x: x, y: y))
        }
    }
    return out
}

/// 길이를 따라 고르게 끊는다. 굽은 자리에서만 촘촘해지면 점이 뭉쳐 보인다.
func evenlySpaced(_ path: [CGPoint], count: Int) -> [CGPoint] {
    var lengths: [CGFloat] = [0]
    for i in 1..<path.count {
        let d = hypot(path[i].x - path[i - 1].x, path[i].y - path[i - 1].y)
        lengths.append(lengths[i - 1] + d)
    }
    let total = lengths[lengths.count - 1]
    var out: [CGPoint] = []
    var cursor = 1
    for k in 0..<count {
        let target = total * CGFloat(k) / CGFloat(count - 1)
        while cursor < lengths.count - 1 && lengths[cursor] < target { cursor += 1 }
        let t = (target - lengths[cursor - 1]) / max(lengths[cursor] - lengths[cursor - 1], CGFloat(0.0001))
        let a = path[cursor - 1], b = path[cursor]
        out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
    }
    return out
}

// MARK: - 그리기

func drawPaper(_ ctx: CGContext, skin: Skin) {
    ctx.setFillColor(skin.background)
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    guard skin.grain > 0 else { return }

    // 닥종이의 결. 씨앗을 고정해 두어 다시 그려도 같은 그림이 나온다.
    var seed: UInt64 = 20260824
    func random() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((seed >> 33) % 100_000) / 100_000
    }
    for _ in 0..<2600 {
        let x = random() * size, y = random() * size
        let r = 1.5 + random() * 3.5
        ctx.setFillColor(CGColor(red: 0.55, green: 0.50, blue: 0.40,
                                 alpha: (0.05 + random() * 0.05) * skin.grain))
        ctx.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
    }
}

/// 한 벌의 빛깔 규칙. 종이가 밝든 어둡든 같은 길에 같은 뜻을 입힌다.
struct Skin {
    let background: CGColor
    /// 갓 밟은 쪽의 밝기와 바랜 쪽의 밝기
    let freshBrightness: CGFloat
    let fadedBrightness: CGFloat
    /// 원색을 얼마나 올릴지 (틴티드는 0 — 시스템이 제 빛으로 물들인다)
    let saturationScale: CGFloat
    let grain: CGFloat
}

/// 걸음 점을 찍는다. 잿빛에서 원색으로 — 옛 걸음과 오늘 걸음이 한 줄에 담긴다.
func drawTrail(_ ctx: CGContext, skin: Skin, dots: Int = 15) {
    let points = evenlySpaced(smoothed(spine), count: dots)
    for (index, point) in points.enumerated() {
        let t = CGFloat(index) / CGFloat(dots - 1)
        // 빛깔은 색상환에서 파랑 언저리부터 붉은 쪽으로 천천히 걸어간다.
        // 무지개처럼 다 쓰면 어지럽고, 한 빛깔만 쓰면 '날마다 다른 빛'이라는 뜻이 사라진다.
        let hue = (0.55 + t * 0.47).truncatingRemainder(dividingBy: 1)
        let saturation = (0.05 + pow(t, 1.35) * 0.83) * skin.saturationScale
        let brightness = skin.fadedBrightness + pow(t, 1.15) * (skin.freshBrightness - skin.fadedBrightness)
        let radius: CGFloat = 33.0 + t * 23.0

        // 종이에 스민 자국 — 점 아래 옅게 한 겹 깔면 인쇄된 점이 아니라 배어든 먹이 된다.
        // 너무 진하면 점마다 테두리가 생겨 구슬을 꿴 것처럼 보인다.
        ctx.setFillColor(color(hue: hue, saturation: saturation * 0.7, brightness: brightness, alpha: 0.10))
        ctx.fillEllipse(in: CGRect(x: point.x - radius * 1.34, y: point.y - radius * 1.34,
                                   width: radius * 2.68, height: radius * 2.68))

        ctx.setFillColor(color(hue: hue, saturation: saturation, brightness: brightness,
                               alpha: 0.66 + t * 0.34))
        ctx.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius,
                                   width: radius * 2, height: radius * 2))
    }
}

// MARK: - 내보내기

func render(_ name: String, _ body: (CGContext) -> Void) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    body(ctx)
    guard let image = ctx.makeImage() else { return }
    let url = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(name)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("그림: \(url.lastPathComponent)")
}

// 밝은 종이
render("icon-light.png") { ctx in
    let skin = Skin(background: paper, freshBrightness: 0.76, fadedBrightness: 0.46,
                    saturationScale: 1, grain: 1)
    drawPaper(ctx, skin: skin)
    drawTrail(ctx, skin: skin)
}

// 어두운 종이 — 밤에 홈 화면이 어두워지면 이쪽이 걸린다
render("icon-dark.png") { ctx in
    let skin = Skin(background: CGColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1),
                    freshBrightness: 0.95, fadedBrightness: 0.62,
                    saturationScale: 0.96, grain: 0.5)
    drawPaper(ctx, skin: skin)
    drawTrail(ctx, skin: skin)
}

// 틴티드 — 시스템이 제 빛으로 물들이므로 밝기만 남긴다
render("icon-tinted.png") { ctx in
    let skin = Skin(background: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
                    freshBrightness: 1.0, fadedBrightness: 0.34,
                    saturationScale: 0, grain: 0)
    drawPaper(ctx, skin: skin)
    drawTrail(ctx, skin: skin)
}
