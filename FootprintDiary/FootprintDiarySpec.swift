//
//  FootprintDiarySpec.swift
//  FootprintDiary
//
//  LeeoKit 계약 구현 — 앱 이름, 개발자 이메일, 피드백 설정.
//

import Foundation
import LeeoKit

enum FootprintDiarySpec: LeeoAppSpec {
    static let appName = "발자국일기"
    static let developerEmail = "mizzking75@gmail.com"
    static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.Ysoup.FeedbackHub", appIdentifier: "com.leeo.FootprintDiary")
}
