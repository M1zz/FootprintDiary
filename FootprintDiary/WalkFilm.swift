//
//  WalkFilm.swift
//  FootprintDiary
//
//  걸은 순서대로 지도가 그려지는 것을 한 편의 필름으로 만든다.
//
//  지도는 다 그려 놓고 보면 '어디를 걸었나'만 남는다. 그런데 이 점들에는 반드시 순서가 있다.
//  어느 날 어디서 시작해 어느 쪽으로 뻗어 나갔는지, 어느 골목을 몇 번이나 되짚었는지는
//  순서를 되살려야만 드러난다. 그래서 지도를 완성품이 아니라 '그려지는 과정'으로 보여 준다.
//
//  붓끝은 주묵으로 짙게, 지나온 자리는 먹으로 옅게 남는다. 옛 사람이 지도를 그릴 때
//  지금 붓이 닿은 자리가 가장 진하고 먹이 마른 자리는 가라앉는 것과 같다.
//
//  여기 담은 것은 '그리는 법'뿐이다. 화면에서 미리 보는 것과 내보내는 영상이 이 한 벌을
//  같이 쓴다 — 본 대로 나가야 하기 때문이다.
//

import Foundation
import MapKit
import UIKit

enum WalkFilm {

    // MARK: - 필름에 담을 것

    /// 한 편의 필름.
    struct Reel {
        /// 시간 순으로 늘어놓은 자리들
        let points: [MKMapPoint]
        /// 각 자리를 지난 때 (점과 짝이 맞는다)
        let times: [Date]
        /// 담을 범위
        let rect: MKMapRect
        let start: Date
        let end: Date

        var isEmpty: Bool { points.count < 2 }
    }

    /// 필름에 쓰는 빛깔. 화면에서 쓰는 것을 그대로 가져와야 본 대로 나간다.
    struct Palette {
        let paper: UIColor
        let ink: UIColor
        let vermilion: UIColor
        let water: UIColor
        let hill: UIColor

        init(traits: UITraitCollection) {
            paper = InkStyle.paper.resolvedColor(with: traits)
            ink = InkStyle.ink.resolvedColor(with: traits)
            vermilion = InkStyle.vermilion.resolvedColor(with: traits)
            water = InkStyle.water.resolvedColor(with: traits)
            hill = InkStyle.hill.resolvedColor(with: traits)
        }
    }

    // MARK: - 얼마나 촘촘히, 얼마나 길게

    /// 필름 한 편에 담는 점의 최대 개수.
    ///
    /// 한 해를 걸으면 점이 수만 개가 된다. 그걸 다 찍으면 화면에서 미리 보는 것이 버벅이고
    /// 영상을 내보내는 데도 오래 걸리는데, 정작 눈에 보이는 그림은 달라지지 않는다.
    /// 고르게 솎아 내면 모양은 그대로 두고 셈만 가볍게 할 수 있다.
    static let maxPoints = 4_000

    /// 붓끝으로 볼 점의 비율. 이만큼이 주묵으로 짙게 남는다.
    static let headRatio = 0.03
    /// 붓끝이 아무리 짧아도 이만큼은 된다 (점이 몇 개 없는 날에도 붓끝이 보이도록)
    static let minimumHead = 8

    /// 지나온 자리의 옅기
    static let trailAlpha = 0.34

    // MARK: - 필름 만들기

    /// 저장된 점에서 기간을 잘라 필름을 만든다.
    ///
    /// 그릴 때 다듬는 규칙은 지도와 똑같이 따른다 — 같은 기록인데 지도와 영상의 모양이
    /// 다르면 안 되기 때문이다. (TrackSmoothing 참고)
    static func reel(from track: [TrackPoint], from start: Date, to end: Date) -> Reel {
        let raw = track
            .filter { $0.timestamp >= start && $0.timestamp <= end }
            .filter { $0.horizontalAccuracy <= 0 || $0.horizontalAccuracy <= LocationManager.maxDrawAccuracy }
            .sorted { $0.timestamp < $1.timestamp }
            .map {
                TrackSmoothing.RawPoint(
                    coordinate: $0.coordinate,
                    timestamp: $0.timestamp,
                    accuracy: $0.horizontalAccuracy
                )
            }

        let smoothed = TrackSmoothing.smoothed(raw)
        let thinned = thinning(smoothed, to: maxPoints)
        let points = thinned.map { MKMapPoint($0.coordinate) }

        return Reel(
            points: points,
            times: thinned.map(\.timestamp),
            rect: bounds(of: points),
            start: start,
            end: end
        )
    }

    /// 고르게 솎아 낸다. 앞뒤 끝은 반드시 남긴다 — 시작과 끝이 잘리면 이야기가 어그러진다.
    private static func thinning(
        _ points: [TrackSmoothing.RawPoint],
        to limit: Int
    ) -> [TrackSmoothing.RawPoint] {
        guard points.count > limit, limit > 1 else { return points }
        let step = Double(points.count - 1) / Double(limit - 1)
        return (0..<limit).map { points[Int((Double($0) * step).rounded())] }
    }

    /// 화면을 맞출 때 양 끝에서 이만큼(비율)은 셈에 넣지 않는다.
    ///
    /// 비행기를 타고 다녀왔거나 위치가 한 번 크게 튀면 점 하나 때문에 범위가 대륙을 건너간다.
    /// 그러면 정작 걸어 다닌 동네는 화면에서 점 하나로 쪼그라든다. 양 끝을 조금 잘라 내면
    /// 늘 걷는 자리에 화면이 맞는다. 잘라 낸 점도 그리기는 그린다 — 화면 밖으로 나갈 뿐이다.
    static let framingTrim = 0.02

