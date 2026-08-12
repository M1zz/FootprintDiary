//
//  SpotLandmark.swift
//  FootprintDiary
//
//  스팟마다 다르게 서 있는 3D 랜드마크.
//
//  외부 모델 파일(USDZ)을 쓰지 않고 상자와 구만으로 조립한다.
//  RealityKit이 iOS 17에서 확실히 만들어 주는 도형이 그 둘뿐이고,
//  덕분에 앱 용량도 늘지 않으며 저폴리 느낌이 앱 분위기와도 맞는다.
//

import Foundation
import UIKit

/// 랜드마크 종류. 스팟의 분류와 이름으로 고른다.
enum LandmarkKind: String, CaseIterable {
    case tree       // 공원·숲
    case tower      // 전망대·타워
    case lighthouse // 바다·강가
    case temple     // 박물관·미술관·도서관
    case cup        // 카페·빵집
    case bench      // 산책로·쉼터
    case camera     // 그 외

    /// 지도 마커에도 같은 성격을 쓰기 위한 SF Symbol
    var symbolName: String {
        switch self {
        case .tree: return "tree.fill"
        case .tower: return "binoculars.fill"
        case .lighthouse: return "water.waves"
        case .temple: return "building.columns.fill"
        case .cup: return "cup.and.saucer.fill"
        case .bench: return "figure.walk"
        case .camera: return "camera.fill"
        }
    }

    var title: String {
        switch self {
        case .tree: return "나무"
        case .tower: return "전망대"
        case .lighthouse: return "등대"
        case .temple: return "기둥 건물"
        case .cup: return "찻잔"
        case .bench: return "쉼터"
        case .camera: return "표지물"
        }
    }

    /// 분류를 먼저 보고, 없으면 이름의 낱말로 고른다.
    /// 한국에서는 자연어 검색 결과에 분류가 비어 오는 경우가 많아 이름 쪽이 실제로 더 자주 쓰인다.
    static func of(category: String?, name: String) -> LandmarkKind {
        switch category {
        case "MKPOICategoryPark", "MKPOICategoryNationalPark": return .tree
        case "MKPOICategoryBeach", "MKPOICategoryMarina": return .lighthouse
        case "MKPOICategoryMuseum", "MKPOICategoryLibrary", "MKPOICategoryTheater": return .temple
        case "MKPOICategoryCafe", "MKPOICategoryBakery", "MKPOICategoryRestaurant": return .cup
        case "MKPOICategoryStadium", "MKPOICategoryAmusementPark": return .tower
        default: break
        }

        let keywords: [(LandmarkKind, [String])] = [
            (.tower, ["전망", "타워", "tower", "view", "observ"]),
            (.lighthouse, ["해변", "바다", "등대", "포구", "항", "beach", "harbor", "light"]),
            (.temple, ["박물관", "미술관", "도서관", "기념관", "museum", "librar", "gallery"]),
            (.cup, ["카페", "커피", "베이커리", "cafe", "coffee", "bakery"]),
            (.bench, ["산책", "둘레길", "광장", "쉼터", "trail", "plaza", "walk"]),
            (.tree, ["공원", "숲", "수목원", "정원", "산", "천", "강", "park", "forest", "garden"])
        ]
        let lowered = name.lowercased()
        for (kind, words) in keywords where words.contains(where: { lowered.contains($0) }) {
            return kind
        }
        return .camera
    }
}

extension PhotoSpot {
    var landmarkKind: LandmarkKind {
        LandmarkKind.of(category: category, name: name)
    }
}

// MARK: - 색

/// 랜드마크를 이루는 조각 하나 (상자 또는 구)
struct LandmarkPiece {
    enum Shape {
        case box(SIMD3<Float>)
        case sphere(Float)
    }

    let shape: Shape
    let position: SIMD3<Float>
    let color: UIColor
}

