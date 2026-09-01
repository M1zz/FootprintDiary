//
//  ExplorerCompassScreen.swift
//  FootprintDiary
//
//  개척 나침반 — 지금 선 자리에서 어느 쪽이 아직 하얀지 보여 주는 화면.
//
//  지도가 아니다. 지도는 이미 있고, 걸을수록 오히려 답하기 어려워지는 물음이 하나
//  남아 있어서 이 화면이 있다 — 오늘 어느 쪽으로 걸어야 새 자리가 나오는가.
//
//  그래서 여기에는 배경 지도도, 길 이름도, 찍어 둔 자리도 없다. 둥근 판 하나와
//  바늘 하나뿐이다. 판 안의 도형은 내가 걸어서 넓힌 땅의 생김새이고, 바늘은 그 도형이
//  가장 얕게 팬 쪽을 가리킨다. 걸으면 도형이 그쪽으로 자라고 바늘은 다른 데를 가리킨다.
//
//  판은 기기가 보는 쪽을 위로 두고 돈다. 진북을 위에 붙박아 두면 '북서'라는 말을
//  듣고 나서 고개를 들어 북서가 어느 쪽인지 다시 가늠해야 한다. 몸을 돌리면 판이
//  따라 도는 편이 걸음을 내딛기까지 한 단계 짧다. 글자만은 돌지 않고 서 있는다.
//

import SwiftUI
import SwiftData
import CoreLocation

struct ExplorerCompassScreen: View {

    @Query(sort: \TrackPoint.timestamp) private var track: [TrackPoint]
    @Query(sort: \Visit.arrivalDate) private var visits: [Visit]

    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss

    @State private var reading: CompassReading?
    /// 지금 판에 그려진 것이 어느 자리에서 읽은 것인지.
    /// 걸어가는 동안 다시 읽을 때가 되었는지 재는 기준이 된다.
    @State private var readAt: CLLocationCoordinate2D?
    @State private var isReading = false

    /// 이만큼 움직이면 다시 읽는다(m).
    ///
    /// 한 걸음마다 다시 읽으면 바늘이 쉴 새 없이 흔들려 읽을 수가 없고, 아주 가끔
    /// 읽으면 한참 걸어온 뒤에도 아까 그 자리의 답을 들고 있게 된다. 반경이 1.5km라
    /// 200m는 판의 한가운데가 눈에 띄게 옮겨 가는 거리다.
    private static let rereadDistance: CLLocationDistance = 200

    var body: some View {
        NavigationStack {
            ZStack {
                Color(InkStyle.paper).ignoresSafeArea()

                if let reading, !reading.isEmpty {
                    filled(reading)
                } else {
                    hint
                }
            }
            .navigationTitle("개척 나침반")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .onAppear {
            // 방향과 거리를 실시간으로 말해야 하므로 이 화면에 있는 동안만 켠다.
            locationManager.startLiveUpdates()
            locationManager.startHeadingUpdates()
            locationManager.refreshCurrentLocation()
            read(force: true)
            FootprintUsage.log(.compassOpened)
        }
        .onDisappear {
            locationManager.stopHeadingUpdates()
            locationManager.stopLiveUpdates()
        }
        .onChange(of: locationManager.lastKnownLocation) { _, _ in
            read()
        }
    }

    // MARK: - 판

    @ViewBuilder
    private func filled(_ reading: CompassReading) -> some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height * 0.62) - 32

