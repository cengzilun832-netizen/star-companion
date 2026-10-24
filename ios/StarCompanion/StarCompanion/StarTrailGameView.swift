import SwiftUI

struct StarTrailGameView: View {
    private enum Phase: Equatable {
        case map
        case showing
        case playing
        case success
        case failed
    }

    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @AppStorage("xingban.ios.relaxed-gameplay.v1") private var relaxedGameplay = false
    @State private var phase = Phase.map
    @State private var level = 1
    @State private var sequence: [Int] = []
    @State private var activeNode: Int?
    @State private var inputIndex = 0
    @State private var lives = 3
    @State private var firstCompletion = false
    @State private var successFeedback = 0
    @State private var errorFeedback = 0
    @State private var sequenceTask: Task<Void, Never>?

    private let maxLevel = 12

    var body: some View {
        ZStack {
            CelestialBackdrop()
                .ignoresSafeArea()

            if phase == .map {
                levelMap
            } else {
                gameStage
            }
        }
        .navigationTitle(
            horizontalSizeClass == .regular
                ? ""
                : store.language.text("星光軌道", "별빛 궤도", "Starlight Trail")
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if phase != .map {
                ToolbarItem(placement: .topBarLeading) {
                    Button(store.language.text("關卡", "스테이지", "Stages"), systemImage: "map") {
                        sequenceTask?.cancel()
                        phase = .map
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Label("\(store.wardrobe.starCoins)", systemImage: "sparkles")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(Color.celestialGold)
            }
        }
        .sensoryFeedback(.success, trigger: successFeedback)
        .sensoryFeedback(.error, trigger: errorFeedback)
        .onDisappear { sequenceTask?.cancel() }
    }

    private var levelMap: some View {
        ScrollView {
            VStack(spacing: 22) {
                HStack(spacing: 20) {
                    StyledStarView(
                        wardrobe: store.wardrobe,
                        mood: store.starVisualMood,
                        size: horizontalSizeClass == .regular ? 150 : 108
                    )

                    VStack(alignment: .leading, spacing: 7) {
                        Text(store.language.text("記住星星亮起的路", "별이 빛나는 길을 기억해요", "Remember the path of light"))
                            .font(horizontalSizeClass == .regular ? .largeTitle.bold() : .title2.bold())
                        Text(store.language.text(
                            "照順序點亮星星。首次通關會獲得星幣，可以拿去替小星買新配件。",
                            "순서대로 별을 밝혀 주세요. 첫 클리어 보상으로 별 코인을 받아 장식을 살 수 있어요.",
                            "Light the stars in order. Your first clear earns Star Coins for new accessories."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineSpacing(4)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
                .background(.white.opacity(0.08), in: .rect(cornerRadius: 26))

                LazyVGrid(columns: mapColumns, spacing: 13) {
                    ForEach(1...maxLevel, id: \.self) { stage in
                        levelButton(stage)
                    }
                }
            }
            .frame(maxWidth: 980)
            .padding(.horizontal, horizontalSizeClass == .regular ? 28 : 16)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
        }
    }

    private func levelButton(_ stage: Int) -> some View {
        let progress = store.starTrailProgress
        let unlocked = progress.isUnlocked(stage)
        let completed = progress.completedLevels.contains(stage)

        return Button {
            guard unlocked else { return }
            level = stage
            startLevel()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: completed ? "star.circle.fill" : (unlocked ? "star.circle" : "lock.fill"))
                    .font(.title)
                    .foregroundStyle(completed ? Color.celestialGold : .white.opacity(unlocked ? 0.88 : 0.34))
                Text(store.language.text("第 \(stage) 關", "스테이지 \(stage)", "Stage \(stage)"))
                    .font(.headline.monospacedDigit())
                if completed {
                    Text(store.language.text("已通關", "클리어", "Cleared"))
                        .font(.caption)
                        .foregroundStyle(Color.celestialGold)
                } else if unlocked {
                    Label("+\(reward(for: stage))", systemImage: "sparkles")
                        .font(.caption)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 126)
            .background(
                completed ? Color.celestialPlum.opacity(0.78) : Color.white.opacity(unlocked ? 0.09 : 0.04),
                in: .rect(cornerRadius: 22)
            )
            .overlay { RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.10), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
    }

    private var gameStage: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 18) {
                    HStack {
                        Label(store.language.text("第 \(level) 關", "스테이지 \(level)", "Stage \(level)"), systemImage: "flag.fill")
                        Spacer()
                        HStack(spacing: 5) {
                            ForEach(0..<3, id: \.self) { index in
                                Image(systemName: index < lives ? "heart.fill" : "heart")
                                    .foregroundStyle(index < lives ? Color.celestialPink : .white.opacity(0.30))
                            }
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.white)

                    VStack(spacing: 5) {
                        Text(stageTitle)
                            .font(.title2.bold())
                        Text(stageSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                    if usesRelaxedGameplay && (phase == .showing || phase == .playing) {
                        Label(relaxedSequenceCopy, systemImage: "list.number")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.celestialGold)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.white.opacity(0.09), in: .capsule)
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                        ForEach(0..<9, id: \.self) { node in
                            starNode(node)
                        }
                    }
                    .frame(maxWidth: horizontalSizeClass == .regular ? 590 : 430)
                    .padding(20)
                    .background(.white.opacity(0.07), in: .rect(cornerRadius: 28))

                    if phase == .success || phase == .failed {
                        resultActions
                    } else {
                        ProgressView(
                            value: Double(inputIndex),
                            total: Double(max(sequence.count, 1))
                        )
                        .tint(Color.celestialGold)
                        .frame(maxWidth: 520)
                    }
                }
                .frame(maxWidth: 760)
                .padding(.horizontal, 22)
                .padding(.vertical, max(18, proxy.safeAreaInsets.top))
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func starNode(_ node: Int) -> some View {
        let isActive = activeNode == node
        let isCorrectProgress = phase == .playing && inputIndex > 0 && sequence.prefix(inputIndex).last == node

        return Button {
            handleTap(node)
        } label: {
            Image(systemName: isActive || isCorrectProgress ? "star.fill" : "star")
                .font(.system(size: horizontalSizeClass == .regular ? 42 : 34, weight: .medium))
                .foregroundStyle(isActive ? .white : Color.celestialGold)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .background(
                    isActive ? Color.celestialPink.opacity(0.88) : Color.white.opacity(0.08),
                    in: .circle
                )
                .shadow(color: isActive ? Color.celestialGold.opacity(0.72) : .clear, radius: 18)
                .scaleEffect(isActive && !reduceMotion ? 1.10 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.62), value: isActive)
        }
        .buttonStyle(.plain)
        .disabled(phase != .playing)
        .accessibilityLabel(store.language.text("星星 \(node + 1)", "별 \(node + 1)", "Star \(node + 1)"))
    }

    private var resultActions: some View {
        VStack(spacing: 12) {
            if phase == .success {
                Label(
                    firstCompletion
                        ? store.language.text("通關！獲得 \(reward(for: level)) 星幣", "클리어! 별 코인 \(reward(for: level))개 획득", "Cleared! You earned \(reward(for: level)) Star Coins")
                        : store.language.text("再次完成這條軌道", "이 궤도를 다시 완주했어요", "You completed this trail again"),
                    systemImage: "party.popper.fill"
                )
                .foregroundStyle(Color.celestialGold)
            } else {
                Label(store.language.text("星光散開了，再試一次", "별빛이 흩어졌어요. 다시 해봐요", "The starlight scattered. Try again"), systemImage: "heart.slash")
                    .foregroundStyle(Color.celestialPink)
            }

            HStack(spacing: 12) {
                Button(store.language.text("再玩一次", "다시 하기", "Play again"), systemImage: "arrow.clockwise") {
                    startLevel()
                }
                .buttonStyle(.glass)

                if phase == .success, level < maxLevel {
                    Button(store.language.text("下一關", "다음 스테이지", "Next stage"), systemImage: "arrow.right") {
                        level += 1
                        startLevel()
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.celestialPink)
                }
            }
        }
        .font(.headline)
        .foregroundStyle(.white)
        .padding(20)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 22))
    }

    private var stageTitle: String {
        switch phase {
        case .showing: store.language.text("看清楚星光順序", "별빛 순서를 잘 봐요", "Watch the starlight")
        case .playing: store.language.text("換你點亮它們", "이제 별을 밝혀 주세요", "Now light them up")
        case .success: store.language.text("軌道接好了！", "궤도가 이어졌어요!", "Trail complete!")
        case .failed: store.language.text("差一點就到了", "거의 다 왔어요", "So close")
        case .map: ""
        }
    }

    private var stageSubtitle: String {
        switch phase {
        case .showing: store.language.text("記住每一顆亮起的位置", "빛나는 위치를 하나씩 기억해요", "Remember each position")
        case .playing: store.language.text("還有 \(sequence.count - inputIndex) 顆", "\(sequence.count - inputIndex)개 남았어요", "\(sequence.count - inputIndex) to go")
        case .success: store.language.text("星幣已放進你的衣櫃", "별 코인을 옷장에 넣었어요", "Your Star Coins are in the wardrobe")
        case .failed: store.language.text("慢一點，看完再開始", "천천히 보고 다시 시작해요", "Take your time and watch once more")
        case .map: ""
        }
    }

    private func startLevel() {
        sequenceTask?.cancel()
        sequence = makeSequence(for: level)
        inputIndex = 0
        lives = 3
        firstCompletion = false
        phase = .showing
        playSequence()
    }

    private func playSequence() {
        sequenceTask?.cancel()
        phase = .showing
        inputIndex = 0
        sequenceTask = Task { @MainActor in
            for node in sequence {
                guard !Task.isCancelled else { return }
                activeNode = node
                try? await Task.sleep(
                    for: usesRelaxedGameplay
                        ? .milliseconds(820)
                        : (reduceMotion ? .milliseconds(240) : .milliseconds(430))
                )
                activeNode = nil
                try? await Task.sleep(
                    for: usesRelaxedGameplay
                        ? .milliseconds(240)
                        : (reduceMotion ? .milliseconds(90) : .milliseconds(150))
                )
            }
            guard !Task.isCancelled else { return }
            phase = .playing
        }
    }

    private func handleTap(_ node: Int) {
        guard phase == .playing, sequence.indices.contains(inputIndex) else { return }
        if node == sequence[inputIndex] {
            activeNode = node
            inputIndex += 1
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                activeNode = nil
            }
            if inputIndex == sequence.count {
                firstCompletion = store.completeStarTrailLevel(level, reward: reward(for: level))
                phase = .success
                successFeedback += 1
            }
        } else {
            lives -= 1
            inputIndex = 0
            errorFeedback += 1
            if lives == 0 {
                phase = .failed
            } else {
                playSequence()
            }
        }
    }

    private func makeSequence(for level: Int) -> [Int] {
        let count = min(3 + (level - 1) / 2, 8)
        var state = UInt64(level * 1_103 + 7_919)
        return (0..<count).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 32) % 9)
        }
    }

    private func reward(for level: Int) -> Int {
        14 + level * 3
    }

    private var usesRelaxedGameplay: Bool {
        relaxedGameplay || voiceOverEnabled
    }

    private var relaxedSequenceCopy: String {
        let path = sequence.map { String($0 + 1) }.joined(separator: " → ")
        return store.language.text("順序提示：\(path)", "순서 힌트: \(path)", "Sequence: \(path)")
    }

    private var mapColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 13),
            count: horizontalSizeClass == .regular ? 4 : 3
        )
    }
}
