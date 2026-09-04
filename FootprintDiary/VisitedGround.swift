//
//  VisitedGround.swift
//  FootprintDiary
//
//  내가 밟아 본 땅. 좌표 하나를 놓고 "거기 가 봤는가"에만 답한다.
//
//  지도를 길게 눌러 스탬프를 찍을 때, 그 자리가 내가 걸어 본 자리인지 아니면 아직
//  한 번도 밟지 않은 자리인지를 여기서 가른다. 백지도 위에 '가볼 곳'을 미리 찍어 두는
//  것과 다녀온 자리를 남기는 것은 같은 도장이라도 뜻이 전혀 다르기 때문이다.
//
//  경로 점은 수만 개가 되므로 좌표를 하나씩 맞대지 않는다. 걸은 자리를 격자 칸으로
//  바꿔 한 번 담아 두고, 물을 때는 칸 하나만 들여다본다.
//

import Foundation
import CoreLocation

struct VisitedGround {

    /// 격자 한 칸의 한 변(m).
    ///
    /// 걸은 점 하나는 제가 든 칸과 둘레 여덟 칸을 켜므로, 실제로 덮이는 거리는 그 점이
    /// 칸 안 어디에 앉았느냐에 따라 한 칸에서 두 칸 사이다 — 남북으로 60~120m.
    /// 동서로는 조금 좁다. 격자를 위경도 '각도'로 끊는데 경도 1도의 실제 폭이 고위도로
    /// 갈수록 줄기 때문이다 (서울에서 48~95m). 스탬프가 '거기 있다'고 치는 거리
    /// (MapStamp.visitRadius, 100m)와 얼추 같은 자다.
    ///
    /// 칸을 넉넉히 잡고 둘레까지 켜는 것은 일부러다. 틀린다면 '가 본 곳을 안 가 봤다고
    /// 하는 쪽'이 아니라 '스쳐 지난 곳도 가 봤다고 하는 쪽'으로 틀려야 한다. 내가 걸어
    /// 지나온 골목이 지도에서 '아직 안 가본 곳'으로 서는 것이 훨씬 이상하다.
    static let reachMeters: CLLocationDistance = 60

    /// 걸었거나 머문 자리가 덮은 칸들
    private let cells: Set<GridCell>
    private let step: Double

    /// - Parameters:
    ///   - walked: 걸어서 지나온 점들
    ///   - stayed: 머무름으로 남은 자리들 (걸음이 끊겨도 거기 있었던 것은 맞다)
    init(walked: [CLLocationCoordinate2D] = [], stayed: [CLLocationCoordinate2D] = []) {
        let step = SpatialGrid.step(meters: Self.reachMeters)
        self.step = step

        // 먼저 점이 든 칸만 모은다. 걸은 길은 같은 칸을 수없이 되밟으므로 이 한 번으로
        // 수만 개가 수백 개로 줄고, 둘레를 넓히는 셈은 그 뒤에 한 번만 돌면 된다.
        var core = Set<GridCell>()
        for coordinate in walked {
            core.insert(SpatialGrid.cell(latitude: coordinate.latitude, longitude: coordinate.longitude, step: step))
        }
        for coordinate in stayed {
            core.insert(SpatialGrid.cell(latitude: coordinate.latitude, longitude: coordinate.longitude, step: step))
        }

        var covered = Set<GridCell>(minimumCapacity: core.count * 9)
        for cell in core {
            for row in -1...1 {
                for col in -1...1 {
                    covered.insert(GridCell(row: cell.row + row, col: cell.col + col))
                }
            }
        }
        cells = covered
    }

    /// 아직 한 걸음도 담기지 않았는지.
    ///
    /// 이때는 아무 데도 가 본 적이 없다고 답하게 되는데, 그 답을 그대로 믿으면
    /// 앱을 처음 켠 날 찍는 자리가 죄다 '가볼 곳'이 된다. 부르는 쪽에서 먼저 본다.
    var isEmpty: Bool { cells.isEmpty }

    /// 이 자리를 걸어 본 적이 있는지
    func hasBeen(at coordinate: CLLocationCoordinate2D) -> Bool {
        cells.contains(
            SpatialGrid.cell(latitude: coordinate.latitude, longitude: coordinate.longitude, step: step)
        )
    }
}
