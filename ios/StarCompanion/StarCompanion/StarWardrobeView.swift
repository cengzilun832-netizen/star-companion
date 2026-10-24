import StoreKit
import SwiftUI

struct StarWardrobeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var membershipStore: MembershipStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var successFeedback = 0
    @State private var errorFeedback = 0
    @State private var selectedCollectionRarity: StarSkinRarity?

    private var isCatalogPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--preview-skin-catalog")
            || ProcessInfo.processInfo.arguments.contains("--preview-skin-collection-only")
        #else
        false
        #endif
    }

    private var isCollectionOnlyPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--preview-skin-collection-only")
        #else
        false
        #endif
    }

    private var personasForDisplay: [StarPersona] {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-skin-catalog-tail") {
            return [
                .prismAurora, .azureButterfly, .velvetEclipse,
                .lunarTide, .moonveil, .frostNocturne,
                .moonRabbit, .halloweenGhost,
            ]
        }
        #endif
        return StarPersona.allCases
    }

    private var collectionSkinsForDisplay: [StarSkinCatalogItem] {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-skin-catalog-tail") {
            return Array(StarSkinCatalog.all.suffix(8))
        }
        #endif
        guard let selectedCollectionRarity else { return StarSkinCatalog.all }
        return StarSkinCatalog.all.filter { $0.rarity == selectedCollectionRarity }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if !isCatalogPreview {
                    previewCard
                    allLooksPurchaseCard
                }
                if !isCollectionOnlyPreview {
                    personaSection
                }
                if !isCatalogPreview {
                    tarotStyleCard
                    auraSection
                    accessorySection
                }
                collectionSkinSection
            }
            .frame(maxWidth: 1080)
            .padding(.horizontal, horizontalSizeClass == .regular ? 28 : 16)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
        }
        .background { CelestialBackdrop().ignoresSafeArea() }
        .navigationTitle(
            horizontalSizeClass == .regular
                ? ""
                : (isCatalogPreview
                    ? store.language.text("小星形象圖鑑", "작은 별 도감", "Little Star Looks")
                    : store.language.text("裝扮小星", "별 꾸미기", "Dress Up Little Star"))
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sensoryFeedback(.success, trigger: successFeedback)
        .sensoryFeedback(.warning, trigger: errorFeedback)
        .task {
            await membershipStore.prepare()
            if membershipStore.hasCheckedEntitlements {
                store.updateAllLooksEntitlement(membershipStore.hasAllLooksUnlocked)
            }
        }
        .onChange(of: membershipStore.hasAllLooksUnlocked) { _, isUnlocked in
            store.updateAllLooksEntitlement(isUnlocked)
            if isUnlocked {
                successFeedback += 1
            }
        }
        .alert(item: Binding(
            get: { membershipStore.allLooksNotice },
            set: { if $0 == nil { membershipStore.dismissAllLooksNotice() } }
        )) { notice in
            allLooksNoticeAlert(notice)
        }
    }

    private var previewCard: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 18) {
                    previewStar
                        .frame(maxWidth: .infinity)
                    previewCopy
                }
            } else {
                HStack(spacing: horizontalSizeClass == .regular ? 30 : 18) {
                    previewStar
                    previewCopy
                }
            }
        }
        .foregroundStyle(.white)
        .padding(horizontalSizeClass == .regular ? 26 : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .celestialSurface(
            Color.white.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 28)
        )
        .overlay { RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.12), lineWidth: 1) }
    }

    private var previewStar: some View {
            StyledStarView(
                wardrobe: store.wardrobe,
                size: horizontalSizeClass == .regular ? 190 : (dynamicTypeSize.isAccessibilitySize ? 150 : 132)
            )
            .accessibilityLabel(store.language.text("目前的小星造型", "현재 별 꾸미기", "Current Little Star style"))
    }

    private var previewCopy: some View {
        VStack(alignment: .leading, spacing: 9) {
                Text(store.language.text("這顆星，只屬於你", "이 별은 오직 당신만의 별", "A star that's uniquely yours"))
                    .font(horizontalSizeClass == .regular ? .largeTitle.bold() : .title2.bold())
                Text(store.language.text(
                    membershipStore.hasAllLooksUnlocked
                        ? "全部造型都已經在衣櫥裡，挑一個今天最像你的樣子。"
                        : "每個帳號都有自己的起始小星。闖關賺星幣，再慢慢把喜歡的形象收進衣櫥。",
                    membershipStore.hasAllLooksUnlocked
                        ? "모든 꾸미기가 옷장에 준비됐어요. 오늘의 나와 가장 닮은 모습을 골라 보세요."
                        : "계정마다 자신만의 첫 별을 만나요. 스테이지에서 별 코인을 모아 좋아하는 모습을 하나씩 소장해 보세요.",
                    membershipStore.hasAllLooksUnlocked
                        ? "Every look is ready in your wardrobe. Pick the one that feels most like you today."
                        : "Every account begins with its own Little Star. Clear stages, earn Star Coins, and slowly collect the looks you love."
                ))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .lineSpacing(4)

                Label(
                    store.language.text("\(store.wardrobe.starCoins) 星幣", "별 코인 \(store.wardrobe.starCoins)개", "\(store.wardrobe.starCoins) Star Coins"),
                    systemImage: "sparkles"
                )
                .font(.headline.monospacedDigit())
                .foregroundStyle(Color.celestialGold)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .celestialSurface(
                    Color.white.opacity(0.10),
                    in: Capsule(),
                    reducedColor: .celestialSurfaceElevated
                )
        }
    }

    private var allLooksPurchaseCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: membershipStore.hasAllLooksUnlocked
                    ? "sparkles.square.filled.on.square"
                    : "square.stack.3d.up.fill")
                    .font(.title2)
                    .foregroundStyle(Color.celestialGold)
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(store.language.text(
                        "一次解鎖全部造型",
                        "모든 꾸미기 한 번에 잠금 해제",
                        "Unlock every look"
                    ))
                    .font(.title3.bold())

                    Text(store.language.text(
                        "衣櫥裡已推出的形象、收藏造型和配件，現在和之後新增的都能直接換上，也不用花星幣。",
                        "옷장에 출시된 모습, 컬렉션 스킨, 장식을 지금부터 새로 추가되는 것까지 별 코인 없이 바로 사용할 수 있어요.",
                        "Use every released persona, collection skin, and accessory without Star Coins—including looks added later."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.76))
                    .lineSpacing(3)
                }

                Spacer(minLength: 0)
            }

            if membershipStore.hasAllLooksUnlocked {
                Label(
                    store.language.text(
                        "全部造型已解鎖",
                        "모든 꾸미기 잠금 해제 완료",
                        "All looks unlocked"
                    ),
                    systemImage: "checkmark.seal.fill"
                )
                .font(.headline)
                .foregroundStyle(Color.celestialNight)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color.celestialGold, in: Capsule())
                .accessibilityHint(store.language.text(
                    "現在可以直接使用衣櫥內所有已推出造型",
                    "이제 옷장에 출시된 모든 꾸미기를 바로 사용할 수 있어요",
                    "You can now use every released look in the wardrobe"
                ))
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        allLooksPurchaseButton
                        restoreAllLooksButton
                    }
                    VStack(spacing: 10) {
                        allLooksPurchaseButton
                        restoreAllLooksButton
                    }
                }

                if membershipStore.allLooksProduct == nil,
                   !membershipStore.isLoadingProducts {
                    Button {
                        Task { await membershipStore.loadProducts() }
                    } label: {
                        Label(
                            store.language.text("重新取得價格", "가격 다시 불러오기", "Reload price"),
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.celestialGold)
                    .accessibilityHint(store.language.text(
                        "重新向 App Store 查詢這項購買",
                        "App Store에서 이 구매 항목을 다시 확인해요",
                        "Checks the App Store for this purchase again"
                    ))
                }
            }

            Text(store.language.text(
                "一次買斷，不是訂閱。尚未推出的造型會等正式上架後才加入；付款與恢復購買由 App Store 處理。",
                "일회성 구매이며 구독이 아니에요. 아직 출시되지 않은 모습은 정식 공개 후 포함되며, 결제와 복원은 App Store에서 처리합니다.",
                "One purchase, not a subscription. Unreleased looks join only when they launch; the App Store handles payment and restoration."
            ))
            .font(.caption)
            .foregroundStyle(.white.opacity(0.60))
        }
        .foregroundStyle(.white)
        .padding(horizontalSizeClass == .regular ? 24 : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .celestialSurface(
            Color.celestialPlum.opacity(0.42),
            in: RoundedRectangle(cornerRadius: 26),
            reducedColor: .celestialSurfaceElevated,
            reducedBoundaryColor: Color.celestialGold.opacity(0.48)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 26)
                .stroke(Color.celestialGold.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var allLooksPurchaseButton: some View {
        Button {
            Task {
                await membershipStore.purchaseAllLooks(
                    appAccountToken: store.storeKitAppAccountToken
                )
            }
        } label: {
            HStack(spacing: 8) {
                if membershipStore.isPurchasingAllLooks {
                    ProgressView()
                        .tint(Color.celestialNight)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(allLooksPurchaseButtonTitle)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(Color.celestialGold)
        .foregroundStyle(Color.celestialNight)
        .disabled(
            membershipStore.allLooksProduct == nil
                || membershipStore.isPurchasingAllLooks
                || membershipStore.isRestoring
        )
        .accessibilityLabel(allLooksPurchaseButtonTitle)
        .accessibilityHint(store.language.text(
            "開啟 App Store 的一次性購買確認",
            "App Store의 일회성 구매 확인을 열어요",
            "Opens the App Store confirmation for a one-time purchase"
        ))
    }

    private var allLooksPurchaseButtonTitle: String {
        if membershipStore.isPurchasingAllLooks {
            return store.language.text("正在連接 App Store", "App Store에 연결 중", "Connecting to the App Store")
        }
        if let product = membershipStore.allLooksProduct {
            return store.language.text(
                "解鎖全部 · \(product.displayPrice)",
                "모두 잠금 해제 · \(product.displayPrice)",
                "Unlock all · \(product.displayPrice)"
            )
        }
        return membershipStore.isLoadingProducts
            ? store.language.text("正在取得價格", "가격 불러오는 중", "Loading price")
            : store.language.text("暫時無法購買", "지금은 구매할 수 없어요", "Currently unavailable")
    }

    private var restoreAllLooksButton: some View {
        Button {
            Task { await membershipStore.restoreAllLooksPurchase() }
        } label: {
            HStack(spacing: 8) {
                if membershipStore.isRestoring {
                    ProgressView()
                        .tint(.white)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
                Text(membershipStore.isRestoring
                    ? store.language.text("正在恢復", "복원 중", "Restoring")
                    : store.language.text("恢復購買", "구매 복원", "Restore purchase"))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(.white)
        .disabled(membershipStore.isRestoring || membershipStore.isPurchasingAllLooks)
        .accessibilityHint(store.language.text(
            "重新檢查這個 Apple 帳號買過的全部造型",
            "이 Apple 계정에서 구매한 모든 꾸미기를 다시 확인해요",
            "Checks this Apple Account for an earlier all-looks purchase"
        ))
    }

    private func allLooksNoticeAlert(_ notice: AllLooksPurchaseNotice) -> Alert {
        let copy: (title: String, message: String) = switch notice {
        case .pending:
            (
                store.language.text("購買還在處理", "구매 처리 중", "Purchase pending"),
                store.language.text(
                    "App Store 還在確認這筆購買，完成後衣櫥會自動解鎖。",
                    "App Store에서 구매를 확인하고 있어요. 완료되면 옷장이 자동으로 열립니다.",
                    "The App Store is still confirming this purchase. The wardrobe will unlock automatically when it finishes."
                )
            )
        case .verificationFailed:
            (
                store.language.text("還不能解鎖", "아직 잠금 해제할 수 없어요", "Couldn't unlock yet"),
                store.language.text(
                    "這次沒有取得可驗證的 App Store 購買紀錄，沒有解鎖造型。請稍後重試或恢復購買。",
                    "확인 가능한 App Store 구매 내역을 받지 못해 꾸미기가 잠금 해제되지 않았어요. 잠시 후 다시 시도하거나 구매를 복원해 주세요.",
                    "No verifiable App Store transaction was returned, so the looks remain locked. Try again later or restore the purchase."
                )
            )
        case .purchased:
            (
                store.language.text("全部造型已解鎖", "모든 꾸미기가 열렸어요", "All looks unlocked"),
                store.language.text(
                    "已推出的形象、收藏造型和配件現在都可以直接換上。之後新增的造型也會一起加入。",
                    "출시된 모습, 컬렉션 스킨, 장식을 이제 바로 사용할 수 있어요. 앞으로 추가되는 꾸미기도 함께 열립니다.",
                    "Every released persona, collection skin, and accessory is ready to use. Future additions will unlock too."
                )
            )
        case .restored(let hasEntitlement):
            hasEntitlement
                ? (
                    store.language.text("購買已恢復", "구매를 복원했어요", "Purchase restored"),
                    store.language.text("全部造型可以再次使用了。", "모든 꾸미기를 다시 사용할 수 있어요.", "All looks are available again.")
                )
                : (
                    store.language.text("沒有找到購買紀錄", "구매 내역을 찾지 못했어요", "No purchase found"),
                    store.language.text(
                        "這個 Apple 帳號目前沒有可恢復的全部造型購買。",
                        "이 Apple 계정에서 복원할 모든 꾸미기 구매 내역을 찾지 못했어요.",
                        "No all-looks purchase was found for this Apple Account."
                    )
                )
        case .failed(let message):
            (
                store.language.text("暫時無法連接 App Store", "App Store에 연결할 수 없어요", "Couldn't reach the App Store"),
                message
            )
        }

        return Alert(
            title: Text(copy.title),
            message: Text(copy.message),
            dismissButton: .default(Text(store.language.text("好", "확인", "OK"))) {
                membershipStore.dismissAllLooksNotice()
            }
        )
    }

    private var personaSection: some View {
        wardrobeSection(
            title: store.language.text("你的小星形象", "나의 작은 별", "Your Little Star"),
            subtitle: store.language.text(
                "大家的小星不需要長得一樣。先選一個最像你的，以後還會加入更多。",
                "모두의 별이 같을 필요는 없어요. 지금 나를 가장 닮은 모습을 골라 보세요. 새로운 모습도 계속 추가할게요.",
                "No two Little Stars need to look alike. Choose the one that feels like you; more looks will arrive over time."
            )
        ) {
            LazyVGrid(columns: wardrobeColumns, spacing: 12) {
                ForEach(personasForDisplay) { persona in
                    personaButton(persona)
                }
            }
        }
    }

    private func personaButton(_ persona: StarPersona) -> some View {
        let isOwned = store.wardrobe.availablePersonas.contains(persona)
        let isUsable = store.canUsePersona(
            persona,
            hasAllLooksUnlocked: membershipStore.hasAllLooksUnlocked
        )
        let isIncluded = isUsable && !isOwned
        let isSelected = store.wardrobe.selectedCollectionSkinID == nil
            && store.wardrobe.displayedPersona == persona
        let isAvailable = persona.isAvailable()

        return Button {
            if isUsable {
                store.selectPersona(
                    persona,
                    hasAllLooksUnlocked: membershipStore.hasAllLooksUnlocked
                )
                successFeedback += 1
            } else if store.purchasePersona(
                persona,
                hasAllLooksUnlocked: membershipStore.hasAllLooksUnlocked
            ) {
                successFeedback += 1
            } else {
                errorFeedback += 1
            }
        } label: {
            VStack(spacing: 7) {
                Image(persona.assetName)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(height: horizontalSizeClass == .regular ? 104 : 88)
                    .accessibilityHidden(true)

                Text(persona.title(in: store.language))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Label(
                    isUsable
                        ? (isSelected
                            ? store.language.text("現在的樣子", "현재 모습", "Current look")
                            : (isIncluded
                                ? store.language.text("已解鎖", "잠금 해제", "Unlocked")
                                : store.language.text("已擁有", "보유 중", "Owned")))
                        : (isAvailable
                            ? "\(persona.price)"
                            : store.language.text("等待相遇", "만날 날을 기다려요", "Coming soon")),
                    systemImage: isUsable
                        ? (isSelected ? "checkmark.circle.fill" : (isIncluded ? "lock.open.fill" : "checkmark"))
                        : (isAvailable ? "sparkles" : "lock.fill")
                )
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(isSelected ? Color.celestialPink : .white.opacity(0.72))

                if let seasonalNote = persona.seasonalNote(in: store.language) {
                    Text(seasonalNote)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(.white)
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: horizontalSizeClass == .regular ? 178 : 164)
            .celestialSurface(
                isSelected ? Color.celestialPlum.opacity(0.82) : Color.white.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 20),
                reducedColor: isSelected ? .celestialPlum : .celestialSurfaceOpaque
            )
            .overlay { RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(isSelected ? 0.25 : 0.10), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .disabled(!isUsable && !isAvailable)
        .accessibilityLabel(persona.title(in: store.language))
        .accessibilityHint(
            isUsable
                ? store.language.text("點一下換成這個形象", "탭하여 이 모습으로 바꿔요", "Tap to use this look")
                : (isAvailable
                    ? store.language.text("需要 \(persona.price) 星幣", "별 코인 \(persona.price)개 필요", "Costs \(persona.price) Star Coins")
                    : store.language.text("限定期間開放", "한정 기간에 열려요", "Available during its limited season"))
        )
    }

    private var collectionSkinSection: some View {
        wardrobeSection(
            title: store.language.text(
                "星星收藏館 · \(StarSkinCatalog.all.count)",
                "별 컬렉션 · \(StarSkinCatalog.all.count)",
                "Star Collection · \(StarSkinCatalog.all.count)"
            ),
            subtitle: store.language.text(
                "從星星圖庫裡慢慢挑。不必一次收齊，喜歡哪顆再帶回家。",
                "별 도감을 천천히 둘러보세요. 모두 모을 필요 없이, 마음에 드는 별만 데려오면 돼요.",
                "Take your time browsing the star archive. You don't need them all—bring home only the ones you love."
            )
        ) {
            VStack(alignment: .leading, spacing: 14) {
                collectionRarityFilters

                LazyVGrid(columns: wardrobeColumns, spacing: 12) {
                    ForEach(collectionSkinsForDisplay) { skin in
                        collectionSkinButton(skin)
                    }
                }
            }
        }
    }

    private var collectionRarityFilters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                collectionFilterButton(
                    title: store.language.text("全部", "전체", "All"),
                    rarity: nil
                )
                ForEach(StarSkinRarity.allCases) { rarity in
                    collectionFilterButton(title: rarity.title(in: store.language), rarity: rarity)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func collectionFilterButton(title: String, rarity: StarSkinRarity?) -> some View {
        let isSelected = selectedCollectionRarity == rarity
        return Button {
            if reduceMotion {
                selectedCollectionRarity = rarity
            } else {
                withAnimation(.snappy(duration: 0.25)) {
                    selectedCollectionRarity = rarity
                }
            }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.celestialNight : .white.opacity(0.76))
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .celestialSurface(
                    isSelected ? Color.celestialGold : Color.white.opacity(0.08),
                    in: Capsule(),
                    reducedColor: isSelected ? .celestialGold : .celestialSurfaceOpaque,
                    reducedBoundaryColor: isSelected
                        ? Color.celestialNight.opacity(0.72)
                        : Color.white.opacity(0.30)
                )
        }
        .buttonStyle(.plain)
    }

    private func collectionSkinButton(_ skin: StarSkinCatalogItem) -> some View {
        let isOwned = store.wardrobe.availableCollectionSkinIDs.contains(skin.id)
        let isIncluded = membershipStore.hasAllLooksUnlocked && !isOwned
        let isUsable = store.canUseCollectionSkin(
            skin,
            hasAllLooksUnlocked: membershipStore.hasAllLooksUnlocked
        )
        let isSelected = store.wardrobe.selectedCollectionSkinID == skin.id

        return Button {
            if isUsable {
                store.selectCollectionSkin(
                    skin,
                    hasAllLooksUnlocked: membershipStore.hasAllLooksUnlocked
                )
                successFeedback += 1
            } else if store.purchaseCollectionSkin(
                skin,
                hasAllLooksUnlocked: membershipStore.hasAllLooksUnlocked
            ) {
                successFeedback += 1
            } else {
                errorFeedback += 1
            }
        } label: {
            VStack(spacing: 7) {
                Image(skin.assetName)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(height: horizontalSizeClass == .regular ? 104 : 88)
                    .accessibilityHidden(true)

                Text(skin.title(in: store.language))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(skin.rarity.title(in: store.language))
                    .font(.caption2.bold())
                    .foregroundStyle(rarityColor(skin.rarity))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .celestialSurface(
                        rarityColor(skin.rarity).opacity(0.13),
                        in: Capsule(),
                        reducedColor: .celestialSurfaceElevated,
                        reducedBoundaryColor: rarityColor(skin.rarity).opacity(0.72)
                    )

                Label(
                    isUsable
                        ? (isSelected
                            ? store.language.text("現在的樣子", "현재 모습", "Current look")
                            : (isIncluded
                                ? store.language.text("已解鎖", "잠금 해제", "Unlocked")
                                : store.language.text("已擁有", "보유 중", "Owned")))
                        : "\(skin.price)",
                    systemImage: isUsable
                        ? (isSelected ? "checkmark.circle.fill" : (isIncluded ? "lock.open.fill" : "checkmark"))
                        : "sparkles"
                )
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(isSelected ? Color.celestialPink : .white.opacity(0.72))
            }
            .foregroundStyle(.white)
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: horizontalSizeClass == .regular ? 196 : 182)
            .celestialSurface(
                isSelected ? Color.celestialPlum.opacity(0.82) : Color.white.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 20),
                reducedColor: isSelected ? .celestialPlum : .celestialSurfaceOpaque
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(rarityColor(skin.rarity).opacity(isSelected ? 0.42 : 0.14), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(skin.title(in: store.language))
        .accessibilityValue(skin.rarity.title(in: store.language))
        .accessibilityHint(
            isUsable
                ? store.language.text("點一下換成這個形象", "탭하여 이 모습으로 바꿔요", "Tap to use this look")
                : store.language.text("需要 \(skin.price) 星幣", "별 코인 \(skin.price)개 필요", "Costs \(skin.price) Star Coins")
        )
    }

    private func rarityColor(_ rarity: StarSkinRarity) -> Color {
        switch rarity {
        case .common: .white.opacity(0.78)
        case .rare: .cyan
        case .epic: .celestialPink
        case .legendary: .celestialGold
        }
    }

    private var tarotStyleCard: some View {
        Toggle(isOn: Binding(
            get: { store.wardrobe.followsTarotMeaning },
            set: store.setFollowsTarotMeaning
        )) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.language.text(
                        "抽完牌，讓小星換上對應的星光",
                        "카드를 뽑으면 작은 별도 그 의미에 맞게 빛나요",
                        "Let tarot shape Little Star's glow"
                    ))
                        .font(.headline)
                    Text(store.language.text(
                        "會多一圈光環和小圖案，你選好的星星不會被換掉。",
                        "빛의 고리와 작은 무늬만 더해지고, 고른 별 모습은 그대로예요.",
                        "It adds a halo and small details without replacing the star you chose."
                    ))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
                }
            } icon: {
                Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                    .foregroundStyle(Color.celestialGold)
            }
        }
        .tint(Color.celestialPink)
        .foregroundStyle(.white)
        .padding(20)
        .celestialSurface(
            Color.white.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 22)
        )
    }

    private var auraSection: some View {
        wardrobeSection(
            title: store.language.text("選一種星光", "별빛 선택", "Choose a glow"),
            subtitle: store.language.text("手動星光會在關閉牌義跟隨時顯示。", "카드 연동을 끄면 선택한 별빛이 보여요.", "Your chosen glow appears whenever tarot matching is off.")
        ) {
            LazyVGrid(columns: wardrobeColumns, spacing: 12) {
                ForEach(StarAura.allCases) { aura in
                    Button {
                        store.selectAura(aura)
                        successFeedback += 1
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: aura.glowSymbol)
                                .font(.title2)
                                .foregroundStyle(Color.celestialGold)
                            Text(aura.title(in: store.language))
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.center)
                            Image(systemName: store.wardrobe.selectedAura == aura ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(store.wardrobe.selectedAura == aura ? Color.celestialPink : .white.opacity(0.40))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 126)
                        .celestialSurface(
                            store.wardrobe.selectedAura == aura
                                ? Color.celestialPlum.opacity(0.82)
                                : Color.white.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 20),
                            reducedColor: store.wardrobe.selectedAura == aura
                                ? .celestialPlum
                                : .celestialSurfaceOpaque
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var accessorySection: some View {
        wardrobeSection(
            title: store.language.text("配件小商店", "장식 상점", "Accessory Shop"),
            subtitle: store.language.text(
                "小道具會戴在「經典小星」上；完整造型已經有自己的服裝。",
                "작은 장식은 '기본 별'에 착용해요. 완성형 모습은 이미 자신만의 의상을 입고 있어요.",
                "Small accessories appear on Classic. Complete looks already include their own outfits."
            )
        ) {
            LazyVGrid(columns: wardrobeColumns, spacing: 12) {
                ForEach(StarAccessory.allCases) { accessory in
                    accessoryButton(accessory)
                }
            }
        }
    }

    private func accessoryButton(_ accessory: StarAccessory) -> some View {
        let isOwned = store.wardrobe.ownedAccessories.contains(accessory)
        let isIncluded = membershipStore.hasAllLooksUnlocked && !isOwned
        let isUsable = store.canUseAccessory(
            accessory,
            hasAllLooksUnlocked: membershipStore.hasAllLooksUnlocked
        )
        let isSelected = store.wardrobe.selectedAccessory == accessory

        return Button {
            if isUsable {
                store.selectAccessory(
                    accessory,
                    hasAllLooksUnlocked: membershipStore.hasAllLooksUnlocked
                )
                successFeedback += 1
            } else if store.purchaseAccessory(
                accessory,
                hasAllLooksUnlocked: membershipStore.hasAllLooksUnlocked
            ) {
                successFeedback += 1
            } else {
                errorFeedback += 1
            }
        } label: {
            VStack(spacing: 9) {
                Image(systemName: accessory.symbol)
                    .font(.title2)
                    .foregroundStyle(isUsable ? Color.celestialGold : .white.opacity(0.58))
                Text(accessory.title(in: store.language))
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                Label(
                    isUsable
                        ? (isSelected
                            ? store.language.text("使用中", "사용 중", "Equipped")
                            : (isIncluded
                                ? store.language.text("已解鎖", "잠금 해제", "Unlocked")
                                : store.language.text("已擁有", "보유 중", "Owned")))
                        : "\(accessory.price)",
                    systemImage: isUsable
                        ? (isSelected ? "checkmark.circle.fill" : (isIncluded ? "lock.open.fill" : "checkmark"))
                        : "sparkles"
                )
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(isSelected ? Color.celestialPink : .white.opacity(0.70))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 136)
            .celestialSurface(
                isSelected ? Color.celestialPlum.opacity(0.82) : Color.white.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 20),
                reducedColor: isSelected ? .celestialPlum : .celestialSurfaceOpaque
            )
            .overlay { RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.10), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityHint(
            isUsable
                ? store.language.text("點一下換上這個配件", "탭하여 이 장식을 착용해요", "Tap to equip this accessory")
                : store.language.text("需要 \(accessory.price) 星幣", "별 코인 \(accessory.price)개 필요", "Costs \(accessory.price) Star Coins")
        )
    }

    private func wardrobeSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.bold())
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.66))
            content()
        }
        .foregroundStyle(.white)
        .padding(20)
        .celestialSurface(
            Color.white.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }

    private var wardrobeColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 12),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : (horizontalSizeClass == .regular ? 4 : 2)
        )
    }
}
