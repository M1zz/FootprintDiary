//
//  TerrainSkin.swift
//  FootprintDiary
//
//  같은 본(TerrainMap.swift)을 어떻게 칠할지.
//
//  먹은 본 안을 옅은 빛 한 가지로 덮는다. 종이에 인쇄된 무늬처럼 겨우 알아볼 만큼만.
//  그림지도는 관광 안내도처럼 산에는 동글동글한 봉우리를, 숲에는 나무를, 물에는 물결과
//  돛단배를 그려 넣고, 물가에는 진한 테두리와 흰 거품 띠를 두른다.
//  모양은 둘이 같다 — 어디가 물이고 어디가 산인지는 이미 떠 둔 본이 알려 준다.
//  달라지는 것은 그 안을 무엇으로 채우느냐뿐이다.
//
//  봉우리와 나무는 타일마다 따로 그려진다. 그래서 자리를 '지도 좌표의 격자 + 고정된 흔들림'으로
//  정한다. 아무렇게나 뿌리면 화면을 조금만 옮겨도 타일이 다시 그려지면서 산이 제자리에서
//  떨리고, 타일 경계에서 반쪽짜리 나무가 생긴다. 격자 간격은 화면 기준(pt)으로 잡으므로
//  어느 배율에서나 그림의 크기와 촘촘함이 같다.
//
//  그림은 에셋 카탈로그에 같은 이름이 있으면 그것을 쓰고, 없으면 여기서 그린 것을 쓴다.
//  이름: TerrainMountain1~5, TerrainTree1~5, TerrainWave, TerrainBoat, TerrainDuck
//  (투명 배경, 아래 가운데가 발 딛는 자리)
//

import MapKit
import UIKit

/// 지도의 물과 산을 무엇으로 칠할지
enum TerrainSkin: String, CaseIterable {
    /// 옅은 먹빛 한 가지
    case ink
    /// 봉우리·나무·물결을 그려 넣은 그림지도
    case picture

    /// 물가 테두리의 두께(1배 본의 픽셀). 1배 본의 한 픽셀이 화면 1pt 남짓이다.
    static let shoreWidth = 2
    /// 물가 거품 띠의 두께(1배 본의 픽셀)
    static let foamWidth = 3
}

// MARK: - 본 다듬기

/// 본을 조금 부풀리거나 깎는다. 물가 테두리와 거품 띠가 여기서 나온다.
enum StencilShape {
    /// 바깥으로 radius만큼 부풀린 본
    static func grown(_ stencil: CGImage, by radius: Int) -> CGImage? {
        reshaped(stencil, radius: radius) { count, _ in count > 0 }
    }

    /// 안으로 radius만큼 깎은 본
    static func shrunk(_ stencil: CGImage, by radius: Int) -> CGImage? {
        reshaped(stencil, radius: radius) { count, full in count == full }
    }

    private static func reshaped(_ stencil: CGImage, radius: Int, keep: (Int, Int) -> Bool) -> CGImage? {
        guard stencil.bitsPerPixel == 8, let data = stencil.dataProvider?.data as Data? else { return nil }
        let width = stencil.width, height = stencil.height, stride = stencil.bytesPerRow
        let bytes = [UInt8](data)
        guard bytes.count >= stride * height, width > 0, height > 0 else { return nil }

        // 스텐실은 무늬가 0이다
        var inside = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            for x in 0..<width { inside[y * width + x] = bytes[y * stride + x] < 128 }
        }
        let counts = boxCounts(inside, width: width, height: height, radius: radius)
        var output = [UInt8](repeating: 255, count: width * height)
        for y in 0..<height {
            let spanY = min(y + radius, height - 1) - max(y - radius, 0) + 1
            for x in 0..<width {
                let spanX = min(x + radius, width - 1) - max(x - radius, 0) + 1
                if keep(counts[y * width + x], spanX * spanY) { output[y * width + x] = 0 }
            }
        }

        guard let provider = CGDataProvider(data: Data(output) as CFData) else { return nil }
        return CGImage(
            maskWidth: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            provider: provider,
            decode: nil,
            shouldInterpolate: true
        )
    }

    /// 둘레 안에 든 참의 개수. 가로로 한 번, 세로로 한 번 창을 밀며 센다.
    private static func boxCounts(_ source: [Bool], width: Int, height: Int, radius: Int) -> [Int] {
        var rows = [Int](repeating: 0, count: width * height)
        for y in 0..<height {
            let base = y * width
            var running = 0
            for x in 0...min(radius, width - 1) where source[base + x] { running += 1 }
            for x in 0..<width {
                rows[base + x] = running
                let leaving = x - radius, entering = x + radius + 1
                if leaving >= 0, source[base + leaving] { running -= 1 }
                if entering < width, source[base + entering] { running += 1 }
            }
        }
        var counts = [Int](repeating: 0, count: width * height)
        for x in 0..<width {
            var running = 0
            for y in 0...min(radius, height - 1) { running += rows[y * width + x] }
            for y in 0..<height {
                counts[y * width + x] = running
                let leaving = y - radius, entering = y + radius + 1
                if leaving >= 0 { running -= rows[leaving * width + x] }
                if entering < height { running += rows[entering * width + x] }
            }
        }
        return counts
    }
}

// MARK: - 본 읽기

/// 본의 한 자리가 얼마나 무늬 안쪽인지 읽는다.
///
/// 렌더러는 여러 스레드에서 동시에 그리므로 만들 때 바이트를 한 번 꺼내 두고 읽기만 한다.
struct StencilSampler {
    private let rect: MKMapRect
    private let width: Int
    private let height: Int
    private let bytesPerRow: Int
    private let bytes: [UInt8]

