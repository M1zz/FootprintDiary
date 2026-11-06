//
//  PaywallView.swift
//  FootprintDiary
//
//  Plus · Pro 를 파는 한 장. 칸 카드 둘(칸마다 연 구독 / 평생, 주 · 월은 펼쳐서) → 세 칸 비교표 → 약관.
//
//  **걸어서 그린 지도는 언제나 무료라는 말을 먼저 한다.** 사는 사람도 안 사는 사람도
//  이 화면을 닫고 나서 계속 걷는다.
//
//  ⚠️ 스토어에 아직 없는 상품은 불러와지지 않는다. 그 단추는 서지 않는다(없는 것을 팔지 않는다).
//  첫 해 할인(App Store 첫 구독 할인)과 "연 구독 N년치" 한 줄은 `LeeoTermPicker` 가 알아서 보인다.
//

import SwiftUI
import StoreKit
import LeeoKit

struct PaywallView: View {
    /// 어디서 들어왔는가. 그 기능이 든 칸을 맨 위에 세우고 강조한다.
    var highlight: ProFeature?
    /// 처음 고를 길. 오래 걸을 사람이 모이는 자리(필름 내보내기)나 '평생으로 바꾸기'에서는 평생.
    var term: LeeoPlanTerm = .yearly

    @State private var purchases = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// 결제 시트를 **이 페이월이 떠 있는 창**에 띄운다.
    @Environment(\.purchase) private var purchaseAction

