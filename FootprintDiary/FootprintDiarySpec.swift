//
//  FootprintDiarySpec.swift
//  FootprintDiary
//
//  LeeoKit 계약 구현 — 앱 이름, 개발자 이메일, 피드백 설정.
//

import Foundation
import LeeoKit

enum FootprintDiarySpec: LeeoAppSpec {
    static let appName = "벅뚜벅뚜"
    static let developerEmail = "leeo@kakao.com"
    static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.Ysoup.FeedbackHub", appIdentifier: "com.leeo.FootprintDiary")

    /// 법적·지원 링크 — docs/ 의 GitHub Pages (README 에 걸린 주소와 같다).
    /// 계정을 만들지 않는다.
    static let legal = LeeoLegalConfig(
        privacyURL: URL(string: "https://m1zz.github.io/FootprintDiary/privacy.html")!,
        supportURL: URL(string: "https://m1zz.github.io/FootprintDiary/support.html")!,
        marketingURL: URL(string: "https://m1zz.github.io/FootprintDiary/")!
    )

    /// App Store 앱 ID — 리뷰 남기기·친구에게 소개하기 링크.
    static let appStoreID: String? = "6789952970"

    /// 수익모델 — 무료로 내려받고, 무료 · Plus · Pro 세 칸. 유료 칸마다 주 · 월 · 연 구독과 평생.
    /// 걸음 기록 · 지도 · 일기 · iCloud 보관은 기간 제한 없이 무료다.
    /// 칸마다 무엇이 열리는지는 `ProFeature.tier` 한 곳에 있다(→ ProEntitlement.swift).
    static let monetization = LeeoMonetization.freemiumSubscription(
        LeeoSubscriptionConfig(
            productIDs: ProEntitlement.productIDs,
            // 자체 약관이 없으므로 애플 표준 사용권 계약(EULA)을 건다. 구독을 파는 앱의 심사 필수 항목이다.
            termsURL: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!,
            entitlementIDs: ProEntitlement.entitlementIDs,
            gate: LeeoGatePolicy(
                freeLimits: [Gate.stamps: ProEntitlement.freeStampLimit],
                proOnly: Set(ProFeature.allCases.filter { $0 != .unlimitedStamps }.map(\.rawValue))),
            // 위젯과 함께 읽는 그 통.
            cacheSuiteName: "group.com.leeo.FootprintDiary",
            // 개발자 응원 팁. 소모성 세 가지, 작은 것부터. 기능을 열지 않는다(→ `tipJar`).
            tipJar: LeeoTipJarConfig(productIDs: ProEntitlement.tipProductIDs)))

    /// 게이트 열쇠말.
    enum Gate {
        static let stamps = "stamps"
    }

    /// 백업 금고가 함께 떠 두는 공유 저장소 (위젯과 나누는 기록).
    static let appGroups = ["group.com.leeo.FootprintDiary"]

    /// 개발자 응원(팁). 결제 리스너를 함께 쓰도록 `LeeoStore` 가 만든 것을 쓴다.
    @MainActor static var tipJar: LeeoTipJar? { PurchaseManager.shared.store.tipJar }
}