    init?(stencil: CGImage?, rect: MKMapRect) {
        guard let stencil, stencil.bitsPerPixel == 8,
              let data = stencil.dataProvider?.data as Data?,
              rect.size.width > 0, rect.size.height > 0 else { return nil }
        self.rect = rect
        width = stencil.width
        height = stencil.height
        bytesPerRow = stencil.bytesPerRow
        bytes = [UInt8](data)
        guard bytes.count >= bytesPerRow * height else { return nil }
    }

    /// 0이면 바깥, 1이면 무늬 한가운데. (스텐실은 무늬가 0, 바깥이 255다)
    func coverage(at point: MKMapPoint) -> Double {
        guard rect.contains(point) else { return 0 }
        let x = min(width - 1, max(0, Int((point.x - rect.minX) / rect.size.width * Double(width))))
        let y = min(height - 1, max(0, Int((point.y - rect.minY) / rect.size.height * Double(height))))
        return 1 - Double(bytes[y * bytesPerRow + x]) / 255
    }

    /// 이 자리와 둘레 여덟 곳이 모두 무늬 안인지 — 가장자리가 아니라 한복판인지
    func isDeep(at point: MKMapPoint, reach: Double, threshold: Double = 0.6) -> Bool {
        let diagonal = reach * 0.7
        let offsets: [(Double, Double)] = [
            (0, 0), (-reach, 0), (reach, 0), (0, -reach), (0, reach),
            (-diagonal, -diagonal), (diagonal, -diagonal), (-diagonal, diagonal), (diagonal, diagonal),
        ]
        return offsets.allSatisfy { dx, dy in
            coverage(at: MKMapPoint(x: point.x + dx, y: point.y + dy)) > threshold
        }
    }
}

// MARK: - 그림

/// 그림지도에 뿌리는 그림 한 벌. 밝은 화면과 어두운 화면이 저마다 한 벌씩 갖는다.
struct TerrainSprites {
    /// 0 홑봉우리, 1 쌍봉우리, 2 세 봉우리, 3 눈 덮인 큰 산, 4 웃는 산
    let mountains: [UIImage]
    /// 0 둥근 나무, 1 침엽수, 2 꽃나무, 3 단풍나무, 4 덤불
    let trees: [UIImage]
    let wave: UIImage
    let boat: UIImage
    let duck: UIImage
    /// 빈 뭍에 흩뿌리는 풀포기와 들꽃
    let tuft: UIImage
    let flower: UIImage

    enum Mountain: Int { case single, double, triple, snowy, smiling }
    enum Tree: Int { case round, pine, blossom, autumn, bush }

    /// 빛깔은 그리는 중에 물어볼 수 없으므로 여기서 미리 정해 둔다 (메인에서 부른다)
    init(traits: UITraitCollection) {
        let palette = Palette(dark: traits.userInterfaceStyle == .dark)
        func asset(_ name: String) -> UIImage? {
            UIImage(named: name, in: nil, compatibleWith: traits)
        }
        mountains = (0..<5).map { index in
            asset("TerrainMountain\(index + 1)") ?? Self.drawMountain(Mountain(rawValue: index)!, palette: palette)
        }
        trees = (0..<5).map { index in
            asset("TerrainTree\(index + 1)") ?? Self.drawTree(Tree(rawValue: index)!, palette: palette)
        }
        wave = asset("TerrainWave") ?? Self.drawWave(palette: palette)
        boat = asset("TerrainBoat") ?? Self.drawBoat(palette: palette)
        duck = asset("TerrainDuck") ?? Self.drawDuck(palette: palette)
        tuft = asset("TerrainTuft") ?? Self.drawTuft(palette: palette)
        flower = asset("TerrainFlower") ?? Self.drawFlower(palette: palette)
    }

    func mountain(_ kind: Mountain) -> UIImage { mountains[kind.rawValue] }
    func tree(_ kind: Tree) -> UIImage { trees[kind.rawValue] }

    private struct Palette {
        let outline: UIColor
        let shadow: UIColor
        let highlight: UIColor
        let peak: UIColor
        let peakShade: UIColor
        let peakBack: UIColor
        let snow: UIColor
        let blush: UIColor
        let leaf: UIColor
        let leafLight: UIColor
        let pine: UIColor
        let blossom: UIColor
        let autumn: UIColor
        let trunk: UIColor
        let wave: UIColor
        let hull: UIColor
        let sail: UIColor
        let duck: UIColor
        let beak: UIColor
        let grass: UIColor
        let petal: UIColor

