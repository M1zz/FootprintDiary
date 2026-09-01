//
//  ExplorerCompass.swift
//  FootprintDiary
//
//  "지금 서 있는 자리에서, 어느 쪽이 아직 하얀가"를 셈한다.
//
//  지도는 내가 걸은 곳을 보여 준다. 그런데 지도를 아무리 들여다봐도 좀처럼 답하지
//  못하는 물음이 하나 있다 — 오늘 어느 쪽으로 걸어야 새 자리가 나오는가. 걸은 자리가
//  많아질수록 오히려 더 어려워진다. 온 화면이 점으로 덮이면 빈 곳이 눈에 안 들어온다.
//
//  그래서 눈이 아니라 셈에 맡긴다. 지금 자리를 한가운데 두고 둘레를 여덟 방위로 가르고,
//  방위마다 두 가지를 잰다.
//
//  - **채움** — 그 부채꼴 안의 칸 가운데 몇 칸을 밟았는가.
//  - **뻗음** — 그 방위로 가장 멀리까지 걸어 나간 자리가 몇 미터인가.
//
//  둘이 말하는 것이 다르다. 채움은 '얼마나 촘촘히 훑었나'이고, 뻗음은 '얼마나 멀리까지
//  나가 봤나'이다. 집 둘레만 뱅뱅 돈 사람은 채움이 높고 뻗음이 짧다. 한 방향으로 쭉
//  걸어 다녀온 사람은 그 반대다. 여덟 방위의 뻗음을 이으면 도형 하나가 나오는데,
//  그것이 이 사람이 걸어서 넓힌 땅의 생김새다. 남의 것과 같을 수 없다.
//
//  이 셈은 내 지난 기록 전체가 있어야 성립한다. 오늘 처음 켠 앱에서는 아무 말도 하지
//  못하고, 반 년을 걸은 사람의 화면은 반 년어치만큼만 말한다. 그것이 요점이다.
//
//  거리와 방위는 등장방형 근사로 잰다. 반경이 기껏 1.5km라 대권 거리와의 차이가
//  센티미터 단위이고, 칸이 수천 개라 칸마다 CLLocation을 만들면 그 비용이 훨씬 크다.
//

import Foundation
import CoreLocation

// MARK: - 셈의 결과

/// 여덟 방위 가운데 하나
struct CompassSector: Identifiable {

    /// 0이 북, 시계 방향으로 하나씩 (0=북, 1=북동, … 7=북서)
    let index: Int

    /// 부채꼴 한가운데의 방위각(도). 북이 0, 동이 90.
    let bearing: CLLocationDirection

    /// 이 부채꼴 안에 든 칸 수
    let total: Int

    /// 그 가운데 밟은 칸 수
    let walked: Int

    /// 이 방위로 가장 멀리 밟은 자리까지의 거리(m). 한 칸도 없으면 0.
    let reach: CLLocationDistance

    var id: Int { index }

    /// 채움 0…1
    var coverage: Double {
        total == 0 ? 0 : Double(walked) / Double(total)
    }

    var name: String { ExplorerCompass.directionNames[index] }
}

/// 한 자리에서 읽어 낸 나침반 한 장
struct CompassReading {

    /// 이 셈의 한가운데 (읽은 자리)
    let center: CLLocationCoordinate2D

    /// 둘레를 어디까지 봤는지 (m)
    let radius: CLLocationDistance

    /// 북부터 시계 방향으로 여덟 칸
    let sectors: [CompassSector]

    /// 반경 안에서 밟은 칸 수
    let walkedCells: Int

    /// 반경 안의 모든 칸 수
    let totalCells: Int

    /// 반경 안을 얼마나 밟았는가 0…1
    var coverage: Double {
        totalCells == 0 ? 0 : Double(walkedCells) / Double(totalCells)
    }

    /// 나침반이 아직 아무 말도 할 수 없는 상태인지.
    ///
    /// 한 칸도 밟지 않았을 때만이 아니다. 선 자리 한 칸만 밟혀 있을 때도 여덟 방위가
    /// 모두 0이라, 바늘은 어느 쪽이든 가리킬 수 있고 그러면 맨 앞의 북을 가리킨다.
    /// 아무 뜻 없는 바늘은 틀린 바늘보다 나을 것이 없다. 어느 쪽으로든 제 칸 밖으로
    /// 나가 본 기록이 있어야 비로소 견줄 것이 생긴다.
    var isEmpty: Bool { walkedCells == 0 || longestReach == 0 }