extension LandmarkKind {
    /// 랜드마크를 이루는 조각들. 원점이 바닥, y가 위쪽이다.
    var pieces: [LandmarkPiece] {
        let brown = UIColor(red: 0.45, green: 0.31, blue: 0.19, alpha: 1)
        let green = UIColor(red: 0.24, green: 0.62, blue: 0.32, alpha: 1)
        let deepGreen = UIColor(red: 0.16, green: 0.48, blue: 0.25, alpha: 1)
        let stone = UIColor(white: 0.82, alpha: 1)
        let red = UIColor(red: 0.85, green: 0.26, blue: 0.24, alpha: 1)
        let orange = UIColor.systemOrange
        let cream = UIColor(red: 0.98, green: 0.95, blue: 0.88, alpha: 1)

        switch self {
        case .tree:
            return [
                .init(shape: .box(SIMD3(0.22, 1.2, 0.22)), position: SIMD3(0, 0.6, 0), color: brown),
                .init(shape: .sphere(0.62), position: SIMD3(0, 1.55, 0), color: green),
                .init(shape: .sphere(0.42), position: SIMD3(0.45, 1.2, 0.15), color: deepGreen),
                .init(shape: .sphere(0.38), position: SIMD3(-0.42, 1.3, -0.12), color: deepGreen)
            ]

        case .tower:
            return [
                .init(shape: .box(SIMD3(0.9, 0.9, 0.9)), position: SIMD3(0, 0.45, 0), color: stone),
                .init(shape: .box(SIMD3(0.65, 0.9, 0.65)), position: SIMD3(0, 1.35, 0), color: stone),
                .init(shape: .box(SIMD3(0.45, 0.8, 0.45)), position: SIMD3(0, 2.2, 0), color: cream),
                .init(shape: .box(SIMD3(1.0, 0.16, 1.0)), position: SIMD3(0, 2.65, 0), color: orange),
                .init(shape: .sphere(0.24), position: SIMD3(0, 2.95, 0), color: orange)
            ]

        case .lighthouse:
            return [
                .init(shape: .box(SIMD3(1.0, 0.3, 1.0)), position: SIMD3(0, 0.15, 0), color: stone),
                .init(shape: .box(SIMD3(0.6, 0.7, 0.6)), position: SIMD3(0, 0.65, 0), color: cream),
                .init(shape: .box(SIMD3(0.55, 0.6, 0.55)), position: SIMD3(0, 1.3, 0), color: red),
                .init(shape: .box(SIMD3(0.5, 0.6, 0.5)), position: SIMD3(0, 1.9, 0), color: cream),
                .init(shape: .sphere(0.3), position: SIMD3(0, 2.4, 0), color: UIColor.systemYellow)
            ]

        case .temple:
            let columnHeight: Float = 1.1
            var pieces: [LandmarkPiece] = [
                .init(shape: .box(SIMD3(1.8, 0.22, 1.2)), position: SIMD3(0, 0.11, 0), color: stone)
            ]
            for x in [Float(-0.65), -0.22, 0.22, 0.65] {
                pieces.append(.init(
                    shape: .box(SIMD3(0.18, columnHeight, 0.18)),
                    position: SIMD3(x, 0.22 + columnHeight / 2, 0),
                    color: cream
                ))
            }
            pieces.append(.init(
                shape: .box(SIMD3(2.0, 0.24, 1.4)),
                position: SIMD3(0, 0.22 + columnHeight + 0.12, 0),
                color: stone
            ))
            pieces.append(.init(
                shape: .box(SIMD3(1.5, 0.22, 1.0)),
                position: SIMD3(0, 0.22 + columnHeight + 0.34, 0),
                color: red
            ))
            return pieces

        case .cup:
            return [
                .init(shape: .box(SIMD3(1.1, 0.12, 1.1)), position: SIMD3(0, 0.06, 0), color: cream),
                .init(shape: .box(SIMD3(0.8, 0.7, 0.8)), position: SIMD3(0, 0.47, 0), color: UIColor.white),
                .init(shape: .box(SIMD3(0.16, 0.36, 0.16)), position: SIMD3(0.48, 0.5, 0), color: UIColor.white),
                .init(shape: .box(SIMD3(0.7, 0.08, 0.7)), position: SIMD3(0, 0.83, 0), color: brown),
                .init(shape: .sphere(0.1), position: SIMD3(0.1, 1.05, 0), color: UIColor(white: 1, alpha: 1))
            ]

        case .bench:
            return [
                .init(shape: .box(SIMD3(0.14, 0.42, 0.14)), position: SIMD3(-0.5, 0.21, 0), color: stone),
                .init(shape: .box(SIMD3(0.14, 0.42, 0.14)), position: SIMD3(0.5, 0.21, 0), color: stone),
                .init(shape: .box(SIMD3(1.4, 0.12, 0.5)), position: SIMD3(0, 0.48, 0), color: brown),
                .init(shape: .box(SIMD3(1.4, 0.4, 0.12)), position: SIMD3(0, 0.72, -0.2), color: brown)
            ]

        case .camera:
            return [
                .init(shape: .box(SIMD3(0.2, 1.3, 0.2)), position: SIMD3(0, 0.65, 0), color: stone),
                .init(shape: .box(SIMD3(0.9, 0.6, 0.5)), position: SIMD3(0, 1.6, 0), color: orange),
                .init(shape: .sphere(0.22), position: SIMD3(0, 1.6, 0.3), color: UIColor(white: 0.15, alpha: 1))
            ]
        }
    }
}