        init(dark: Bool) {
            if dark {
                outline = UIColor(red: 0.62, green: 0.74, blue: 0.58, alpha: 1)
                shadow = UIColor(white: 0, alpha: 0.35)
                highlight = UIColor(white: 1, alpha: 0.25)
                peak = UIColor(red: 0.30, green: 0.44, blue: 0.30, alpha: 1)
                peakShade = UIColor(red: 0.23, green: 0.35, blue: 0.24, alpha: 1)
                peakBack = UIColor(red: 0.24, green: 0.34, blue: 0.27, alpha: 1)
                snow = UIColor(red: 0.80, green: 0.84, blue: 0.86, alpha: 1)
                blush = UIColor(red: 0.80, green: 0.45, blue: 0.50, alpha: 0.7)
                leaf = UIColor(red: 0.32, green: 0.48, blue: 0.29, alpha: 1)
                leafLight = UIColor(red: 0.42, green: 0.58, blue: 0.36, alpha: 1)
                pine = UIColor(red: 0.22, green: 0.40, blue: 0.31, alpha: 1)
                blossom = UIColor(red: 0.70, green: 0.46, blue: 0.54, alpha: 1)
                autumn = UIColor(red: 0.72, green: 0.48, blue: 0.24, alpha: 1)
                trunk = UIColor(red: 0.42, green: 0.32, blue: 0.24, alpha: 1)
                wave = UIColor(red: 0.50, green: 0.68, blue: 0.80, alpha: 1)
                hull = UIColor(red: 0.62, green: 0.32, blue: 0.26, alpha: 1)
                sail = UIColor(red: 0.85, green: 0.86, blue: 0.84, alpha: 1)
                duck = UIColor(red: 0.85, green: 0.74, blue: 0.36, alpha: 1)
                beak = UIColor(red: 0.86, green: 0.52, blue: 0.26, alpha: 1)
                grass = UIColor(red: 0.36, green: 0.48, blue: 0.32, alpha: 1)
                petal = UIColor(red: 0.78, green: 0.62, blue: 0.68, alpha: 1)
            } else {
                outline = UIColor(red: 0.25, green: 0.40, blue: 0.24, alpha: 1)
                shadow = UIColor(red: 0.25, green: 0.35, blue: 0.15, alpha: 0.18)
                highlight = UIColor(white: 1, alpha: 0.65)
                peak = UIColor(red: 0.53, green: 0.78, blue: 0.45, alpha: 1)
                peakShade = UIColor(red: 0.41, green: 0.66, blue: 0.38, alpha: 1)
                peakBack = UIColor(red: 0.71, green: 0.87, blue: 0.58, alpha: 1)
                snow = UIColor(white: 1, alpha: 1)
                blush = UIColor(red: 1.00, green: 0.55, blue: 0.60, alpha: 0.75)
                leaf = UIColor(red: 0.45, green: 0.74, blue: 0.38, alpha: 1)
                leafLight = UIColor(red: 0.66, green: 0.87, blue: 0.50, alpha: 1)
                pine = UIColor(red: 0.27, green: 0.58, blue: 0.42, alpha: 1)
                blossom = UIColor(red: 0.99, green: 0.72, blue: 0.80, alpha: 1)
                autumn = UIColor(red: 0.99, green: 0.69, blue: 0.33, alpha: 1)
                trunk = UIColor(red: 0.60, green: 0.43, blue: 0.30, alpha: 1)
                wave = UIColor(white: 1, alpha: 1)
                hull = UIColor(red: 0.86, green: 0.38, blue: 0.30, alpha: 1)
                sail = UIColor(white: 1, alpha: 1)
                duck = UIColor(red: 1.00, green: 0.86, blue: 0.35, alpha: 1)
                beak = UIColor(red: 1.00, green: 0.55, blue: 0.25, alpha: 1)
                grass = UIColor(red: 0.55, green: 0.72, blue: 0.42, alpha: 1)
                petal = UIColor(red: 1.00, green: 0.80, blue: 0.84, alpha: 1)
            }
        }
    }

    // MARK: 봉우리

    /// 동글동글한 봉우리. 꼭대기가 뾰족하지 않고 종처럼 둥글다.
    private static func drawMountain(_ kind: Mountain, palette: Palette) -> UIImage {
        let size = CGSize(width: 64, height: 50)
        let base = size.height - 4
        return UIGraphicsImageRenderer(size: size).image { renderer in
            let context = renderer.cgContext

            // 발밑 그림자
            palette.shadow.setFill()
            UIBezierPath(ovalIn: CGRect(x: 6, y: base - 3, width: 52, height: 7)).fill()

            @discardableResult
            func mound(centerX: CGFloat, top: CGFloat, halfWidth: CGFloat, fill: UIColor, shaded: Bool) -> UIBezierPath {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: centerX - halfWidth, y: base))
                path.addCurve(
                    to: CGPoint(x: centerX, y: top),
                    controlPoint1: CGPoint(x: centerX - halfWidth * 0.62, y: base - 2),
                    controlPoint2: CGPoint(x: centerX - halfWidth * 0.55, y: top)
                )
                path.addCurve(
                    to: CGPoint(x: centerX + halfWidth, y: base),
                    controlPoint1: CGPoint(x: centerX + halfWidth * 0.55, y: top),
                    controlPoint2: CGPoint(x: centerX + halfWidth * 0.62, y: base - 2)
                )
                path.close()
                fill.setFill()
                path.fill()

                if shaded {
                    // 해를 등진 오른쪽 비탈에 그늘
                    context.saveGState()
                    path.addClip()
                    palette.peakShade.setFill()
                    let shade = UIBezierPath()
                    shade.move(to: CGPoint(x: centerX + halfWidth * 0.08, y: top))
                    shade.addQuadCurve(
                        to: CGPoint(x: centerX + halfWidth * 0.25, y: base),
                        controlPoint: CGPoint(x: centerX - halfWidth * 0.2, y: (top + base) / 2)
                    )
                    shade.addLine(to: CGPoint(x: centerX + halfWidth, y: base))
                    shade.addLine(to: CGPoint(x: centerX + halfWidth, y: top))
                    shade.close()
                    shade.fill()
                    context.restoreGState()

                    // 왼쪽 비탈의 반짝이는 빛
                    let shine = UIBezierPath()
                    shine.move(to: CGPoint(x: centerX - halfWidth * 0.42, y: top + (base - top) * 0.42))
                    shine.addQuadCurve(
                        to: CGPoint(x: centerX - halfWidth * 0.12, y: top + 4),
                        controlPoint: CGPoint(x: centerX - halfWidth * 0.38, y: top + 6)
                    )
                    palette.highlight.setStroke()
                    shine.lineWidth = 2
                    shine.lineCapStyle = .round
                    shine.stroke()
                }

                palette.outline.setStroke()
                path.lineWidth = 1.8
                path.lineJoinStyle = .round
                path.stroke()
                return path
            }

