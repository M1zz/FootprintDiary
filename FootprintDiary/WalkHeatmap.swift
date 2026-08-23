//
//  WalkHeatmap.swift
//  FootprintDiary
//
//  걸은 길을 선이 아니라 촘촘한 점으로 그린다.
//
//  선으로 그리면 한 번 지난 길과 백 번 지난 길이 똑같아 보인다. 점 하나하나를 칸으로
//  세면 자주 지난 칸일수록 짙어져서, 내 생활 반경이 어디에 뭉쳐 있는지가 그대로 드러난다.
//  옛 지도에서 자주 쓰는 길이 굵게 그려진 것과 같은 뜻이다.
//
//  빛깔은 '언제 밟았는가'를 말한다. 그날 걸은 자리는 모두 그날의 원색 하나로 찍히고,
//  다시 밟지 않은 채 해가 지나면 빛이 서서히 빠져 잿빛이 된다. 2년이면 다 바랜다.
//  그래서 지도를 펼치면 요즘 사는 동네는 알록달록하고, 옛날에 살던 동네는 흑백 사진처럼
//  남는다. 발길이 끊긴 자리가 스스로 사라지지 않고 '빛바랜 채로' 남는 것이 요점이다.
//
//  한 칸을 여러 날 밟았다면 가장 나중에 밟은 날이 이긴다. 덧칠하는 것과 같다.
//
//  점이 수만 개가 되므로 하나씩 오버레이로 올리지 않고, 오버레이 하나가 한꺼번에 그린다.
//

import Foundation
import MapKit

/// 격자 한 칸
struct HeatCell {
    let center: CLLocationCoordinate2D
    /// 서로 다른 통과 횟수 (한 번의 산책에서 여러 점이 들어와도 1로 센다)
    let passes: Int
    /// 마지막으로 밟은 때. 여러 날 밟았으면 가장 나중 것만 남아 앞선 날을 덮는다.
    let lastVisit: Date
    /// 그날의 첫 시각(자정). 같은 날 밟은 칸끼리 같은 빛깔을 뽑는 열쇠다.
    let lastVisitDay: Date
}

enum WalkHeatmap {

    /// 칸 한 변의 길이(m). 경로 점 간격(8~12m)과 비슷해야 점이 이가 빠지지 않는다.
    static let cellMeters: CLLocationDistance = 10

    /// 칸의 크기를 재는 위도.
    ///
    /// 격자를 위경도 '각도'로 끊으면 가로 한 칸이 세로 한 칸보다 좁아진다. 경도 1도의
    /// 실제 폭은 위도로 올라갈수록 줄어들기 때문이다 — 서울에서는 위도 1도의 0.79배다.
    /// 그러면 점이 좌우로는 맞붙고 위아래로는 벌어져, 격자무늬가 아니라 줄무늬로 보인다.
    ///
    /// 그래서 각도가 아니라 지도 좌표로 끊는다. 메르카토르는 각을 지키는 투영이라,
    /// 지도 좌표에서 정사각이면 화면에서도 어느 위도에서나 정사각이다. 대신 칸의 실제
    /// 크기가 위도마다 조금씩 달라진다 — 이 위도에서 딱 cellMeters고, 남쪽으로 갈수록
    /// 조금 크고 북쪽으로 갈수록 조금 작다. 눈에 보이는 것은 어디서나 고른 격자다.
    static let referenceLatitude: CLLocationDegrees = 37.5

    /// 칸 한 변 (지도 좌표).
    /// 격자를 끊는 자와 점을 그리는 자가 같아야 간격이 고르게 나온다.
    static var cellMapSize: Double {
        MKMapPointsPerMeterAtLatitude(referenceLatitude) * cellMeters
    }

    /// 이 횟수 이상 지나면 가장 짙게 그린다.
    /// 데이터가 늘 때마다 색이 바뀌지 않도록 기준을 고정해 둔다.
    static let hottest = 10