    @State private var plusTerm: LeeoPlanTerm = .yearly
    @State private var proTerm: LeeoPlanTerm = .yearly
    @State private var loadingProducts = true
    @State private var redeemingCode = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    plansStatus
                    ForEach(tierOrder, id: \.self) { tierCard($0) }
                    PlanComparisonTable()
                    if let message = purchases.failureMessage, !purchases.products.isEmpty {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    legal
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("요금제")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Label("닫기", systemImage: "xmark") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("복원") { Task { await restore() } }
                        .disabled(purchases.isWorking)
                }
            }
            .offerCodeRedemption(isPresented: $redeemingCode) { _ in
                Task {
                    await purchases.refresh()
                    if purchases.tier > .free { dismiss() }
                }
            }
            .task {
                switch highlight?.tier {
                case .pro?: proTerm = term
                case .plus?: plusTerm = term
                default: plusTerm = term; proTerm = term
                }
                LeeoAnalyticsCenter.track(.paywallShown(reason: highlight?.rawValue ?? "settings"))
                await loadPlans()
            }
        }
        // 앱의 강조색은 옅은 살구빛이라 단추 글자가 묻힌다. 도장과 같은 주묵으로 칠한다.
        .tint(Color(InkStyle.sealRed))
    }

    /// 들어온 기능의 칸을 앞에.
    private var tierOrder: [ProTier] { highlight?.tier == .pro ? [.pro, .plus] : [.plus, .pro] }

    // MARK: 머리

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("벅뚜벅뚜 Plus · Pro")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("걸어서 그린 지도는 언제나 무료예요. 꾸미고 넓히는 도구를 연 구독이나 평생으로 고르세요.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("가족 공유로 가족 모두의 Apple 계정에서 함께 열려요.", systemImage: "person.2.fill")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 칸

    private func tierCard(_ tier: ProTier) -> some View {
        let highlighted = highlight?.tier == tier && purchases.tier < tier
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(tier.title)
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                if purchases.tier == tier {
                    Text("지금 쓰는 칸")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                Spacer(minLength: 0)
            }
            Text(tier.tagline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if tier == .pro {
                featureRow(systemImage: "square.stack.3d.up.fill", title: String(localized: "Plus의 모든 것"), note: nil)
            }
            ForEach(features(in: tier)) { feature in
                featureRow(systemImage: feature.systemImage, title: feature.title, note: feature.note,
                           highlighted: feature == highlight)
            }
            // 스토어에서 불러온 상품이 있을 때만 고르기와 구매 단추를 세운다.
            if purchases.canBuy(tier) && (yearly(tier) != nil || lifetime(tier) != nil) {
                LeeoTermPicker(term: termBinding(tier), yearly: yearly(tier), lifetime: lifetime(tier))
                    .padding(.top, 4)
                buyButton(tier)
                shortPlans(tier)
            }
        }
        .paywallCard()
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(highlighted ? Color(InkStyle.sealRed) : .clear, lineWidth: 2)
        }
    }

    /// 그 칸에서 새로 열리는 것. 지금 누른 자리가 맨 위.
    private func features(in tier: ProTier) -> [ProFeature] {
        let opened = ProFeature.opened(by: tier)
        guard let highlight, opened.contains(highlight) else { return opened }
        return [highlight] + opened.filter { $0 != highlight }
    }

    private func featureRow(systemImage: String, title: String, note: String?, highlighted: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(highlighted ? Color(InkStyle.sealRed) : .secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                if let note {
                    Text(note)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 상품

    private func termBinding(_ tier: ProTier) -> Binding<LeeoPlanTerm> {
        tier == .plus ? $plusTerm : $proTerm
    }

    private func yearly(_ tier: ProTier) -> Product? {
        purchases.product(tier == .plus ? ProEntitlement.plusYearlyID : ProEntitlement.proYearlyID)
    }

    /// 칸의 평생. **Plus 평생을 이미 산 사람에게는 Pro 평생 자리에 올리기 상품을 세운다.**
    private func lifetime(_ tier: ProTier) -> Product? {
        if tier == .plus { return purchases.product(ProEntitlement.plusLifetimeID) }
        return purchases.product(upgradesToPro ? ProEntitlement.upgradeID : ProEntitlement.proLifetimeID)
    }

    private var upgradesToPro: Bool { purchases.ownsLifetime(.plus) }

    private func buyButton(_ tier: ProTier) -> some View {
        let chosen = termBinding(tier).wrappedValue
        let product = chosen == .yearly ? yearly(tier) : lifetime(tier)
        let title: String = switch chosen {
        case .yearly: String(localized: "연 구독 시작")
        case .lifetime where tier == .pro && upgradesToPro: String(localized: "Pro 평생으로 올리기")
        case .lifetime: String(localized: "평생으로 사기")
        }
        return Button {
            guard let product else { return }
            Task { await buy(product, opening: tier) }
        } label: {
            Group {
                if purchases.isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text(title).font(.headline)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(purchases.isWorking || product.map { purchases.owns($0.id) } ?? true)
    }

    /// 주 · 월 구독. 연이 기본이고, 짧게 써 보고 싶은 사람에게만 펼쳐 보인다. 스토어에 없으면 줄째 숨는다.
    @ViewBuilder
    private func shortPlans(_ tier: ProTier) -> some View {
        let weekly = purchases.product(tier == .plus ? ProEntitlement.plusWeeklyID : ProEntitlement.proWeeklyID)
        let monthly = purchases.product(tier == .plus ? ProEntitlement.plusMonthlyID : ProEntitlement.proMonthlyID)
        if weekly != nil || monthly != nil {
            DisclosureGroup("주간 · 월간으로 보기") {
                VStack(spacing: 8) {
                    if let weekly { shortPlanButton(weekly, tier, title: String(localized: "주간 \(weekly.displayPrice)")) }
                    if let monthly { shortPlanButton(monthly, tier, title: String(localized: "월간 \(monthly.displayPrice)")) }
                }
                .padding(.top, 8)
            }
        }
    }

    private func shortPlanButton(_ product: Product, _ tier: ProTier, title: String) -> some View {
        Button {
            Task { await buy(product, opening: tier) }
        } label: {
            Text(title)
                .monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.bordered)
        .disabled(purchases.isWorking || purchases.owns(product.id))
    }

    private func buy(_ product: Product, opening tier: ProTier) async {
        await purchases.purchase(product, using: purchaseAction)
        if purchases.tier >= tier { dismiss() }
    }

    private func restore() async {
        await purchases.restore()
        if purchases.tier > .free { dismiss() }
    }

    // MARK: 불러오기

    @ViewBuilder
    private var plansStatus: some View {
        if purchases.products.isEmpty && loadingProducts {
            HStack(spacing: 10) {
                ProgressView()
                Text("요금제를 불러오는 중…").foregroundStyle(.secondary)
            }
        } else if purchases.products.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("요금제를 불러오지 못했어요. 인터넷 연결을 확인하고 다시 불러와 주세요.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await loadPlans() }
                } label: {
                    Label("다시 불러오기", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    /// 샌드박스(심사 환경)는 첫 조회가 빈손으로 돌아오는 일이 잦아 한 번 더 청한다.
    private func loadPlans() async {
        loadingProducts = true
        await purchases.loadProducts()
        if purchases.products.isEmpty {
            try? await Task.sleep(for: .seconds(1.5))
            await purchases.loadProducts()
        }
        loadingProducts = false
    }

    // MARK: 약관 (구독을 파는 앱의 심사 필수 항목)

    private var legal: some View {
        VStack(alignment: .leading, spacing: 12) {
            if purchases.products.contains(where: { $0.subscription != nil }) {
                Text("구독은 기간이 끝나기 24시간 전까지 해지하지 않으면 같은 값으로 자동 갱신되고, Apple 계정으로 결제돼요. 연 구독을 처음 시작하면 첫 해는 할인된 값으로, 그 뒤로는 정가로 갱신돼요. 해지와 관리는 App Store 계정 설정에서 할 수 있어요. 평생은 구독이 아니라 한 번만 결제해요.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits {
                HStack(spacing: 20) { legalButtons }
                VStack(alignment: .leading, spacing: 12) { legalButtons }
            }
        }
    }

    @ViewBuilder
    private var legalButtons: some View {
        if let terms = FootprintDiarySpec.monetization.subscriptionTermsURL {
            Button("이용약관") { openURL(terms) }
        }
        Button("개인정보 처리방침") { openURL(FootprintDiarySpec.legal.privacyURL) }
        Button("구매 복원") { Task { await restore() } }
            .disabled(purchases.isWorking)
        Button("코드 사용") { redeemingCode = true }
            .disabled(purchases.isWorking)
    }
}

// MARK: - 세 칸 비교표

/// 페이월에 그대로 서는 표. 무료로 되는 것을 먼저 말한다.
struct PlanComparisonTable: View {
    private enum Cell {
        case yes, no, text(String)
    }

    private struct Row: Identifiable {
        let label: String
        let cells: [Cell]   // 무료 · Plus · Pro
        var id: String { label }
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    private var rows: [Row] {
        let unlimited = String(localized: "무제한")
        let preview = String(localized: "미리보기")
        return [
            Row(label: String(localized: "걸음 기록 · 지도"), cells: [.yes, .yes, .yes]),
            Row(label: String(localized: "iCloud 보관 · 동기화"), cells: [.yes, .yes, .yes]),
            Row(label: String(localized: "일기 · 달력 · 오늘의 발자취"), cells: [.yes, .yes, .yes]),
            Row(label: String(localized: "기간 보기 (주 · 달 · 해)"), cells: [.yes, .yes, .yes]),
            Row(label: String(localized: "기록 내보내기 (GPX · CSV)"), cells: [.yes, .yes, .yes]),
            Row(label: String(localized: "도장"),
                cells: [.text(String(localized: "\(ProEntitlement.freeStampLimit)곳")), .text(unlimited), .text(unlimited)]),
            Row(label: ProFeature.stickerCamera.title, cells: [.no, .yes, .yes]),
            Row(label: ProFeature.pictureMap.title, cells: [.no, .yes, .yes]),
            Row(label: ProFeature.customPeriod.title, cells: [.no, .yes, .yes]),
            Row(label: String(localized: "위젯"), cells: [.no, .no, .yes]),
            Row(label: ProFeature.filmExport.title, cells: [.text(preview), .text(preview), .yes]),
            Row(label: ProFeature.compass.title, cells: [.no, .no, .yes]),
        ]
    }

    private let tiers: [ProTier] = [.free, .plus, .pro]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("한눈에 비교")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            if typeSize.isAccessibilitySize {
                stacked
            } else {
                grid
            }
        }
        .paywallCard()
    }

    /// 보통 글자: 네 칸 표.
    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                ForEach(tiers, id: \.self) { tier in
                    Text(shortName(tier))
                        .font(.body.weight(.semibold))
                        .gridColumnAlignment(.center)
                }
            }
            .accessibilityHidden(true)
            ForEach(rows) { row in
                Divider()
                GridRow {
                    Text(row.label)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                        cellView(cell)
                            .frame(minWidth: 56)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken(row))
            }
        }
    }

    /// 아주 큰 글자: 줄마다 위아래로.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.label).font(.body.weight(.semibold))
                    ForEach(Array(zip(tiers, row.cells)), id: \.0) { tier, cell in
                        HStack {
                            Text(shortName(tier)).foregroundStyle(.secondary)
                            Spacer()
                            cellView(cell)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken(row))
            }
        }
    }

    private func shortName(_ tier: ProTier) -> String {
        switch tier {
        case .free: String(localized: "무료")
        case .plus: "Plus"
        case .pro:  "Pro"
        }
    }

    @ViewBuilder
    private func cellView(_ cell: Cell) -> some View {
        switch cell {
        case .yes:
            Image(systemName: "checkmark")
                .font(.body.weight(.bold))
                .foregroundStyle(.green)
        case .no:
            Text(verbatim: "–").foregroundStyle(.secondary)
        case .text(let value):
            Text(value)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// VoiceOver 가 한 줄을 한 번에 읽는다: "도장, 무료 30곳, Plus 무제한, Pro 무제한".
    private func spoken(_ row: Row) -> String {
        let parts = zip(tiers, row.cells).map { tier, cell -> String in
            let value: String = switch cell {
            case .yes: String(localized: "포함")
            case .no: String(localized: "없음")
            case .text(let text): text
            }
            return "\(shortName(tier)) \(value)"
        }
        return ([row.label] + parts).joined(separator: ", ")
    }
}

// MARK: - 잠긴 자리

/// 잠긴 단추 · 줄에 붙는 작은 자물쇠. 눌러 보기 전에 잠긴 걸 알 수 있게.
struct ProLockBadge: View {
    let feature: ProFeature

    var body: some View {
        Image(systemName: "lock.fill")
            .font(.body.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityLabel(String(localized: "잠김, \(feature.tier.title) 필요"))
    }
}

// MARK: - 걸은 지 이레째 되는 날

/// 걸음이 남은 날이 일곱이 된 날, 지도 위에 **한 번만** 서는 작은 카드. 무료로 쓰는 사람에게만, 닫기 쉽게.
/// 일주일치 길이 쌓여 지도가 제 모양을 갖추기 시작한 지금이 꾸미고 자랑하고 싶어지는 때다.
struct SeventhDayNudge: View {
    /// 지금까지 그린 길이(m)
    let atlasMeters: Double
    let onShowPlans: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shoeprints.fill")
                .font(.title3)
                .foregroundStyle(Color(InkStyle.sealRed))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("지금까지 그린 길 \(DayTimeline.distanceText(atlasMeters))")
                    .font(.headline)
                    .foregroundStyle(Color(InkStyle.ink))
                Text("일주일 동안 걸어 그린 내 지도예요. Plus로 꾸미고, Pro로 위젯과 영상까지 가져가요.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("요금제 보기", action: onShowPlans)
                    .buttonStyle(.bordered)
                    .tint(Color(InkStyle.sealRed))
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("닫기"))
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - 카드 바탕

private struct PaywallCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private extension View {
    func paywallCard() -> some View { modifier(PaywallCard()) }
}
