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
    /// 카메라로 찍어 넣은 심볼 (없으면 nil). 있으면 종류 그림 대신 이것이 찍힌다.
    let sticker: UIImage?
    /// 그 심볼의 크기(바이트). 심볼이 바뀌었는지 값싸게 견주는 데만 쓴다.
    let stickerBytes: Int
    /// 내가 붙인 이름 (없으면 빈 글). 도장 아래에 적힌다.
    let placeName: String
    /// 끌어서 옮길 수 있어야 하므로 MKAnnotation 규약대로 쓰기 가능해야 한다
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { placeName.isEmpty ? kind.title : placeName }

    init(stamp: MapStamp) {
        // 모델이 지워져도 지도가 흔들리지 않도록 값을 복사해 둔다
        self.id = stamp.persistentModelID
        self.kind = stamp.kind
        self.sticker = stamp.sticker.flatMap(UIImage.init(data:))
        self.stickerBytes = stamp.sticker?.count ?? 0
        self.placeName = stamp.placeName
        self.coordinate = stamp.coordinate
    }
}

/// 낙관처럼 보이는 도장 그림. SF Symbol을 붉은 인장 안에 새긴다.
enum StampSeal {
    static let size = CGSize(width: 30, height: 30)

    /// 카메라로 찍은 심볼이 서는 크기.
    ///
    /// 갈래 도장(30)보다 크다. 저쪽은 붉은 네모 안에 흰 획 하나라 30이면 넉넉히 읽히지만,
    /// 이쪽은 사진에서 떼어 낸 것이라 안에 잔 것이 훨씬 많다. 같은 30에 앉히면 간판의
    /// 글씨도, 사람의 얼굴도 뭉개져 '무언가 찍혀 있다'까지밖에 말하지 못한다.
    ///
    /// 44는 손가락으로 짚을 수 있는 가장 작은 크기이기도 하다. 심볼은 눌러서 그 자리를
    /// 여는 단추이므로, 알아볼 수 있는 크기와 짚을 수 있는 크기가 여기서 만난다.
    /// 더 키우면 스탬프 몇 개만 모여도 서로를 가린다.
    static let stickerSize = CGSize(width: 44, height: 44)

    private static var cache: [String: UIImage] = [:]

    /// 카메라로 찍은 스티커를 도장 크기로 앉힌다.
    ///
    /// 종이도 테두리도 깔지 않는다. 배경이 이미 지워져 있고 흰 테두리를 두르고
    /// 나온 그림이라(StickerMaker), 그대로 얹으면 지도에 붙여 놓은 것처럼 선다.
    /// 네모 종이를 한 겹 깔면 도리어 지도에 창문이 뚫린 것처럼 보인다.
    ///
    /// 그림자만 옅게 깐다. 흰 테두리가 밝은 종이 위에서는 배경과 붙어 보이는데,
    /// 그림자 한 겹이면 떠 있는 것으로 갈린다.
    ///
    /// 갈무리하지 않는다: 스티커는 스탬프마다 다르고, 갈래처럼 몇 백 개를 돌려쓰는
    /// 물건이 아니다.
    static func image(sticker: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        return UIGraphicsImageRenderer(size: stickerSize, format: format).image { ctx in
            ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 0.5),
                                    blur: 2,
                                    color: UIColor.black.withAlphaComponent(0.28).cgColor)
            sticker.draw(in: CGRect(origin: .zero, size: stickerSize))
        }
    }

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

    /// 이름을 붙인 스탬프만 도장 아래에 이름을 단다.
    /// 종류 이름까지 모두 달면 백지 지도가 글씨로 덮인다 — 내가 부르는 이름만 남긴다.
    private let nameLabel = StampNameLabel()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        nameLabel.isUserInteractionEnabled = false
        addSubview(nameLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:)는 쓰지 않는다")
    }

    override var annotation: (any MKAnnotation)? {
        didSet {
            guard let stamp = annotation as? StampAnnotation else { return }
            image = stamp.sticker.map(StampSeal.image(sticker:)) ?? StampSeal.image(for: stamp.kind)
            centerOffset = .zero
            canShowCallout = false
            isDraggable = true
            // 내 위치 점보다 아래에 깔린다. 스탬프가 여러 개 겹쳐도 지금 내가 어디인지는
            // 늘 보여야 한다 — 백지 지도에서는 그것이 유일한 '지금'의 기준이다.
            zPriority = Self.stampPriority

            nameLabel.text = stamp.placeName
            nameLabel.isHidden = stamp.placeName.isEmpty
            setNeedsLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !nameLabel.isHidden else { return }
        let width = bounds.width > 0 ? bounds.width : StampSeal.size.width
        let height = bounds.height > 0 ? bounds.height : StampSeal.size.height
        let fits = nameLabel.sizeThatFits(CGSize(width: StampNameLabel.maxWidth, height: .greatestFiniteMagnitude))
        nameLabel.frame = CGRect(
            x: (width - fits.width) / 2,
            y: height + 2,
            width: fits.width,
            height: fits.height
        )
    }
}

/// 도장 아래에 붙는 이름표. 종이 위에 먹으로 쓴 것처럼 보이게 둔다.
private final class StampNameLabel: UILabel {
    /// 이름이 길어도 지도를 가리지 않도록 여기서 자른다
    static let maxWidth: CGFloat = 96

    private let insets = UIEdgeInsets(top: 2, left: 5, bottom: 2, right: 5)

    override init(frame: CGRect) {
        super.init(frame: frame)
        let base = UIFont.systemFont(ofSize: 10, weight: .semibold)
        font = UIFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: 10)
        textColor = InkStyle.ink
        backgroundColor = InkStyle.paper.withAlphaComponent(0.82)
        textAlignment = .center
        numberOfLines = 1
        lineBreakMode = .byTruncatingTail
        layer.cornerRadius = 4
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:)는 쓰지 않는다")
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let inner = CGSize(width: min(size.width, Self.maxWidth) - insets.left - insets.right, height: size.height)
        let fits = super.sizeThatFits(inner)
        return CGSize(
            width: min(fits.width + insets.left + insets.right, Self.maxWidth),
            height: fits.height + insets.top + insets.bottom
        )
    }
}
