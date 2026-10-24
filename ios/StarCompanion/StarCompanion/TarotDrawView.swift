import SwiftUI

struct TarotDrawView: View {
    private enum Phase: Equatable {
        case resting
        case shuffling
        case choosing
        case revealed
    }

    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var phase = Phase.resting

    let reading: TarotReadingRecord
    let onCancel: () -> Void
    let onReveal: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let usesWideLayout = proxy.size.width >= 760
                && proxy.size.width > proxy.size.height * 1.12
                && !dynamicTypeSize.isAccessibilitySize

            ZStack(alignment: .topTrailing) {
                CelestialBackdrop()
                    .ignoresSafeArea()

                if usesWideLayout {
                    wideRitual(in: proxy.size)
                } else {
                    ScrollView {
                        verticalRitual(in: proxy.size)
                            .frame(
                                minHeight: max(
                                    1,
                                    proxy.size.height
                                        - proxy.safeAreaInsets.top
                                        - proxy.safeAreaInsets.bottom
                                )
                            )
                    }
                    .scrollIndicators(.hidden)
                }

                closeButton
                    .padding(.top, max(proxy.safeAreaInsets.top, 12))
                    .padding(.trailing, max(proxy.safeAreaInsets.trailing, 18))
            }
        }
        .task { await performRitual() }
        .sensoryFeedback(.impact(weight: .light), trigger: phase)
        .sensoryFeedback(.success, trigger: phase == .revealed)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(store.language.text("塔羅抽牌儀式", "타로 카드 뽑기 의식", "Tarot card draw"))
    }

    private func verticalRitual(in size: CGSize) -> some View {
        let cardWidth = min(max(1, size.width - 48), 440)
        return VStack(spacing: 18) {
            starImage(width: min(size.width * 0.38, 190))
            ritualHeader
            cardStage(width: cardWidth)
                .frame(height: min(cardWidth * 0.75, 330))
            ritualAction
            privacyCopy
        }
        .padding(.horizontal, 24)
        .padding(.top, 66)
        .padding(.bottom, 24)
    }

    private func wideRitual(in size: CGSize) -> some View {
        let cardWidth = min(size.width * 0.46, 560)
        return HStack(spacing: min(size.width * 0.06, 78)) {
            VStack(spacing: 18) {
                starImage(width: min(size.height * 0.40, 290))
                ritualHeader
                privacyCopy
            }
            .frame(maxWidth: 430)

            VStack(spacing: 24) {
                cardStage(width: cardWidth)
                    .frame(height: min(size.height * 0.66, 470))
                ritualAction
            }
            .frame(maxWidth: 600)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, max(44, size.width * 0.07))
        .padding(.vertical, 40)
    }

    private func starImage(width: CGFloat) -> some View {
        Image("LuckyStarTarot")
            .resizable()
            .scaledToFit()
            .frame(width: width)
            .shadow(color: Color.celestialPink.opacity(0.28), radius: 20, y: 9)
            .accessibilityHidden(true)
    }

    private var ritualHeader: some View {
        VStack(spacing: 6) {
            Text(titleCopy)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(subtitleCopy)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.68))
        }
        .foregroundStyle(.white)
        .frame(minHeight: 74)
    }

    @ViewBuilder
    private var ritualAction: some View {
        if phase == .revealed {
            Button(action: onReveal) {
                Label(store.language.text("看牌義", "카드 해석 보기", "See what it means"), systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.celestialPlum)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            HStack(spacing: 8) {
                ProgressView()
                    .tint(.white)
                Text(store.language.text("正在洗牌…", "카드를 섞는 중…", "Shuffling…"))
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.72))
            .frame(maxWidth: .infinity, minHeight: 52)
        }
    }

    private var privacyCopy: some View {
        Text(store.language.text(
            "抽牌完成後，問題會存到目前帳號的塔羅紀錄。正式帳號會同步，本機預覽不會上傳。",
            "카드 뽑기를 마치면 질문이 현재 계정의 타로 기록에 저장돼요. 정식 계정은 동기화하고, 기기 미리보기는 업로드하지 않아요.",
            "After a draw, your question is saved in the current account's tarot history. Verified accounts sync it; local previews don't upload it."
        ))
        .font(.caption2)
        .multilineTextAlignment(.center)
        .foregroundStyle(.white.opacity(0.46))
        .frame(maxWidth: 440)
    }

    private var closeButton: some View {
        Button(action: onCancel) {
            Image(systemName: "xmark")
                .font(.headline)
                .frame(width: 42, height: 42)
        }
        .buttonStyle(.glass)
        .tint(.white.opacity(0.22))
        .accessibilityLabel(store.language.text("取消抽牌", "카드 뽑기 취소", "Cancel card draw"))
    }

    private func cardStage(width: CGFloat) -> some View {
        ZStack {
            if store.placedFurniture.contains(.telescope) {
                TelescopeConstellationEffect(
                    isActive: phase == .shuffling || phase == .choosing || phase == .revealed,
                    reduceMotion: reduceMotion
                )
                .frame(width: width, height: width * 0.72)
                .transition(.opacity)
                .accessibilityHidden(true)
            }

            ForEach(0..<3, id: \.self) { index in
                let isCenter = index == 1
                TarotCard(
                    cardName: reading.cardName,
                    cardSymbol: reading.cardSymbol ?? "sparkles",
                    isRevealed: isCenter && phase == .revealed
                )
                .frame(width: min(width * 0.46, 232), height: min(width * 0.69, 346))
                .rotationEffect(.degrees(rotation(for: index)))
                .offset(x: horizontalOffset(for: index, stageWidth: width), y: verticalOffset(for: index))
                .scaleEffect(isCenter && (phase == .choosing || phase == .revealed) ? 1.08 : 0.94)
                .opacity(opacity(for: index))
                .zIndex(isCenter ? 2 : 1)
            }

            RadialGradient(
                colors: [Color.celestialGold.opacity(phase == .revealed ? 0.42 : 0.12), .clear],
                center: .center,
                startRadius: 5,
                endRadius: width * 0.45
            )
            .blendMode(.screen)
            .allowsHitTesting(false)
            .zIndex(0)
        }
        .frame(width: width)
        .animation(reduceMotion ? nil : .spring(response: 0.65, dampingFraction: 0.72), value: phase)
    }

    private var titleCopy: String {
        switch phase {
        case .resting: store.language.text("想好你的問題", "질문을 떠올려 보세요", "Hold your question in mind")
        case .shuffling: store.language.text("洗牌中", "카드를 섞고 있어요", "Shuffling the deck")
        case .choosing: store.language.text("就這張", "이 카드예요", "This is the one")
        case .revealed: store.language.text("抽到「\(reading.cardTitle(in: store.language))」", "‘\(reading.cardTitle(in: store.language))’ 카드가 나왔어요", "You drew \(reading.cardTitle(in: store.language))")
        }
    }

    private var subtitleCopy: String {
        if phase == .revealed {
            return reading.keywords ?? store.language.text("點開看看這張牌怎麼說。", "카드를 눌러 해석을 확인해 보세요.", "Open the card to see what it has to say.")
        }
        return "\(reading.topicTitle) · \(reading.question)"
    }

    private func horizontalOffset(for index: Int, stageWidth: CGFloat) -> CGFloat {
        let direction = CGFloat(index - 1)
        switch phase {
        case .resting: return direction * min(stageWidth * 0.12, 60)
        case .shuffling: return direction * -min(stageWidth * 0.15, 76)
        case .choosing, .revealed: return direction * min(stageWidth * 0.30, 156)
        }
    }

    private func verticalOffset(for index: Int) -> CGFloat {
        switch phase {
        case .resting: return index == 1 ? -4 : 16
        case .shuffling: return index == 1 ? 18 : -8
        case .choosing, .revealed: return index == 1 ? -10 : 24
        }
    }

    private func rotation(for index: Int) -> Double {
        let direction = Double(index - 1)
        switch phase {
        case .resting: return direction * 9
        case .shuffling: return direction * -15
        case .choosing, .revealed: return direction * 13
        }
    }

    private func opacity(for index: Int) -> Double {
        guard phase == .revealed else { return 1 }
        return index == 1 ? 1 : 0.30
    }

    @MainActor
    private func performRitual() async {
        if reduceMotion {
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            phase = .revealed
            return
        }

        withAnimation(.easeInOut(duration: 0.35)) { phase = .shuffling }
        try? await Task.sleep(for: .milliseconds(760))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.58, dampingFraction: 0.68)) { phase = .choosing }
        try? await Task.sleep(for: .milliseconds(720))
        guard !Task.isCancelled else { return }
        withAnimation(.timingCurve(0.24, 0.72, 0.18, 1, duration: 0.72)) { phase = .revealed }
    }
}