    /// 가장 덜 뻗은 방위 — 바늘이 가리키는 쪽.
    ///
    /// 채움이 아니라 뻗음으로 고른다. 채움으로 고르면 강 건너나 산자락처럼 애초에
    /// 걸어 들어갈 수 없는 쪽이 늘 뽑힌다. 아무리 걸어도 답이 바뀌지 않는 안내는
    /// 두 번째부터는 아무도 읽지 않는다. 뻗음은 한 걸음 더 나가면 곧바로 늘어난다.
    var thinnest: CompassSector? {
        sectors.min { lhs, rhs in
            if lhs.reach == rhs.reach { return lhs.index < rhs.index }
            return lhs.reach < rhs.reach
        }
    }

    /// 가장 멀리 뻗은 방위
    var widest: CompassSector? {
        sectors.max { lhs, rhs in
            if lhs.reach == rhs.reach { return lhs.index > rhs.index }
            return lhs.reach < rhs.reach
        }
    }

    /// 도형을 그릴 때 쓰는 자 — 여덟 뻗음 가운데 가장 긴 것.
    /// 0이면 그릴 것이 없다.
    var longestReach: CLLocationDistance {
        sectors.map(\.reach).max() ?? 0
    }
}

// MARK: - 셈

enum ExplorerCompass {

    /// 방위를 여덟으로 가른다.
    ///
    /// 열두 방위로 가르면 '동북동'처럼 입에 붙지 않는 이름이 나오고, 넷으로 가르면
    /// 한 부채꼴이 90도라 '북쪽'이라는 말이 실제로는 북서까지 가리키게 된다.
    /// 여덟이면 이름이 모두 한 낱말이고 부채꼴이 45도다.
    static let sectorCount = 8

    static let directionNames = ["북", "북동", "동", "남동", "남", "남서", "서", "북서"]

    /// 칸 한 변(m).
    ///
    /// 지도에 점을 찍는 칸(10m)보다 훨씬 굵다. 여기서 묻는 것은 '이 자리를 밟았나'가
    /// 아니라 '이 언저리를 지나 봤나'이기 때문이다. 10m로 세면 같은 길을 걸어도
    /// 인도 이쪽과 저쪽이 다른 칸이 되어 채움이 영영 절반을 넘지 못한다.
    static let cellMeters: CLLocationDistance = 50

    /// 둘레를 어디까지 볼지(m).
    ///
    /// 걸어서 다녀올 만한 거리여야 한다. 5km로 잡으면 대부분의 방위가 새하얘서
    /// 어느 쪽이 덜 걸렸는지 가려지지 않고, 500m로 잡으면 늘 다니는 길만 들어와
    /// 여덟 방위가 다 비슷해진다.
    static let radius: CLLocationDistance = 1_500

    /// 위도 1도의 길이(m). 격자 간격을 미터로 되돌릴 때 쓴다.
    private static let metersPerDegree: Double = 111_320

    // MARK: 밟은 칸

    /// 지나온 자리들을 칸 집합으로 바꾼다.
    ///
    /// 경로 점은 12m 간격으로 찍히고 칸은 50m라 이웃한 점 여럿이 한 칸에 겹쳐 든다.
    /// 집합이라 겹쳐도 한 칸으로 남는다.
    static func walkedCells(_ coordinates: [CLLocationCoordinate2D]) -> Set<GridCell> {
        let step = SpatialGrid.step(meters: cellMeters)
        var cells: Set<GridCell> = []
        cells.reserveCapacity(coordinates.count / 4)
        for coordinate in coordinates where coordinate.isUsable {
            cells.insert(
                SpatialGrid.cell(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    step: step
                )
            )
        }
        return cells
    }

    // MARK: 나침반 한 장

