//
//  TerrainMap.swift
//  FootprintDiary
//
//  종이에 물길과 산을 인쇄한다.
//
//  백지 지도의 어려움은 '어디가 어딘지 모른다'는 것 하나다. 그런데 물과 산은 발자국으로
//  그려지지 않는다 — 물은 걸어서 갈 수 없고, 산은 걸어도 그 능선이 점으로는 드러나지 않는다.
//  그려지지 않는 것을 비워 두면 백지는 끝까지 백지다. 그래서 이 둘은 내가 그리는 것이 아니라
//  미리 인쇄된 '종이의 무늬'로 둔다. 대동여지도도 물길과 산줄기를 먼저 앉히고 그 사이를 채웠다.
//
//  다만 무늬는 무늬답게 옅어야 한다. 짙게 깔면 이 앱은 그냥 '지도 위에 점 찍는 앱'이 된다.
//  그래서 산은 물보다 한참 더 옅다 — 산은 걸어서 갈 수 있는 곳이라 채워 나갈 몫이 남아 있다.
//
//  MapKit에는 이것들의 모양을 내주는 길이 없다. 그래서 지도를 한 장 찍어 빛깔로 골라 본을 뜬다.
//  애플 지도에서 물은 하늘빛 시안 한 가지이고, 숲과 산은 초록이 빨강·파랑보다 또렷이 세다.
//  도시의 뭍은 빨강과 초록이 같은 값이라 이 하나로 깨끗이 갈린다.
//
//  물과 산은 따로 찍는다. 애플 지도는 배율에 따라 무엇을 그릴지 달리 정하는데,
//  국립공원 같은 큰 산은 4km쯤 물러나야 초록으로 칠해지고 가까이 다가가면 아예 사라진다
//  (남산 같은 도시 공원은 정반대다). 그래서 물은 지금 보는 배율 그대로, 산은 넉넉히
//  물러난 자리에서 뜬다. 산은 덩어리가 커서 본이 성글어도 흉하지 않고, 오히려 산자락이
//  부드럽게 번져 종이에 어울린다. 넓게 뜬 본은 웬만큼 걸어 다녀도 다시 찍을 일이 없다.
//
//  뜬 본에는 흠이 난다. 다리와 도로가 강 위를 지나고 도로 번호 표지가 강 한복판에 얹히는데,
//  그 화소는 물빛이 아니라서 물 한가운데 뭍이 뚫린 꼴이 된다. 그래서 본을 뜬 뒤에 한 번 메운다.
//
//  본은 늘 '밝은 쪽' 지도에서 뜬다. 어두운 쪽은 온 지도가 남빛이라 물과 뭍이 갈리지 않기
//  때문이다. 어차피 찍은 그림은 화면에 한 번도 나가지 않는다 — 모양만 빌리고 빛깔은
//  이 앱이 제 먹으로 칠한다. 그래서 밝은 화면과 어두운 화면이 저마다 제 빛을 갖는다.
//

import Foundation
import MapKit
import UIKit

/// 뜬 본 한 장 — 어느 범위를 어떤 모양으로 덮는지.
///
/// 스텐실은 '0인 자리에 칠한다'는 CoreGraphics 이미지 마스크 규약을 따른다.
/// 그래서 무늬가 놓일 자리가 0, 나머지가 255다. 해당 무늬가 없으면 nil이다.
struct TerrainMask {
    /// 물의 본이 덮는 범위 (지금 보는 배율)
    let waterRect: MKMapRect
    let water: CGImage?
    /// 산의 본이 덮는 범위 (넉넉히 물러난 자리라 물보다 넓다)
    let hillRect: MKMapRect
    let hills: CGImage?

    var isEmpty: Bool { water == nil && hills == nil }
    /// 둘을 다 품는 범위
    var bounds: MKMapRect { waterRect.union(hillRect) }
}

/// 본을 뜬 결과.
///
/// '아무것도 없더라'와 '지도를 못 찍었다'는 전혀 다른 말이다. 앞은 그대로 받아들이면 되지만
/// 뒤는 다시 해 봐야 한다. 둘을 뭉뚱그려 nil로 두면, 한 번 실패한 자리는 아무것도 없는 곳으로
/// 굳어 다시는 시도하지 않는다.
enum TerrainSearch {
    case found(TerrainMask)
    /// 물도 산도 없는 자리 (도시 한복판은 이쪽이 보통이다)
    case bare
    /// 지도를 찍지 못했다 — 이어서 여러 번 찍으면 애플이 잠시 막아 둔다
    case failed
}

