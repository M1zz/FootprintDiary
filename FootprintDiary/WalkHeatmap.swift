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
//  빛깔은 '언제 밟았는가'를 말하되, 묻는 것은 단 하나 — 오늘인가 아닌가.
//  오늘 걸은 자리는 날마다 똑같이 주묵(붉은 먹)이고, 지난 걸음은 모두 남빛이다.
//  그리고 다시 밟지 않은 채 석 달이 지나면 빛이 다 빠져 잿빛이 된다.
//
//  전에는 날마다 빛깔을 하나씩 뽑았다. 알록달록하긴 했지만 어제가 무슨 색이었는지
//  아무도 외우지 못하니, 색이 예쁘기만 하고 아무 말도 하지 않았다. 오늘 하나만 붙박이
//  빛깔로 세워 두면 지도를 펼치는 순간 '오늘 어디를 걸었나'가 색 하나로 바로 읽힌다.
//  나머지 걸음은 한 빛깔로 묶여 '지난 길'이라는 바탕이 되고, 잿빛으로 물러난 자리는
//  발길이 끊긴 지 오래인 곳이다 — 사라지지 않고 '빛바랜 채로' 남는 것이 요점이다.
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
    /// 그날의 첫 시각(자정). 이것이 오늘의 첫 시각과 같은지로 주묵과 남빛이 갈린다.
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

    /// 오늘 밟은 자리인지.
    ///
    /// '얼마나 오래됐나'(freshness)와 따로 묻는다. 오늘 걸은 자리는 바램의 자로 재면
    /// 어제와 거의 붙어 있는데(오늘 1.00, 어제 0.99), 지도를 열고 가장 먼저 찾는 것은
    /// 늘 '오늘 어디를 걸었나'다. 그래서 오늘만은 눈금이 아니라 예/아니오로 갈라
    /// 아예 다른 빛깔(주묵)을 준다.
    ///
    /// 시각이 아니라 '날'로 끊는 것이 중요하다. 스물네 시간으로 재면 어젯밤 걸음이
    /// 오늘 아침까지 오늘 행세를 한다. 자정을 넘기면 지난 걸음이다.
    static func isToday(lastVisitDay: Date, today: Date) -> Bool {
        lastVisitDay >= today
    }

    /// 밟은 자리에서 빛이 다 빠지기까지 두는 시간.
    ///
    /// 석 달이다. 한 철이 지나도록 다시 밟지 않은 길은 이미 생활에서 빠진 길이라,
    /// 잿빛으로 물러나 앉아야 요즘 다니는 길이 도드라진다. 전에는 두 해로 잡았는데
    /// 그러면 웬만한 자리가 죄다 제 빛을 지니고 있어, 바램이 아무 말도 하지 않았다.
    static let fadingSpan: TimeInterval = 60 * 60 * 24 * 90

    /// 0~1로 누른 싱싱함. 1이면 갓 밟은 자리, 0이면 온전히 바랜 자리.
    ///
    /// 곧게 줄인다. 처음에 훅 빠지고 뒤에 오래 끄는 식으로 휘면 '한 달 전에 간 곳'과
    /// '두 달 전에 간 곳'이 둘 다 잿빛으로 뭉개져, 정작 알고 싶은 옛 자리의 앞뒤가 사라진다.
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
///
/// 묶음 안에서는 바랜 점부터 싱싱한 점 차례로 세워 둔다. 늘어놓은 차례가 곧 그리는 차례라,
/// 이렇게 해 두어야 겹치는 자리에서 요즘 걸음이 옛 걸음 위에 온다.
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
            // 바랜 것을 먼저 깔고 싱싱한 것을 위에 얹되, 오늘 걸은 자리는 무조건 맨 위다.
            //
            // 점은 제 칸보다 굵게 그려져 이웃 칸의 점과 겹친다. 늘어놓은 차례가 곧 그리는
            // 차례라, 뒤죽박죽으로 두면 오늘 걸은 자리가 몇 달 전 잿빛 점에 반쯤 덮인다.
            // 자주 지난 칸일수록 점이 굵어지니, 옛날에 자주 다닌 길일수록 더 많이 덮는다.
            // 나중 날이 앞선 날을 덮는다는 규칙은 한 칸 안에서만이 아니라 겹치는 자리에서도
            // 지켜져야 한다.
            //
            // 오늘을 따로 앞세우는 까닭: 어젯밤 늦게 걸은 점과 오늘 새벽에 걸은 점은
            // 싱싱함이 소수점 넷째 자리에서야 갈린다. 그 실낱같은 차이에 오늘의 자리를
            // 맡길 수는 없다.
            flat.append(contentsOf: group.sorted {
                $0.isToday == $1.isToday ? $0.freshness < $1.freshness : !$0.isToday
            })
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
                freshness: winner.freshness,
                isToday: winner.isToday
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
        /// 0~1로 누른 싱싱함. 1이면 갓 밟은 자리, 0이면 온전히 바랜 자리(잿빛).
        let freshness: Double
        /// 오늘 밟은 자리인지. 참이면 주묵, 거짓이면 남빛.
        ///
        /// 싱싱함과 따로 두는 까닭은 재는 자가 다르기 때문이다. 싱싱함은 석 달을 재는
        /// 눈금이라 오늘과 어제가 거의 붙어 있다. 이 앱에서 가장 자주 묻는 물음이
        /// '오늘 어디를 걸었나'인데, 눈금 하나로는 그 답을 그려 낼 수 없다.
        let isToday: Bool
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
    init(cells: [HeatCell], now: Date = .now, calendar: Calendar = .current) {
        // 격자를 끊은 자와 같은 자로 잰다. 다른 자로 재면 점이 칸보다 크거나 작아져
        // 좌우로는 맞붙고 위아래로는 벌어진다.
        cellMapSize = WalkHeatmap.cellMapSize

        let today = calendar.startOfDay(for: now)

        let finest: [Dot] = cells.map { cell in
            Dot(
                point: MKMapPoint(cell.center),
                heat: min(Double(cell.passes - 1) / Double(WalkHeatmap.hottest - 1), 1),
                freshness: WalkHeatmap.freshness(lastVisit: cell.lastVisit, now: now),
                isToday: WalkHeatmap.isToday(lastVisitDay: cell.lastVisitDay, today: today)
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
    private let isDark: Bool

    // 그리는 중에는 화면 설정을 물어볼 수 없으므로 만들 때 미리 갈라 둔다.
    init(overlay: DotGridOverlay, traits: UITraitCollection) {
        isDark = traits.userInterfaceStyle == .dark
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

            // 짙기는 셋이 함께 정한다 — 얼마나 자주 지났나, 얼마나 안 바랬나, 그리고 오늘인가.
            //
            // 오늘 걸은 자리는 아예 꽉 채운다. 마지막 몫이 없으면 오늘 처음 걷는 골목이
            // 지도에서 가장 흐린 점이 된다. 한 번 지난 길이라 진하기의 횟수 몫이 0이고,
            // 석 달을 재는 싱싱함만으로는 오늘과 어제가 갈리지 않기 때문이다. 그러면
            // 반투명한 오늘 점 아래로 옛 점의 빛깔이 비쳐 올라와, 위에 그려 놓고도
            // 묻힌 것처럼 보인다.
            //
            // 겹치는 자리에서 오늘이 맨 위에 서게 하는 것은 이 한 가지면 된다 — 밑이
            // 비치지 않을 만큼 꽉 채우는 것. 굵기까지 건드리면 점끼리 맞물려 띠가 된다.
            //
            // 잿빛으로 다 바랜 자리도 0.45는 남긴다. 더 지우면 옛 동네가 아예 없었던 곳처럼
            // 보이는데, 발길이 끊긴 자리가 '빛바랜 채로' 남는 것이 이 지도의 요점이다.
            let alpha = dot.isToday ? 1 : min(1, 0.45 + 0.35 * freshness + 0.20 * CGFloat(dot.heat))

            // 굵기는 지난 횟수만 따른다.
            //
            // 요즘 걸은 자리라고 굵혀 봤더니 지도가 뭉갰다. 점은 칸 간격의 84%로 그려지는데
            // 1.45배가 되면 지름이 간격의 122%가 되어 이웃 점과 맞물린다. 어제오늘 걸은
            // 자리가 죄다 그렇게 되니 점 하나하나가 아니라 굵은 띠로 보인다.
            // 오늘 걸음을 앞세우는 일은 굵기가 아니라 차례와 진하기가 맡는다.
            // (바랜 자리가 가늘어지지 않아야 하는 것도 그대로다 — 가늘어지면 지워진 것처럼 보인다)
            let scaleUp = 1.0 + 0.45 * dot.heat

            // 오늘이면 주묵, 아니면 남빛. 석 달이 지난 자리는 둘 다 잿빛으로 만난다.
            let color = DotPalette.color(isToday: dot.isToday, freshness: dot.freshness, dark: isDark)

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
