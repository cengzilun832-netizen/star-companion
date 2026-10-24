import SwiftUI

struct GameHubView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("xingban.ios.relaxed-gameplay.v1") private var relaxedGameplay = false
    @State private var previewCometPresented: Bool

    init() {
        #if DEBUG
        _previewCometPresented = State(
            initialValue: ProcessInfo.processInfo.arguments.contains("--preview-comet-game")
        )
        #else
        _previewCometPresented = State(initialValue: false)
        #endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    welcomeCard
                    relaxedModeCard

                    LazyVGrid(columns: gameColumns, spacing: 16) {
                        starTrailCard
                        cometCatchCard
                    }
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
                    : store.language.text("星光遊樂場", "별빛 놀이터", "Starlight Arcade")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Label("\(store.wardrobe.starCoins)", systemImage: "sparkles")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(Color.celestialGold)
                }
            }
            .navigationDestination(isPresented: $previewCometPresented) {
                CometCatchGameView()
            }
        }
    }

    private var relaxedModeCard: some View {
        Toggle(isOn: $relaxedGameplay) {
            VStack(alignment: .leading, spacing: 5) {
                Text(store.language.text("悠閒模式", "느긋한 모드", "Relaxed mode"))
                    .font(.headline)
                Text(store.language.text(
                    "拿掉彗星倒數，星光軌道也會把順序留在畫面上。VoiceOver 開啟時會自動使用。",
                    "혜성의 제한 시간을 없애고 별빛 순서도 화면에 남겨 둬요. VoiceOver를 켜면 자동으로 적용됩니다.",
                    "Removes the comet timer and leaves the starlight sequence on screen. It turns on automatically with VoiceOver."
                ))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.68))
            }
        }
        .tint(Color.celestialPink)
        .foregroundStyle(.white)
        .padding(18)
        .celestialSurface(
            Color.white.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.12), lineWidth: 1) }
    }

    private var welcomeCard: some View {
        HStack(spacing: horizontalSizeClass == .regular ? 28 : 18) {
            StyledStarView(
                wardrobe: store.wardrobe,
                mood: store.starVisualMood,
                size: horizontalSizeClass == .regular ? 158 : 108
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(store.language.text("今天想玩哪一關？", "오늘은 어떤 게임을 할까요?", "What shall we play today?"))
                    .font(horizontalSizeClass == .regular ? .largeTitle.bold() : .title2.bold())
                Text(store.language.text(
                    "每款遊戲都有自己的 12 關。首次通關會拿到星幣，替你的小星收藏新配件。",
                    "게임마다 12개의 스테이지가 있어요. 첫 클리어로 별 코인을 받아 작은 별의 장식을 모아 보세요.",
                    "Each game has 12 stages. Your first clear earns Star Coins for Little Star's accessory collection."
                ))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .lineSpacing(4)
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

    private var starTrailCard: some View {
        NavigationLink {
            StarTrailGameView()
        } label: {
            gameCard(
                title: store.language.text("星光軌道", "별빛 궤도", "Starlight Trail"),
                subtitle: store.language.text("看一次，再照順序點亮", "순서를 기억하고 별을 밝혀요", "Watch once, then repeat the path"),
                symbol: "point.3.connected.trianglepath.dotted",
                progress: store.starTrailProgress,
                colors: [Color.celestialPlum, Color.indigo.opacity(0.92)]
            )
        }
        .buttonStyle(.plain)
    }

    private var cometCatchCard: some View {
        NavigationLink {
            CometCatchGameView()
        } label: {
            gameCard(
                title: store.language.text("接住彗星", "혜성 잡기", "Comet Catch"),
                subtitle: store.language.text("在星光消失前找到它", "별빛이 사라지기 전에 찾아요", "Find the glow before it slips away"),
                symbol: "sparkles",
                progress: store.cometCatchProgress,
                colors: [Color.pink.opacity(0.82), Color.purple.opacity(0.92)]
            )
        }
        .buttonStyle(.plain)
    }

    private func gameCard(
        title: String,
        subtitle: String,
        symbol: String,
        progress: StarTrailProgress,
        colors: [Color]
    ) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: symbol)
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(Color.celestialGold)
                    .frame(width: 64, height: 64)
                    .celestialSurface(
                        Color.white.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 18),
                        reducedColor: .celestialSurfaceElevated
                    )
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.headline.bold())
                    .foregroundStyle(.white.opacity(0.66))
            }

            Text(title)
                .font(.title2.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(2)

            Spacer(minLength: 4)

            ProgressView(value: Double(progress.completedLevels.count), total: 12)
                .tint(Color.celestialGold)
            HStack {
                Text(store.language.text(
                    "已完成 \(progress.completedLevels.count)/12",
                    "\(progress.completedLevels.count)/12 완료",
                    "\(progress.completedLevels.count)/12 cleared"
                ))
                Spacer()
                Label(
                    store.language.text("第 \(progress.highestUnlockedLevel) 關", "스테이지 \(progress.highestUnlockedLevel)", "Stage \(progress.highestUnlockedLevel)"),
                    systemImage: "flag.fill"
                )
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.76))
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: horizontalSizeClass == .regular ? 292 : 258, alignment: .leading)
        .celestialSurface(
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 28),
            reducedColor: .celestialSurfaceElevated
        )
        .overlay { RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.14), lineWidth: 1) }
        .shadow(color: colors.last?.opacity(0.20) ?? .clear, radius: 18, y: 9)
    }

    private var gameColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 16),
            count: horizontalSizeClass == .regular ? 2 : 1
        )
    }
}