    /// 점들을 담을 범위. 가장자리에 여백을 둬야 붓끝이 화면 밖에 걸리지 않는다.
    private static func bounds(of points: [MKMapPoint]) -> MKMapRect {
        guard !points.isEmpty else { return .world }

        let trim = min(points.count / 2, max(1, Int(Double(points.count) * framingTrim)))
        let xs = points.map(\.x).sorted()
        let ys = points.map(\.y).sorted()
        let low = trim, high = points.count - 1 - trim
        guard low <= high else { return .world }

        let minX = xs[low], maxX = xs[high]
        let minY = ys[low], maxY = ys[high]

        // 한 자리에만 머문 기록이면 너비가 0이 된다. 그때도 볼 수 있게 최소 크기를 준다.
        let width = max(maxX - minX, 1_000.0)
        let height = max(maxY - minY, 1_000.0)
        let rect = MKMapRect(x: minX, y: minY, width: width, height: height)
        return rect
            .insetBy(dx: -width * 0.12, dy: -height * 0.12)
            .intersection(.world)
    }

    // MARK: - 그리기

    /// 필름 한 칸을 그린다.
    ///
    /// progress는 0에서 1까지. 그만큼의 점이 찍힌 상태를 그린다.
    /// 좌표계는 왼쪽 위가 원점이고 아래로 갈수록 커지는 쪽(UIKit과 같은 방향)을 쓴다.
    static func draw(
        _ reel: Reel,
        terrain: TerrainMask?,
        palette: Palette,
        progress: Double,
        in context: CGContext,
        size: CGSize
    ) {
        let canvas = CGRect(origin: .zero, size: size)
        context.setFillColor(palette.paper.cgColor)
        context.fill(canvas)

        guard !reel.isEmpty, size.width > 0, size.height > 0 else { return }

        let transform = Projection(rect: reel.rect, size: size)

        // 종이에 미리 인쇄된 무늬 — 산을 먼저 깔고 물을 얹는다
        if let terrain {
            if let hills = terrain.hills {
                paint(hills, with: palette.hill, in: transform.rect(for: terrain.hillRect), on: context)
            }
            if let water = terrain.water {
                paint(water, with: palette.water, in: transform.rect(for: terrain.waterRect), on: context)
            }
        }

        let shown = max(1, min(reel.points.count, Int((Double(reel.points.count) * progress).rounded())))
        let head = max(minimumHead, Int(Double(reel.points.count) * headRatio))
        let trailEnd = max(0, shown - head)

        let radius = max(1.4, size.width * 0.0038)

        // 1. 지나온 자리 — 먹으로 옅게
        context.setFillColor(palette.ink.withAlphaComponent(trailAlpha).cgColor)
        for index in 0..<trailEnd {
            let point = transform.point(for: reel.points[index])
            context.fillEllipse(in: CGRect(
                x: point.x - radius, y: point.y - radius,
                width: radius * 2, height: radius * 2
            ))
        }

        // 2. 붓끝 — 주묵으로, 끝으로 갈수록 짙고 굵게
        for index in trailEnd..<shown {
            let along = head > 1 ? Double(index - trailEnd) / Double(head - 1) : 1
            let point = transform.point(for: reel.points[index])
            let size = radius * (1.0 + 1.1 * along)
            context.setFillColor(palette.vermilion.withAlphaComponent(0.45 + 0.55 * along).cgColor)
            context.fillEllipse(in: CGRect(
                x: point.x - size, y: point.y - size,
                width: size * 2, height: size * 2
            ))
        }
    }

    /// 지금 어느 날을 그리고 있는지
    static func caption(_ reel: Reel, progress: Double) -> String {
        guard !reel.isEmpty else { return "" }
        let index = max(0, min(reel.times.count - 1, Int((Double(reel.times.count) * progress).rounded()) - 1))
        return Self.dayFormatter.string(from: reel.times[index])
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일"
        return formatter
    }()

    // MARK: - 거들기

    /// 지도 좌표를 화면 좌표로 옮기는 자.
    /// 가로세로 비율을 지켜 담고 남는 쪽은 가운데로 민다.
    struct Projection {
        let rect: MKMapRect
        let scale: Double
        let offsetX: Double
        let offsetY: Double

        init(rect: MKMapRect, size: CGSize) {
            self.rect = rect
            let scale = min(size.width / rect.size.width, size.height / rect.size.height)
            self.scale = scale
            offsetX = (size.width - rect.size.width * scale) / 2
            offsetY = (size.height - rect.size.height * scale) / 2
        }

        func point(for mapPoint: MKMapPoint) -> CGPoint {
            CGPoint(
                x: offsetX + (mapPoint.x - rect.origin.x) * scale,
                y: offsetY + (mapPoint.y - rect.origin.y) * scale
            )
        }

        func rect(for mapRect: MKMapRect) -> CGRect {
            let origin = point(for: mapRect.origin)
            return CGRect(
                x: origin.x, y: origin.y,
                width: mapRect.size.width * scale,
                height: mapRect.size.height * scale
            )
        }
    }

    /// 스텐실을 제 빛깔로 찍는다. (TerrainRenderer와 같은 규약 — 0인 자리에 칠한다)
    private static func paint(_ stencil: CGImage, with color: UIColor, in target: CGRect, on context: CGContext) {
        guard !target.isEmpty else { return }
        context.saveGState()
        // 이미지는 아래에서 위로 그려진다. 제 범위의 한가운데를 축으로 뒤집어야 바로 선다.
        context.translateBy(x: 0, y: target.maxY + target.minY)
        context.scaleBy(x: 1, y: -1)
        context.clip(to: target, mask: stencil)
        context.setFillColor(color.cgColor)
        context.fill(target)
        context.restoreGState()
    }
}
