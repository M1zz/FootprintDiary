//
//  WhatsNew.swift
//  FootprintDiary
//
//  새로 생긴 것을 알리는 한 장.
//
//  업데이트를 받아도 무엇이 바뀌었는지는 스토어의 글을 읽은 사람만 안다. 그런데 이번처럼
//  단추를 설정으로 옮긴 판에서는, 모르고 지도를 연 사람에게 '단추가 없어졌다'로 보인다.
//  그래서 그 판을 처음 여는 한 번만 이 장을 띄우고, 그 뒤로는 설정에서 다시 볼 수 있게 둔다.
//
//  처음 설치한 사람에게는 띄우지 않는다. 그 사람에게는 모든 것이 새것이라, '새로 생긴 것'은
//  안내를 막 마친 사람 앞에 한 겹 더 놓이는 관문일 뿐이다 (ContentView에서 본 것으로 적어 둔다).
//

import SwiftUI

enum WhatsNew {
    /// 이 장이 말하는 판. 내용을 고치면 이 값도 올려야 이미 본 사람에게 다시 뜬다.
    static let version = "1.0.7"

    /// 마지막으로 본 판
    static let seenKey = "footprint.whatsNewSeen"

    struct Item: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let detail: String
    }

    static let items: [Item] = [
        Item(
            symbol: "mountain.2",
            title: String(localized: "그림지도"),
            detail: String(localized: "산과 나무, 물결을 그려 넣은 지도로 바꿔 볼 수 있어요. 걸은 자리에는 숲 사이로 오솔길이 트여요.")
        ),
        Item(
            symbol: "calendar",
            title: String(localized: "기간으로 좁혀 보기"),
            detail: String(localized: "이번 주, 이번 달, 올해처럼 기간을 골라 그때 걸은 길과 도장만 볼 수 있어요.")
        ),
        Item(
            symbol: "sparkles",
            title: String(localized: "지도가 한결 비었어요"),
            detail: String(localized: "가끔 쓰는 단추는 설정으로 옮겼어요. 설정의 '지도에 보이기'에서 원하는 것만 다시 꺼내 둘 수 있어요.")
        ),
        Item(
            symbol: "square.grid.2x2",
            title: String(localized: "설정에서 바로 열기"),
            detail: String(localized: "개척 나침반, 그려지는 것 보기, 오늘의 발자취를 설정의 '모아 보기'에서 열 수 있어요.")
        ),
        Item(
            symbol: "car",
            title: String(localized: "차 안에서 멈춘 자리는 그리지 않아요"),
            detail: String(localized: "신호에 걸려 서 있던 차가 산책길로 남던 것을 고쳤어요.")
        ),
        Item(
            symbol: "lightbulb",
            title: String(localized: "처음 보는 단추에 작은 안내"),
            detail: String(localized: "단추가 무슨 일을 하는지 한 번씩 짚어 드려요.")
        ),
    ]

    static var hasUnseen: Bool {
        UserDefaults.standard.string(forKey: seenKey) != version
    }

    static func markSeen() {
        UserDefaults.standard.set(version, forKey: seenKey)
    }
}

struct WhatsNewView: View {
    /// 여기서 고른 화면을 연다. 이 장은 먼저 닫힌다.
    var onOpen: ((AtlasDestination) -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("새로 생긴 것")
                            .font(.system(.title, design: .serif, weight: .bold))
                        Text("버전 \(WhatsNew.version)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(WhatsNew.items) { item in
                            row(symbol: item.symbol, title: item.title, detail: item.detail)
                        }
                    }

                    if let onOpen {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("설정에서도 열 수 있어요")
                                .font(.headline)
                            ForEach([AtlasDestination.compass, .film, .timeline, .period]) { destination in
                                Button {
                                    dismiss()
                                    onOpen(destination)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: destination.symbol)
                                            .frame(width: 24)
                                            .foregroundStyle(Color(InkStyle.sealRed))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(destination.title)
                                                .font(.subheadline.weight(.semibold))
                                            Text(destination.summary)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(12)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(24)
            }
            .background(Color(InkStyle.paper))
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                } label: {
                    Text("확인")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(InkStyle.sealRed))
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { WhatsNew.markSeen() }
    }

    private func row(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Color(InkStyle.sealRed))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