/// 지도를 한 장 찍어 물과 산의 본을 뜬다.
final class TerrainFinder {

    /// 물빛으로 볼 색상의 범위(도). 애플 지도의 물은 195도 언저리 한 가지다.
    static let waterHue: ClosedRange<Double> = 185...235
    /// 물빛은 뚜렷하다. 옅은 회색 길이 파랑으로 새지 않도록 이만큼은 요구한다.
    static let waterSaturation = 0.15

    /// 풀빛으로 볼 색상의 범위(도). 숲·공원은 70~90도 언저리의 누런 초록이다.
    static let hillHue: ClosedRange<Double> = 55...160
    /// 숲빛은 종이빛과 아주 가깝다(뭍 249,249,244 / 숲 233,240,225).
    /// 그래서 문턱을 낮게 두되, '초록이 빨강보다 세다'는 조건이 도시를 먼저 걸러 낸다.
    static let hillSaturation = 0.035

    /// 이보다 어두운 색은 무늬로 보지 않는다 (글씨·그림자)
    static let minimumBrightness = 0.35
    /// 산의 본을 뜰 때 적어도 이만큼(m)은 물러난다.
    static let minimumHillMeters: CLLocationDistance = 5_000
    /// 산의 본은 이보다 성기게(m/픽셀) 찍어야 한다.
    ///
    /// 애플 지도가 무엇을 그릴지는 '범위의 크기'가 아니라 '한 픽셀이 몇 미터인가'로 정해진다.
    /// 촘촘히 들여다보면 국립공원 같은 큰 산의 초록을 아예 걷어 낸다 — 7m/픽셀에서는 한 점도
    /// 안 나오고 14m/픽셀부터 96%가 나온다. 그래서 산만은 일부러 성기게 찍는다.
    /// 산은 덩어리가 커서 성겨도 모양이 상하지 않는다.
    static let hillMetersPerPixel: CLLocationDistance = 22
    /// 산의 본 가장자리를 번지게 할 둘레(본의 픽셀).
    /// 성글게 뜬 본을 그대로 늘리면 산자락이 계단처럼 각진다. 옛 지도의 산은 그렇게 생기지 않았다.
    static let hillFeather = 3
    /// 본의 긴 변(픽셀). 물과 산은 덩어리가 커서 이 정도면 가장자리가 뭉개지지 않는다.
    static let stencilWidth: CGFloat = 768
    /// 성글게 찍더라도 이보다 작게는 만들지 않는다
    static let minimumStencilWidth: CGFloat = 128
    /// 본이 지나치게 길쭉해지지 않도록 자른다
    static let stencilMaxHeight: CGFloat = 1_536
    /// 다리·도로가 낸 가느다란 흠을 메울 때 보는 둘레(픽셀).
    /// 이만큼보다 좁은 틈은 무늬로 덮인다. 물가와 산자락을 뭉갤 만큼 크면 안 된다.
    static let mendRadius = 4
    /// 무늬에 온통 둘러싸인 조각이 이 넓이(전체 대비)보다 작으면 흠으로 보고 메운다.
    /// 여의도처럼 진짜 섬은 이보다 훨씬 크므로 살아남는다.
    static let markAreaRatio = 0.003

    /// 아직 그리고 있는 것들. 끝날 때까지 붙들고 있는다.
    ///
    /// 그리다 만 지도를 중간에 걷어 내면(`cancel()`) 그 순간 그림판이 쓰고 있던 자리까지
    /// 함께 사라진다. 화면 카드는 그 자리를 아직 쓰고 있어서 앱이 통째로 내려앉는다.
    /// 지도를 축소했다가 곧바로 확대하면 앞선 것이 채 끝나기 전에 새것을 찍게 되는데,
    /// 바로 그 자리다. 그래서 한 번 시작한 것은 끝까지 두고, 늦게 온 결과만 버린다.
    private var running: [MKMapSnapshotter] = []
    /// 지난 요청의 결과가 늦게 도착해 새 것을 덮어쓰지 않도록 세는 번호
    private var generation = 0
    /// 뜬 산의 본을 들고 있는다. 넓게 떠 두므로 웬만큼 걸어 다녀도 다시 찍을 일이 없다.
    private var heldHills: (rect: MKMapRect, stencil: CGImage?)?

