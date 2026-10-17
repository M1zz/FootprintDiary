//
//  Neighborhood.swift
//  FootprintDiary
//
//  내가 걸은 자리로 그린 '내 동네'의 테두리.
//
//  점은 '어디를 지났나'를 말하지만 '내 동네가 어디까지인가'는 말하지 않는다. 골목 몇 줄을
//  걸었을 뿐인데도 사람은 그 사이 블록까지 자기 동네로 여긴다. 그래서 점을 그대로 잇지 않고
//  땅으로 부풀린다.
//
//  1. 걸은 자리마다 둘레 80m(반 블록)를 '아는 땅'으로 친다.
//  2. 아는 땅 사이의 200m 안쪽 틈은 메운다 — 나란히 걸은 두 길 사이의 블록이 여기서 채워진다.
//  3. 그러고도 안쪽에 갇힌 빈자리는 동네 안의 구멍일 뿐이라 메운다.
//  4. 한 번 들렀을 뿐인 작은 자리는 동네라 부르기 어려워 버린다.
//  5. 남은 땅의 바깥 테두리를 따서 매끈하게 다듬는다. 계단진 격자 대신 손으로 그은 경계가 된다.
//
//  테두리는 옛 지도의 경계처럼 점선으로 긋는다. 선 바깥이 아직 모르는 땅이라는 것이 보이면
//  그 선을 넘어가 보고 싶어진다.
//

import MapKit
import UIKit

/// 동네 하나의 테두리
struct NeighborhoodArea {
    let ring: [MKMapPoint]