    /// 밟은 자리에서 빛이 다 빠지기까지 두는 시간.
    ///
    /// 2년으로 잡은 데는 까닭이 있다. 한 해로 끊으면 작년 이맘때 다니던 길이 벌써
    /// 잿빛이라 '요즘'이 너무 좁아지고, 5년으로 늘리면 웬만한 자리가 다 알록달록해
    /// 빛깔이 아무 말도 하지 않게 된다. 이사·이직처럼 생활 반경이 통째로 바뀌는
    /// 주기가 대략 이쯤이라, 2년이면 지난 삶과 지금 삶이 눈으로 갈린다.
    static let fadingSpan: TimeInterval = 60 * 60 * 24 * 365 * 2

    /// 0~1로 누른 싱싱함. 1이면 갓 밟은 자리, 0이면 온전히 바랜 자리.
    ///
    /// 곧게 줄인다. 처음에 훅 빠지고 뒤에 오래 끄는 식으로 휘면 '작년에 간 곳'과
    /// '3년 전에 간 곳'이 둘 다 잿빛으로 뭉개져, 정작 알고 싶은 옛 자리의 앞뒤가 사라진다.
    static func freshness(lastVisit: Date, now: Date) -> Double {
        let age = now.timeIntervalSince(lastVisit)
        // 기기 시계가 뒤로 간 뒤에 쌓인 점은 '앞날'에 찍혀 있다. 갓 밟은 것으로 친다.
        guard age > 0 else { return 1 }
        return max(0, 1 - age / fadingSpan)
    }

    /// 통과 묶음들을 칸으로 센다.
    /// 한 통과가 같은 칸을 여러 번 밟아도 1로 세야 '몇 번 다닌 길'이 된다.
    static func cells(passes: [[WalkTrail.Point]], calendar: Calendar = .current) -> [HeatCell] {
        let step = cellMapSize
        var counts: [GridCell: Int] = [:]
        /// 칸마다 마지막으로 밟은 때. 나중 것이 앞선 것을 덮는다.
        var latest: [GridCell: Date] = [:]

        for pass in passes {
            var touched: Set<GridCell> = []
            for point in pass {
                let cell = gridCell(at: MKMapPoint(point.coordinate), step: step)
                touched.insert(cell)
                if point.timestamp > (latest[cell] ?? .distantPast) {
                    latest[cell] = point.timestamp
                }
            }
            for cell in touched {
                counts[cell, default: 0] += 1
            }
        }

        // 하루의 첫 시각을 셈하는 것은 값이 비싸므로, 이미 셈한 날은 다시 셈하지 않는다.
        // 칸은 수만 개라도 날은 기껏해야 몇 백 개다.
        var dayCache: [Date: Date] = [:]

        return counts.map { cell, passes in
            // 통과로 센 칸은 반드시 점이 하나는 있으므로 마지막 때가 비는 일은 없다.
            let visit = latest[cell] ?? .distantPast
            let day: Date
            if let cached = dayCache[visit] {
                day = cached
            } else {
                day = calendar.startOfDay(for: visit)
                dayCache[visit] = day
            }
            return HeatCell(
                // 칸의 한가운데에 점을 찍는다
                center: center(of: cell, step: step),
                passes: passes,
                lastVisit: visit,
                lastVisitDay: day
            )
        }
    }

    /// 지도 좌표를 정사각 격자의 한 칸으로 끊는다
    private static func gridCell(at point: MKMapPoint, step: Double) -> GridCell {
        GridCell(row: Int(floor(point.y / step)), col: Int(floor(point.x / step)))
    }

    /// 칸의 한가운데 좌표
    private static func center(of cell: GridCell, step: Double) -> CLLocationCoordinate2D {
        MKMapPoint(
            x: (Double(cell.col) + 0.5) * step,
            y: (Double(cell.row) + 0.5) * step
        ).coordinate
    }
}

// MARK: - 날마다 하나씩 뽑는 빛깔

/// 그날 걸은 자리에 찍을 원색을 고른다.
///
/// 칸마다 따로 뽑지 않고 날마다 하나만 뽑는다. 칸마다 뽑으면 한 골목이 색종이 조각처럼
/// 어지러워지고, 무엇보다 '언제 걸었는가'라는 뜻이 사라진다. 하루를 한 빛깔로 묶어야
/// 지도 위에서 그날의 걸음이 한 덩어리로 보인다.
enum DotPalette {