    /// 주어진 범위의 물과 산을 찾는다. 앞선 요청의 결과는 버린다.
    ///
    /// 물은 준 범위 그대로, 산은 넉넉히 물러난 범위에서 뜬다. 둘을 함께 찍고 다 모이면 알린다.
    func find(in rect: MKMapRect, completion: @escaping (TerrainSearch) -> Void) {
        generation += 1
        let token = generation

        let hillRect = Self.widened(rect, toAtLeast: Self.minimumHillMeters)
        var water: CGImage?
        var hills: CGImage?
        var stumbled = false
        let group = DispatchGroup()

        group.enter()
        snapshot(of: rect, coarserThan: nil) { image in
            if let image { water = Self.stencil(of: image, keeping: .water) } else { stumbled = true }
            group.leave()
        }

        // 들고 있는 산의 본이 지금 자리를 아직 덮고 있으면 다시 찍지 않는다.
        // 산은 5km 너비로 떠 두므로 한 번 뜨면 오래 간다 — 걸어서 벗어나기 어렵다.
        if let heldHills, heldHills.rect.contains(rect) {
            hills = heldHills.stencil
        } else {
            group.enter()
            snapshot(of: hillRect, coarserThan: Self.hillMetersPerPixel) { image in
                if let image { hills = Self.stencil(of: image, keeping: .hill) } else { stumbled = true }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            // 이미 다른 자리를 보고 있다면 늦게 온 이 결과는 버린다
            guard let self, token == self.generation else { return }

            guard !stumbled else { completion(.failed); return }
            self.heldHills = (rect: hillRect, stencil: hills)

            let mask = TerrainMask(waterRect: rect, water: water, hillRect: hillRect, hills: hills)
            completion(mask.isEmpty ? .bare : .found(mask))
        }
    }

    /// 지금 찍고 있는 것의 결과를 더는 쓰지 않겠다는 뜻이다.
    ///
    /// 그리던 것을 중간에 걷어 내지는 않는다. 걷어 내는 그 순간이 앱이 내려앉는 자리다.
    /// 그림은 제 속도로 끝나게 두고, 다 되면 아무도 받지 않아 조용히 버려진다.
    func cancel() {
        generation += 1
    }

    /// 한 범위를 찍는다. 화소를 훑는 일은 메인에서 하면 지도가 뚝뚝 끊기므로 뒤로 물린다.
    private func snapshot(
        of rect: MKMapRect,
        coarserThan metersPerPixel: CLLocationDistance?,
        then handle: @escaping (UIImage?) -> Void
    ) {
        let options = MKMapSnapshotter.Options()
        options.mapRect = rect

        var width = Self.stencilWidth
        // 성글게 찍으라는 주문이 있으면 픽셀 수를 줄여 그 배율로 내려간다
        if let metersPerPixel {
            let meters = rect.size.width / MKMapPointsPerMeterAtLatitude(rect.origin.coordinate.latitude)
            width = min(width, CGFloat(meters / metersPerPixel))
        }
        width = max(width, Self.minimumStencilWidth)

        // 높이만 자르면 본이 옆으로 늘어나 가장자리가 엉뚱한 자리에 인쇄된다. 둘을 함께 줄인다.
        let aspect = rect.size.height / rect.size.width
        var height = width * aspect
        if height > Self.stencilMaxHeight {
            height = Self.stencilMaxHeight
            width = height / max(aspect, 0.0001)
        }
        // 셈이 어긋나 크기가 성하지 않으면(0이거나 값이 아니면) 찍기를 그만둔다.
        // 그런 크기를 주면 그림판이 자리를 잡지 못한 채 허물어지고, 앱이 함께 내려앉는다.
        let size = CGSize(width: Self.sane(width), height: Self.sane(height))
        guard size.width > 0, size.height > 0 else { handle(nil); return }
        options.size = size
        // 관심지점을 지워 두면 그 표시가 물 위에 얹혀 본에 구멍을 내지 않는다
        let configuration = MKStandardMapConfiguration(emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration
        // 늘 밝은 쪽으로, 배율은 1로 찍는다. 화면에 그대로 나갈 그림이 아니라 본일 뿐이다.
        options.traitCollection = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: .light),
            UITraitCollection(displayScale: 1)
        ])

