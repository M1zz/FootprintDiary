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

    /// 수익모델 — 인앱 결제가 없는 완전 무료 앱.
    static let monetization = LeeoMonetization.free
}