    /// 갓 밟았을 때의 채도. 원색이라 부를 만큼은 올리되, 종이 위에서 눈이 아프지 않은 선.
    static let vividSaturation: CGFloat = 0.88

    /// 갓 밟은 점의 밝기. 종이 위에서 원색이 원색답게 보이는 자리.
    static let freshBrightness: (light: CGFloat, dark: CGFloat) = (0.78, 0.95)

    /// 온전히 바랜 점의 밝기. 그 자리에서 채도가 0이 되므로 이 값이 곧 잿빛의 농도다.
    ///
    /// 밝은 종이에서는 어둡게, 어두운 종이에서는 밝게 잡는다. 한쪽에 맞춰 두면
    /// 다른 쪽에서 옛 발자국이 배경에 묻혀 아예 없는 것처럼 보인다.
    static let fadedBrightness: (light: CGFloat, dark: CGFloat) = (0.42, 0.70)

    /// 뽑을 수 있는 빛깔들 (색상환에서의 자리).
    ///
    /// 색상환을 고르게 갈라 놓고 순서를 섞어 두었다. 차례대로 늘어놓으면 이어진 날들이
    /// 빨강·주황·노랑처럼 비슷한 빛을 물려받아 어제와 오늘이 구별되지 않는다.
    static let hues: [CGFloat] = [0.00, 0.55, 0.11, 0.72, 0.33, 0.86, 0.06, 0.47, 0.78, 0.24, 0.63, 0.16]

    /// 그날의 빛깔. 같은 날이면 언제 물어도 같은 값이 나온다.
    ///
    /// 스위프트의 기본 해시는 앱을 켤 때마다 씨앗이 달라진다. 그것으로 뽑으면 어제 파랗던
    /// 동네가 오늘 앱을 다시 켰을 때 노래진다. 그래서 셈을 직접 적는다.
    static func hue(forDay day: Date) -> CGFloat {
        // 날의 첫 시각을 초로 세어 씨앗으로 삼는다. 이웃한 날끼리 멀리 흩어지도록 섞는다.
        var seed = UInt64(bitPattern: Int64(day.timeIntervalSinceReferenceDate.rounded()))
        seed = (seed ^ (seed >> 30)) &* 0xBF58476D1CE4E5B9
        seed = (seed ^ (seed >> 27)) &* 0x94D049BB133111EB
        seed ^= seed >> 31
        return hues[Int(seed % UInt64(hues.count))]
    }

    /// 그날의 빛깔을 바래기 전 그대로. 지도의 갓 찍은 점과 같은 빛이라 글과 지도가 이어진다.
    static func freshColor(forDay day: Date) -> UIColor {
        let hue = hue(forDay: day)
        return UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            return UIColor(
                hue: hue,
                saturation: vividSaturation,
                brightness: dark ? freshBrightness.dark : freshBrightness.light,
                alpha: 1
            )
        }
    }
}

// MARK: - 지도에 올리는 오버레이

/// 한 배율에 맞춰 미리 묶어 둔 점 한 판.
///
/// 판을 여러 벌 두는 까닭이 있다. 점은 10m 칸마다 하나씩 찍히는데, 지도를 물러나서 보면
/// 그 10m가 화면에서 1픽셀도 안 된다. 그런데도 십수만 개를 하나씩 그리면, 눈에는 한 덩어리로
/// 뭉개진 그림 하나가 나오려고 셈은 십수만 번 돈다. 그려 봐야 서로 덮을 뿐인 점들이다.
/// 그래서 물러난 배율에서 쓸 성긴 판을 미리 만들어 두고, 배율에 맞는 판을 골라 쓴다.
///
/// 판 안에서는 점을 버킷 차례로 늘어놓는다. 지도는 화면을 타일로 쪼개어 타일마다 그리라고
/// 시키는데, 판이 뒤죽박죽이면 타일 하나를 그릴 때마다 온 점을 처음부터 훑어야 한다.
/// 버킷으로 묶어 두면 그 타일에 걸치는 묶음만 보면 된다.
struct DotSheet {
    /// 이 판의 점 하나가 대표하는 땅의 한 변 (맵 좌표)
    let cellSize: Double
    /// 버킷 차례대로 늘어놓은 점들
    let dots: [DotGridOverlay.Dot]
    /// 버킷 한 변 (맵 좌표)
    let bucketSize: Double
    /// 버킷 → dots 안에서 그 버킷이 차지하는 구간
    let ranges: [GridCell: Range<Int>]

