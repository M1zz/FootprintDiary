//
//  CloudSync.swift
//  FootprintDiary
//
//  걸음과 기록을 아이클라우드에 얹는다.
//
//  이 앱의 기록은 다시 만들 수 없다. 사진은 다시 찍을 수 있고 일기는 다시 쓸 수 있지만,
//  '작년 봄에 어느 골목을 걸었는가'는 그때 거기 있어야만 남는다. 기기 안에만 두면
//  기기를 잃는 날 그 몇 해가 통째로 사라진다. 그래서 내 아이클라우드에 함께 둔다.
//
//  남의 눈에 닿는 곳이 아니라 내 개인 데이터베이스(private)다. 기기를 바꾸면 따라오고,
//  아이폰과 아이패드를 함께 쓰면 양쪽이 같은 지도를 본다.
//
//  주고받기는 SwiftData가 알아서 한다. 여기서 하는 일은 두 가지뿐이다 —
//  어느 그릇에 담을지 이름을 대고, 지금 잘 오가고 있는지를 설정 화면에서 볼 수 있게 하는 것.
//  조용히 안 되고 있는 것이 가장 나쁘다.
//

import CloudKit
import CoreData
import Foundation

@MainActor
final class CloudSync: ObservableObject {

    /// 기록이 담기는 그릇. 개발자 계정에 만들어 둔 이름과 글자 하나까지 같아야 한다.
    static let containerID = "iCloud.com.leeo.FootprintDiary"

    /// 저장소가 아이클라우드에 붙은 채로 열렸는지.
    ///
    /// 앱이 켜질 때 한 번 정해진다. 붙이지 못하면 기기 안에만 열고 이 값이 거짓이 되는데,
    /// 그때 화면에 아무 말도 하지 않으면 사용자는 저장되고 있다고 믿은 채로 지낸다.
    static var isAttached = false

    enum State {
        /// 아이클라우드에 잘 붙어 있다
        case on
        /// 기기에 아이클라우드 계정이 없다
        case signedOut
        /// 기기 설정(스크린타임 등)이 막고 있다
        case restricted
        /// 알아보는 중
        case checking
        /// 저장소가 기기 안에만 열렸다
        case localOnly
        case failed(String)
    }

    @Published private(set) var state: State = .checking
    /// 마지막으로 주고받은 때와 그 결과. 아직 한 번도 없었으면 비어 있다.
    @Published private(set) var lastExchange: (date: Date, succeeded: Bool)?

    private var observers: [NSObjectProtocol] = []

    init() {
        // 로그인·로그아웃은 앱을 켜 둔 채로도 일어난다
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .CKAccountChanged, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in await self?.refresh() }
            }
        )
        // SwiftData 속은 NSPersistentCloudKitContainer다. 주고받기가 끝날 때마다 알려 준다.
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: nil, queue: .main
            ) { [weak self] note in
                guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event,
                      let endDate = event.endDate else { return }
                Task { @MainActor in
                    self?.lastExchange = (endDate, event.succeeded)
                }
            }
        )
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func refresh() async {
        guard Self.isAttached else {
            state = .localOnly
            return
        }
        do {
            let status = try await CKContainer(identifier: Self.containerID).accountStatus()
            switch status {
            case .available: state = .on
            case .noAccount: state = .signedOut
            case .restricted: state = .restricted
            case .couldNotDetermine, .temporarilyUnavailable: state = .checking
            @unknown default: state = .checking
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - 화면에 쓰는 말

    var title: String {
        switch state {
        case .on: return "아이클라우드에 저장 중"
        case .signedOut: return "아이클라우드에 로그인되어 있지 않아요"
        case .restricted: return "아이클라우드를 쓸 수 없어요"
        case .checking: return "아이클라우드 상태를 보는 중"
        case .localOnly: return "이 기기에만 저장 중"
        case .failed: return "아이클라우드에 닿지 못했어요"
        }
    }

    var detail: String {
        switch state {
        case .on:
            guard let lastExchange else {
                return "걸음·스탬프·일기가 내 아이클라우드에 함께 저장됩니다. 기기를 바꿔도 그대로 따라와요."
            }
            let when = Self.clock.string(from: lastExchange.date)
            return lastExchange.succeeded
                ? "마지막으로 주고받은 때: \(when)"
                : "마지막으로 주고받다가 멈췄어요 (\(when)). 잠시 뒤 저절로 다시 시도합니다."
        case .signedOut:
            return "설정 앱에서 아이클라우드에 로그인하면 기록이 저장되기 시작해요. 그때까지 기록은 이 기기 안에만 남습니다."
        case .restricted:
            return "기기 설정이 아이클라우드를 막고 있어요. 기록은 이 기기 안에만 남습니다."
        case .checking:
            return "잠시 뒤 다시 알아봅니다."
        case .localOnly:
            return "아이클라우드를 붙이지 못해 기기 안에만 열었어요. 기록은 그대로 남아 있고, 다음에 켤 때 다시 시도합니다."
        case .failed(let message):
            return message
        }
    }

    var symbolName: String {
        switch state {
        case .on: return "checkmark.icloud.fill"
        case .signedOut, .restricted, .localOnly: return "exclamationmark.icloud"
        case .checking: return "icloud"
        case .failed: return "xmark.icloud"
        }
    }

    var isHealthy: Bool {
        if case .on = state { return true }
        return false
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 a h:mm"
        return formatter
    }()
}
