import StoreKit
import SwiftUI

struct SubscriptionView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var membershipStore: MembershipStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        NavigationStack {
            ZStack {
                CelestialBackdrop()
                    .ignoresSafeArea()

                if membershipStore.products.isEmpty {
                    unavailableStoreContent
                } else {
                    activeStoreContent
                }
            }
            .foregroundStyle(.white)
            .navigationTitle(store.language.text("星光會員", "별빛 멤버십", "Starlight Membership"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.language.text("關閉", "닫기", "Close"), action: dismiss.callAsFunction)
                }
            }
        }
        .task { await membershipStore.prepare() }
        .alert(item: Binding(
            get: { membershipStore.notice },
            set: { if $0 == nil { membershipStore.dismissNotice() } }
        )) { notice in
            noticeAlert(notice)
        }
    }

    private func noticeAlert(_ notice: MembershipNotice) -> Alert {
        let copy = noticeCopy(notice)
        return Alert(
            title: Text(copy.title),
            message: Text(copy.message),
            dismissButton: .default(Text(store.language.text("知道了", "확인", "OK"))) {
                membershipStore.dismissNotice()
            }
        )
    }

    private func noticeCopy(_ notice: MembershipNotice) -> (title: String, message: String) {
        switch notice {
        case .pending:
            return (
                store.language.text("正在等待確認", "승인 대기 중", "Waiting for approval"),
                store.language.text(
                    "這筆購買還在等待 App Store 或家長核准。確認完成後，會員資格會自動更新。",
                    "이 구매는 App Store 또는 보호자 승인을 기다리고 있어요. 승인이 끝나면 멤버십이 자동으로 업데이트됩니다.",
                    "This purchase is waiting for App Store or parental approval. Membership will update automatically once it is approved."
                )
            )
        case .verificationFailed:
            return (
                store.language.text("無法驗證這筆購買", "구매를 확인할 수 없어요", "Couldn't verify this purchase"),
                store.language.text(
                    "App Store 沒有回傳可驗證的交易，因此目前不會解鎖會員。請稍後再試或恢復購買。",
                    "App Store에서 확인 가능한 거래를 받지 못해 멤버십을 열지 않았어요. 잠시 후 다시 시도하거나 구매를 복원해 주세요.",
                    "The App Store didn't return a verifiable transaction, so membership remains locked. Try again later or restore purchases."
                )
            )
        case .restored(true):
            return (
                store.language.text("會員資格已恢復", "멤버십을 복원했어요", "Membership restored"),
                store.language.text("你的星光會員功能已重新開啟。", "별빛 멤버십 기능을 다시 열었어요.", "Your Starlight Membership features are available again.")
            )
        case .restored(false):
            return (
                store.language.text("沒有找到有效訂閱", "활성 구독을 찾지 못했어요", "No active subscription found"),
                store.language.text(
                    "這個 Apple 帳號目前沒有可恢復的星光會員方案。",
                    "이 Apple 계정에는 복원할 수 있는 별빛 멤버십이 없어요.",
                    "There isn't an active Starlight Membership to restore for this Apple Account."
                )
            )
        case .failed:
            return (
                store.language.text("App Store 暫時無法完成操作", "App Store 작업을 완료할 수 없어요", "The App Store couldn't finish"),
                store.language.text(
                    "請確認網路與 Apple 帳號狀態後再試一次。這次沒有完成付款，也不會解鎖會員。",
                    "네트워크와 Apple 계정 상태를 확인한 뒤 다시 시도해 주세요. 이번 결제는 완료되지 않았고 멤버십도 열리지 않았어요.",
                    "Check your connection and Apple Account, then try again. No payment completed, and membership remains locked."
                )
            )
        }
    }

    private var activeStoreContent: some View {
        SubscriptionStoreView(subscriptions: membershipStore.products) {
            marketingContent
        }
            .subscriptionStoreControlStyle(.prominentPicker)
            .subscriptionStoreButtonLabel(.multiline)
            .storeButton(.visible, for: .restorePurchases)
            .subscriptionStorePolicyDestination(for: .privacyPolicy) {
                SubscriptionPrivacyView()
            }
            .subscriptionStorePolicyDestination(
                url: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!,
                for: .termsOfService
            )
            .subscriptionStorePolicyForegroundStyle(.white, .white.opacity(0.72))
            .tint(Color.celestialPink)
            .foregroundStyle(.white)
            .background(.clear)
            .onInAppPurchaseCompletion { _, result in
                await membershipStore.purchaseFinished(result)
            }
    }

    private var unavailableStoreContent: some View {
        ScrollView {
            VStack(spacing: 22) {
                marketingContent

                VStack(spacing: 12) {
                    if membershipStore.isLoadingProducts {
                        ProgressView()
                            .tint(.white)
                        Text(store.language.text("正在向 App Store 取得方案…", "App Store에서 요금제를 불러오는 중…", "Loading plans from the App Store…"))
                    } else {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.title2)
                            .foregroundStyle(Color.celestialGold)
                        Text(store.language.text("目前無法取得會員方案", "현재 멤버십 요금제를 불러올 수 없어요", "Membership plans are unavailable right now"))
                            .font(.headline)
                        Text(store.language.text("請確認網路後再試一次。已訂閱的話，也可以恢復購買。", "네트워크를 확인한 뒤 다시 시도해 주세요. 이미 구독했다면 구매 복원을 이용할 수 있어요.", "Check your connection and try again. If you've subscribed before, you can also restore purchases."))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.68))
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: 620)
                .padding(22)
                .celestialSurface(
                    Color.white.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 22),
                    reducedColor: .celestialSurfaceElevated
                )

                HStack(spacing: 12) {
                    Button {
                        Task { await membershipStore.loadProducts() }
                    } label: {
                        Label(store.language.text("再試一次", "다시 시도", "Try again"), systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .celestialGlassButtonStyle(prominent: true)
                    .tint(Color.celestialPink)
                    .disabled(membershipStore.isLoadingProducts)

                    Button {
                        Task { await membershipStore.restorePurchases() }
                    } label: {
                        Label(store.language.text("恢復購買", "구매 복원", "Restore purchases"), systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .celestialGlassButtonStyle()
                    .disabled(membershipStore.isRestoring)
                }
                .frame(maxWidth: 620)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 32)
        }
    }

    private var marketingContent: some View {
        VStack(spacing: horizontalSizeClass == .regular ? 22 : 16) {
            Image("LuckyStarCelebrate")
                .resizable()
                .scaledToFit()
                .frame(width: horizontalSizeClass == .regular ? 176 : 126)
                .shadow(color: Color.celestialPink.opacity(0.38), radius: 24, y: 10)
                .accessibilityHidden(true)

            VStack(spacing: 7) {
                Text(store.language.text("讓每天的星光多一點", "매일의 별빛을 조금 더", "A little more starlight, every day"))
                    .font(horizontalSizeClass == .regular ? .largeTitle.bold() : .title.bold())
                    .multilineTextAlignment(.center)
                Text(store.language.text(
                    "不限次數翻看今日指引，也能隨時重新抽一張塔羅牌。",
                    "오늘의 메시지를 원하는 만큼 다시 보고, 언제든 타로 카드를 새로 뽑아 보세요.",
                    "Replay today's guidance and draw fresh tarot cards whenever you like."
                ))
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.76))
            }

            Group {
                if horizontalSizeClass == .regular {
                    HStack(spacing: 12) {
                        benefit(
                            store.language.text("塔羅不限次數", "타로 무제한", "Unlimited tarot"),
                            symbol: "rectangle.portrait.on.rectangle.portrait"
                        )
                        benefit(
                            store.language.text("指引自由重翻", "메시지 다시 보기", "Replay guidance"),
                            symbol: "rectangle.on.rectangle.angled"
                        )
                        benefit(
                            store.language.text("支援星伴成長", "별친구의 성장을 응원", "Help Little Star grow"),
                            symbol: "star.fill"
                        )
                    }
                } else {
                    VStack(spacing: 9) {
                        benefit(
                            store.language.text("塔羅不限次數", "타로 무제한", "Unlimited tarot"),
                            symbol: "rectangle.portrait.on.rectangle.portrait"
                        )
                        benefit(
                            store.language.text("指引自由重翻", "메시지 다시 보기", "Replay guidance"),
                            symbol: "rectangle.on.rectangle.angled"
                        )
                        benefit(
                            store.language.text("支援星伴成長", "별친구의 성장을 응원", "Help Little Star grow"),
                            symbol: "star.fill"
                        )
                    }
                }
            }
            .frame(maxWidth: 820)

            if let monthly = membershipStore.monthlyProduct,
               let yearly = membershipStore.yearlyProduct {
                HStack(spacing: 10) {
                    planPrice(
                        store.language.text("月繳", "월간", "Monthly"),
                        price: monthly.displayPrice,
                        period: store.language.text("／月", "/월", "/month")
                    )
                    planPrice(
                        store.language.text("年繳", "연간", "Yearly"),
                        price: yearly.displayPrice,
                        period: store.language.text("／年", "/년", "/year"),
                        badge: membershipStore.yearlySavingsPercentage.map {
                            store.language.text("省 \($0)%", "\($0)% 절약", "Save \($0)%")
                        }
                    )
                }
                .frame(maxWidth: 620)
                .accessibilityElement(children: .contain)
            }

            Text(store.language.text(
                "付款由 App Store 安全處理，星伴不會取得你的付款資料。訂閱會自動續訂，可隨時在 Apple 帳號中管理或取消。",
                "결제는 App Store에서 안전하게 처리되며 별친구는 결제 정보를 받지 않습니다. 구독은 자동 갱신되며 Apple 계정에서 언제든 관리하거나 취소할 수 있어요.",
                "The App Store securely handles payment; Star Companion never receives your payment details. Subscriptions renew automatically and can be managed or canceled from your Apple Account."
            ))
            .font(.caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white.opacity(0.64))
            .frame(maxWidth: 680)
        }
        .padding(.horizontal, horizontalSizeClass == .regular ? 36 : 20)
        .padding(.top, horizontalSizeClass == .regular ? 30 : 18)
    }

    private func benefit(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 14)
            .celestialSurface(
                Color.white.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 18),
                reducedColor: .celestialSurfaceElevated
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
    }

    private func planPrice(_ title: String, price: String, period: String, badge: String? = nil) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                if let badge {
                    Text(badge)
                        .font(.caption2.bold())
                        .foregroundStyle(Color.celestialGold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .celestialSurface(
                            Color.celestialGold.opacity(0.13),
                            in: Capsule(),
                            reducedColor: .celestialSurfaceElevated,
                            reducedBoundaryColor: Color.celestialGold.opacity(0.72)
                        )
                }
            }
            Text(price + period)
                .font(.headline.weight(.bold))
        }
        .frame(maxWidth: .infinity, minHeight: 68)
        .celestialSurface(
            Color.white.opacity(0.09),
            in: RoundedRectangle(cornerRadius: 17),
            reducedColor: .celestialSurfaceElevated
        )
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct SubscriptionPrivacyView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        List {
            Section {
                Label {
                    Text(store.language.text(
                        "會員資格與付款由 App Store 處理。正式登入後，運勢、塔羅與星球資料會跟著星伴帳號同步。星伴不會取得你的付款資料，也不出售或用這些內容追蹤你。",
                        "멤버십과 결제는 App Store에서 처리합니다. 정식 로그인 후에는 운세, 타로와 별 데이터가 별동무 계정을 따라 동기화됩니다. 별동무는 결제 정보를 받지 않으며, 이 콘텐츠를 판매하거나 추적에 사용하지 않습니다.",
                        "Membership and payment are handled by the App Store. After a verified sign-in, fortunes, tarot readings, and planet data sync with the Star Companion account. Star Companion doesn't receive your payment details, sell this content, or use it to track you."
                    ))
                } icon: {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(Color("AccentColor"))
                }
            }

            Section(store.language.text("訂閱與付款", "구독 및 결제", "Subscription & payment")) {
                Text(store.language.text(
                    "購買、續訂與付款資料由 Apple 和 App Store 處理。星伴只讀取經 App Store 驗證的有效訂閱狀態，用來解鎖會員功能。",
                    "구매, 갱신 및 결제 정보는 Apple과 App Store에서 처리합니다. 별친구는 회원 기능을 열기 위해 App Store에서 확인된 구독 상태만 읽습니다.",
                    "Apple and the App Store handle purchases, renewals, and payment details. Star Companion reads only the App Store-verified entitlement needed to unlock member features."
                ))
            }
        }
        .navigationTitle(store.language.text("隱私權政策", "개인정보 처리방침", "Privacy Policy"))
    }
}
