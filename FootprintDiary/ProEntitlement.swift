//
//  ProEntitlement.swift
//  FootprintDiary
//
//  벅뚜벅뚜의 어느 칸(무료 · Plus · Pro)을 쓰는가. 칸마다 무엇이 열리는지는 여기 한 곳에만 적는다.
//
//   · 무료: 걸음 기록 · 지도 · 일기 · 달력 · 오늘의 발자취 · 기간 보기(주 · 달 · 해) · iCloud 보관,
//           도장 30곳, 필름 미리보기, 기록 내보내기(GPX · CSV).
//   · Plus: 도장 제한 없음, 간판 스티커 카메라, 그림지도, 기간 직접 정하기.
//   · Pro:  Plus 전부 + 홈 화면 · 잠금화면 위젯, 필름 영상 내보내기, 개척 나침반.
//
//  ⚠️ 이미 만든 것은 어떤 칸에서도 잠그거나 지우지 않는다. 한도는 **새로 찍는 도장**만 본다.
//     서른 곳을 넘은 옛 도장 · 붙여 둔 스티커는 그대로 보이고 쓰인다.
//  ⚠️ iCloud 보관은 무료다. 칸에 따라 저장소를 켜고 끄면 다시 만들 수 없는 걸음 기록이 사라질 수 있다.
//  ⚠️ 팁은 권한이 아니다. 팁 상품을 `tierByProduct` 에 넣지 않는다.
//
//  StoreKit 은 여기 없다. 영수증 확인은 `PurchaseManager` 가 하고 그 결과를 여기 한 줄로 적는다.
//

import Foundation

/// 칸. 값이 클수록 더 많이 연다. Pro 는 Plus 를 전부 포함한다.
enum ProTier: Int, Comparable, CaseIterable {
    case free = 0
    case plus = 1
    case pro = 2

    static func < (lhs: ProTier, rhs: ProTier) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .free: String(localized: "무료")
        case .plus: String(localized: "벅뚜벅뚜 Plus")
        case .pro:  String(localized: "벅뚜벅뚜 Pro")
        }
    }

    /// 페이월 카드의 한 줄.
    var tagline: String {
        switch self {
        case .free: String(localized: "걸어서 그리는 내 지도와 일기, 기간 제한 없이 무료.")
        case .plus: String(localized: "내 지도를 내 취향대로")
        case .pro:  String(localized: "매일 보고, 자랑하고, 더 멀리")
        }
    }
}

/// 값을 받고 여는 것. 페이월 카드와 잠긴 자리가 이 목록 하나를 함께 읽는다.
enum ProFeature: String, CaseIterable, Identifiable {
    case unlimitedStamps
    case stickerCamera
    case pictureMap
    case customPeriod
    case widgets
    case filmExport
    case compass

    var id: String { rawValue }

    /// 이 기능을 여는 가장 낮은 칸.
    var tier: ProTier {
        switch self {
        case .unlimitedStamps, .stickerCamera, .pictureMap, .customPeriod: .plus
        case .widgets, .filmExport, .compass: .pro
        }
    }

    /// 그 칸에서 새로 열리는 것 (페이월 카드 차례).
    static func opened(by tier: ProTier) -> [ProFeature] { allCases.filter { $0.tier == tier } }

    var title: String {
        switch self {
        case .unlimitedStamps: String(localized: "도장 제한 없음")
        case .stickerCamera:   String(localized: "간판 스티커 카메라")
        case .pictureMap:      String(localized: "그림지도")
        case .customPeriod:    String(localized: "기간 직접 정하기")
        case .widgets:         String(localized: "홈 화면 · 잠금화면 위젯")
        case .filmExport:      String(localized: "필름 영상 내보내기")
        case .compass:         String(localized: "개척 나침반")
        }
    }

    var note: String {
        switch self {
        case .unlimitedStamps: String(localized: "가본 곳 · 가볼 곳을 서른 곳 넘게, 마음껏 찍어요.")
        case .stickerCamera:   String(localized: "단골 가게 간판을 찍어 그 자리만의 도장으로 남겨요.")
        case .pictureMap:      String(localized: "산 · 숲 · 물이 그림으로 그려진 지도로 바꿔 봐요.")
        case .customPeriod:    String(localized: "여행 간 사흘처럼 원하는 날짜만 골라 지도를 봐요.")
        case .widgets:         String(localized: "앱을 열지 않아도 오늘 그은 길이 보여요.")
        case .filmExport:      String(localized: "백지에서 내 동네가 채워지는 영상을 친구에게 보내요.")
        case .compass:         String(localized: "덜 걸은 방향을 가리켜 오늘 갈 길을 골라 줘요.")
        }
    }

    var systemImage: String {
        switch self {
        case .unlimitedStamps: "seal.fill"
        case .stickerCamera:   "camera.viewfinder"
        case .pictureMap:      "mountain.2.fill"
        case .customPeriod:    "calendar.badge.clock"
        case .widgets:         "apps.iphone"
        case .filmExport:      "film"
        case .compass:         "location.north.line"
        }
    }
}

enum ProEntitlement {

    // MARK: - 무료 한도

    /// 무료로 찍을 수 있는 도장 수 (가본 곳 · 가볼 곳을 함께 센다).
    static let freeStampLimit = 30

    // MARK: - 상품 ID
    //
    // ⚠️ App Store Connect · `FootprintDiary.storekit` 과 글자 하나까지 같아야 한다.
    //    주 · 월 · 연 구독 여섯은 **한 구독 그룹**에 넣는다(Pro 가 위 단계). 그래야 서로 갈아탄다.

