//
//  WalkSpots.swift
//  FootprintDiary
//
//  멀리서 보아도 '여기를 걸었다'가 보이게 하는 표지.
//
//  발자국 점은 땅의 크기 그대로 찍힌다. 그래서 나라 하나가 한 화면에 드는 배율로 물러나면
//  여행지에서 걸은 자리가 점 하나보다 작아져 지도에서 사라진다. 다녀온 곳을 찾으려고
//  지도를 펼쳤는데 정작 그곳이 보이지 않는다.
//
//  그래서 멀리 물러났을 때는 걸은 무리마다 발자국 표지를 하나 세운다. 가까이 붙은 표지는
//  MapKit이 하나로 묶어 개수를 적고, 누르면 그 자리로 날아간다. 가까이 들어가면 표지는
//  물러나고 점이 제 모습으로 보인다.
//

import MapKit
import UIKit

/// 걸은 무리 하나
final class WalkSpotAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    /// 이 무리가 덮는 범위. 누르면 여기로 간다.
    let area: MKMapRect

    init(coordinate: CLLocationCoordinate2D, area: MKMapRect) {
        self.coordinate = coordinate
        self.area = area
        super.init()
    }
}

enum WalkSpots {
    /// 이만큼(m) 안에 붙은 걸음은 한 무리로 본다. 한 도시 안에서 걸은 것은 대개 하나로 묶인다.
    static let groupingMeters: CLLocationDistance = 3_000
    /// 화면 1pt가 이보다 넓은 땅(m)을 덮을 만큼 물러나면 표지를 세운다.
    /// 화면 너비로 치면 20km 남짓 — 이때부터 동네 하나가 손톱만 해진다.
    static let showAboveMetersPerPoint: Double = 50

    /// 걸은 칸들을 무리로 묶는다. 칸이 수만 개여도 굵은 격자 하나로 세므로 가볍다.
    static func spots(of points: [MKMapPoint]) -> [WalkSpotAnnotation] {
        guard let first = points.first else { return [] }
        let bucket = groupingMeters * MKMapPointsPerMeterAtLatitude(first.coordinate.latitude)

        struct Bucket { var sumX = 0.0, sumY = 0.0, count = 0, rect = MKMapRect.null }
        var buckets: [Int64: Bucket] = [:]
        for point in points {
            let key = Int64(Int(point.x / bucket)) << 32 | Int64(UInt32(truncatingIfNeeded: Int(point.y / bucket)))
            var entry = buckets[key, default: Bucket()]
            entry.sumX += point.x
            entry.sumY += point.y
            entry.count += 1
            entry.rect = entry.rect.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
            buckets[key] = entry
        }

        // 맞닿은 칸끼리 이어 한 무리로
        var seen = Set<Int64>()
        var result: [WalkSpotAnnotation] = []
        for start in buckets.keys where !seen.contains(start) {
            var group = Bucket()
            var stack = [start]
            seen.insert(start)
            while let key = stack.popLast() {
                guard let entry = buckets[key] else { continue }
                group.sumX += entry.sumX
                group.sumY += entry.sumY
                group.count += entry.count
                group.rect = group.rect.union(entry.rect)
                let x = Int(key >> 32), y = Int(Int32(truncatingIfNeeded: key))
                for dx in -1...1 {
                    for dy in -1...1 {
                        let next = Int64(x + dx) << 32 | Int64(UInt32(truncatingIfNeeded: y + dy))
                        guard buckets[next] != nil, !seen.contains(next) else { continue }
                        seen.insert(next)
                        stack.append(next)
                    }
                }
            }
            // 가운데에 가장 가까운 '걸은 자리'가 아니라 무게중심에 세운다 — 멀리서 보는 표지라 충분하다
            let center = MKMapPoint(x: group.sumX / Double(group.count), y: group.sumY / Double(group.count))
            result.append(WalkSpotAnnotation(coordinate: center.coordinate, area: group.rect))
        }
        return result
    }
}

/// 발자국 표지. 무리가 여럿 묶이면 개수를 함께 적는다.
final class WalkSpotView: MKAnnotationView {
    static let reuseIdentifier = "walkSpot"
    static let clusterIdentifier = "walkSpots"
    /// 도장(200)보다 아래 — 멀리서도 도장이 먼저 보이게
    static let spotPriority = MKAnnotationViewZPriority(rawValue: 150)
    static let side: CGFloat = 30

    private let badge = UILabel()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: Self.side, height: Self.side)
        badge.font = .preferredFont(forTextStyle: .body).withWeight(.bold)
        badge.textColor = .white
        badge.textAlignment = .center
        badge.layer.masksToBounds = true
        addSubview(badge)
        canShowCallout = false
        zPriority = Self.spotPriority
        displayPriority = .required
        collisionMode = .circle
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:)는 쓰지 않는다")
    }

    override var annotation: (any MKAnnotation)? {
        didSet { refresh() }
    }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        refresh()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        refresh()
    }

    private func refresh() {
        let count = (annotation as? MKClusterAnnotation)?.memberAnnotations.count ?? 1
        // 묶인 표지는 위로 겹쳐 쌓이지 않게 묶음 이름을 비운다
        clusteringIdentifier = annotation is MKClusterAnnotation ? nil : Self.clusterIdentifier
        image = Self.image(traits: traitCollection)
        accessibilityLabel = count > 1 ? String(localized: "걸은 곳 \(count)군데") : String(localized: "걸은 곳")
        isAccessibilityElement = true

        badge.isHidden = count < 2
        guard count > 1 else { return }
        badge.text = "\(count)"
        let fits = badge.sizeThatFits(CGSize(width: 80, height: 40))
        let height = fits.height + 2
        let width = max(height, fits.width + 10)
        badge.frame = CGRect(x: Self.side - width * 0.6, y: -height * 0.35, width: width, height: height)
        badge.layer.cornerRadius = height / 2
        badge.backgroundColor = InkStyle.sealRed.resolvedColor(with: traitCollection)
    }

    private static var cache: [Bool: UIImage] = [:]

    /// 남빛 동그라미에 흰 발자국. 지난 걸음의 빛깔(남빛)과 같아 '내 발자국'으로 읽힌다.
    static func image(traits: UITraitCollection) -> UIImage {
        let dark = traits.userInterfaceStyle == .dark
        if let image = cache[dark] { return image }
        let size = CGSize(width: side, height: side)
        let image = UIGraphicsImageRenderer(size: size).image { renderer in
            let context = renderer.cgContext
            let circle = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
            context.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: UIColor.black.withAlphaComponent(0.3).cgColor)
            DotPalette.past.resolvedColor(with: traits).setFill()
            UIBezierPath(ovalIn: circle).fill()
            context.setShadow(offset: .zero, blur: 0)
            UIColor.white.setStroke()
            let ring = UIBezierPath(ovalIn: circle.insetBy(dx: 1, dy: 1))
            ring.lineWidth = 2
            ring.stroke()
            let symbol = UIImage(
                systemName: "shoeprints.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
            )?.withTintColor(.white, renderingMode: .alwaysOriginal)
            if let symbol {
                symbol.draw(at: CGPoint(x: (size.width - symbol.size.width) / 2, y: (size.height - symbol.size.height) / 2))
            }
        }
        cache[dark] = image
        return image
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        UIFont.systemFont(ofSize: pointSize, weight: weight)
    }
}
