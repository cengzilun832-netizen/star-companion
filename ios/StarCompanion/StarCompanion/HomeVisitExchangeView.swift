import SwiftUI

struct HomeVisitExchangeSheet: View {
    let link: PendingHomeVisitLink

    var body: some View {
        NavigationStack {
            switch link {
            case let .card(card):
                IncomingHomeVisitCardView(card: card)
            case let .receipt(receipt):
                IncomingHomeVisitReceiptView(receipt: receipt)
            }
        }
    }
}

private struct IncomingHomeVisitCardView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var reaction = HomeVisitReaction.warmWave
    @State private var sharesAlias = false
    @State private var receiptURL: URL?

    let card: HomeVisitCard

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SharedStarHomePreview(card: card)

                VStack(alignment: .leading, spacing: 8) {
                    Text(store.language.text("你收到一張小星訪客卡", "작은 별의 방문 카드가 도착했어요", "A Little Star visit card arrived"))
                        .font(.title2.bold())
                    Text(store.language.text(
                        "這是分享當下的房間快照，不會讀取對方之後的變動。",
                        "공유한 순간의 방 모습이에요. 이후 변경 사항을 읽지 않아요.",
                        "This is a snapshot of the room when it was shared. It doesn't read later changes."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
                    Label(expiryText, systemImage: "clock.fill")
                        .font(.caption)
                        .foregroundStyle(Color.celestialGold)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 12) {
                    Text(store.language.text("留下一個小反應", "작은 마음을 남겨요", "Leave a little reaction"))
                        .font(.headline)
                    Picker("", selection: $reaction) {
                        ForEach(HomeVisitReaction.allCases) { item in
                            Label(item.title(in: store.language), systemImage: item.symbol)
                                .tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle(isOn: $sharesAlias) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.language.text("在回條顯示我的暱稱", "답장 카드에 내 별명 표시", "Show my nickname on the reply"))
                                .font(.subheadline.weight(.semibold))
                            Text(store.language.text("預設關閉，也可以匿名留下一點星塵。", "기본값은 꺼짐이며 익명으로 별가루를 남길 수도 있어요.", "Off by default. You can leave Stardust anonymously."))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.60))
                        }
                    }
                    .tint(Color.celestialPink)

                    if let receiptURL {
                        ShareLink(item: receiptURL) {
                            Label(store.language.text("分享星塵回條給屋主", "별가루 답장을 주인에게 보내기", "Share Stardust reply with the host"), systemImage: "paperplane.fill")
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Color.celestialPlum)
                    } else {
                        Button {
                            prepareReceipt()
                        } label: {
                            Label(store.language.text("準備星塵回條", "별가루 답장 준비하기", "Prepare Stardust reply"), systemImage: "sparkles")
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Color.celestialPlum)
                    }

                    Text(store.language.text(
                        "回條不會扣除你的星塵。屋主收到並確認後，才會在自己的裝置上增加 8 點。",
                        "답장을 보내도 내 별가루는 줄지 않아요. 주인이 받아 확인한 뒤 자신의 기기에서 8개를 받아요.",
                        "The reply doesn't spend your Stardust. The host receives 8 on their device only after opening and accepting it."
                    ))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))

                    Label {
                        Text(store.language.text(
                            "這是離線預覽回條，沒有伺服器簽章，星塵不能交易或兌現。",
                            "이것은 서버 서명이 없는 오프라인 미리보기 답장입니다. 별가루는 거래하거나 현금화할 수 없어요.",
                            "This is an offline preview receipt without a server signature. Stardust can't be traded or redeemed for value."
                        ))
                    } icon: {
                        Image(systemName: "info.circle.fill")
                    }
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.52))
                }
                .padding(20)
                .background(.white.opacity(0.08), in: .rect(cornerRadius: 22))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: horizontalSizeClass == .regular ? 820 : 680)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background { CelestialBackdrop().ignoresSafeArea() }
        .navigationTitle(card.hostAlias ?? store.language.text("星友的房間", "별 친구의 방", "A star friend's room"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(store.language.text("完成", "완료", "Done")) {
                    store.dismissPendingHomeVisitLink()
                    dismiss()
                }
            }
        }
        .onChange(of: reaction) { _, _ in receiptURL = nil }
        .onChange(of: sharesAlias) { _, _ in receiptURL = nil }
    }

    private var expiryText: String {
        let date = card.expiresAt.formatted(.dateTime.month().day().locale(store.language.locale))
        return store.language.text("有效至 \(date)", "\(date)까지 유효", "Valid until \(date)")
    }

    private func prepareReceipt() {
        receiptURL = store.makeHomeVisitReceiptURL(
            for: card,
            reaction: reaction,
            sharesAlias: sharesAlias
        )
    }
}