        let snapshotter = MKMapSnapshotter(options: options)
        // 끝날 때까지 붙들어 둔다. 그리는 중에 놓아 버리면 걷어 내는 것과 다를 바 없다.
        running.append(snapshotter)
        snapshotter.start(with: DispatchQueue.global(qos: .userInitiated)) { [weak self] snapshot, _ in
            handle(snapshot?.image)
            DispatchQueue.main.async { self?.running.removeAll { $0 === snapshotter } }
        }
    }

    /// 성한 픽셀 수인지 본다. 값이 아니거나 끝이 없으면 0을 돌려 '찍지 말라'고 알린다.
    private static func sane(_ value: CGFloat) -> CGFloat {
        value.isFinite ? max(value.rounded(), 1) : 0
    }

    /// 산의 본을 뜰 범위. 좁으면 애플 지도가 큰 산을 아예 그리지 않으므로 뒤로 물러선다.
    private static func widened(_ rect: MKMapRect, toAtLeast meters: CLLocationDistance) -> MKMapRect {
        let wanted = meters * MKMapPointsPerMeterAtLatitude(rect.origin.coordinate.latitude)
        guard rect.size.width > 0, rect.size.width < wanted else { return rect }
        // 가로세로 비율을 지켜야 본이 늘어나지 않는다
        let scale = wanted / rect.size.width
        let widened = rect.insetBy(
            dx: -rect.size.width * (scale - 1) / 2,
            dy: -rect.size.height * (scale - 1) / 2
        )
        // 지도 밖으로 넘어간 범위는 찍히지 않는다
        let clamped = widened.intersection(.world)
        return clamped.isNull ? rect : clamped
    }

    // MARK: - 본 뜨기

    /// 뽑아낼 무늬
    private enum Feature {
        case water
        case hill

        func matches(_ r: Double, _ g: Double, _ b: Double) -> Bool {
            switch self {
            case .water: return isWater(r, g, b)
            case .hill: return isHill(r, g, b)
            }
        }
    }

    /// 찍은 그림에서 한 갈래의 무늬만 골라 스텐실로 굽는다
    private static func stencil(of image: UIImage, keeping feature: Feature) -> CGImage? {
        guard let source = image.cgImage else { return nil }
        let width = source.width, height = source.height
        guard width > 0, height > 0 else { return nil }

        // 화소를 직접 읽으려면 배치를 우리가 아는 꼴로 한 번 다시 그려야 한다
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = pixels.withUnsafeMutableBytes({ buffer in
            CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }) else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        var area = [Bool](repeating: false, count: width * height)
        var found = 0
        for index in 0..<(width * height) {
            let offset = index * 4
            if feature.matches(
                Double(pixels[offset]) / 255,
                Double(pixels[offset + 1]) / 255,
                Double(pixels[offset + 2]) / 255
            ) {
                area[index] = true
                found += 1
            }
        }
        // 이 무늬가 한 점도 없는 자리에서는 본을 만들지 않는다
        guard found > 0 else { return nil }
        return stencil(
            of: area,
            width: width,
            height: height,
            feather: feature == .hill ? hillFeather : 0
        )
    }

    /// 흠을 메운 뒤 CoreGraphics가 쓸 수 있는 스텐실로 굽는다
    private static func stencil(of area: [Bool], width: Int, height: Int, feather: Int) -> CGImage? {
        var mended = mendingThinMarks(area, width: width, height: height)
        mended = fillingTrappedMarks(mended, width: width, height: height)

        // 스텐실은 0인 자리에 칠한다. 그래서 바깥을 255로 두고 무늬만 0으로 뚫는다.
        let bytes: [UInt8]
        if feather > 0 {
            // 둘레에 든 무늬의 비율로 진하기를 매긴다. 안쪽은 0, 바깥은 255, 가장자리는 그 사이가 되어
            // 각진 계단 대신 종이에 스민 자국처럼 번진다.
            let counts = boxCounts(mended, width: width, height: height, radius: feather)
            bytes = (0..<(width * height)).map { index in
                let x = index % width, y = index / width
                let full = span(at: x, radius: feather, limit: width)
                    * span(at: y, radius: feather, limit: height)
                return UInt8(255 - min(255, counts[index] * 255 / max(full, 1)))
            }
        } else {
            bytes = mended.map { $0 ? UInt8(0) : UInt8(255) }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            maskWidth: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            provider: provider,
            decode: nil,
            // 늘려 그릴 때 가장자리를 부드럽게 — 각진 계단이 종이에 어울리지 않는다
            shouldInterpolate: true
        )
    }

    // MARK: - 빛깔 가려내기

    /// 이 화소가 물빛인지. UIColor를 거치지 않고 직접 재는 건 화소가 수십만 개이기 때문이다.
    private static func isWater(_ r: Double, _ g: Double, _ b: Double) -> Bool {
        let highest = max(r, g, b), lowest = min(r, g, b)
        let delta = highest - lowest
        guard highest > minimumBrightness, delta > 0 else { return false }
        guard delta / highest > waterSaturation else { return false }
        // 파랑이 가장 센 색이어야 한다. 이 하나로 숲(초록)과 땅(누런빛)이 먼저 걸러진다.
        guard b == highest else { return false }

        var hue = 60 * (4 + (r - g) / delta)
        if hue < 0 { hue += 360 }
        return waterHue.contains(hue)
    }

    /// 이 화소가 숲·산의 풀빛인지.
    ///
    /// 초록이 빨강보다 '엄격히' 세야 한다는 것이 이 판정의 핵심이다. 애플 지도에서 도시의
    /// 뭍은 빨강과 초록이 똑같은 값(249,249,244)이라 여기서 곧바로 걸러지고, 숲은
    /// 초록이 한두 눈금 앞선다(233,240,225). 채도만으로는 이 둘이 갈리지 않는다.
    private static func isHill(_ r: Double, _ g: Double, _ b: Double) -> Bool {
        let highest = max(r, g, b), lowest = min(r, g, b)
        let delta = highest - lowest
        guard highest > minimumBrightness, delta > 0 else { return false }
        guard g == highest, g > r, g > b else { return false }
        guard delta / highest > hillSaturation else { return false }

        var hue = 60 * (2 + (b - r) / delta)
        if hue < 0 { hue += 360 }
        return hillHue.contains(hue)
    }

    // MARK: - 흠 메우기

    /// 무늬 위를 지나는 다리·도로가 낸 가느다란 흠을 메운다.
    ///
    /// 무늬를 한 번 부풀렸다가 같은 만큼 깎는다(닫힘 연산). 부풀릴 때 가는 틈이 덮이고,
    /// 깎을 때 가장자리는 제자리로 돌아온다. 그래서 강을 가로지르는 다리는 사라지고
    /// 해안선과 산자락은 그대로 남는다. 둘레보다 두꺼운 것은 건드리지 않는다.
    private static func mendingThinMarks(_ area: [Bool], width: Int, height: Int) -> [Bool] {
        let radius = mendRadius
        guard radius > 0 else { return area }

        // 부풀리기 — 둘레 안에 무늬가 한 점이라도 있으면 무늬로 본다
        let grown = boxCounts(area, width: width, height: height, radius: radius).map { $0 > 0 }

        // 깎기 — 둘레가 온통 무늬일 때만 무늬로 남긴다
        let grownCounts = boxCounts(grown, width: width, height: height, radius: radius)
        return (0..<(width * height)).map { index in
            let x = index % width, y = index / width
            let full = span(at: x, radius: radius, limit: width) * span(at: y, radius: radius, limit: height)
            return grownCounts[index] == full
        }
    }

    /// 무늬에 온통 갇힌 자잘한 빈자리를 메운다.
    ///
    /// 도로 번호 표지처럼 강 한복판에 동그마니 얹힌 것이 여기 걸린다. 가장자리에 닿아 있는
    /// 빈자리는 바깥과 이어져 있다는 뜻이므로 건드리지 않고, 갇힌 것 중에서도 넓은 것은
    /// 진짜 섬이거나 산속 마을이므로 남긴다 — 여의도를 지워 버리면 안 된다.
    private static func fillingTrappedMarks(_ area: [Bool], width: Int, height: Int) -> [Bool] {
        let total = width * height
        let maxArea = max(1, Int(Double(total) * markAreaRatio))
        var filled = area
        var visited = [Bool](repeating: false, count: total)
        var stack: [Int] = []

        func step(_ next: Int) {
            guard !visited[next], !area[next] else { return }
            visited[next] = true
            stack.append(next)
        }

        /// 여기서부터 이어진 빈자리를 모두 훑는다
        func sweep(from start: Int, collecting: Bool) -> [Int] {
            var body: [Int] = []
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            visited[start] = true
            while let index = stack.popLast() {
                if collecting { body.append(index) }
                let x = index % width, y = index / width
                if x > 0 { step(index - 1) }
                if x < width - 1 { step(index + 1) }
                if y > 0 { step(index - width) }
                if y < height - 1 { step(index + width) }
            }
            return body
        }

        // 1. 가장자리에 닿은 빈자리부터 표시해 둔다 (바깥과 이어져 있다는 뜻)
        var edges: [Int] = []
        for x in 0..<width { edges.append(x); edges.append((height - 1) * width + x) }
        for y in 0..<height { edges.append(y * width); edges.append(y * width + width - 1) }
        for index in edges where !area[index] && !visited[index] {
            _ = sweep(from: index, collecting: false)
        }

        // 2. 남은 빈자리는 무늬에 갇힌 것이다. 작으면 흠으로 보고 메운다.
        for index in 0..<total where !area[index] && !visited[index] {
            let body = sweep(from: index, collecting: true)
            guard body.count <= maxArea else { continue }
            for pixel in body { filled[pixel] = true }
        }
        return filled
    }

    /// 가장자리에서 잘린 둘레의 실제 길이
    private static func span(at position: Int, radius: Int, limit: Int) -> Int {
        min(position + radius, limit - 1) - max(position - radius, 0) + 1
    }

    /// 둘레 안에 든 참의 개수. 가로로 한 번, 세로로 한 번 미끄러뜨려 센다.
    /// 화소마다 둘레를 다시 훑으면 백만 번이 넘어가므로 창을 밀며 더하고 뺀다.
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

