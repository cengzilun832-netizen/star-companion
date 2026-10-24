import SwiftUI

struct WatchPetRootView: View {
    @StateObject private var store = WatchPetStore()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 12 : 8) {
                    header

                    WatchKawaiiStar(
                        mood: store.snapshot.mood,
                        size: starSize(for: proxy.size),
                        reduceMotion: reduceMotion
                    )
                    .accessibilityLabel(moodAccessibilityText)

                    VStack(spacing: 3) {
                        Text(moodTitle)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.75)

                        Text(todayStatus)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    foodProgress
                    actionButtons
                    syncNote
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .background(WatchCosmosBackground(mood: store.snapshot.mood))
        }
        .containerBackground(for: .navigation) {
            Color(red: 0.035, green: 0.025, blue: 0.12)
        }
        .task { store.requestFreshSnapshot() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .foregroundStyle(accent)
            Text(store.language.text("今日小星", "오늘의 작은 별", "Little Star Today"))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 2)
            Circle()
                .fill(store.syncState == .current ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(syncAccessibilityText)
    }

    private var foodProgress: some View {
        VStack(spacing: 4) {
            HStack {
                Label(
                    store.language.text("星光", "별빛", "Starlight"),
                    systemImage: "sparkles"
                )
                .font(.caption2.weight(.medium))
                Spacer()
                Text("\(store.snapshot.food)%")
                    .font(.caption2.monospacedDigit().weight(.semibold))
            }

            ProgressView(value: Double(store.snapshot.food), total: 100)
                .tint(accent)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            store.language.text(
                "小星的星光是 \(store.snapshot.food)％",
                "작은 별의 별빛은 \(store.snapshot.food)%예요",
                "Little Star has \(store.snapshot.food) percent starlight"
            )
        )
    }

    @ViewBuilder
    private var actionButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                feedButton
                interactButton
            }
            VStack(spacing: 6) {
                feedButton
                interactButton
            }
        }
    }

    private var feedButton: some View {
        Button(action: store.feed) {
            Label(
                store.language.text("餵星光", "별빛 주기", "Feed"),
                systemImage: "takeoutbag.and.cup.and.straw.fill"
            )
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(accent.opacity(0.88))
        .disabled(!store.snapshot.canFeed || store.syncState != .current)
        .accessibilityHint(
            store.snapshot.canFeed
                ? store.language.text(
                    "今天已餵 \(store.snapshot.feedCount) 次，最多 \(store.snapshot.feedLimit) 次",
                    "오늘 \(store.snapshot.feedCount)번 먹였고 최대 \(store.snapshot.feedLimit)번이에요",
                    "Fed \(store.snapshot.feedCount) of \(store.snapshot.feedLimit) times today"
                )
                : store.language.text("今天已經餵好了", "오늘 먹이 주기는 끝났어요", "Feeding is done for today")
        )
    }

    private var interactButton: some View {
        Button(action: store.interact) {
            Label(
                store.language.text("摸摸", "쓰다듬기", "Pet"),
                systemImage: "hand.raised.fill"
            )
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.pink)
        .disabled(!store.snapshot.canInteract || store.syncState != .current)
        .accessibilityHint(
            store.snapshot.canInteract
                ? store.language.text("今天可以輕輕陪它一次", "오늘 한 번 다정하게 쓰다듬을 수 있어요", "You can give one gentle touch today")
                : store.language.text("今天已經陪過它了", "오늘은 이미 함께했어요", "You already spent a gentle moment together today")
        )
    }

    @ViewBuilder
    private var syncNote: some View {
        switch store.syncState {
        case .current:
            EmptyView()
        case .sending:
            Label(
                store.language.text("正在告訴 iPhone…", "iPhone에 전하는 중…", "Telling iPhone…"),
                systemImage: "iphone.radiowaves.left.and.right"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        case .queued:
            Label(
                store.language.text("會在連上 iPhone 後完成", "iPhone에 연결되면 완료돼요", "Will finish when iPhone reconnects"),
                systemImage: "clock.arrow.circlepath"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
    }

    private func starSize(for size: CGSize) -> CGFloat {
        if dynamicTypeSize.isAccessibilitySize { return min(size.width * 0.43, 78) }
        return min(size.width * 0.50, size.height * 0.39, 100)
    }

    private var todayStatus: String {
        if store.snapshot.gentleMode {
            return store.language.text("今天慢慢來，我陪你。", "오늘은 천천히 가요. 곁에 있을게요.", "Take today slowly. I'm here.")
        }
        if store.snapshot.feedCount >= store.snapshot.feedLimit {
            return store.language.text("今天吃飽了，星光很亮。", "오늘은 배불러서 별빛이 환해요.", "All fed today, and glowing bright.")
        }
        let remaining = max(0, store.snapshot.feedLimit - store.snapshot.feedCount)
        return store.language.text(
            "今天還可以餵 \(remaining) 次",
            "오늘 \(remaining)번 더 먹일 수 있어요",
            "\(remaining) feeding\(remaining == 1 ? "" : "s") left today"
        )
    }

    private var moodTitle: String {
        switch store.snapshot.mood {
        case .happy: store.language.text("心情亮晶晶", "기분이 반짝여요", "Feeling bright")
        case .calm: store.language.text("安靜靠著你", "조용히 기대어 있어요", "Resting close")
        case .tired: store.language.text("有一點睏", "조금 졸려요", "A little sleepy")
        case .low: store.language.text("今天柔柔的", "오늘은 부드럽게", "Soft and quiet")
        case .glowing: store.language.text("剛吃到星光", "별빛을 먹었어요", "Full of starlight")
        case .delighted: store.language.text("開心得發亮", "기뻐서 빛나요", "Glowing with joy")
        }
    }

    private var moodAccessibilityText: String {
        store.language.text(
            "小星，\(moodTitle)",
            "작은 별, \(moodTitle)",
            "Little Star, \(moodTitle.lowercased())"
        )
    }

    private var syncAccessibilityText: String {
        switch store.syncState {
        case .current:
            return store.language.text("今日小星，已和 iPhone 同步", "오늘의 작은 별, iPhone과 동기화됨", "Little Star Today, synced with iPhone")
        case .sending:
            return store.language.text("今日小星，正在同步", "오늘의 작은 별, 동기화 중", "Little Star Today, syncing")
        case .queued:
            return store.language.text("今日小星，等待連上 iPhone", "오늘의 작은 별, iPhone 연결 대기 중", "Little Star Today, waiting for iPhone")
        }
    }

    private var accent: Color {
        switch store.snapshot.mood {
        case .happy: Color(red: 1.00, green: 0.79, blue: 0.45)
        case .calm: Color(red: 0.77, green: 0.68, blue: 1.00)
        case .tired: Color(red: 0.54, green: 0.67, blue: 0.95)
        case .low: Color(red: 0.66, green: 0.57, blue: 0.86)
        case .glowing: Color(red: 0.46, green: 0.91, blue: 0.96)
        case .delighted: Color(red: 1.00, green: 0.55, blue: 0.75)
        }
    }
}

private struct WatchKawaiiStar: View {
    let mood: WatchPetMood
    let size: CGFloat
    let reduceMotion: Bool

    @State private var floating = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accent.opacity(0.48), accent.opacity(0.10), .clear],
                        center: .center,
                        startRadius: 2,
                        endRadius: size * 0.70
                    )
                )
                .frame(width: size * 1.35, height: size * 1.35)
                .blur(radius: size * 0.08)

            Image(systemName: "star.fill")
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.white, accent.opacity(0.96), Color(red: 1, green: 0.66, blue: 0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    accent
                )
                .frame(width: size, height: size)
                .shadow(color: accent.opacity(0.62), radius: size * 0.12, y: 3)

            face
                .offset(y: size * 0.06)

            Image(systemName: decorationSymbol)
                .font(.system(size: size * 0.18, weight: .bold))
                .foregroundStyle(.white, accent)
                .offset(x: size * 0.39, y: -size * 0.32)
                .accessibilityHidden(true)
        }
        .frame(width: size * 1.36, height: size * 1.20)
        .offset(y: reduceMotion ? 0 : (floating ? -3 : 3))
        .scaleEffect(reduceMotion ? 1 : (floating ? 1.025 : 0.985))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                floating = true
            }
        }
    }

    @ViewBuilder
    private var face: some View {
        if mood == .tired || mood == .low {
            HStack(spacing: size * 0.18) {
                Capsule().frame(width: size * 0.11, height: 2)
                Capsule().frame(width: size * 0.11, height: 2)
            }
            .foregroundStyle(Color(red: 0.19, green: 0.08, blue: 0.28))
        } else {
            HStack(spacing: size * 0.18) {
                Circle().frame(width: size * 0.09)
                Circle().frame(width: size * 0.09)
            }
            .foregroundStyle(Color(red: 0.19, green: 0.05, blue: 0.28))
        }
    }

    private var decorationSymbol: String {
        switch mood {
        case .happy: "sparkles"
        case .calm: "heart.fill"
        case .tired: "moon.zzz.fill"
        case .low: "cloud.fill"
        case .glowing: "sun.max.fill"
        case .delighted: "party.popper.fill"
        }
    }

    private var accent: Color {
        switch mood {
        case .happy: Color(red: 1.00, green: 0.79, blue: 0.45)
        case .calm: Color(red: 0.77, green: 0.68, blue: 1.00)
        case .tired: Color(red: 0.54, green: 0.67, blue: 0.95)
        case .low: Color(red: 0.66, green: 0.57, blue: 0.86)
        case .glowing: Color(red: 0.46, green: 0.91, blue: 0.96)
        case .delighted: Color(red: 1.00, green: 0.55, blue: 0.75)
        }
    }
}

private struct WatchCosmosBackground: View {
    let mood: WatchPetMood

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.025, blue: 0.12),
                    Color(red: 0.13, green: 0.065, blue: 0.25),
                    Color.black,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { context, size in
                let points: [(Double, Double, Double)] = [
                    (0.08, 0.12, 1.4), (0.25, 0.06, 0.8), (0.42, 0.16, 1.0),
                    (0.72, 0.08, 1.5), (0.91, 0.21, 0.9), (0.15, 0.42, 0.8),
                    (0.84, 0.48, 1.2), (0.06, 0.72, 1.1), (0.37, 0.82, 0.7),
                    (0.68, 0.74, 0.9), (0.94, 0.88, 1.3),
                ]
                for point in points {
                    let rect = CGRect(
                        x: size.width * point.0,
                        y: size.height * point.1,
                        width: point.2,
                        height: point.2
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.66)))
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