    /// 선 자리를 한가운데 두고 여덟 방위를 읽는다.
    ///
    /// - Parameters:
    ///   - center: 읽는 자리 (보통 지금 내 위치)
    ///   - walked: `walkedCells(_:)`로 미리 뽑아 둔 밟은 칸
    static func read(
        at center: CLLocationCoordinate2D,
        walked: Set<GridCell>,
        radius: CLLocationDistance = ExplorerCompass.radius
    ) -> CompassReading {

        let step = SpatialGrid.step(meters: cellMeters)
        let half = step / 2

        // 반경을 덮는 사각형을 훑고 원 밖은 버린다.
        let rowRadius = max(1, Int(ceil(radius / (metersPerDegree * step))))
        let colRadius = SpatialGrid.columnRadius(atLatitude: center.latitude, step: step, meters: radius)
        let originCell = SpatialGrid.cell(latitude: center.latitude, longitude: center.longitude, step: step)

        // 경도 1도의 실제 길이는 위도에 따라 줄어든다. 반경이 1.5km라
        // 그 안에서는 한 번 구해 둔 값을 그대로 써도 어긋나지 않는다.
        let metersPerLonDegree = metersPerDegree * max(cos(center.latitude * .pi / 180), 0.01)

        var totals = [Int](repeating: 0, count: sectorCount)
        var walkeds = [Int](repeating: 0, count: sectorCount)
        var reaches = [CLLocationDistance](repeating: 0, count: sectorCount)
        var totalCells = 0
        var walkedCellCount = 0

        for dRow in -rowRadius...rowRadius {
            for dCol in -colRadius...colRadius {
                let cell = GridCell(row: originCell.row + dRow, col: originCell.col + dCol)

                // 칸의 한가운데로 잰다. 남서 모서리로 재면 온 격자가 한쪽으로 반 칸 쏠린다.
                let cellLat = Double(cell.row) * step + half
                let cellLon = Double(cell.col) * step + half

                let north = (cellLat - center.latitude) * metersPerDegree
                let east = (cellLon - center.longitude) * metersPerLonDegree
                let distance = (north * north + east * east).squareRoot()
                guard distance <= radius else { continue }

                totalCells += 1
                let sector = sectorIndex(north: north, east: east)
                totals[sector] += 1

                guard walked.contains(cell) else { continue }
                walkedCellCount += 1
                walkeds[sector] += 1

                // 서 있는 칸은 뻗음으로 세지 않는다.
                //
                // 칸의 한가운데는 내가 선 자리에서 반 칸쯤 비켜나 있고, 어느 쪽으로
                // 비켜나 있는지는 순전히 격자가 어디서 끊겼느냐에 달렸다. 그대로 두면
                // 정북으로만 걸어온 사람의 판에 난데없이 북서쪽 25m가 돋는다.
                // 걷지 않은 쪽이 0이 아니게 되는 것이라, 작아도 거짓말이다.
                //
                // 거리로 자르지 않고 칸으로 가려낸다. 한가운데가 얼마나 비켜나는지는
                // 반 칸(25m)이 아니라 반 대각선(32m)까지 벌어져서, 거리로 자르면
                // 기준을 32m로 올려야 하고 그러면 바로 옆 칸까지 함께 잘려 나간다.
                guard cell != originCell else { continue }
                if distance > reaches[sector] { reaches[sector] = distance }
            }
        }

        let sectors = (0..<sectorCount).map { index in
            CompassSector(
                index: index,
                bearing: Double(index) * (360.0 / Double(sectorCount)),
                total: totals[index],
                walked: walkeds[index],
                reach: reaches[index]
            )
        }

        return CompassReading(
            center: center,
            radius: radius,
            sectors: sectors,
            walkedCells: walkedCellCount,
            totalCells: totalCells
        )
    }

    /// 한가운데에서 본 방향이 어느 부채꼴에 드는지.
    ///
    /// 북은 -22.5도부터 22.5도까지다. 그래서 반 칸(22.5도)을 미리 더하고 나눈다.
    /// 그러지 않으면 '북'이 북에서 북동까지를 가리키게 되어 이름과 실제가 어긋난다.
    static func sectorIndex(north: Double, east: Double) -> Int {
        let width = 360.0 / Double(sectorCount)
        var bearing = atan2(east, north) * 180 / .pi
        if bearing < 0 { bearing += 360 }
        return Int((bearing + width / 2).truncatingRemainder(dividingBy: 360) / width) % sectorCount
    }
}

// MARK: - 거들기

extension CLLocationCoordinate2D {

    /// 값이 비어 있지 않은지.
    ///
    /// 아이클라우드에서 내려온 옛 기록에 (0, 0)이 섞여 들어오는 일이 있다. 기니만 앞바다에
    /// 칸이 하나 생기는 것으로 끝나지 않고, 그 한 점 때문에 뻗음이 수천 킬로미터가 된다.
    var isUsable: Bool {
        CLLocationCoordinate2DIsValid(self) && !(latitude == 0 && longitude == 0)
    }
}