    /// 버킷 한 변을 칸 몇 개 몫으로 잡을지.
    /// 잘게 쪼개면 사전이 커지고, 크게 잡으면 타일 하나에 딸려 오는 점이 늘어난다.
    static let bucketCells = 64

    init(cellSize: Double, dots source: [DotGridOverlay.Dot]) {
        self.cellSize = cellSize
        let bucketSize = cellSize * Double(Self.bucketCells)
        self.bucketSize = bucketSize

        var byBucket: [GridCell: [DotGridOverlay.Dot]] = [:]
        for dot in source {
            byBucket[Self.bucket(of: dot.point, size: bucketSize), default: []].append(dot)
        }

        var flat: [DotGridOverlay.Dot] = []
        flat.reserveCapacity(source.count)
        var ranges: [GridCell: Range<Int>] = [:]
        ranges.reserveCapacity(byBucket.count)
        for (key, group) in byBucket {
            let start = flat.count
            flat.append(contentsOf: group)
            ranges[key] = start..<flat.count
        }
        self.dots = flat
        self.ranges = ranges
    }

    static func bucket(of point: MKMapPoint, size: Double) -> GridCell {
        GridCell(row: Int(floor(point.y / size)), col: Int(floor(point.x / size)))
    }

    /// 점을 굵은 격자로 묶는다.
    ///
    /// 한 칸에 여럿이 들면 가장 최근에 밟은 것만 남긴다 — 지도의 규칙(나중 날이 앞선 날을
    /// 덮는다)을 성긴 판에서도 그대로 지켜야, 물러나서 봐도 요즘 다닌 자리가 요즘 빛으로 보인다.
    /// 진하기만은 그 칸에서 가장 짙은 것을 따른다. 자주 다닌 길이 성긴 판에서 옅어지면
    /// 물러나서 볼 때 생활 반경이 흐려진다.
    static func merged(_ source: [DotGridOverlay.Dot], into cellSize: Double) -> [DotGridOverlay.Dot] {
        var best: [GridCell: DotGridOverlay.Dot] = [:]
        best.reserveCapacity(source.count / 2)
        for dot in source {
            let key = bucket(of: dot.point, size: cellSize)
            guard let old = best[key] else { best[key] = dot; continue }
            let winner = dot.freshness > old.freshness ? dot : old
            best[key] = DotGridOverlay.Dot(
                point: winner.point,
                heat: max(dot.heat, old.heat),
                hue: winner.hue,
                freshness: winner.freshness
            )
        }
        return Array(best.values)
    }
}

final class DotGridOverlay: NSObject, MKOverlay {
    struct Dot {
        let point: MKMapPoint
        /// 0~1로 누른 진하기 (자주 지난 칸일수록 1에 가깝다)
        let heat: Double
        /// 마지막으로 밟은 날의 빛깔 (색상환에서의 자리, 0~1)
        let hue: CGFloat
        /// 0~1로 누른 싱싱함. 1이면 갓 밟은 자리, 0이면 온전히 바랜 자리.
        let freshness: Double
    }

    /// 촘촘한 판부터 성긴 판까지. 배율에 맞는 것을 골라 쓴다.
    let sheets: [DotSheet]
    /// 칸 한 변의 크기 (맵 좌표)
    let cellMapSize: Double
    let boundingMapRect: MKMapRect
    var coordinate: CLLocationCoordinate2D { boundingMapRect.origin.coordinate }

