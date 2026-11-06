//
//  ProPass.swift
//  FootprintDiary · FootprintWidget
//
//  앱이 영수증을 읽고 적어 둔 칸(무료 · Plus · Pro) 한 줄. 위젯은 이것만 읽는다.
//
//  위젯은 StoreKit 을 묻지 않는다. 앱이 적은 답을 앱 그룹에서 읽어, Pro 가 아니면
//  오늘 걸음 대신 'Pro로 열기' 자리를 내건다 (→ PurchaseManager 가 칸이 바뀔 때 위젯을 다시 그린다).
//

import Foundation

enum ProPass {
    /// 칸 값. 0 무료 · 1 Plus · 2 Pro (ProTier.rawValue 와 같다).
    static let key = "pro.tier"
    static let proValue = 2

    static var defaults: UserDefaults { UserDefaults(suiteName: WalkSnapshotStore.appGroup) ?? .standard }

    /// 적힌 칸. **nil 은 '무료'가 아니라 '앱이 아직 애플에게 묻지 않았다'** 이다.
    static var storedValue: Int? { defaults.object(forKey: key) as? Int }

    /// 위젯을 열어 둘 것인가.
    ///
    /// 아직 모르면 연다. 페이월 전부터 쓰던 사람은 곧 Pro 로 확인되는데, 그 전에 잠그면
    /// 업데이트 직후 홈 화면의 위젯이 까닭 없이 잠긴다.
    static var opensWidgets: Bool { (storedValue ?? proValue) >= proValue }

    /// 잠긴 위젯을 누르면 여는 주소. 앱이 받아 Pro 페이월을 띄운다.
    static let unlockURL = URL(string: "footprintdiary://pro/widgets")!
}