private struct TelescopeConstellationEffect: View {
    let isActive: Bool
    let reduceMotion: Bool

    var body: some View {
        if reduceMotion || !isActive {
            constellation(time: 0)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                constellation(time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func constellation(time: TimeInterval) -> some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<14, id: \.self) { index in
                    let angle = Double(index) / 14 * Double.pi * 2 + time * 0.18
                    let radius = min(proxy.size.width, proxy.size.height) * (index.isMultiple(of: 2) ? 0.42 : 0.32)
                    Image(systemName: index.isMultiple(of: 3) ? "sparkle" : "circle.fill")
                        .font(.system(size: index.isMultiple(of: 3) ? 11 : 4, weight: .light))
                        .foregroundStyle(index.isMultiple(of: 4) ? Color.celestialGold : .white)
                        .opacity(0.34 + 0.28 * sin(time * 0.8 + Double(index)))
                        .position(
                            x: proxy.size.width / 2 + cos(angle) * radius,
                            y: proxy.size.height / 2 + sin(angle) * radius * 0.62
                        )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct TarotCard: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let cardName: String
    let cardSymbol: String
    let isRevealed: Bool

    var body: some View {
        ZStack {
            cardBack
                .opacity(isRevealed ? 0 : 1)

            cardFace
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(isRevealed ? 1 : 0)
        }
        .rotation3DEffect(
            .degrees(isRevealed ? 180 : 0),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.72
        )
        .shadow(color: isRevealed ? Color.celestialGold.opacity(0.52) : .black.opacity(0.32), radius: 22, y: 12)
        .animation(reduceMotion ? nil : .timingCurve(0.22, 0.76, 0.18, 1, duration: 0.78), value: isRevealed)
        .accessibilityLabel(
            isRevealed
                ? cardName
                : store.language.text("塔羅牌", "타로 카드", "Tarot card")
        )
    }

    private var cardBack: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(
                    colors: [Color.celestialPlum, Color.celestialNight],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            RoundedRectangle(cornerRadius: 15)
                .stroke(Color.celestialGold.opacity(0.68), lineWidth: 1.5)
                .padding(8)
            VStack(spacing: 14) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 34))
                Image(systemName: "sparkles")
                    .font(.system(size: 22))
                Text(store.language.text("星伴", "별동무", "Star Companion"))
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.4)
            }
            .foregroundStyle(Color.celestialGold)
        }
    }

    private var cardFace: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(
                    colors: [Color(red: 1.0, green: 0.94, blue: 0.78), Color(red: 0.93, green: 0.78, blue: 0.91)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            RoundedRectangle(cornerRadius: 15)
                .stroke(Color.celestialPlum.opacity(0.56), lineWidth: 1.5)
                .padding(8)
            VStack(spacing: 15) {
                Image(systemName: cardSymbol)
                    .font(.system(size: 38))
                Text(cardName)
                    .font(.title3.bold())
                Text(store.language.text("你的牌", "당신의 카드", "Your card"))
                    .font(.caption2.bold())
            }
            .foregroundStyle(Color.celestialPlum)
        }
    }
}