            ScrollView {
                VStack(spacing: 24) {
                    CompassDial(reading: reading, heading: locationManager.heading)
                        .frame(width: side, height: side)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                    verdict(reading)
                    sectorTable(reading)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
    }

    /// 판 아래에 한 문장으로 말해 주는 자리.
    /// 판은 생김새를 보여 주고, 여기서는 그래서 어느 쪽인지를 말한다.
    @ViewBuilder
    private func verdict(_ reading: CompassReading) -> some View {
        VStack(spacing: 10) {
            if let thin = reading.thinnest {
                Text("\(thin.name)쪽이 가장 얕습니다")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(InkStyle.sealRed))

                Text(reachSentence(thin))
                    .font(.subheadline)
                    .foregroundStyle(Color(InkStyle.ink).opacity(0.75))
                    .multilineTextAlignment(.center)
            }

            Divider().padding(.vertical, 2)

            HStack(spacing: 28) {
                figure(
                    title: "둘레 \(distanceText(reading.radius)) 안",
                    value: "\(Int((reading.coverage * 100).rounded()))%",
                    caption: "밟은 자리"
                )
                if let wide = reading.widest, wide.reach > 0 {
                    figure(
                        title: "가장 멀리",
                        value: distanceText(wide.reach),
                        caption: "\(wide.name)쪽"
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(InkStyle.ink).opacity(0.04))
        )
    }

    private func reachSentence(_ sector: CompassSector) -> String {
        if sector.reach < 1 {
            return "그쪽으로는 아직 한 걸음도 나가 보지 않으셨어요."
        }
        return "그쪽으로는 \(distanceText(sector.reach))까지 걸어 보셨습니다. 오늘 더 나가 보시겠어요?"
    }

    private func figure(title: String, value: String, caption: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color(InkStyle.ink).opacity(0.5))
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color(InkStyle.ink))
            Text(caption)
                .font(.caption2)
                .foregroundStyle(Color(InkStyle.ink).opacity(0.5))
        }
        .accessibilityElement(children: .combine)
    }

    /// 여덟 방위를 표로 한 번 더 늘어놓는다.
    ///
    /// 판만으로는 두 방위의 길이 차가 눈에 잘 안 잡히고, 무엇보다 판은 소리 내어
    /// 읽어 줄 수가 없다. 표가 있으면 보이스오버로도 같은 것을 알 수 있다.
    private func sectorTable(_ reading: CompassReading) -> some View {
        VStack(spacing: 0) {
            ForEach(reading.sectors) { sector in
                let isThinnest = sector.index == reading.thinnest?.index

                HStack(spacing: 12) {
                    Text(sector.name)
                        .font(.subheadline.weight(isThinnest ? .semibold : .regular))
                        .foregroundStyle(
                            isThinnest ? Color(InkStyle.sealRed) : Color(InkStyle.ink)
                        )
                        .frame(width: 34, alignment: .leading)

                    // 뻗음을 막대로 한 번 더 보여 준다. 숫자만 있으면 여덟 줄을
                    // 눈으로 견줘야 하는데, 막대는 견주는 일을 눈이 대신 해 준다.
                    GeometryReader { geometry in
                        let longest = max(reading.longestReach, 1)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(InkStyle.ink).opacity(0.08))
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        isThinnest
                                        ? Color(InkStyle.sealRed).opacity(0.65)
                                        : Color(InkStyle.ink).opacity(0.35)
                                    )
                                    .frame(width: geometry.size.width * (sector.reach / longest))
                            }
                    }
                    .frame(height: 6)

                    Text(sector.reach < 1 ? "—" : distanceText(sector.reach))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color(InkStyle.ink).opacity(0.6))
                        .frame(width: 56, alignment: .trailing)

                    Text("\(Int((sector.coverage * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color(InkStyle.ink).opacity(0.4))
                        .frame(width: 38, alignment: .trailing)
                }
                .padding(.vertical, 9)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(sector.name)쪽, "
                    + (sector.reach < 1 ? "걸어 나간 기록 없음" : "\(distanceText(sector.reach))까지, ")
                    + "채움 \(Int((sector.coverage * 100).rounded()))퍼센트"
                )

                if sector.index < reading.sectors.count - 1 {
                    Divider().opacity(0.4)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(InkStyle.ink).opacity(0.04))
        )
    }

    // MARK: - 아직 말할 것이 없을 때

    private var hint: some View {
        VStack(spacing: 14) {
            Image(systemName: "location.north.line")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Color(InkStyle.ink).opacity(0.3))

            Text(hintTitle)
                .font(.headline)
                .foregroundStyle(Color(InkStyle.ink))

            Text(hintBody)
                .font(.subheadline)
                .foregroundStyle(Color(InkStyle.ink).opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private var hintTitle: String {
        locationManager.currentLocation == nil ? "지금 자리를 찾는 중입니다" : "아직 그릴 것이 없습니다"
    }

    private var hintBody: String {
        if locationManager.currentLocation == nil {
            return "나침반은 선 자리를 한가운데 두고 둘레를 읽습니다.\n하늘이 보이는 곳에서 잠깐만 기다려 주세요."
        }
        return "이 나침반은 지금까지 걸으신 자리로 그립니다.\n조금 걸으신 뒤에 다시 열어 보세요."
    }

    // MARK: - 읽기

    /// 지금 자리에서 나침반을 다시 읽는다.
    ///
    /// 칸을 수천 개 훑고 경로 점 전부를 집합으로 만드는 셈이라 화면 바깥에서 한다.
    /// 걷는 중에 여는 화면이라 한 번의 멎음도 손에 그대로 잡힌다.
    private func read(force: Bool = false) {
        guard let location = locationManager.currentLocation else { return }
        guard !isReading else { return }

        if !force, let readAt {
            let previous = CLLocation(latitude: readAt.latitude, longitude: readAt.longitude)
            guard location.distance(from: previous) > Self.rereadDistance else { return }
        }

        // SwiftData 모델은 이 자리에서만 만진다. 좌표만 뽑아 넘기면
        // 셈은 값만 들고 화면 바깥으로 나갈 수 있다.
        let coordinates = track.map(\.coordinate) + visits.map(\.coordinate)
        let center = location.coordinate

        isReading = true
        readAt = center

        Task.detached(priority: .userInitiated) {
            let walked = ExplorerCompass.walkedCells(coordinates)
            let result = ExplorerCompass.read(at: center, walked: walked)
            await MainActor.run {
                reading = result
                isReading = false
            }
        }
    }

    // MARK: - 거들기

    private func distanceText(_ meters: CLLocationDistance) -> String {
        if meters >= 1_000 {
            return String(format: "%.1fkm", meters / 1_000)
        }
        return "\(Int((meters / 10).rounded()) * 10)m"
    }
}

// MARK: - 둥근 판

/// 나침반의 판.
///
/// 그리는 것이 판 하나에 도형 하나, 눈금 몇 줄, 글자 여덟이라 뷰를 여덟 개 쌓는 대신
/// Canvas 하나에 그린다. 판이 돌 때마다 뷰가 새로 배치되지 않아 손가락을 따라오는
/// 것처럼 부드럽다.
private struct CompassDial: View {

    let reading: CompassReading
    /// 기기가 보고 있는 방위. 나침반이 없는 기기(또는 시뮬레이터)에서는 nil.
    let heading: CLLocationDirection?

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            // 글자가 판 바깥에 서므로 그만큼을 남긴다.
            let dial = min(size.width, size.height) / 2 - 22
            // 판을 돌리는 각. 기기가 북동(45도)을 보고 있으면 판을 -45도 돌려
            // 북동이 위로 온다. 나침반이 없으면 진북을 위에 둔다.
            let rotation = -(heading ?? 0)

            drawRings(in: &context, center: center, dial: dial)
            drawCoverage(in: &context, center: center, dial: dial, rotation: rotation)
            drawReach(in: &context, center: center, dial: dial, rotation: rotation)
            drawNeedle(in: &context, center: center, dial: dial, rotation: rotation)
            drawLabels(in: &context, center: center, dial: dial, rotation: rotation)

            // 선 자리
            let dot = CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7)
            context.fill(Path(ellipseIn: dot), with: .color(Color(InkStyle.ink)))
        }
        .accessibilityElement()
        .accessibilityLabel(dialDescription)
    }

    private var dialDescription: String {
        guard let thin = reading.thinnest else { return "개척 나침반" }
        return "개척 나침반. 둘레의 \(Int((reading.coverage * 100).rounded()))퍼센트를 밟으셨고, \(thin.name)쪽이 가장 얕습니다."
    }

    // MARK: 눈금 원

    /// 500m마다 옅은 원을 하나씩. 도형의 크기를 거리로 읽을 수 있게 하는 자다.
    private func drawRings(in context: inout GraphicsContext, center: CGPoint, dial: CGFloat) {
        let ink = Color(InkStyle.ink)
        var ring = 500.0
        while ring <= reading.radius {
            let r = dial * CGFloat(ring / reading.radius)
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            let isOutermost = ring + 1 >= reading.radius
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(ink.opacity(isOutermost ? 0.28 : 0.12)),
                style: StrokeStyle(lineWidth: 1, dash: isOutermost ? [] : [3, 4])
            )
            ring += 500
        }
    }

    // MARK: 채움 부채꼴

    /// 방위마다 '얼마나 촘촘히 훑었나'를 부채꼴의 짙기로 깐다.
    /// 도형(뻗음)보다 뒤에 깔려야 해서 먼저 그린다.
    private func drawCoverage(
        in context: inout GraphicsContext,
        center: CGPoint,
        dial: CGFloat,
        rotation: Double
    ) {
        let width = 360.0 / Double(ExplorerCompass.sectorCount)
        for sector in reading.sectors where sector.coverage > 0 {
            var path = Path()
            path.move(to: center)
            path.addArc(
                center: center,
                radius: dial,
                startAngle: .degrees(sector.bearing - width / 2 + rotation - 90),
                endAngle: .degrees(sector.bearing + width / 2 + rotation - 90),
                clockwise: false
            )
            path.closeSubpath()
            // 다 밟아도 0.3을 넘지 않는다. 이 층은 바탕이고, 눈이 먼저 가야 할 것은
            // 그 위의 도형과 바늘이다.
            //
            // 바닥값을 두지 않는다. 조금이라도 밟았으면 얼마간 칠해 주는 편이 친절해
            // 보이지만, 반경 안 칸이 3500개라 한 칸(0.03%)을 밟아도 부채꼴 하나가
            // 통째로 물든다. 표에는 0%라 적히는데 판은 칠해져 있으면 둘 중 하나는
            // 거짓말이다. 짙기를 채움에 그대로 비례시키면 한 칸은 보이지 않는다.
            context.fill(
                path,
                with: .color(Color(InkStyle.ink).opacity(sector.coverage * 0.30))
            )
        }
    }

    // MARK: 뻗음 도형

    /// 여덟 방위의 뻗음을 이어 만든 도형 — 걸어서 넓힌 땅의 생김새.
    private func drawReach(
        in context: inout GraphicsContext,
        center: CGPoint,
        dial: CGFloat,
        rotation: Double
    ) {
        guard reading.longestReach > 0 else { return }

        var path = Path()
        for (offset, sector) in reading.sectors.enumerated() {
            let r = dial * CGFloat(min(sector.reach / reading.radius, 1))
            let point = pointAt(bearing: sector.bearing, radius: r, center: center, rotation: rotation)
            if offset == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()

        context.fill(path, with: .color(Color(InkStyle.ink).opacity(0.16)))
        context.stroke(
            path,
            with: .color(Color(InkStyle.ink).opacity(0.55)),
            style: StrokeStyle(lineWidth: 1.5, lineJoin: .round)
        )

        // 꼭짓점에 점을 하나씩 찍어 여덟 방위가 어디인지 도형에서도 읽히게 한다.
        for sector in reading.sectors where sector.reach > 0 {
            let r = dial * CGFloat(min(sector.reach / reading.radius, 1))
            let point = pointAt(bearing: sector.bearing, radius: r, center: center, rotation: rotation)
            let rect = CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)
            context.fill(Path(ellipseIn: rect), with: .color(Color(InkStyle.ink).opacity(0.7)))
        }
    }

    // MARK: 바늘

    /// 가장 얕은 방위를 가리키는 바늘.
    ///
    /// 나침반의 바늘은 북을 가리키는 물건이지만, 이 판에서 북은 아무것도 아니다.
    /// 걸어서 답이 바뀌는 것만이 가리킬 값어치가 있다.
    private func drawNeedle(
        in context: inout GraphicsContext,
        center: CGPoint,
        dial: CGFloat,
        rotation: Double
    ) {
        guard let thin = reading.thinnest else { return }

        let tip = pointAt(bearing: thin.bearing, radius: dial * 0.92, center: center, rotation: rotation)
        let base = pointAt(bearing: thin.bearing, radius: dial * 0.16, center: center, rotation: rotation)

        var shaft = Path()
        shaft.move(to: base)
        shaft.addLine(to: tip)
        context.stroke(
            shaft,
            with: .color(Color(InkStyle.sealRed)),
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
        )

        // 화살촉 — 바늘 끝에서 좌우로 벌린 두 점을 이어 삼각형을 만든다.
        let left = pointAt(bearing: thin.bearing - 9, radius: dial * 0.78, center: center, rotation: rotation)
        let right = pointAt(bearing: thin.bearing + 9, radius: dial * 0.78, center: center, rotation: rotation)
        var head = Path()
        head.move(to: tip)
        head.addLine(to: left)
        head.addLine(to: right)
        head.closeSubpath()
        context.fill(head, with: .color(Color(InkStyle.sealRed)))
    }

    // MARK: 방위 이름

    /// 판 바깥에 여덟 이름. 판이 돌아도 글자는 서 있는다 —
    /// 글자까지 같이 돌면 남쪽을 볼 때 '남'이 거꾸로 선다.
    private func drawLabels(
        in context: inout GraphicsContext,
        center: CGPoint,
        dial: CGFloat,
        rotation: Double
    ) {
        for sector in reading.sectors {
            let point = pointAt(bearing: sector.bearing, radius: dial + 14, center: center, rotation: rotation)
            let isNorth = sector.index == 0
            context.draw(
                Text(sector.name)
                    .font(.system(size: isNorth ? 13 : 11, weight: isNorth ? .semibold : .regular))
                    .foregroundStyle(Color(InkStyle.ink).opacity(isNorth ? 0.9 : 0.55)),
                at: point
            )
        }
    }

    /// 방위각과 반지름으로 판 위의 자리를 잡는다.
    /// 화면은 y가 아래로 자라므로 0도(북)가 위에 오려면 90도를 빼야 한다.
    private func pointAt(
        bearing: Double,
        radius: CGFloat,
        center: CGPoint,
        rotation: Double
    ) -> CGPoint {
        let angle = (bearing + rotation - 90) * .pi / 180
        return CGPoint(
            x: center.x + radius * CGFloat(cos(angle)),
            y: center.y + radius * CGFloat(sin(angle))
        )
    }
}
