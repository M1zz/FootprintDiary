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
//  걷다 보면 처음 닿는 자리가 생긴다. 그 순간은 지나고 나면 그림에 남지 않으므로,
//  붓끝이 그 자리에 이르는 칸에서 도장을 '탕' 하고 내리찍어 이름을 남긴다.
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
        /// 필름 도중에 찍히는 자리들 (찍히는 차례대로)
        let marks: [Mark]
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
        /// 낙관을 찍는 인주 빛 (도장과 그 테)
        let seal: UIColor

        init(traits: UITraitCollection) {
            paper = InkStyle.paper.resolvedColor(with: traits)
            ink = InkStyle.ink.resolvedColor(with: traits)
            vermilion = InkStyle.vermilion.resolvedColor(with: traits)
            water = InkStyle.water.resolvedColor(with: traits)
            hill = InkStyle.hill.resolvedColor(with: traits)
            seal = InkStyle.sealRed.resolvedColor(with: traits)
        }
    }

    // MARK: - 도중에 찍히는 자리

    /// 필름에 앉히기 전의 자리. 아직 필름 어디쯤에서 찍힐지는 모른다.
    struct Arrival {
        let coordinate: CLLocationCoordinate2D
        /// 도장 밑에 적을 이름
        let name: String
        /// 도장 안에 새길 그림 (SF Symbol)
        let symbolName: String
        /// 그 자리에 처음 닿은 때
        let time: Date
    }

    /// 필름 도중에 '탕' 하고 찍히는 자리.
    ///
    /// 언제 찍힐지를 시각이 아니라 필름의 자리(0~1)로 들고 있는다. 미리보기든 내보내기든
    /// 그리는 쪽은 '지금 어디까지 그렸나'만 알므로, 그 자만으로 셈이 끝나야 둘이 어긋나지 않는다.
    struct Mark {
        let point: MKMapPoint
        let name: String
        let symbolName: String
        /// 필름의 어디쯤에서 찍히는지 (0~1)
        let progress: Double
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
    static func reel(
        from track: [TrackPoint],
        arrivals: [Arrival] = [],
        from start: Date,
        to end: Date
    ) -> Reel {
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
        let times = thinned.map(\.timestamp)
        let rect = bounds(of: points)

        return Reel(
            points: points,
            times: times,
            marks: marks(from: arrivals, times: times, rect: rect),
            rect: rect,
            start: start,
            end: end
        )
    }

    /// 도장이 한꺼번에 쏟아지면 어느 것이 어디 찍혔는지 알 수 없다.
    /// 앞의 도장과 이만큼(필름 길이에 대한 비율)은 사이를 둔다.
    static let markGap = 0.03
    /// 한 편에 찍는 도장의 최대 개수. 이보다 많으면 이름표가 종이를 덮는다.
    static let maxMarks = 18

    /// 자리들을 필름의 어느 칸에 앉힐지 정한다.
    ///
    /// 화면 밖으로 나가는 자리는 버린다 — 찍히는 소리만 나고 아무것도 보이지 않으면
    /// 보는 사람은 무엇을 놓쳤나 싶어 뒤로 감는다.
    private static func marks(from arrivals: [Arrival], times: [Date], rect: MKMapRect) -> [Mark] {
        guard times.count > 1, !arrivals.isEmpty else { return [] }

        let candidates = arrivals
            .sorted { $0.time < $1.time }
            .compactMap { arrival -> Mark? in
                let point = MKMapPoint(arrival.coordinate)
                guard rect.contains(point) else { return nil }
                // 마지막 칸에 걸치면 내리찍다 만 도장으로 끝난다. 다 앉을 만큼은 남겨 둔다.
                let at = min(progress(of: arrival.time, in: times), 1 - strikeSpan)
                return Mark(
                    point: point,
                    name: arrival.name,
                    symbolName: arrival.symbolName,
                    progress: max(0, at)
                )
            }

        var kept: [Mark] = []
        for mark in candidates where mark.progress - (kept.last?.progress ?? -.infinity) >= markGap {
            kept.append(mark)
        }

        guard kept.count > maxMarks else { return kept }
        let step = Double(kept.count - 1) / Double(maxMarks - 1)
        return (0..<maxMarks).map { kept[Int((Double($0) * step).rounded())] }
    }

    /// 이 시각이 필름의 어디쯤인지. 점이 촘촘하므로 이분법으로 짚는다.
    private static func progress(of time: Date, in times: [Date]) -> Double {
        guard let first = times.first, let last = times.last else { return 0 }
        if time <= first { return 0 }
        if time >= last { return 1 }

        var low = 0
        var high = times.count - 1
        while low < high {
            let middle = (low + high) / 2
            if times[middle] < time { low = middle + 1 } else { high = middle }
        }
        // 그리는 쪽은 progress만큼의 점을 앞에서부터 찍는다. 그 점이 찍히는 칸과 맞춘다.
        return Double(low + 1) / Double(times.count)
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

        // 3. 붓끝이 지나온 자리에 찍힌 도장
        stamp(reel, palette: palette, progress: progress, transform: transform, in: context, size: size)
    }

    // MARK: - 도장 찍기

    /// 도장 하나가 다 내리찍히는 데 걸리는 동안 (필름 길이에 대한 비율).
    /// 12초짜리 필름에서 0.6초쯤 — 눈이 따라갈 만하면서 다음 도장을 기다리게 하지 않는 길이다.
    static let strikeSpan = 0.05
    /// 내려오기 시작할 때의 도장 크기 배수. 위에서 떨어지는 것처럼 보이려면 크게 시작해야 한다.
    static let strikeScale = 2.6
    /// 그중 내려앉는 데 쓰는 몫. 나머지는 닿은 자리에 인주가 번지는 테에 쓴다.
    static let strikeDrop = 0.45

    /// 이미 지나온 자리의 도장을 모두 찍는다.
    ///
    /// 한 번 찍힌 도장은 끝까지 남는다 — 다 그린 마지막 칸이 곧 '이름이 다 적힌 내 지도'가 된다.
    private static func stamp(
        _ reel: Reel,
        palette: Palette,
        progress: Double,
        transform: Projection,
        in context: CGContext,
        size: CGSize
    ) {
        let landed = reel.marks.filter { $0.progress <= progress }
        guard !landed.isEmpty else { return }

        let side = max(16, size.width * 0.058)
        /// 이미 이름표가 자리를 잡은 곳. 겹치면 뒤엣것의 이름표를 접는다.
        var taken: [CGRect] = []

        // 글자와 그림은 UIKit 손을 빌린다. 미리보기 쪽은 그릴 자리를 일러 주지 않으므로 손수 밀어 넣는다.
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }

        // 찍힌 차례대로 그리므로 방금 내리찍는 것이 맨 위에 온다
        for mark in landed {
            let center = transform.point(for: mark.point)
            let age = min(1, max(0, (progress - mark.progress) / strikeSpan))
            let drop = min(1, age / strikeDrop)
            // 끝에서 부드럽게 멎는다 — 등속으로 내려오면 도장이 아니라 미끄러지는 그림이 된다
            let landing = 1 - pow(1 - drop, 3)

            if age > strikeDrop {
                let spread = (age - strikeDrop) / (1 - strikeDrop)
                burst(at: center, side: side, spread: spread, palette: palette, in: context)
            }

            seal(
                mark.symbolName,
                at: center,
                side: side * (strikeScale + (1 - strikeScale) * landing),
                glyphSide: side,
                alpha: 0.25 + 0.75 * landing,
                palette: palette,
                in: context
            )

            let nameAlpha = min(1, max(0, (age - strikeDrop) / 0.4))
            guard !mark.name.isEmpty, nameAlpha > 0.02 else { continue }
            label(mark.name, below: center, side: side, alpha: nameAlpha, palette: palette, taken: &taken, size: size)
        }
    }

    /// 닿는 순간 인주가 한 번 번진다. 이 테가 없으면 도장이 그냥 나타난 것처럼 보인다.
    private static func burst(
        at center: CGPoint,
        side: CGFloat,
        spread: Double,
        palette: Palette,
        in context: CGContext
    ) {
        let radius = side * (0.55 + 1.1 * spread)
        context.saveGState()
        context.setStrokeColor(palette.seal.withAlphaComponent(0.5 * (1 - spread)).cgColor)
        context.setLineWidth(max(1, side * 0.07))
        context.strokeEllipse(in: CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        ))
        context.restoreGState()
    }

    /// 낙관 하나. 지도에 찍는 스탬프(StampSeal)와 같은 모양이라 앱 안에서 같은 물건으로 읽힌다.
    private static func seal(
        _ symbolName: String,
        at center: CGPoint,
        side: CGFloat,
        glyphSide: CGFloat,
        alpha: Double,
        palette: Palette,
        in context: CGContext
    ) {
        let box = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        context.saveGState()
        context.setAlpha(alpha)

        let seal = UIBezierPath(roundedRect: box, cornerRadius: side * 0.26)
        palette.seal.setFill()
        seal.fill()
        UIColor.white.withAlphaComponent(0.9).setStroke()
        seal.lineWidth = max(1, side * 0.05)
        seal.stroke()

        // 그림은 앉은 크기로 한 번만 구워 두고, 내려오는 동안에는 늘려 그린다
        if let glyph = glyph(symbolName, pointSize: glyphSide * 0.5) {
            let scale = side / max(glyphSide, 1)
            let width = glyph.size.width * scale
            let height = glyph.size.height * scale
            glyph.draw(in: CGRect(
                x: center.x - width / 2, y: center.y - height / 2,
                width: width, height: height
            ))
        }
        context.restoreGState()
    }

    /// 도장 아래에 붙는 이름표
    private static func label(
        _ text: String,
        below center: CGPoint,
        side: CGFloat,
        alpha: Double,
        palette: Palette,
        taken: inout [CGRect],
        size: CGSize
    ) {
        let fontSize = max(9, side * 0.42)
        let base = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .center

        let line = NSAttributedString(string: text, attributes: [
            .font: UIFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: fontSize),
            .foregroundColor: palette.ink.withAlphaComponent(alpha),
            .paragraphStyle: paragraph
        ])

        // 이름이 길어도 종이의 셋에 하나를 넘지 않는다 — 지도가 글씨에 덮이면 안 된다
        let limit = size.width * 0.34
        let measured = line.boundingRect(
            with: CGSize(width: limit, height: fontSize * 1.6),
            options: [.usesLineFragmentOrigin],
            context: nil
        )
        let padX = fontSize * 0.5
        let padY = fontSize * 0.22
        let width = min(ceil(measured.width), limit) + padX * 2
        let height = ceil(measured.height) + padY * 2

        var box = CGRect(x: center.x - width / 2, y: center.y + side * 0.62, width: width, height: height)
        // 종이 밖으로 걸치면 읽을 수 없으므로 안으로 민다
        box.origin.x = min(max(4, box.origin.x), max(4, size.width - width - 4))

        // 앞서 앉은 이름표와 겹치면 접는다. 도장은 이미 찍혔으니 자리는 남는다.
        guard !taken.contains(where: { $0.intersects(box.insetBy(dx: -2, dy: -2)) }) else { return }
        taken.append(box)

        palette.paper.withAlphaComponent(0.82 * alpha).setFill()
        UIBezierPath(roundedRect: box, cornerRadius: height * 0.32).fill()
        line.draw(
            with: box.insetBy(dx: padX, dy: padY),
            options: [.usesLineFragmentOrigin],
            context: nil
        )
    }

    /// 도장 안에 새길 그림.
    ///
    /// 한 칸마다 새로 만들면 스물넉 장을 굽는 동안 같은 그림을 수백 번 만든다. 미리보기(주 갈래)와
    /// 내보내기(딴 갈래)가 함께 쓰므로, 갈래를 가리지 않는 그릇에 담아 둔다.
    private static let glyphCache = NSCache<NSString, UIImage>()

    private static func glyph(_ symbolName: String, pointSize: CGFloat) -> UIImage? {
        let key = "\(symbolName)@\(Int(pointSize.rounded()))" as NSString
        if let cached = glyphCache.object(forKey: key) { return cached }

        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        guard let image = UIImage(systemName: symbolName, withConfiguration: configuration)?
            .withTintColor(.white, renderingMode: .alwaysOriginal) else { return nil }

        glyphCache.setObject(image, forKey: key)
        return image
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
