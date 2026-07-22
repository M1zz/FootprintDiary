//
//  FootprintDiarySupportView.swift
//  FootprintDiary
//
//  지원 화면 — 피드백/리뷰/버전 정보 (LeeoKit 제공)
//

import SwiftUI
import LeeoKit

struct FootprintDiarySupportView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LeeoSupportSection<FootprintDiarySpec>()
                } header: {
                    Text("지원")
                }
            }
            .navigationTitle("설정")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}