private struct CometCatchGameView: View {
    private enum Phase: Equatable {
        case map
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
    @State private var targetNode: Int?
    @State private var score = 0
    @State private var lives = 3
    @State private var tick = 0
    @State private var tappedCurrentTarget = false
    @State private var firstCompletion = false
    @State private var successFeedback = 0
    @State private var errorFeedback = 0
    @State private var loopTask: Task<Void, Never>?

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
                : store.language.text("接住彗星", "혜성 잡기", "Comet Catch")
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if phase != .map {
                ToolbarItem(placement: .topBarLeading) {
                    Button(store.language.text("關卡", "스테이지", "Stages"), systemImage: "map") {
                        loopTask?.cancel()
                        targetNode = nil
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
        .onDisappear { loopTask?.cancel() }
    }

    private var levelMap: some View {
        ScrollView {
            VStack(spacing: 22) {
                HStack(spacing: 20) {
                    StyledStarView(
                        wardrobe: store.wardrobe,
                        mood: store.starVisualMood,
                        size: horizontalSizeClass == .regular ? 150 : 108,
                        isCelebrating: true
                    )

                    VStack(alignment: .leading, spacing: 7) {
                        Text(store.language.text("別讓彗星溜走", "혜성을 놓치지 마세요", "Don't let the comet slip away"))
                            .font(horizontalSizeClass == .regular ? .largeTitle.bold() : .title2.bold())
                        Text(store.language.text(
                            "彗星會在九個位置間閃現。看見金色星光就點下去，首次通關會得到星幣。",
                            "혜성이 아홉 자리 사이에서 반짝여요. 금빛 별을 발견하면 탭하고 첫 클리어 별 코인을 받아요.",
                            "The comet flashes between nine spots. Tap the golden glow when it appears; your first clear earns Star Coins."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineSpacing(4)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
                .celestialSurface(
                    Color.white.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 26)
                )

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
        let progress = store.cometCatchProgress
        let unlocked = progress.isUnlocked(stage)
        let completed = progress.completedLevels.contains(stage)

        return Button {
            guard unlocked else { return }
            level = stage
            startLevel()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: completed ? "sparkles.rectangle.stack.fill" : (unlocked ? "sparkles" : "lock.fill"))
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
            .celestialSurface(
                completed ? Color.pink.opacity(0.48) : Color.white.opacity(unlocked ? 0.09 : 0.04),
                in: RoundedRectangle(cornerRadius: 22),
                reducedColor: completed ? .celestialPlum : .celestialSurfaceOpaque
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

                    if usesRelaxedGameplay, phase == .playing {
                        Label(
                            store.language.text("彗星會停下來等你", "혜성이 멈춰서 기다려요", "The comet will wait for you"),
                            systemImage: "tortoise.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.celestialGold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .celestialSurface(
                            Color.white.opacity(0.09),
                            in: Capsule(),
                            reducedColor: .celestialSurfaceElevated
                        )
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                        ForEach(0..<9, id: \.self) { node in
                            cometNode(node)
                        }
                    }
                    .frame(maxWidth: horizontalSizeClass == .regular ? 590 : 430)
                    .padding(20)
                    .celestialSurface(
                        Color.white.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 28)
                    )

                    if phase == .success || phase == .failed {
                        resultActions
                    } else {
                        ProgressView(value: Double(score), total: Double(targetCount))
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

    private func cometNode(_ node: Int) -> some View {
        let isTarget = targetNode == node

        return Button {
            handleTap(node)
        } label: {
            Image(systemName: isTarget ? "sparkles" : "circle.dotted")
                .font(.system(size: horizontalSizeClass == .regular ? 42 : 34, weight: .semibold))
                .foregroundStyle(isTarget ? Color.celestialGold : .white.opacity(0.26))
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .celestialSurface(
                    isTarget ? Color.pink.opacity(0.52) : Color.white.opacity(0.06),
                    in: Circle(),
                    reducedColor: isTarget ? .celestialPlum : .celestialSurfaceOpaque
                )
                .shadow(color: isTarget ? Color.celestialGold.opacity(0.78) : .clear, radius: 20)
                .scaleEffect(isTarget && !reduceMotion ? 1.10 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.62), value: isTarget)
        }
        .buttonStyle(.plain)
        .disabled(phase != .playing)
        .accessibilityLabel(
            isTarget
                ? store.language.text("彗星在這裡", "혜성이 여기 있어요", "Comet is here")
                : store.language.text("空的星位 \(node + 1)", "빈 별자리 \(node + 1)", "Empty star spot \(node + 1)")
        )
    }

    private var resultActions: some View {
        VStack(spacing: 12) {
            if phase == .success {
                Label(
                    firstCompletion
                        ? store.language.text("接住了！獲得 \(reward(for: level)) 星幣", "잡았어요! 별 코인 \(reward(for: level))개 획득", "Caught it! You earned \(reward(for: level)) Star Coins")
                        : store.language.text("又接住一次彗星", "혜성을 다시 잡았어요", "You caught the comet again"),
                    systemImage: "party.popper.fill"
                )
                .foregroundStyle(Color.celestialGold)
            } else {
                Label(store.language.text("彗星飛遠了，再試一次", "혜성이 멀리 날아갔어요. 다시 해봐요", "The comet flew away. Try again"), systemImage: "heart.slash")
                    .foregroundStyle(Color.celestialPink)
            }

            HStack(spacing: 12) {
                Button(store.language.text("再玩一次", "다시 하기", "Play again"), systemImage: "arrow.clockwise") {
                    startLevel()
                }
                .celestialGlassButtonStyle()

                if phase == .success, level < maxLevel {
                    Button(store.language.text("下一關", "다음 스테이지", "Next stage"), systemImage: "arrow.right") {
                        level += 1
                        startLevel()
                    }
                    .celestialGlassButtonStyle(prominent: true)
                    .tint(Color.celestialPink)
                }
            }
        }
        .font(.headline)
        .foregroundStyle(.white)
        .padding(20)
        .celestialSurface(
            Color.white.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 22)
        )
    }

    private var stageTitle: String {
        switch phase {
        case .playing: store.language.text("找到亮起的彗星", "빛나는 혜성을 찾아요", "Find the glowing comet")
        case .success: store.language.text("接得剛剛好！", "딱 맞게 잡았어요!", "Perfect catch!")
        case .failed: store.language.text("差一點就接到了", "조금만 더 하면 잡을 수 있어요", "Almost had it")
        case .map: ""
        }
    }

    private var stageSubtitle: String {
        switch phase {
        case .playing: store.language.text("已接住 \(score)/\(targetCount)", "\(score)/\(targetCount) 잡았어요", "Caught \(score)/\(targetCount)")
        case .success: store.language.text("星幣已放進你的衣櫃", "별 코인을 옷장에 넣었어요", "Your Star Coins are in the wardrobe")
        case .failed: store.language.text("先看清楚金色光點再下手", "금빛을 확인하고 천천히 탭해요", "Look for the golden glow before tapping")
        case .map: ""
        }
    }

    private func startLevel() {
        loopTask?.cancel()
        score = 0
        lives = 3
        tick = 0
        targetNode = nil
        tappedCurrentTarget = false
        firstCompletion = false
        phase = .playing
        runLoop()
    }

    private func runLoop() {
        loopTask?.cancel()
        loopTask = Task { @MainActor in
            while phase == .playing, score < targetCount, lives > 0 {
                tappedCurrentTarget = false
                targetNode = nextTargetNode()

                if usesRelaxedGameplay {
                    while phase == .playing, !tappedCurrentTarget {
                        do {
                            try await Task.sleep(for: .milliseconds(180))
                        } catch {
                            return
                        }
                    }
                    guard phase == .playing else { return }
                    targetNode = nil
                    try? await Task.sleep(for: .milliseconds(160))
                    continue
                }

                do {
                    try await Task.sleep(for: appearanceDuration)
                } catch {
                    return
                }

                guard phase == .playing else { return }
                if !tappedCurrentTarget {
                    lives -= 1
                    errorFeedback += 1
                    if lives == 0 {
                        targetNode = nil
                        phase = .failed
                        return
                    }
                }

                targetNode = nil
                try? await Task.sleep(for: reduceMotion ? .milliseconds(180) : .milliseconds(110))
            }
        }
    }

    private func handleTap(_ node: Int) {
        guard phase == .playing, !tappedCurrentTarget else { return }
        tappedCurrentTarget = true

        if node == targetNode {
            score += 1
            successFeedback += 1
            targetNode = nil
            if score >= targetCount {
                loopTask?.cancel()
                firstCompletion = store.completeCometCatchLevel(level, reward: reward(for: level))
                phase = .success
            }
        } else {
            lives -= 1
            targetNode = nil
            errorFeedback += 1
            if lives == 0 {
                loopTask?.cancel()
                phase = .failed
            }
        }
    }

    private func nextTargetNode() -> Int {
        tick += 1
        let mixed = level &* 1_103_515_245 &+ tick &* 12_345 &+ 7_919
        let candidate = abs(mixed % 9)
        if candidate == targetNode {
            return (candidate + 1) % 9
        }
        return candidate
    }

    private var targetCount: Int {
        min(5 + level, 16)
    }

    private var appearanceDuration: Duration {
        if reduceMotion { return .milliseconds(1_100) }
        return .milliseconds(max(460, 960 - level * 38))
    }

    private var usesRelaxedGameplay: Bool {
        relaxedGameplay || voiceOverEnabled
    }

    private func reward(for level: Int) -> Int {
        10 + level * 4
    }

    private var mapColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 13),
            count: horizontalSizeClass == .regular ? 4 : 3
        )
    }
}