    /// 화면에서 점이 이만큼(px)은 떨어져 있어야 한다.
    /// 이보다 붙으면 그려 봐야 서로 덮을 뿐이라, 한 판 성긴 것으로 물러난다.
    static let minimumSpacingOnScreen = 2.0

    /// 판을 이보다 적은 점으로 더 줄이지는 않는다. 더 줄여 봐야 아끼는 셈이 얼마 안 된다.
    static let coarsestDotCount = 1_500

    /// - Parameter now: 얼마나 바랬는지 재는 기준 때. 시험할 때만 바꾼다.
    init(cells: [HeatCell], now: Date = .now) {
        // 격자를 끊은 자와 같은 자로 잰다. 다른 자로 재면 점이 칸보다 크거나 작아져
        // 좌우로는 맞붙고 위아래로는 벌어진다.
        cellMapSize = WalkHeatmap.cellMapSize

        // 빛깔은 날마다 하나뿐이라, 칸마다 다시 뽑지 않고 날마다 한 번만 뽑아 나눠 쓴다.
        var hueByDay: [Date: CGFloat] = [:]

        let finest: [Dot] = cells.map { cell in
            let hue: CGFloat
            if let cached = hueByDay[cell.lastVisitDay] {
                hue = cached
            } else {
                hue = DotPalette.hue(forDay: cell.lastVisitDay)
                hueByDay[cell.lastVisitDay] = hue
            }
            return Dot(
                point: MKMapPoint(cell.center),
                heat: min(Double(cell.passes - 1) / Double(WalkHeatmap.hottest - 1), 1),
                hue: hue,
                freshness: WalkHeatmap.freshness(lastVisit: cell.lastVisit, now: now)
            )
        }

        // 한 판 물러날 때마다 칸을 두 배로 넓혀 묶는다. 점이 넉넉히 줄어들 때까지.
        var sheets = [DotSheet(cellSize: cellMapSize, dots: finest)]
        var coarse = finest
        var size = cellMapSize
        while coarse.count > Self.coarsestDotCount {
            size *= 2
            coarse = DotSheet.merged(coarse, into: size)
            sheets.append(DotSheet(cellSize: size, dots: coarse))
        }
        self.sheets = sheets

        if finest.isEmpty {
            boundingMapRect = .world
        } else {
            let xs = finest.map(\.point.x), ys = finest.map(\.point.y)
            let minX = xs.min()!, maxX = xs.max()!
            let minY = ys.min()!, maxY = ys.max()!
            // 점의 굵기만큼 넉넉히 잡아 두어야 가장자리가 잘리지 않는다
            let margin = cellMapSize * 4
            boundingMapRect = MKMapRect(
                x: minX - margin,
                y: minY - margin,
                width: (maxX - minX) + margin * 2,
                height: (maxY - minY) + margin * 2
            )
        }
        super.init()
    }

    /// 이 배율에서 쓸 판. 점이 화면에서 충분히 떨어지는 판 가운데 가장 촘촘한 것을 고른다.
    func sheet(for zoomScale: MKZoomScale) -> DotSheet {
        let scale = Double(zoomScale)
        guard scale > 0, scale.isFinite else { return sheets[sheets.count - 1] }
        for sheet in sheets where sheet.cellSize * scale >= Self.minimumSpacingOnScreen {
            return sheet
        }
        return sheets[sheets.count - 1]
    }
}

final class DotGridRenderer: MKOverlayRenderer {
    private let freshBrightness: CGFloat
    private let fadedBrightness: CGFloat

