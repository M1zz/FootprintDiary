//
//  SpotFinder.swift
//  FootprintDiary
//
//  [보관] 애플 지도 자연어 검색으로 '탐험할 곳'을 뽑는 규칙.
//
//  앱이 '탐험 일지' 한 화면으로 정리되면서 쓰이지 않는다.
//  지우지 않고 통째로 주석 처리해 둔다 — 되살리려면 아래 주석을 벗기고
//  ContentView에서 다시 연결하면 된다. (동작하던 마지막 상태: 커밋 a0de097)
//

/*
//
//  SpotFinder.swift
//  FootprintDiary
//
//  사진 스팟을 만들어 내는 규칙.
//
//  스팟은 '미끼'다. 매일 가는 자리에 스팟이 있으면 가만히 있어도 모이니까
//  걸을 이유가 생기지 않는다. 그래서 아직 밟지 않은 자리에만, 걸어갈 만한
//  거리에만 만든다.
//
//  장소 후보는 애플 지도의 관심 지점에서 가져온다. 서버 없이 전국이 커버되고,
//  '사람이 갈 수 있는 곳'만 나온다는 게 중요하다.
//

import Foundation
import MapKit
import SwiftData

enum SpotFinder {

    /// 관심 지점을 찾을 반경
    static let searchRadius: CLLocationDistance = 2_000
    /// 너무 가까우면 걸을 이유가 안 되고, 너무 멀면 안 간다
    static let minWalkDistance: CLLocationDistance = 250
    static let maxWalkDistance: CLLocationDistance = 2_000
    /// 스팟끼리 이만큼은 떨어뜨린다
    static let minSpotSpacing: CLLocationDistance = 250
    /// 주변에 유지할 미수집 스팟 수
    static let targetCount = 3

    /// 걸어가서 볼 만한 곳을 찾는 검색어. 앞에 있는 것부터 우선해서 고른다.
    ///
    /// 카테고리 기반 검색(MKLocalPointsOfInterestRequest)은 한국에서 결과를 돌려주지
    /// 않는다(지도 데이터 제약). 자연어 검색은 정상 동작하므로 이쪽을 쓴다.
    static var queries: [String] {
        let isKorean = Locale.current.language.languageCode?.identifier == "ko"
        return isKorean
            ? ["공원", "산책로", "전망대", "카페"]
            : ["park", "trail", "viewpoint", "cafe"]
    }

    struct Candidate {
        let name: String
        let coordinate: CLLocationCoordinate2D
        let category: String?
        /// 검색어 순서 (작을수록 먼저 권한다)
        let priority: Int
    }

    // MARK: - 검색

    static func search(near center: CLLocationCoordinate2D) async -> [Candidate] {
        var found: [Candidate] = []
        var seen = Set<String>()

        // 한꺼번에 여러 건을 던지면 요청이 막히므로 순서대로 부른다
        for (index, query) in queries.enumerated() {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(
                center: center,
                latitudinalMeters: searchRadius * 2,
                longitudinalMeters: searchRadius * 2
            )
            guard let response = try? await MKLocalSearch(request: request).start() else { continue }

            for item in response.mapItems {
                guard let name = item.name, !name.isEmpty else { continue }
                let coordinate = item.placemark.coordinate
                let key = "\(name)|\(round(coordinate.latitude * 10_000))|\(round(coordinate.longitude * 10_000))"
                guard seen.insert(key).inserted else { continue }
                found.append(Candidate(
                    name: name,
                    coordinate: coordinate,
                    category: item.pointOfInterestCategory?.rawValue,
                    priority: index
                ))
            }
        }
        return found
    }

    // MARK: - 채워 넣기

    /// 주변에 갈 곳이 모자라면 새 스팟을 만든다. 만든 개수를 돌려준다.
    @MainActor
    static func replenish(
        near location: CLLocation,
        context: ModelContext
    ) async -> Int {
        let spots = (try? context.fetch(FetchDescriptor<PhotoSpot>())) ?? []
        let pending = spots.filter { !$0.isCollected && $0.distance(from: location) <= maxWalkDistance }
        let missing = targetCount - pending.count
        guard missing > 0 else { return 0 }

        let candidates = await search(near: location.coordinate)
        guard !candidates.isEmpty else { return 0 }

        let visits = (try? context.fetch(FetchDescriptor<Visit>())) ?? []
        let picked = pick(
            missing,
            from: candidates,
            near: location,
            avoiding: spots,
            alreadyWalked: visits
        )

        for candidate in picked {
            context.insert(PhotoSpot(
                latitude: candidate.coordinate.latitude,
                longitude: candidate.coordinate.longitude,
                name: candidate.name,
                category: candidate.category
            ))
        }
        if !picked.isEmpty { try? context.save() }
        return picked.count
    }

    /// 규칙에 맞는 후보를 가까운 순으로 고른다.
    /// 가까운 쪽을 먼저 두는 건, 실제로 갈 확률이 높은 곳부터 주기 위해서다.
    static func pick(
        _ limit: Int,
        from candidates: [Candidate],
        near location: CLLocation,
        avoiding existingSpots: [PhotoSpot],
        alreadyWalked visits: [Visit]
    ) -> [Candidate] {
        var chosen: [Candidate] = []

        // 자연어 검색은 지정한 범위 밖의 결과도 섞어 주므로 거리로 반드시 거른다.
        // 같은 우선순위 안에서는 가까운 곳부터 — 실제로 갈 확률이 높다.
        let sorted = candidates
            .map { ($0, CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)) }
            .filter { _, spotLocation in
                let distance = spotLocation.distance(from: location)
                return distance >= minWalkDistance && distance <= maxWalkDistance
            }
            .sorted { left, right in
                if left.0.priority != right.0.priority { return left.0.priority < right.0.priority }
                return left.1.distance(from: location) < right.1.distance(from: location)
            }

        for (candidate, spotLocation) in sorted {
            guard chosen.count < limit else { break }

            // 이미 밟아 본 자리면 새로울 게 없다
            let alreadyThere = visits.contains {
                $0.distance(latitude: candidate.coordinate.latitude, longitude: candidate.coordinate.longitude)
                < LocationManager.discoveryRadius
            }
            if alreadyThere { continue }

            // 기존 스팟, 그리고 이번에 고른 것들과 겹치지 않게
            let tooClose = existingSpots.contains { spotLocation.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) < minSpotSpacing }
                || chosen.contains { spotLocation.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)) < minSpotSpacing }
            if tooClose { continue }

            chosen.append(candidate)
        }
        return chosen
    }
}
*/
