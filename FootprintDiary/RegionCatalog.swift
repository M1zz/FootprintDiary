//
//  RegionCatalog.swift
//  FootprintDiary
//
//  도감(수집판)의 기준이 되는 행정구역 목록과, CLPlacemark 값을 그 기준에
//  맞춰 정규화하는 규칙.
//
//  애플이 돌려주는 행정구역 필드는 나라·기기 설정에 따라 계층이 달라진다.
//  (서울은 locality가 "서울특별시"로 오기도 하고 "강남구"로 오기도 한다)
//  그래서 값을 그대로 믿지 않고, 후보들 중 '구/군/시'로 끝나는 것을 골라 쓴다.
//

import Foundation

enum RegionCatalog {

    /// 대한민국 17개 시·도. 도감의 빈칸이 되는 목록이다.
    /// total은 그 아래 시·군·구 수 — 진행도(11/25)의 분모로 쓴다.
    struct Province: Identifiable, Hashable {
        let key: String       // 축약형 (도감 표시용)
        let fullNames: [String] // CLPlacemark가 돌려줄 수 있는 전체 이름들
        let districtTotal: Int  // 시·군·구 수 (세종은 단층이라 0)

        var id: String { key }
    }

    /// 시·군·구 수는 2026년 기준 값이다. 행정구역 개편이 있으면 여기만 고치면 된다.
    static let provinces: [Province] = [
        Province(key: "서울", fullNames: ["서울특별시", "Seoul"], districtTotal: 25),
        Province(key: "부산", fullNames: ["부산광역시", "Busan"], districtTotal: 16),
        Province(key: "대구", fullNames: ["대구광역시", "Daegu"], districtTotal: 9),
        Province(key: "인천", fullNames: ["인천광역시", "Incheon"], districtTotal: 10),
        Province(key: "광주", fullNames: ["광주광역시", "Gwangju"], districtTotal: 5),
        Province(key: "대전", fullNames: ["대전광역시", "Daejeon"], districtTotal: 5),
        Province(key: "울산", fullNames: ["울산광역시", "Ulsan"], districtTotal: 5),
        Province(key: "세종", fullNames: ["세종특별자치시", "세종시", "Sejong"], districtTotal: 0),
        Province(key: "경기", fullNames: ["경기도", "Gyeonggi-do"], districtTotal: 31),
        Province(key: "강원", fullNames: ["강원특별자치도", "강원도", "Gangwon-do"], districtTotal: 18),
        Province(key: "충북", fullNames: ["충청북도", "Chungcheongbuk-do"], districtTotal: 11),
        Province(key: "충남", fullNames: ["충청남도", "Chungcheongnam-do"], districtTotal: 15),
        Province(key: "전북", fullNames: ["전북특별자치도", "전라북도", "Jeollabuk-do"], districtTotal: 14),
        Province(key: "전남", fullNames: ["전라남도", "Jeollanam-do"], districtTotal: 22),
        Province(key: "경북", fullNames: ["경상북도", "Gyeongsangbuk-do"], districtTotal: 22),
        Province(key: "경남", fullNames: ["경상남도", "Gyeongsangnam-do"], districtTotal: 18),
        Province(key: "제주", fullNames: ["제주특별자치도", "제주도", "Jeju-do"], districtTotal: 2)
    ]

    static func province(for key: String) -> Province? {
        provinces.first { $0.key == key }
    }

    /// 시·도 이름을 도감 키(축약형)로 바꾼다. 한국 밖이면 국가명을 그대로 쓴다.
    static func provinceKey(
        administrativeArea: String?,
        isoCountryCode: String?,
        country: String?
    ) -> String? {
        if let code = isoCountryCode, code.uppercased() != "KR" {
            return country ?? code.uppercased()
        }
        guard let area = administrativeArea?.trimmingCharacters(in: .whitespaces), !area.isEmpty else {
            // 국가 코드가 없고 시·도도 없으면 판별 불가
            return country
        }
        if let matched = provinces.first(where: { province in
            province.key == area || province.fullNames.contains(area)
        }) {
            return matched.key
        }
        // 전체 이름이 조금 다르게 와도 앞 두 글자로 맞춰 본다 (예: "강원자치도")
        if let matched = provinces.first(where: { area.hasPrefix($0.key) }) {
            return matched.key
        }
        // 한국이 아닌데 국가 코드가 비어 있는 경우
        if let country, country != "대한민국", country != "South Korea" {
            return country
        }
        return area
    }

    /// 국내 시·도인지 (도감 그리드에 들어가는 칸인지)
    static func isKoreanProvinceKey(_ key: String) -> Bool {
        provinces.contains { $0.key == key }
    }

    /// 시·군·구 후보들 중 실제 시·군·구로 보이는 이름을 고른다.
    /// 읍·면·동(역삼동, 삼평동 …)은 도감 단위가 아니므로 제외한다.
    static func districtName(
        administrativeArea: String?,
        subAdministrativeArea: String?,
        locality: String?,
        subLocality: String?
    ) -> String? {
        let area = administrativeArea?.trimmingCharacters(in: .whitespaces)
        let candidates = [subAdministrativeArea, locality, subLocality]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for candidate in candidates {
            // 시·도 이름 자체(서울특별시 …)는 시·군·구가 아니다
            if candidate == area { continue }
            if provinces.contains(where: { $0.fullNames.contains(candidate) || $0.key == candidate }) { continue }
            if isDistrictName(candidate) { return candidate }
        }
        // 해외 주소는 접미사 규칙이 통하지 않으므로 locality를 그대로 쓴다
        if let locality, !locality.isEmpty, locality != area, !isDongName(locality) {
            return locality
        }
        return nil
    }

    /// "…시 / …군 / …구"로 끝나면 시·군·구로 본다
    static func isDistrictName(_ name: String) -> Bool {
        guard let last = name.last else { return false }
        return last == "시" || last == "군" || last == "구"
    }

    /// "…동 / …읍 / …면 / …리"는 도감 단위가 아니다
    private static func isDongName(_ name: String) -> Bool {
        guard let last = name.last else { return false }
        return last == "동" || last == "읍" || last == "면" || last == "리" || last == "가"
    }
}