    // 그리는 중에는 화면 설정을 물어볼 수 없으므로 만들 때 미리 갈라 둔다.
    init(overlay: DotGridOverlay, traits: UITraitCollection) {
        let dark = traits.userInterfaceStyle == .dark
        freshBrightness = dark ? DotPalette.freshBrightness.dark : DotPalette.freshBrightness.light
        fadedBrightness = dark ? DotPalette.fadedBrightness.dark : DotPalette.fadedBrightness.light
        super.init(overlay: overlay)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? DotGridOverlay else { return }
        let scale = Double(zoomScale)
        guard scale > 0, scale.isFinite else { return }

        // 이 배율에 맞는 판을 고른다. 물러날수록 성긴 판이 나와, 그려 봐야 서로 덮을
        // 점들을 아예 들추지 않는다.
        let sheet = overlay.sheet(for: zoomScale)

        // 점 크기는 그 판의 칸 크기를 따라가되, 너무 작아 안 보이거나 너무 커서 뭉치지 않게 자른다
        let cellOnScreen = sheet.cellSize * scale
        let radiusOnScreen = min(max(cellOnScreen * 0.42, 1.6), 9)
        let radius = radiusOnScreen / scale

        // 화면 밖 점은 그리지 않는다
        let visible = mapRect.insetBy(dx: -sheet.cellSize * 4, dy: -sheet.cellSize * 4)
        guard visible.size.width.isFinite, visible.size.height.isFinite else { return }

        for index in indices(of: visible, in: sheet) {
            let dot = sheet.dots[index]
            guard visible.contains(dot.point) else { continue }
            let center = point(for: dot.point)
            let freshness = CGFloat(dot.freshness)

            // 짙기는 두 가지가 함께 정한다 — 얼마나 자주 지났나, 그리고 얼마나 최근인가.
            //
            // 자주 지난 것만 보면 어제 처음 가 본 길이 30%로 흐려져, 원색으로 찍어도
            // 원색으로 보이지 않는다. 갓 밟은 자리는 한 번만 지났어도 또렷해야 한다.
            // 반대로 다 바랜 자리는 자주 다녔더라도 뒤로 물러나야 요즘 걸음이 앞에 선다.
            let alpha = (0.30 + 0.35 * freshness) + 0.35 * CGFloat(dot.heat)
            // 굵기는 지난 횟수만 따른다. 바랜 자리가 가늘어지면 지도에서 아예 지워진 것처럼 보인다.
            let scaleUp = 1.0 + 0.45 * dot.heat

            // 바래는 것은 '색이 빠지는 것'이다. 채도를 0으로 끌면 그 자리가 곧 잿빛이라,
            // 원색과 잿빛을 따로 섞을 것 없이 한 줄로 이어진다.
            let color = UIColor(
                hue: dot.hue,
                saturation: DotPalette.vividSaturation * freshness,
                brightness: fadedBrightness + (freshBrightness - fadedBrightness) * freshness,
                alpha: 1
            )

            context.setFillColor(color.withAlphaComponent(alpha).cgColor)
            let size = radius * scaleUp
            context.fillEllipse(in: CGRect(
                x: center.x - size,
                y: center.y - size,
                width: size * 2,
                height: size * 2
            ))
        }
    }

    /// 이 범위에 걸치는 버킷들이 판에서 차지하는 자리들.
    ///
    /// 지도는 타일마다 그리라고 시킨다. 버킷을 보지 않고 판을 통째로 훑으면 타일 수만큼
    /// 온 점을 되풀이해 훑게 되어, 걸음이 쌓일수록 확대·축소가 무거워진다.
    private func indices(of rect: MKMapRect, in sheet: DotSheet) -> [Int] {
        // 지도 좌표를 벗어난 값이 들어오면 칸 번호를 셈하다 넘칠 수 있어 세상 안으로 자른다.
        let clamped = rect.intersection(.world)
        guard !clamped.isNull, clamped.size.width > 0 else { return [] }

        let minCol = Int(floor(clamped.minX / sheet.bucketSize))
        let maxCol = Int(floor(clamped.maxX / sheet.bucketSize))
        let minRow = Int(floor(clamped.minY / sheet.bucketSize))
        let maxRow = Int(floor(clamped.maxY / sheet.bucketSize))

        var found: [Int] = []
        for col in minCol...maxCol {
            for row in minRow...maxRow {
                guard let range = sheet.ranges[GridCell(row: row, col: col)] else { continue }
                found.append(contentsOf: range)
            }
        }
        return found
    }
}