private struct IncomingHomeVisitReceiptView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var outcome: HomeVisitReceiptAcceptance?

    let receipt: HomeVisitReceipt

    var body: some View {
        ZStack {
            CelestialBackdrop().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    ZStack {
                        Circle().fill(Color.celestialPlum.opacity(0.46)).frame(width: 170, height: 170)
                        Image(systemName: receipt.reaction.symbol)
                            .font(.system(size: 58, weight: .semibold))
                            .foregroundStyle(Color.celestialGold)
                    }

                    Text(store.language.text("有一位星友來過", "별 친구가 다녀갔어요", "A star friend stopped by"))
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                    Text(HomeVisitLinkCodec.sanitizedAlias(receipt.visitorAlias)
                         ?? store.language.text("匿名星友", "익명의 별 친구", "Anonymous star friend"))
                        .font(.headline)
                        .foregroundStyle(Color.celestialPink)
                    Label(receipt.reaction.title(in: store.language), systemImage: receipt.reaction.symbol)
                        .font(.subheadline.weight(.semibold))

                    Text(store.language.text(
                        "離線預覽回條沒有伺服器簽章，星塵只是本機遊戲數值，不能交易。",
                        "오프라인 미리보기 답장에는 서버 서명이 없으며, 별가루는 거래할 수 없는 기기 내 게임 수치예요.",
                        "Offline preview receipts aren't server-signed. Stardust is an on-device game value and can't be traded."
                    ))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
                    .multilineTextAlignment(.center)

                    if let outcome {
                        Label(outcomeText(outcome), systemImage: outcomeSymbol(outcome))
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(outcomeIsSuccess(outcome) ? Color.celestialGold : .white.opacity(0.72))
                            .padding(20)
                            .frame(maxWidth: .infinity)
                            .background(.white.opacity(0.08), in: .rect(cornerRadius: 22))
                    } else {
                        Button {
                            outcome = store.acceptHomeVisitReceipt(receipt)
                        } label: {
                            Label(store.language.text("收下這份星塵", "이 별가루 받기", "Accept this Stardust"), systemImage: "sparkles")
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Color.celestialPlum)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: 620)
                .padding(28)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(store.language.text("星塵回條", "별가루 답장", "Stardust Reply"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(store.language.text("完成", "완료", "Done")) {
                    store.dismissPendingHomeVisitLink()
                    dismiss()
                }
            }
        }
    }

    private func outcomeText(_ value: HomeVisitReceiptAcceptance) -> String {
        switch value {
        case let .accepted(reward):
            store.language.text("收下了 \(reward) 點星塵。", "별가루 \(reward)개를 받았어요.", "You received \(reward) Stardust.")
        case .acceptedWithoutReward:
            store.language.text("今天已收到三份星塵，這次仍會留下一筆溫柔的拜訪紀錄。", "오늘은 이미 세 번 별가루를 받았어요. 이번 방문도 따뜻한 기록으로 남아요.", "You've received three Stardust gifts today. This visit still stays as a warm memory.")
        case .alreadyAccepted:
            store.language.text("這張回條已經收過了。", "이미 받은 답장이에요.", "This reply was already accepted.")
        case .alreadyVisitedToday:
            store.language.text("這位星友今天已經來過了。", "이 별 친구는 오늘 이미 다녀갔어요.", "This star friend already visited today.")
        case .dailyLimitReached:
            store.language.text(
                "今天的離線訪客回條已收滿，明天再來看小星。",
                "오늘 받을 수 있는 오프라인 방문 답장을 모두 받았어요. 내일 다시 확인해 주세요.",
                "Today's offline visit-reply limit has been reached. Come back tomorrow."
            )
        case .expired:
            store.language.text("這張回條已經過期。", "이 답장은 만료됐어요.", "This reply has expired.")
        case .invalid:
            store.language.text("無法確認這張回條，請朋友從原本的訪客卡再分享一次。", "답장을 확인할 수 없어요. 원래 방문 카드에서 다시 보내 달라고 해 주세요.", "This reply couldn't be verified. Ask your friend to share it again from the original visit card.")
        }
    }

    private func outcomeSymbol(_ value: HomeVisitReceiptAcceptance) -> String {
        outcomeIsSuccess(value) ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
    }

    private func outcomeIsSuccess(_ value: HomeVisitReceiptAcceptance) -> Bool {
        switch value {
        case .accepted, .acceptedWithoutReward: true
        default: false
        }
    }
}

struct SharedStarHomePreview: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let card: HomeVisitCard

    private var theme: StarRoomTheme {
        card.appearance.roomThemeID.flatMap(StarRoomTheme.init(rawValue:)) ?? .observatoryGarden
    }

    private var furniture: [StarFurniture] {
        card.furnitureIDs.compactMap(StarFurniture.init(rawValue:))
    }

    private var visualMood: StarVisualMood {
        StarVisualMood.snapshot(card.appearance.moodID)
    }

    var body: some View {
        ZStack {
            Image("StarHabitat")
                .resizable()
                .scaledToFill()
                .overlay(themeOverlay)
            SeasonalRoomLayer(theme: theme)
            StarHabitatMoodLayer(mood: visualMood)
            SnapshotStarView(snapshot: card.appearance, size: horizontalSizeClass == .regular ? 168 : 126)
            ForEach(Array(furniture.enumerated()), id: \.element) { index, item in
                Image(systemName: item.symbol)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(Color.celestialGold)
                    .padding(10)
                    .background(.black.opacity(0.36), in: .circle)
                    .offset(x: CGFloat(index - 1) * 90, y: horizontalSizeClass == .regular ? 103 : 78)
            }
        }
        .frame(height: horizontalSizeClass == .regular ? 330 : 250)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: 26))
        .overlay(alignment: .topLeading) {
            Label(theme.title(in: store.language), systemImage: theme.symbol)
                .font(.caption.bold())
                .padding(10)
                .background(.black.opacity(0.36), in: .capsule)
                .padding(14)
        }
        .overlay { RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.12)) }
    }

    @ViewBuilder private var themeOverlay: some View {
        switch theme {
        case .observatoryGarden: Color.black.opacity(0.08)
        case .moonRabbitFestival: Color.orange.opacity(0.16).blendMode(.screen)
        case .halloweenGhostNight: Color.purple.opacity(0.28).blendMode(.multiply)
        case .christmasSnowRoom: Color.cyan.opacity(0.18).blendMode(.screen)
        }
    }
}