            switch kind {
            case .double:
                mound(centerX: 44, top: 14, halfWidth: 17, fill: palette.peakBack, shaded: false)
                mound(centerX: 26, top: 5, halfWidth: 22, fill: palette.peak, shaded: true)
            case .triple:
                mound(centerX: 15, top: 18, halfWidth: 13, fill: palette.peakBack, shaded: false)
                mound(centerX: 49, top: 16, halfWidth: 14, fill: palette.peakBack, shaded: false)
                mound(centerX: 32, top: 4, halfWidth: 20, fill: palette.peak, shaded: true)
            case .snowy:
                let peak = mound(centerX: 32, top: 3, halfWidth: 28, fill: palette.peak, shaded: true)
                // 꼭대기를 덮은 눈 — 아래 가장자리를 물결치게
                context.saveGState()
                peak.addClip()
                let snow = UIBezierPath()
                snow.move(to: CGPoint(x: 10, y: 0))
                snow.addLine(to: CGPoint(x: 54, y: 0))
                snow.addLine(to: CGPoint(x: 54, y: 17))
                snow.addQuadCurve(to: CGPoint(x: 41, y: 16), controlPoint: CGPoint(x: 47, y: 21))
                snow.addQuadCurve(to: CGPoint(x: 32, y: 17), controlPoint: CGPoint(x: 36, y: 12))
                snow.addQuadCurve(to: CGPoint(x: 23, y: 16), controlPoint: CGPoint(x: 28, y: 22))
                snow.addQuadCurve(to: CGPoint(x: 10, y: 17), controlPoint: CGPoint(x: 16, y: 12))
                snow.close()
                palette.snow.setFill()
                snow.fill()
                context.restoreGState()
                palette.outline.setStroke()
                peak.lineWidth = 1.8
                peak.stroke()
            case .smiling:
                mound(centerX: 32, top: 6, halfWidth: 27, fill: palette.peak, shaded: true)
                // 감은 눈 두 개와 볼터치
                let eyes = UIBezierPath()
                for x in [25.0, 37.0] {
                    eyes.move(to: CGPoint(x: x - 2.5, y: 28))
                    eyes.addQuadCurve(to: CGPoint(x: x + 2.5, y: 28), controlPoint: CGPoint(x: x, y: 31))
                }
                palette.outline.setStroke()
                eyes.lineWidth = 1.6
                eyes.lineCapStyle = .round
                eyes.stroke()
                palette.blush.setFill()
                UIBezierPath(ovalIn: CGRect(x: 18, y: 31, width: 5, height: 3)).fill()
                UIBezierPath(ovalIn: CGRect(x: 39, y: 31, width: 5, height: 3)).fill()
            case .single:
                mound(centerX: 32, top: 5, halfWidth: 27, fill: palette.peak, shaded: true)
            }
        }
    }

    // MARK: 나무

    private static func drawTree(_ kind: Tree, palette: Palette) -> UIImage {
        let size = CGSize(width: 24, height: 30)
        return UIGraphicsImageRenderer(size: size).image { renderer in
            let context = renderer.cgContext
            palette.shadow.setFill()
            UIBezierPath(ovalIn: CGRect(x: 5, y: 25.5, width: 14, height: 4)).fill()

            func trunk() {
                let path = UIBezierPath(roundedRect: CGRect(x: 10.5, y: 17, width: 3, height: 10.5), cornerRadius: 1.5)
                palette.trunk.setFill()
                path.fill()
            }

            func canopy(_ path: UIBezierPath, fill: UIColor) {
                fill.setFill()
                path.fill()
                // 왼쪽 위의 동그란 반짝임
                context.saveGState()
                path.addClip()
                palette.highlight.setFill()
                UIBezierPath(ovalIn: CGRect(x: 6, y: 4, width: 5, height: 4)).fill()
                context.restoreGState()
                palette.outline.setStroke()
                path.lineWidth = 1.4
                path.lineJoinStyle = .round
                path.stroke()
            }

            switch kind {
            case .pine:
                trunk()
                let pine = UIBezierPath()
                pine.move(to: CGPoint(x: 12, y: 1.5))
                pine.addQuadCurve(to: CGPoint(x: 18, y: 10), controlPoint: CGPoint(x: 15, y: 6))
                pine.addLine(to: CGPoint(x: 16, y: 10))
                pine.addQuadCurve(to: CGPoint(x: 21.5, y: 20), controlPoint: CGPoint(x: 19, y: 15))
                pine.addQuadCurve(to: CGPoint(x: 2.5, y: 20), controlPoint: CGPoint(x: 12, y: 22.5))
                pine.addQuadCurve(to: CGPoint(x: 8, y: 10), controlPoint: CGPoint(x: 5, y: 15))
                pine.addLine(to: CGPoint(x: 6, y: 10))
                pine.addQuadCurve(to: CGPoint(x: 12, y: 1.5), controlPoint: CGPoint(x: 9, y: 6))
                pine.close()
                canopy(pine, fill: palette.pine)
            case .bush:
                let bush = UIBezierPath()
                bush.append(UIBezierPath(ovalIn: CGRect(x: 2, y: 16, width: 10, height: 10)))
                bush.append(UIBezierPath(ovalIn: CGRect(x: 12, y: 16, width: 10, height: 10)))
                bush.append(UIBezierPath(ovalIn: CGRect(x: 6.5, y: 11, width: 11, height: 11)))
                palette.leafLight.setFill()
                bush.fill()
                palette.outline.setStroke()
                bush.lineWidth = 1.2
                bush.stroke()
            default:
                trunk()
                let fill: UIColor
                switch kind {
                case .blossom: fill = palette.blossom
                case .autumn: fill = palette.autumn
                default: fill = palette.leaf
                }
                canopy(UIBezierPath(ovalIn: CGRect(x: 2.5, y: 1.5, width: 19, height: 18)), fill: fill)
            }
        }
    }

    // MARK: 물

    /// 동그랗게 말린 물결
    private static func drawWave(palette: Palette) -> UIImage {
        let size = CGSize(width: 28, height: 12)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 2, y: 9))
            for start in stride(from: 2.0, to: 24.0, by: 8.0) {
                path.addCurve(
                    to: CGPoint(x: start + 8, y: 9),
                    controlPoint1: CGPoint(x: start + 2, y: 2),
                    controlPoint2: CGPoint(x: start + 7, y: 2)
                )
            }
            palette.wave.setStroke()
            path.lineWidth = 2
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
    }

    /// 돛단배
    private static func drawBoat(palette: Palette) -> UIImage {
        let size = CGSize(width: 26, height: 28)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let sail = UIBezierPath()
            sail.move(to: CGPoint(x: 13, y: 2))
            sail.addQuadCurve(to: CGPoint(x: 13, y: 19), controlPoint: CGPoint(x: 24, y: 14))
            sail.close()
            palette.sail.setFill()
            sail.fill()
            let small = UIBezierPath()
            small.move(to: CGPoint(x: 11.5, y: 7))
            small.addLine(to: CGPoint(x: 11.5, y: 19))
            small.addLine(to: CGPoint(x: 4, y: 19))
            small.close()
            small.fill()

            let hull = UIBezierPath()
            hull.move(to: CGPoint(x: 2, y: 20))
            hull.addLine(to: CGPoint(x: 24, y: 20))
            hull.addQuadCurve(to: CGPoint(x: 18, y: 26), controlPoint: CGPoint(x: 22, y: 25))
            hull.addLine(to: CGPoint(x: 7, y: 26))
            hull.addQuadCurve(to: CGPoint(x: 2, y: 20), controlPoint: CGPoint(x: 3, y: 25))
            hull.close()
            palette.hull.setFill()
            hull.fill()

            palette.outline.setStroke()
            for path in [sail, small, hull] {
                path.lineWidth = 1.3
                path.lineJoinStyle = .round
                path.stroke()
            }
        }
    }

    // MARK: 뭍

    /// 풀 세 가닥
    private static func drawTuft(palette: Palette) -> UIImage {
        let size = CGSize(width: 12, height: 9)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 6, y: 8.5))
            path.addQuadCurve(to: CGPoint(x: 1.5, y: 2.5), controlPoint: CGPoint(x: 3, y: 6.5))
            path.move(to: CGPoint(x: 6, y: 8.5))
            path.addLine(to: CGPoint(x: 6, y: 1))
            path.move(to: CGPoint(x: 6, y: 8.5))
            path.addQuadCurve(to: CGPoint(x: 10.5, y: 2.5), controlPoint: CGPoint(x: 9, y: 6.5))
            palette.grass.setStroke()
            path.lineWidth = 1.4
            path.lineCapStyle = .round
            path.stroke()
        }
    }

    /// 꽃잎 다섯 장짜리 들꽃
    private static func drawFlower(palette: Palette) -> UIImage {
        let size = CGSize(width: 10, height: 10)
        return UIGraphicsImageRenderer(size: size).image { _ in
            palette.petal.setFill()
            for index in 0..<5 {
                let angle = Double(index) / 5 * 2 * .pi - .pi / 2
                let center = CGPoint(x: 5 + cos(angle) * 2.6, y: 5 + sin(angle) * 2.6)
                UIBezierPath(ovalIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)).fill()
            }
            palette.duck.setFill()
            UIBezierPath(ovalIn: CGRect(x: 3.6, y: 3.6, width: 2.8, height: 2.8)).fill()
        }
    }

    /// 둥둥 떠 있는 오리
    private static func drawDuck(palette: Palette) -> UIImage {
        let size = CGSize(width: 24, height: 20)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let body = UIBezierPath()
            body.move(to: CGPoint(x: 3, y: 12))
            body.addQuadCurve(to: CGPoint(x: 20, y: 17), controlPoint: CGPoint(x: 6, y: 19))
            body.addQuadCurve(to: CGPoint(x: 15, y: 10), controlPoint: CGPoint(x: 22, y: 11))
            body.addLine(to: CGPoint(x: 3, y: 12))
            body.close()
            body.append(UIBezierPath(ovalIn: CGRect(x: 13, y: 3, width: 9, height: 9)))
            palette.duck.setFill()
            body.fill()

            let beak = UIBezierPath()
            beak.move(to: CGPoint(x: 21, y: 6.5))
            beak.addLine(to: CGPoint(x: 24, y: 8))
            beak.addLine(to: CGPoint(x: 21, y: 9))
            beak.close()
            palette.beak.setFill()
            beak.fill()

            palette.outline.setStroke()
            body.lineWidth = 1.2
            body.stroke()
            palette.outline.setFill()
            UIBezierPath(ovalIn: CGRect(x: 17.5, y: 5.5, width: 1.8, height: 1.8)).fill()
        }
    }
}


