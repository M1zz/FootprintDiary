//
//  AtlasStampAnnotation.swift
//  FootprintDiary
//
//  지도에 찍는 낙관(스탬프)을 지도 위에 얹는 部分.
//
//  지도 본체(AtlasMap.swift)와 나누어 둔다. 스탬프는 지도가 없어도 뜻이 서는 물건이고,
//  지도는 스탬프가 하나도 없어도 제 몫을 한다. 한 파일에 두면 도장 모양 하나 고치려고
//  지도 그리는 코드를 통째로 열어야 한다.
//

import SwiftUI
import MapKit
import SwiftData

// MARK: - 스탬프

/// 지도에 찍힌 스탬프 하나
final class StampAnnotation: NSObject, MKAnnotation {
    let id: PersistentIdentifier
    let kind: StampKind
    /// 끌어서 옮길 수 있어야 하므로 MKAnnotation 규약대로 쓰기 가능해야 한다
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { kind.title }

    init(stamp: MapStamp) {
        // 모델이 지워져도 지도가 흔들리지 않도록 값을 복사해 둔다
        self.id = stamp.persistentModelID
        self.kind = stamp.kind
        self.coordinate = stamp.coordinate
    }
}

/// 낙관처럼 보이는 도장 그림. SF Symbol을 붉은 인장 안에 새긴다.
enum StampSeal {
    static let size = CGSize(width: 30, height: 30)
    private static var cache: [String: UIImage] = [:]

    static func image(for kind: StampKind) -> UIImage {
        if let cached = cache[kind.id] { return cached }

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            // 옛 도장처럼 모서리가 둥근 네모로 찍는다
            let seal = UIBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: 8)
            InkStyle.sealRed.setFill()
            seal.fill()
            UIColor.white.withAlphaComponent(0.9).setStroke()
            seal.lineWidth = 1.5
            seal.stroke()

            let configuration = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            if let glyph = UIImage(systemName: kind.symbolName, withConfiguration: configuration)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                glyph.draw(in: CGRect(
                    x: (size.width - glyph.size.width) / 2,
                    y: (size.height - glyph.size.height) / 2,
                    width: glyph.size.width,
                    height: glyph.size.height
                ))
            }
        }
        cache[kind.id] = image
        return image
    }
}

final class StampAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "stamp"
    /// 내 위치(.max)보다 낮게 둔다
    static let stampPriority = MKAnnotationViewZPriority(rawValue: 200)

    override var annotation: (any MKAnnotation)? {
        didSet {
            guard let stamp = annotation as? StampAnnotation else { return }
            image = StampSeal.image(for: stamp.kind)
            centerOffset = .zero
            canShowCallout = false
            isDraggable = true
            // 내 위치 점보다 아래에 깔린다. 스탬프가 여러 개 겹쳐도 지금 내가 어디인지는
            // 늘 보여야 한다 — 백지 지도에서는 그것이 유일한 '지금'의 기준이다.
            zPriority = Self.stampPriority
        }
    }
}