    /// 테두리 안 넓이(지도 좌표의 제곱). 큰 동네부터 색을 고르는 데만 쓴다.
    var size: Double {
        var sum = 0.0
        for index in ring.indices {
            let a = ring[index], b = ring[(index + 1) % ring.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }
}

enum Neighborhood {

    /// 격자 한 칸(m). 동네 테두리를 뜨기엔 걸음 칸(10m)보다 성겨도 충분하다.
    static let gridMeters: CLLocationDistance = 20
    /// 걸은 자리 둘레로 아는 땅으로 치는 거리(m)
    static let reachMeters: CLLocationDistance = 80
    /// 이보다 좁은 틈은 동네 안으로 메운다(m)
    static let closingMeters: CLLocationDistance = 200
    /// 이보다 좁은 땅은 동네로 치지 않는다(㎡). 골목 한 줄을 한 번 걸은 정도다.
    static let minimumArea: Double = 80_000
    /// 한 덩어리의 격자가 이보다 커지면 칸을 키운다. 도시를 가로질러 걸어도 메모리가 넘치지 않게.
    static let maxGridSide = 1_200

    /// 걸은 자리들로 동네 테두리를 뜬다. 고리 하나가 동네 하나다. 화소를 훑는 일이라 뒤쪽에서 부른다.
    static func outlines(of points: [MKMapPoint]) -> [NeighborhoodArea] {
        guard !points.isEmpty else { return [] }
        return clusters(of: points)
            .flatMap(outlines(ofCluster:))
            .map(NeighborhoodArea.init(ring:))
            // 넓은 동네가 먼저 — 색을 큰 동네부터 차례로 나눠 준다
            .sorted { $0.size > $1.size }
    }

    // MARK: 덩어리 나누기

    /// 서로 멀리 떨어진 걸음은 따로 뜬다. 집 근처와 회사 근처를 한 격자에 담으면 그 사이
    /// 수 km가 통째로 빈 칸이 된다. 다가붙을 수 있는 거리보다 먼 무리끼리는 서로 닿을 일이 없다.
    private static func clusters(of points: [MKMapPoint]) -> [[MKMapPoint]] {
        let perMeter = MKMapPointsPerMeterAtLatitude(points[0].coordinate.latitude)
        // 두 걸음이 한 동네로 붙을 수 있는 가장 먼 거리보다 크게 잡는다
        let bucket = (reachMeters + closingMeters) * 2.2 * perMeter
        var buckets: [Int64: [MKMapPoint]] = [:]
        for point in points {
            buckets[key(Int(point.x / bucket), Int(point.y / bucket)), default: []].append(point)
        }

        var seen = Set<Int64>()
        var result: [[MKMapPoint]] = []
        for start in buckets.keys where !seen.contains(start) {
            var group: [MKMapPoint] = []
            var stack = [start]
            seen.insert(start)
            while let current = stack.popLast() {
                group += buckets[current] ?? []
                let x = Int(current >> 32), y = Int(Int32(truncatingIfNeeded: current))
                for dx in -1...1 {
                    for dy in -1...1 {
                        let next = key(x + dx, y + dy)
                        guard buckets[next] != nil, !seen.contains(next) else { continue }
                        seen.insert(next)
                        stack.append(next)
                    }
                }
            }
            result.append(group)
        }
        return result
    }

    private static func key(_ x: Int, _ y: Int) -> Int64 {
        Int64(x) << 32 | Int64(UInt32(truncatingIfNeeded: y))
    }

    // MARK: 한 덩어리

    private static func outlines(ofCluster points: [MKMapPoint]) -> [[MKMapPoint]] {
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for point in points {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        let perMeter = MKMapPointsPerMeterAtLatitude(MKMapPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2).coordinate.latitude)

        var step = gridMeters * perMeter
        let margin = (reachMeters + closingMeters) * perMeter + step * 3
        let spanX = maxX - minX + margin * 2
        let spanY = maxY - minY + margin * 2
        step = max(step, max(spanX, spanY) / Double(maxGridSide))
        let width = Int((spanX / step).rounded(.up)) + 1
        let height = Int((spanY / step).rounded(.up)) + 1
        let originX = minX - margin, originY = minY - margin
        let stepMeters = step / perMeter

        // 1. 아는 땅 — 걸은 칸마다 동그랗게 찍는다
        let reach = max(1, Int((reachMeters / stepMeters).rounded()))
        var disc: [(Int, Int)] = []
        for dy in -reach...reach {
            for dx in -reach...reach where dx * dx + dy * dy <= reach * reach {
                disc.append((dx, dy))
            }
        }
        var land = [Bool](repeating: false, count: width * height)
        var stamped = Set<Int>()
        for point in points {
            let cx = Int((point.x - originX) / step), cy = Int((point.y - originY) / step)
            guard stamped.insert(cy * width + cx).inserted else { continue }
            for (dx, dy) in disc {
                let x = cx + dx, y = cy + dy
                guard x >= 0, x < width, y >= 0, y < height else { continue }
                land[y * width + x] = true
            }
        }

        // 2. 좁은 틈 메우기 — 부풀렸다가 같은 만큼 깎는다
        let closing = max(1, Int((closingMeters / stepMeters).rounded()))
        let grown = StencilShape.boxCounts(land, width: width, height: height, radius: closing).map { $0 > 0 }
        let grownCounts = StencilShape.boxCounts(grown, width: width, height: height, radius: closing)
        for index in 0..<(width * height) where !land[index] {
            let x = index % width, y = index / width
            let full = span(x, closing, width) * span(y, closing, height)
            if grownCounts[index] == Int32(full) { land[index] = true }
        }

        // 3. 갇힌 빈자리 메우기 — 가장자리에서 닿는 빈자리만 바깥이다
        land = fillingHoles(land, width: width, height: height)

        // 4. 작은 땅 버리기
        let cellArea = stepMeters * stepMeters
        let minimumCells = Int(minimumArea / cellArea)
        land = droppingSmall(land, width: width, height: height, minimumCells: minimumCells)

        // 5. 테두리 따기 → 줄이기 → 다듬기
        return traceLoops(land, width: width, height: height)
            .map { simplified($0, tolerance: 0.9) }
            .filter { $0.count >= 4 }
            .map { smoothed($0, rounds: 3) }
            .map { loop in
                // 격자 칸의 가운데가 그 칸의 자리다
                loop.map { MKMapPoint(x: originX + ($0.x + 0.5) * step, y: originY + ($0.y + 0.5) * step) }
            }
    }

    private static func span(_ position: Int, _ radius: Int, _ limit: Int) -> Int {
        min(position + radius, limit - 1) - max(position - radius, 0) + 1
    }

    private static func fillingHoles(_ land: [Bool], width: Int, height: Int) -> [Bool] {
        var outside = [Bool](repeating: false, count: width * height)
        var stack: [Int] = []
        func visit(_ index: Int) {
            guard !land[index], !outside[index] else { return }
            outside[index] = true
            stack.append(index)
        }
        for x in 0..<width { visit(x); visit((height - 1) * width + x) }
        for y in 0..<height { visit(y * width); visit(y * width + width - 1) }
        while let index = stack.popLast() {
            let x = index % width, y = index / width
            if x > 0 { visit(index - 1) }
            if x < width - 1 { visit(index + 1) }
            if y > 0 { visit(index - width) }
            if y < height - 1 { visit(index + width) }
        }
        return outside.map { !$0 }
    }

    private static func droppingSmall(_ land: [Bool], width: Int, height: Int, minimumCells: Int) -> [Bool] {
        var kept = land
        var visited = [Bool](repeating: false, count: width * height)
        var stack: [Int] = []
        for start in 0..<(width * height) where land[start] && !visited[start] {
            var body: [Int] = []
            visited[start] = true
            stack.append(start)
            while let index = stack.popLast() {
                body.append(index)
                let x = index % width, y = index / width
                for next in [x > 0 ? index - 1 : -1, x < width - 1 ? index + 1 : -1,
                             y > 0 ? index - width : -1, y < height - 1 ? index + width : -1]
                where next >= 0 && land[next] && !visited[next] {
                    visited[next] = true
                    stack.append(next)
                }
            }
            if body.count < minimumCells {
                for index in body { kept[index] = false }
            }
        }
        return kept
    }

    // MARK: 테두리

    /// 칸 네 개가 만나는 모서리마다 땅과 바깥이 갈리는 변을 잇는다(마칭 스퀘어).
    /// 변의 가운데 점을 두 배 좌표(정수)로 적어 두면 이웃 칸과 같은 점이 정확히 맞물린다.
    private static func traceLoops(_ land: [Bool], width: Int, height: Int) -> [[CGPoint]] {
        func at(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && x < width && y >= 0 && y < height && land[y * width + x]
        }
        var links: [Int64: [Int64]] = [:]
        func link(_ a: (Int, Int), _ b: (Int, Int)) {
            let ka = key(a.0, a.1), kb = key(b.0, b.1)
            links[ka, default: []].append(kb)
            links[kb, default: []].append(ka)
        }

        for y in -1..<height {
            for x in -1..<width {
                let tl = at(x, y), tr = at(x + 1, y), br = at(x + 1, y + 1), bl = at(x, y + 1)
                let index = (tl ? 8 : 0) | (tr ? 4 : 0) | (br ? 2 : 0) | (bl ? 1 : 0)
                guard index != 0, index != 15 else { continue }
                // 변의 가운데 (두 배 좌표)
                let top = (2 * x + 1, 2 * y), right = (2 * x + 2, 2 * y + 1)
                let bottom = (2 * x + 1, 2 * y + 2), left = (2 * x, 2 * y + 1)
                switch index {
                case 1, 14: link(left, bottom)
                case 2, 13: link(bottom, right)
                case 3, 12: link(left, right)
                case 4, 11: link(top, right)
                case 6, 9: link(top, bottom)
                case 7, 8: link(left, top)
                case 5: link(left, top); link(bottom, right)
                case 10: link(top, right); link(left, bottom)
                default: break
                }
            }
        }

        var loops: [[CGPoint]] = []
        var used = Set<Int64>()
        for start in links.keys where !used.contains(start) {
            var loop: [CGPoint] = []
            var previous: Int64? = nil
            var current = start
            while !used.contains(current) {
                used.insert(current)
                let x = Int(current >> 32), y = Int(Int32(truncatingIfNeeded: current))
                loop.append(CGPoint(x: Double(x) / 2, y: Double(y) / 2))
                guard let next = links[current]?.first(where: { $0 != previous && !used.contains($0) }) else { break }
                previous = current
                current = next
            }
            if loop.count >= 8 { loops.append(loop) }
        }
        return loops
    }

    /// 닫힌 고리를 더글러스-포이커로 줄인다. 계단 하나하나가 굽이로 남지 않게.
    private static func simplified(_ loop: [CGPoint], tolerance: Double) -> [CGPoint] {
        guard loop.count > 4 else { return loop }
        // 고리를 가장 먼 두 점에서 갈라 두 줄로 줄이고 다시 붙인다
        let first = 0
        var far = 0, farDistance = 0.0
        for (index, point) in loop.enumerated() {
            let distance = hypot(point.x - loop[first].x, point.y - loop[first].y)
            if distance > farDistance { far = index; farDistance = distance }
        }
        let a = Array(loop[first...far])
        let b = Array(loop[far...]) + [loop[first]]
        return Array(reduce(a, tolerance).dropLast()) + Array(reduce(b, tolerance).dropLast())
    }

    private static func reduce(_ line: [CGPoint], _ tolerance: Double) -> [CGPoint] {
        guard line.count > 2, let start = line.first, let end = line.last else { return line }
        let dx = end.x - start.x, dy = end.y - start.y
        let length = max(hypot(dx, dy), 0.0001)
        var worst = 0, worstDistance = 0.0
        for index in 1..<(line.count - 1) {
            let point = line[index]
            let distance = abs(dy * point.x - dx * point.y + end.x * start.y - end.y * start.x) / length
            if distance > worstDistance { worst = index; worstDistance = distance }
        }
        guard worstDistance > tolerance else { return [start, end] }
        let left = reduce(Array(line[...worst]), tolerance)
        let right = reduce(Array(line[worst...]), tolerance)
        return left.dropLast() + right
    }

    /// 모서리를 깎아 둥글린다(차이킨). 한 번 깎을 때마다 각이 반씩 무뎌진다.
    private static func smoothed(_ loop: [CGPoint], rounds: Int) -> [CGPoint] {
        var points = loop
        for _ in 0..<rounds {
            var next: [CGPoint] = []
            next.reserveCapacity(points.count * 2)
            for index in points.indices {
                let p = points[index], q = points[(index + 1) % points.count]
                next.append(CGPoint(x: p.x * 0.75 + q.x * 0.25, y: p.y * 0.75 + q.y * 0.25))
                next.append(CGPoint(x: p.x * 0.25 + q.x * 0.75, y: p.y * 0.25 + q.y * 0.75))
            }
            points = next
        }
        return points
    }
}

// MARK: - 지도에 올리는 것

/// 동네 테두리. MKPolygon으로 올리지 않는 것은 종이(MKPolygon)와 섞이지 않게 하려는 것이다.
final class NeighborhoodOverlay: NSObject, MKOverlay {
    /// 넓은 동네부터 늘어서 있다. 차례가 곧 색의 차례다.
    let rings: [[MKMapPoint]]
    let boundingMapRect: MKMapRect

    init(areas: [NeighborhoodArea]) {
        rings = areas.map(\.ring)
        var rect = MKMapRect.null
        for point in rings.joined() {
            rect = rect.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
        }
        // 선 굵기만큼 넉넉히 — 가장자리 타일에서 선이 잘리지 않게
        boundingMapRect = rect.insetBy(dx: -rect.size.width * 0.02 - 200, dy: -rect.size.height * 0.02 - 200)
        super.init()
    }

    var coordinate: CLLocationCoordinate2D {
        MKMapPoint(x: boundingMapRect.midX, y: boundingMapRect.midY).coordinate
    }
}

/// 동네마다 다른 빛깔의 점선으로 가른다.
///
/// 이름표를 달아 보았지만 지도 위 글씨 상자가 관광 안내판처럼 보였다. 빛깔만으로도
/// '여기와 저기는 다른 동네'는 충분히 읽힌다. 물(파랑)과 도장(주묵)과 헷갈리지 않게
/// 그 둘은 피하고, 종이 위에서 차분한 흙빛·풀빛으로 고른다. 넓은 동네부터 차례로
/// 나눠 주므로, 다닐 때마다 가장 넓은 내 동네는 늘 같은 첫 빛깔이다.
final class NeighborhoodRenderer: MKOverlayRenderer {
    /// (밝은 화면, 어두운 화면)
    static let palette: [(light: UIColor, dark: UIColor)] = [
        (UIColor(red: 0.42, green: 0.55, blue: 0.24, alpha: 1), UIColor(red: 0.62, green: 0.76, blue: 0.42, alpha: 1)), // 쑥
        (UIColor(red: 0.76, green: 0.52, blue: 0.13, alpha: 1), UIColor(red: 0.90, green: 0.70, blue: 0.36, alpha: 1)), // 황토
        (UIColor(red: 0.56, green: 0.31, blue: 0.50, alpha: 1), UIColor(red: 0.78, green: 0.56, blue: 0.72, alpha: 1)), // 자주
        (UIColor(red: 0.18, green: 0.52, blue: 0.47, alpha: 1), UIColor(red: 0.42, green: 0.74, blue: 0.68, alpha: 1)), // 청록
        (UIColor(red: 0.62, green: 0.40, blue: 0.27, alpha: 1), UIColor(red: 0.82, green: 0.62, blue: 0.48, alpha: 1)), // 밤색
        (UIColor(red: 0.40, green: 0.42, blue: 0.50, alpha: 1), UIColor(red: 0.66, green: 0.68, blue: 0.76, alpha: 1))  // 먹
    ]

    private let colors: [UIColor]
    private let halo: UIColor
    private lazy var paths: [CGPath] = {
        guard let overlay = overlay as? NeighborhoodOverlay else { return [] }
        return overlay.rings.map { ring in
            let path = CGMutablePath()
            if ring.count > 2 {
                path.addLines(between: ring.map { point(for: $0) })
                path.closeSubpath()
            }
            return path
        }
    }()

    init(overlay: NeighborhoodOverlay, traits: UITraitCollection) {
        let dark = traits.userInterfaceStyle == .dark
        colors = Self.palette.map { dark ? $0.dark : $0.light }
        halo = InkStyle.paper.resolvedColor(with: traits).withAlphaComponent(0.75)
        super.init(overlay: overlay)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let unit = 1 / zoomScale
        context.setLineJoin(.round)
        context.setLineCap(.round)

        for (index, path) in paths.enumerated() {
            let color = colors[index % colors.count]

            // 안쪽을 그 빛깔로 아주 옅게 — 선 안이 한 동네라는 것이 한눈에 들어오게
            context.addPath(path)
            context.setFillColor(color.withAlphaComponent(0.07).cgColor)
            context.fillPath()

            // 밑에 종이빛 테두리를 깔아 점·그림 위에서도 선이 묻히지 않게
            context.addPath(path)
            context.setLineDash(phase: 0, lengths: [])
            context.setStrokeColor(halo.cgColor)
            context.setLineWidth(6 * unit)
            context.strokePath()

            // 옛 지도의 경계처럼 점선
            context.addPath(path)
            context.setStrokeColor(color.withAlphaComponent(0.9).cgColor)
            context.setLineWidth(2.4 * unit)
            context.setLineDash(phase: 0, lengths: [7 * unit, 5 * unit])
            context.strokePath()
        }
    }
}