// MARK: - 지도에 올리는 것

final class TerrainOverlay: NSObject, MKOverlay {
    let mask: TerrainMask

    init(mask: TerrainMask) {
        self.mask = mask
        super.init()
    }

    var boundingMapRect: MKMapRect { mask.bounds }
    var coordinate: CLLocationCoordinate2D { mask.bounds.origin.coordinate }
}

final class TerrainRenderer: MKOverlayRenderer {
    /// 미리 뽑아 둔 빛깔 (그리는 중에는 화면 설정을 물어볼 수 없다)
    private let waterColor: UIColor
    private let hillColor: UIColor

    init(overlay: TerrainOverlay, traits: UITraitCollection) {
        waterColor = InkStyle.water.resolvedColor(with: traits)
        hillColor = InkStyle.hill.resolvedColor(with: traits)
        super.init(overlay: overlay)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? TerrainOverlay else { return }
        // 산을 먼저 깔고 물을 그 위에 얹는다 (산속 저수지가 숲에 묻히지 않게).
        // 둘은 덮는 범위가 달라서 저마다 제 자리에 인쇄한다.
        paint(overlay.mask.hills, with: hillColor, in: overlay.mask.hillRect, on: context)
        paint(overlay.mask.water, with: waterColor, in: overlay.mask.waterRect, on: context)
    }

    private func paint(_ stencil: CGImage?, with color: UIColor, in mapRect: MKMapRect, on context: CGContext) {
        guard let stencil else { return }
        let target = rect(for: mapRect)
        guard !target.isEmpty else { return }

        context.saveGState()
        // 지도 좌표는 남쪽으로 갈수록 커지고 이미지는 아래에서 위로 그려진다.
        // 뒤집지 않으면 무늬가 위아래가 바뀐 채 인쇄된다. (제 범위의 한가운데를 축으로 뒤집는다)
        context.translateBy(x: 0, y: target.maxY + target.minY)
        context.scaleBy(x: 1, y: -1)

        context.clip(to: target, mask: stencil)
        context.setFillColor(color.cgColor)
        context.fill(target)
        context.restoreGState()
    }
}
