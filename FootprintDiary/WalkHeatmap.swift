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
//  점이 수만 개가 되므로 하나씩 오버레이로 올리지 않고, 오버레이 하나가 한꺼번에 그린다.
//

import Foundation
import MapKit

/// 격자 한 칸
struct HeatCell {
    let center: CLLocationCoordinate2D
    /// 서로 다른 통과 횟수 (한 번의 산책에서 여러 점이 들어와도 1로 센다)
    let passes: Int
    /// 오늘 지난 칸인가
    let isToday: Bool
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

    /// 통과 묶음들을 칸으로 센다.
    /// 한 통과가 같은 칸을 여러 번 밟아도 1로 세야 '몇 번 다닌 길'이 된다.
    static func cells(passes: [[WalkTrail.Point]], today: Date, calendar: Calendar = .current) -> [HeatCell] {
        let step = cellMapSize
        var counts: [GridCell: Int] = [:]
        var todayCells: Set<GridCell> = []

        for pass in passes {
            var touched: Set<GridCell> = []
            for point in pass {
                let cell = gridCell(at: MKMapPoint(point.coordinate), step: step)
                touched.insert(cell)
                if calendar.isDate(point.timestamp, inSameDayAs: today) {
                    todayCells.insert(cell)
                }
            }
            for cell in touched {
                counts[cell, default: 0] += 1
            }
        }

        return counts.map { cell, passes in
            HeatCell(
                // 칸의 한가운데에 점을 찍는다
                center: center(of: cell, step: step),
                passes: passes,
                isToday: todayCells.contains(cell)
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

final class DotGridOverlay: NSObject, MKOverlay {
    struct Dot {
        let point: MKMapPoint
        /// 0~1로 누른 진하기
        let heat: Double
        let isToday: Bool
    }

    let dots: [Dot]
    /// 칸 한 변의 크기 (맵 좌표). 확대 정도에 맞춰 점 크기를 정하는 데 쓴다.
    let cellMapSize: Double
    let boundingMapRect: MKMapRect
    var coordinate: CLLocationCoordinate2D { boundingMapRect.origin.coordinate }

    init(cells: [HeatCell]) {
        // 격자를 끊은 자와 같은 자로 잰다. 다른 자로 재면 점이 칸보다 크거나 작아져
        // 좌우로는 맞붙고 위아래로는 벌어진다.
        cellMapSize = WalkHeatmap.cellMapSize

        dots = cells.map { cell in
            Dot(
                point: MKMapPoint(cell.center),
                heat: min(Double(cell.passes - 1) / Double(WalkHeatmap.hottest - 1), 1),
                isToday: cell.isToday
            )
        }

        if dots.isEmpty {
            boundingMapRect = .world
        } else {
            let xs = dots.map(\.point.x), ys = dots.map(\.point.y)
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
}

final class DotGridRenderer: MKOverlayRenderer {
    /// 미리 뽑아 둔 색 (그리는 중에는 화면 설정을 물어볼 수 없다)
    private let inkColor: UIColor
    private let todayColor: UIColor

    init(overlay: DotGridOverlay, traits: UITraitCollection) {
        inkColor = InkStyle.ink.resolvedColor(with: traits)
        todayColor = InkStyle.vermilion.resolvedColor(with: traits)
        super.init(overlay: overlay)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? DotGridOverlay else { return }

        // 점 크기는 칸 크기를 따라가되, 너무 작아 안 보이거나 너무 커서 뭉치지 않게 자른다
        let cellOnScreen = overlay.cellMapSize * Double(zoomScale)
        let radiusOnScreen = min(max(cellOnScreen * 0.42, 1.6), 9)
        let radius = radiusOnScreen / Double(zoomScale)

        // 화면 밖 점은 그리지 않는다
        let visible = mapRect.insetBy(dx: -overlay.cellMapSize * 4, dy: -overlay.cellMapSize * 4)

        for dot in overlay.dots where visible.contains(dot.point) {
            let center = point(for: dot.point)
            // 자주 지난 칸일수록 짙고 조금 굵게
            let alpha = 0.30 + 0.65 * dot.heat
            let scale = 1.0 + 0.45 * dot.heat
            let color = dot.isToday ? todayColor : inkColor

            context.setFillColor(color.withAlphaComponent(alpha).cgColor)
            let size = radius * scale
            context.fillEllipse(in: CGRect(
                x: center.x - size,
                y: center.y - size,
                width: size * 2,
                height: size * 2
            ))
        }
    }
}