// MARK: - 걸은 자리

/// 내가 걸은 자리를 칸으로 들고 있다가 '이 네모에 발자국이 하나라도 있나'에 답한다.
///
/// 그림은 걸은 자리를 비켜 선다. 숲 한가운데로 걸어 들어가면 그 자리의 나무와 봉우리가
/// 걷혀 오솔길이 난다 — 걸은 만큼 길이 트이고, 아직 안 간 곳은 빽빽한 숲으로 남는다.
/// 렌더러가 여러 스레드에서 함께 읽으므로 만든 뒤에는 바꾸지 않는다.
final class WalkedGround {
    /// 촘촘한 칸과 성긴 칸 (지도 좌표). 작은 그림은 촘촘한 칸으로, 크게 물러나 그린 그림은 성긴 칸으로 본다.
    private let fineSize: Double
    private let coarseSize: Double
    private let fine: [Int64: [MKMapPoint]]
    private let coarse: [Int64: [MKMapPoint]]

    /// 한 변에 이보다 많은 촘촘한 칸이 걸리면 성긴 칸으로 본다
    private static let fineLimit = 12

    init(cells: [HeatCell]) {
        fineSize = WalkHeatmap.cellMapSize * 8
        coarseSize = fineSize * 16
        var fine: [Int64: [MKMapPoint]] = [:]
        var coarse: [Int64: [MKMapPoint]] = [:]
        for cell in cells {
            let point = MKMapPoint(cell.center)
            fine[Self.key(point, size: fineSize), default: []].append(point)
            coarse[Self.key(point, size: coarseSize), default: []].append(point)
        }
        self.fine = fine
        self.coarse = coarse
    }

