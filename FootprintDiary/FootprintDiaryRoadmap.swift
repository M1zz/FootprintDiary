//
//  FootprintDiaryRoadmap.swift
//  FootprintDiary (벅뚜벅뚜)
//
//  **앞으로 만들 것**의 원본. 설정 ▸ 앞으로 만들 기능(`LeeoRoadmapView`)이 이 목록을 그대로 보여 준다.
//
//  ⚠️ 개발하다 "이건 다음에" 가 생기면 **여기에 한 줄을 더한다.** 코드의 TODO 주석으로만 남기지 않는다.
//     - 새 항목: `.planned`. 손대기 시작하면 `.building`. 내보내면 `.shipped("1.2.0")`.
//     - id 는 한 번 정하면 바꾸지 않는다(문구는 바꿔도 된다).
//     - 문구는 사용자 말로 쓴다(내부 이름 · 기술 용어 금지). 영어는 FootprintDiary/Localizable.xcstrings 에 넣는다
//       (영어가 빠지면 영어 쓰는 사람에게 한국어가 보인다).
//     - 사용자에게 보일 만한 것만 적는다. 리팩터링 · 시험 · 빌드 설정은 `.sprintcommander/tasks.json` 의 몫이다.
//

import SwiftUI
import LeeoKit

extension FootprintDiarySpec {
    static var roadmap: [LeeoRoadmapItem] {[
        // MARK: 다음에 만들어요
        .init(id: "a11y.voiceover", status: .planned,
              title: NSLocalizedString("VoiceOver로 더 편하게", comment: "Roadmap item: better VoiceOver support"),
              detail: NSLocalizedString("VoiceOver가 지도와 기록의 단추와 내용을 빠짐없이, 알맞은 순서로 읽어 줘요.", comment: "Roadmap item detail: better VoiceOver support")),
        .init(id: "a11y.largetext", status: .planned,
              title: NSLocalizedString("큰 글씨에 맞춘 화면", comment: "Roadmap item: layouts for larger text"),
              detail: NSLocalizedString("글자 크기를 키워도 잘리지 않고 보기 좋게 다시 배치돼요.", comment: "Roadmap item detail: layouts for larger text")),
        .init(id: "a11y.contrast", status: .planned,
              title: NSLocalizedString("보기 편한 색과 대비", comment: "Roadmap item: better colors and contrast"),
              detail: NSLocalizedString("대비를 높이거나 색을 구별하기 어려워도 지도의 길과 스탬프를 알아볼 수 있어요.", comment: "Roadmap item detail: better colors and contrast")),
        .init(id: "a11y.motion", status: .planned,
              title: NSLocalizedString("움직임 줄이기", comment: "Roadmap item: respect Reduce Motion"),
              detail: NSLocalizedString("움직임 줄이기를 켜면 지도와 화면 효과가 차분해져요.", comment: "Roadmap item detail: respect Reduce Motion")),
        .init(id: "lang.english", status: .planned,
              title: NSLocalizedString("영어 지원", comment: "Roadmap item: English language"),
              detail: NSLocalizedString("앱을 영어로도 쓸 수 있어요.", comment: "Roadmap item detail: English language")),
        .init(id: "lang.more", status: .planned,
              title: NSLocalizedString("더 많은 언어", comment: "Roadmap item: more languages"),
              detail: NSLocalizedString("더 많은 나라 말로 앱을 쓸 수 있게 해요.", comment: "Roadmap item detail: more languages")),
        .init(id: "shortcuts", status: .planned,
              title: NSLocalizedString("Siri와 단축어", comment: "Roadmap item: Siri and Shortcuts"),
              detail: NSLocalizedString("Siri에게 물어 오늘 걸은 거리를 바로 확인해요.", comment: "Roadmap item detail: Siri and Shortcuts")),
        .init(id: "backup", status: .planned,
              title: NSLocalizedString("백업과 내보내기", comment: "Roadmap item: backup and export"),
              detail: NSLocalizedString("걸은 길과 일기를 파일로 저장하고 다시 불러올 수 있어요.", comment: "Roadmap item detail: backup and export")),
        .init(id: "lock.faceid", status: .planned,
              title: NSLocalizedString("Face ID 잠금", comment: "Roadmap item: Face ID lock"),
              detail: NSLocalizedString("Face ID나 Touch ID로 앱을 잠가 내가 걸은 곳과 일기를 지켜요.", comment: "Roadmap item detail: Face ID lock")),
        .init(id: "notifications", status: .planned,
              title: NSLocalizedString("산책 알림", comment: "Roadmap item: notifications"),
              detail: NSLocalizedString("하루를 마칠 때 오늘 걸은 길을 알림으로 알려 줘요.", comment: "Roadmap item detail: notifications")),
        .init(id: "fold", status: .planned,
              title: NSLocalizedString("펼치는 아이폰 화면", comment: "Roadmap item: foldable iPhone layout"),
              detail: NSLocalizedString("펼치는 아이폰에서 지도와 기록을 두 쪽으로 나눠 봐요.", comment: "Roadmap item detail: foldable iPhone layout")),
        .init(id: "data.delete", status: .planned,
              title: NSLocalizedString("내 기록 한 번에 지우기", comment: "Roadmap item: delete all my data"),
              detail: NSLocalizedString("원하면 앱 안에서 걸은 길과 일기를 모두 지울 수 있어요.", comment: "Roadmap item detail: delete all my data")),
        .init(id: "autosave", status: .planned,
              title: NSLocalizedString("쓰던 일기 이어 쓰기", comment: "Roadmap item: keep unsaved drafts"),
              detail: NSLocalizedString("일기를 쓰다가 앱이 꺼져도 쓰던 내용이 남아 있어요.", comment: "Roadmap item detail: keep unsaved drafts")),
    ]}
}

// MARK: - 화면

/// 설정 ▸ 앞으로 만들 기능. "이런 기능이 있으면 좋겠어요" 는 기능 제안으로 시작하는 피드백 창을 연다.
struct RoadmapScreen: View {
    @State private var showFeedback = false

    var body: some View {
        LeeoRoadmapView<FootprintDiarySpec>(onSuggest: { showFeedback = true })
            .sheet(isPresented: $showFeedback) {
                NavigationStack {
                    LeeoFeedbackView<FootprintDiarySpec>(initialType: .feature)
                }
            }
    }
}