    private static let prefix = "com.leeo.FootprintDiary"

    static let plusWeeklyID   = prefix + ".plus.weekly"
    static let plusMonthlyID  = prefix + ".plus.monthly"
    static let plusYearlyID   = prefix + ".plus.yearly"
    /// Plus 평생.
    static let plusLifetimeID = prefix + ".plus"
    static let proWeeklyID    = prefix + ".pro.weekly"
    static let proMonthlyID   = prefix + ".pro.monthly"
    static let proYearlyID    = prefix + ".pro.yearly"
    /// Pro 평생.
    static let proLifetimeID  = prefix + ".pro"
    /// Plus 평생을 산 사람이 Pro 평생으로 올리는 값.
    static let upgradeID      = prefix + ".pro.upgrade"
    /// 연 구독 중인 사람의 졸업가 Pro 평생 (→ LeeoGraduation).
    static let graduateID     = prefix + ".pro.graduate"

    /// 개발자 응원 팁 (소모성 셋, 작은 것부터). 아무것도 열지 않는다.
    static let tipProductIDs = [prefix + ".tip.small", prefix + ".tip.medium", prefix + ".tip.large"]

    /// 페이월이 불러올 상품. 스토어에 아직 없는 것은 불러와지지 않고, 그 단추는 서지 않는다.
    static let productIDs = [plusYearlyID, plusLifetimeID, proYearlyID, proLifetimeID, upgradeID, graduateID,
                             plusWeeklyID, plusMonthlyID, proWeeklyID, proMonthlyID]

    /// 상품마다 여는 칸. 구독은 같은 칸의 평생과 같은 권한, 올리기 · 졸업은 Pro 평생이다.
    static let tierByProduct: [String: ProTier] = [
        plusWeeklyID: .plus, plusMonthlyID: .plus, plusYearlyID: .plus, plusLifetimeID: .plus,
        proWeeklyID: .pro, proMonthlyID: .pro, proYearlyID: .pro, proLifetimeID: .pro,
        upgradeID: .pro, graduateID: .pro,
    ]

    static var entitlementIDs: Set<String> { Set(tierByProduct.keys) }

    /// 평생 상품 (끝나지 않는 것).
    static let lifetimeIDs: Set<String> = [plusLifetimeID, proLifetimeID, upgradeID, graduateID]

    /// 연 구독. 구독 졸업을 제안할 대상이다. 주 · 월 구독에 졸업가를 주면 한 주 값으로 평생이 싸진다.
    static let yearlyIDs: Set<String> = [plusYearlyID, proYearlyID]

    /// 자동 갱신 구독 전부.
    static let subscriptionIDs: Set<String> = [plusWeeklyID, plusMonthlyID, plusYearlyID,
                                               proWeeklyID, proMonthlyID, proYearlyID]

    /// 가진 상품이 여는 칸. 가장 높은 것을 쓴다.
    static func tier(owning productIDs: Set<String>) -> ProTier {
        productIDs.compactMap { tierByProduct[$0] }.max() ?? .free
    }

    /// 이 칸의 평생을 이미 가졌는가.
    static func ownsLifetime(_ tier: ProTier, in productIDs: Set<String>) -> Bool {
        productIDs.contains { lifetimeIDs.contains($0) && tierByProduct[$0] == tier }
    }

    // MARK: - 지금 쓰는 칸 (영수증의 거울)
    //
    // 위젯과 함께 읽는 앱 그룹에 적는다(→ Shared/ProPass.swift).

    /// 지금 쓰는 칸. 스토어 스크린샷용 가상 기록은 모든 기능을 보인다.
    static var tier: ProTier {
        #if DEBUG
        if DemoSeed.isOn { return .pro }
        #endif
        return cachedTier ?? .free
    }

    /// 적혀 있는 답. **nil 은 '무료'가 아니라 '아직 애플에게 안 물어봤다'** 이다.
    static var cachedTier: ProTier? { ProPass.storedValue.flatMap(ProTier.init(rawValue:)) }

    /// `PurchaseManager` 만 부른다.
    static func setTier(_ value: ProTier) {
        guard cachedTier != value else { return }
        ProPass.defaults.set(value.rawValue, forKey: ProPass.key)
    }

    // MARK: - 페이월 전부터 쓰던 사람

    /// 모든 기능이 무료였던 마지막 빌드(1.0.10 빌드 10). 이 빌드 이하로 처음 받은 사람은 Pro 평생이다.
    static let lastFreeBuild = 10

    private static let legacyCheckedKey = "pro.legacy.checked"
    private static let legacyUserKey = "pro.legacy.user"

    /// 이 기기에서 페이월 전부터 벅뚜벅뚜를 쓰고 있었는가.
    static var usedBeforePaywall: Bool { UserDefaults.standard.bool(forKey: legacyUserKey) }

    /// 페이월이 생긴 버전을 **처음 켤 때 한 번만** 적는다. 그때 이미 안내를 마친 사람은 쓰던 사람이다.
    /// 그 뒤에 새로 시작한 사람은 세지 않는다.
    static func noteUseBeforePaywall() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: legacyCheckedKey) else { return }
        defaults.set(true, forKey: legacyCheckedKey)
        if defaults.bool(forKey: "footprint.hasOnboarded") { defaults.set(true, forKey: legacyUserKey) }
    }
}