    /// 이 네모 안에 걸은 자리가 있는지
    func touches(_ rect: MKMapRect) -> Bool {
        let span = rect.size.width / fineSize
        let (size, table) = span > Double(Self.fineLimit) ? (coarseSize, coarse) : (fineSize, fine)
        let minX = Int64((rect.minX / size).rounded(.down)), maxX = Int64((rect.maxX / size).rounded(.down))
        let minY = Int64((rect.minY / size).rounded(.down)), maxY = Int64((rect.maxY / size).rounded(.down))
        for x in minX...maxX {
            for y in minY...maxY {
                guard let points = table[(x << 32) | (y & 0xFFFF_FFFF)] else { continue }
                if points.contains(where: { rect.contains($0) }) { return true }
            }
        }
        return false
    }

    private static func key(_ point: MKMapPoint, size: Double) -> Int64 {
        let x = Int64((point.x / size).rounded(.down)), y = Int64((point.y / size).rounded(.down))
        return (x << 32) | (y & 0xFFFF_FFFF)
    }
}

/// 렌더러가 들고 있는 걸은 자리. 걸을 때마다 바뀌고, 그리는 쪽은 여러 스레드에서 읽는다.
final class WalkedBox {
    private let lock = NSLock()
    private var value: WalkedGround?

    var current: WalkedGround? {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

/// 걸은 자리를 비켜 그리는 그리개
protocol WalkAwareRenderer: MKOverlayRenderer {
    var walked: WalkedBox { get }
}

// MARK: - 격자

/// 지도 좌표의 격자. 그림을 놓을 자리를 여기서 뽑는다.
enum MapGrid {
    /// 격자를 훑는다. 줄마다 반 칸씩 엇갈리고, 칸마다 정해진 만큼 흔들린다.
    /// 흔들림과 두 뽑기(roll, pick — 0..<1)는 칸의 번호에서만 나오므로 언제 다시 그려도 같다.
    static func forEachSpot(
        spacing: Double,
        in mapRect: MKMapRect,
        margin: Double,
        salt: UInt64,
        _ body: (MKMapPoint, Double, Double) -> Void
    ) {
        guard spacing > 0, spacing.isFinite else { return }
        let area = mapRect.insetBy(dx: -margin, dy: -margin)
        let rowHeight = spacing * 0.87
        let firstRow = Int((area.minY / rowHeight).rounded(.down))
        let lastRow = Int((area.maxY / rowHeight).rounded(.up))
        let firstColumn = Int((area.minX / spacing).rounded(.down)) - 1
        let lastColumn = Int((area.maxX / spacing).rounded(.up))
        guard lastRow >= firstRow, lastColumn >= firstColumn else { return }

        for row in firstRow...lastRow {
            let stagger = row & 1 == 0 ? 0 : spacing / 2
            for column in firstColumn...lastColumn {
                var seed = UInt64(bitPattern: Int64(row)) &* 0x9E37_79B9_7F4A_7C15
                    ^ UInt64(bitPattern: Int64(column)) &* 0xC2B2_AE3D_27D4_EB4F
                    ^ salt &* 0x1656_67B1_9E37_79F9
                let jitterX = random(&seed) - 0.5
                let jitterY = random(&seed) - 0.5
                let roll = random(&seed)
                let pick = random(&seed)
                let point = MKMapPoint(
                    x: Double(column) * spacing + stagger + jitterX * spacing * 0.6,
                    y: Double(row) * rowHeight + jitterY * rowHeight * 0.6
                )
                guard area.contains(point) else { continue }
                body(point, roll, pick)
            }
        }
    }

    /// 배율에 따라 그림을 얼마나 키울지.
    ///
    /// 그림을 화면에서 늘 같은 크기로 두면 확대해도 축소해도 똑같아 보여 지도가 납작해진다.
    /// 다가가면 조금 커지고 물러나면 조금 작아지되, 배율만큼 곧이곧대로 따라가지는 않는다 —
    /// 그러면 확대했을 때 산 하나가 화면을 다 덮는다. 한 걸음(1pt)이 2m일 때를 1로 둔다.
    ///
    /// 위도는 타일마다 재지 말고 오버레이 하나에 하나만 쓴다. 타일마다 위도가 조금씩 달라
    /// 크기가 달라지면 격자 간격까지 달라져, 타일 경계에서 그림이 반쯤 잘려 나간다.
    static func growth(unit: Double, for overlay: MKOverlay) -> Double {
        let bounds = overlay.boundingMapRect
        let point = MKMapPoint(x: bounds.midX, y: bounds.midY)
        let metersPerPoint = unit / MKMapPointsPerMeterAtLatitude(point.coordinate.latitude)
        guard metersPerPoint > 0, metersPerPoint.isFinite else { return 1 }
        return min(1.5, max(0.65, pow(2 / metersPerPoint, 0.3)))
    }

    /// splitmix64 — 같은 씨앗이면 늘 같은 수를 낸다
    private static func random(_ state: inout UInt64) -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}

/// 한 타일에 놓을 그림들. 아래(남쪽)에 선 것이 위에 겹치도록 모았다가 한꺼번에 그린다.
struct SpriteBatch {
    private struct Placement {
        let image: UIImage
        let rect: MKMapRect
    }

    private var placements: [Placement] = []
    let walked: WalkedGround?
    /// 발자국 둘레로 비워 둘 너비 (지도 좌표). 점의 반지름보다 조금 넉넉하게.
    let clearance: Double

    init(walked: WalkedGround?, clearance: Double) {
        self.walked = walked
        self.clearance = clearance
    }

    /// 그림의 아래 가운데가 이 자리를 딛고 서는 네모
    static func footprint(of image: UIImage, at point: MKMapPoint, width: Double) -> MKMapRect {
        let height = width * image.size.height / max(image.size.width, 1)
        return MKMapRect(x: point.x - width / 2, y: point.y - height, width: width, height: height)
    }

    /// 걸은 자리를 덮지 않으면 놓는다. 놓았으면 그 네모를, 비켜야 했으면 nil을 돌려준다.
    @discardableResult
    mutating func place(_ image: UIImage, at point: MKMapPoint, width: Double) -> MKMapRect? {
        let rect = Self.footprint(of: image, at: point, width: width)
        if let walked {
            // 그림 가장자리는 투명한 몫이 있어 조금 안쪽만 본다
            let body = rect
                .insetBy(dx: rect.size.width * 0.12, dy: rect.size.height * 0.08)
                .insetBy(dx: -clearance, dy: -clearance)
            guard !walked.touches(body) else { return nil }
        }
        placements.append(Placement(image: image, rect: rect))
        return rect
    }

    func draw(in context: CGContext, renderer: MKOverlayRenderer) {
        guard !placements.isEmpty else { return }
        let sorted = placements.sorted { $0.rect.maxY < $1.rect.maxY }
        UIGraphicsPushContext(context)
        for placement in sorted {
            placement.image.draw(in: renderer.rect(for: placement.rect))
        }
        UIGraphicsPopContext()
    }
}

// MARK: - 산과 물에 뿌리기

/// 본 안에 그림을 뿌린다. 자리는 지도 좌표의 격자에서 나오므로 몇 번을 다시 그려도 같다.
struct TerrainScatter {
    let hills: StencilSampler?
    let water: StencilSampler?
    let sprites: TerrainSprites

    /// 봉우리 하나의 너비(pt)와 그 사이 간격(pt). 배율에 따라 함께 커지고 작아진다.
    static let mountainWidth: Double = 54
    static let mountainSpacing: Double = 46
    /// 나무 하나의 너비(pt)와 그 사이 간격(pt)
    static let treeWidth: Double = 17
    static let treeSpacing: Double = 16
    /// 물결 하나의 너비(pt)와 그 사이 간격(pt)
    static let waveWidth: Double = 24
    static let waveSpacing: Double = 50
    /// 발자국 둘레로 비워 둘 너비(pt). 가장 진한 점의 반지름보다 조금 크다.
    static let dotClearance: Double = 8

    func draw(
        _ mapRect: MKMapRect,
        zoomScale: MKZoomScale,
        in context: CGContext,
        renderer: MKOverlayRenderer,
        walked: WalkedGround?
    ) {
        // 화면 1pt가 지도 좌표로 얼마인지
        let unit = 1 / Double(zoomScale)
        let grow = MapGrid.growth(unit: unit, for: renderer.overlay)
        var batch = SpriteBatch(walked: walked, clearance: Self.dotClearance * unit)

        func wet(_ point: MKMapPoint) -> Bool { (water?.coverage(at: point) ?? 0) > 0.5 }

        if let water {
            let width = Self.waveWidth * unit * grow
            MapGrid.forEachSpot(spacing: Self.waveSpacing * unit * grow, in: mapRect, margin: width * 2, salt: 3) { point, roll, pick in
                guard roll < 0.7 else { return }
                if water.isDeep(at: point, reach: width * 1.6, threshold: 0.5) {
                    // 넓은 물 한가운데에는 가끔 돛단배와 오리가 떠 있다
                    if pick < 0.025 {
                        batch.place(sprites.boat, at: point, width: width * 1.5)
                    } else if pick < 0.045 {
                        batch.place(sprites.duck, at: point, width: width * 1.1)
                    } else {
                        batch.place(sprites.wave, at: point, width: width * (0.75 + pick * 0.5))
                    }
                } else if water.isDeep(at: point, reach: width * 0.55, threshold: 0.5) {
                    // 좁은 강에는 작은 물결만
                    batch.place(sprites.wave, at: point, width: width * 0.6)
                }
            }
        }

        if let hills {
            let width = Self.mountainWidth * unit * grow
            /// 세운 봉우리들 — 나무가 그 발치를 파고들지 않도록 기억해 둔다
            var standing: [MKMapRect] = []
            MapGrid.forEachSpot(spacing: Self.mountainSpacing * unit * grow, in: mapRect, margin: width * 1.6, salt: 1) { point, roll, pick in
                guard hills.isDeep(at: point, reach: width * 0.5), !wet(point) else { return }

                // 산이 넓게 이어질수록 봉우리가 커진다. 한복판에는 눈 덮인 큰 산이 선다.
                let image: UIImage
                let scale: Double
                if hills.isDeep(at: point, reach: width * 1.4), roll < 0.35 {
                    image = sprites.mountain(.snowy)
                    scale = 1.3 + pick * 0.2
                } else {
                    let kind: TerrainSprites.Mountain
                    switch pick {
                    case ..<0.06: kind = .smiling
                    case ..<0.40: kind = .single
                    case ..<0.75: kind = .double
                    default: kind = .triple
                    }
                    image = sprites.mountain(kind)
                    let inner = hills.isDeep(at: point, reach: width * 0.95)
                    scale = (inner ? 1.05 : 0.8) + roll * 0.2
                }
                if let rect = batch.place(image, at: point, width: width * scale) {
                    standing.append(rect.insetBy(dx: rect.size.width * 0.1, dy: 0))
                }
            }

            let treeWidth = Self.treeWidth * unit * grow
            MapGrid.forEachSpot(spacing: Self.treeSpacing * unit * grow, in: mapRect, margin: treeWidth * 2, salt: 2) { point, roll, pick in
                let cover = hills.coverage(at: point)
                guard roll < 0.75, cover > 0.5, !wet(point) else { return }
                // 봉우리가 선 자리는 비워 둔다. 걸어서 봉우리가 걷힌 자리에는 나무가 대신 선다.
                guard !standing.contains(where: { $0.contains(point) }) else { return }

                let kind: TerrainSprites.Tree
                switch pick {
                case ..<0.06: kind = .blossom
                case ..<0.11: kind = .autumn
                case ..<0.36: kind = .pine
                case ..<0.50: kind = .bush
                default: kind = .round
                }
                // 숲 가장자리의 나무는 작고 안쪽으로 갈수록 자란다
                let scale = (0.7 + 0.3 * min(cover, 1)) * (0.85 + roll * 0.4)
                batch.place(sprites.tree(kind), at: point, width: treeWidth * scale)
            }
        }

        batch.draw(in: context, renderer: renderer)
    }
}

// MARK: - 종이

/// 그림지도의 종이.
///
/// 먹 지도의 종이는 빛 한 가지지만, 그림지도는 물도 산도 없는 도심에서도 그림책 같아야 한다.
/// 그래서 물감이 번진 듯한 옅은 얼룩과 종이 결을 깔고, 빈 뭍에 풀포기와 들꽃을 드문드문 뿌린다.
/// 풀과 꽃도 걸은 자리는 비켜 선다.
final class PicturePaperRenderer: MKOverlayRenderer, WalkAwareRenderer {
    let walked = WalkedBox()
    private let paper: UIColor
    private let warmGradient: CGGradient
    private let coolGradient: CGGradient
    private let grain: UIColor
    private let sprites: TerrainSprites

    /// 얼룩 사이의 간격과 크기(pt)
    static let blotSpacing: Double = 150
    static let blotRadius: Double = 90
    /// 종이 결 사이의 간격(pt)
    static let grainSpacing: Double = 9
    /// 풀포기 사이의 간격(pt)
    static let tuftSpacing: Double = 40

    init(overlay: MKOverlay, traits: UITraitCollection) {
        paper = InkStyle.picturePaper.resolvedColor(with: traits)
        let dark = traits.userInterfaceStyle == .dark
        let warm = dark
            ? UIColor(red: 0.20, green: 0.17, blue: 0.13, alpha: 0.35)
            : UIColor(red: 0.98, green: 0.87, blue: 0.68, alpha: 0.38)
        let cool = dark
            ? UIColor(red: 0.12, green: 0.18, blue: 0.16, alpha: 0.35)
            : UIColor(red: 0.84, green: 0.92, blue: 0.78, alpha: 0.42)
        func fading(_ color: UIColor) -> CGGradient {
            CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [color.cgColor, color.withAlphaComponent(color.cgColor.alpha * 0.6).cgColor, color.withAlphaComponent(0).cgColor] as CFArray,
                locations: [0, 0.55, 1]
            )!
        }
        warmGradient = fading(warm)
        coolGradient = fading(cool)
        grain = dark ? UIColor(white: 1, alpha: 0.05) : UIColor(red: 0.45, green: 0.35, blue: 0.2, alpha: 0.08)
        sprites = TerrainSprites(traits: traits)
        super.init(overlay: overlay)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let area = mapRect.intersection(overlay.boundingMapRect)
        guard !area.isNull, area.size.width > 0 else { return }
        let unit = 1 / Double(zoomScale)

        context.saveGState()
        context.clip(to: rect(for: area))
        context.setFillColor(paper.cgColor)
        context.fill(rect(for: area))

        // 물감 얼룩 — 크고 옅게, 따뜻한 빛과 서늘한 빛이 번갈아
        let radius = Self.blotRadius * unit
        MapGrid.forEachSpot(spacing: Self.blotSpacing * unit, in: mapRect, margin: radius * 1.4, salt: 11) { point, roll, pick in
            guard roll < 0.6 else { return }
            let size = radius * (0.7 + pick * 0.7)
            let center = self.point(for: point)
            // 그리개 좌표는 지도 좌표와 눈금이 같다 (원점만 옮겨져 있다).
            // 가장자리로 갈수록 스러지게 칠해야 동그라미가 아니라 번진 물감으로 보인다.
            context.drawRadialGradient(
                pick < 0.5 ? warmGradient : coolGradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: CGFloat(size),
                options: []
            )
        }

        // 종이 결 — 아주 작은 점을 흩뿌린다
        let grainPath = CGMutablePath()
        let dot = 0.6 * unit
        MapGrid.forEachSpot(spacing: Self.grainSpacing * unit, in: mapRect, margin: dot, salt: 12) { point, roll, _ in
            guard roll < 0.45 else { return }
            let r = rect(for: MKMapRect(x: point.x - dot, y: point.y - dot, width: dot * 2, height: dot * 2))
            grainPath.addEllipse(in: r)
        }
        context.addPath(grainPath)
        context.setFillColor(grain.cgColor)
        context.fillPath()
        context.restoreGState()

        // 빈 뭍의 풀포기와 들꽃
        let grow = MapGrid.growth(unit: unit, for: overlay)
        var batch = SpriteBatch(walked: walked.current, clearance: TerrainScatter.dotClearance * unit)
        let width = 11 * unit * grow
        MapGrid.forEachSpot(spacing: Self.tuftSpacing * unit * grow, in: mapRect, margin: width * 2, salt: 13) { point, roll, pick in
            if roll < 0.2 {
                batch.place(sprites.tuft, at: point, width: width * (0.8 + pick * 0.5))
            } else if roll < 0.25 {
                batch.place(sprites.flower, at: point, width: width * (0.7 + pick * 0.3))
            }
        }
        context.saveGState()
        context.clip(to: rect(for: area))
        batch.draw(in: context, renderer: self)
        context.restoreGState()
    }
}
