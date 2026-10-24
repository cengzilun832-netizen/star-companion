import SwiftUI

/// A presentation-only mood layer. `PetMood` remains the persisted source of
/// truth; this type also accounts for the low-energy mode and a hungry star so
/// those quieter states are visible without changing any daily-limit rules.
enum StarVisualMood: String, Equatable {
    case happy
    case calm
    case tired
    case low
    case glowing
    case delighted

    static func resolved(petMood: PetMood, food: Int, gentleMode: Bool) -> StarVisualMood {
        if gentleMode { return .low }
        if food <= 24 { return .tired }

        return switch petMood {
        case .happy: .happy
        case .glowing: .glowing
        case .affectionate: .calm
        case .delighted: .delighted
        }
    }

    static func snapshot(_ moodID: String?) -> StarVisualMood {
        if let value = moodID.flatMap(StarVisualMood.init(rawValue:)) { return value }
        guard let petMood = moodID.flatMap(PetMood.init(rawValue:)) else { return .happy }
        return resolved(petMood: petMood, food: 100, gentleMode: false)
    }

    func accessibilityText(in language: AppLanguage) -> String {
        switch self {
        case .happy:
            language.text("小星心情亮晶晶", "작은 별의 기분이 반짝여요", "Little Star feels bright and happy")
        case .calm:
            language.text("小星正安靜地靠著你", "작은 별이 조용히 곁에 기대어 있어요", "Little Star is resting calmly beside you")
        case .tired:
            language.text("小星有點睏，星光慢了下來", "작은 별이 조금 졸려서 별빛도 천천히 흘러요", "Little Star is sleepy, and its glow has slowed down")
        case .low:
            language.text("今天把星光調柔一點", "오늘은 별빛을 조금 더 부드럽게 낮췄어요", "The starlight is softer today")
        case .glowing:
            language.text("小星剛吃到星光，正在發亮", "작은 별이 별빛을 먹고 환하게 빛나요", "Little Star is glowing after a starlight snack")
        case .delighted:
            language.text("小星完成約定，開心得發亮", "작은 별이 약속을 지켜 신나게 빛나요", "Little Star kept its promise and is shining with delight")
        }
    }

    var accentColor: Color {
        switch self {
        case .happy: .celestialGold
        case .calm: .celestialLavender
        case .tired: Color(red: 0.48, green: 0.57, blue: 0.82)
        case .low: Color(red: 0.50, green: 0.43, blue: 0.66)
        case .glowing: Color(red: 0.48, green: 0.88, blue: 0.94)
        case .delighted: .celestialPink
        }
    }

    var decorationSymbol: String {
        switch self {
        case .happy: "sparkles"
        case .calm: "heart.fill"
        case .tired: "moon.zzz.fill"
        case .low: "moon.haze.fill"
        case .glowing: "sun.max.fill"
        case .delighted: "party.popper.fill"
        }
    }

    var ambientSymbol: String {
        switch self {
        case .happy, .glowing, .delighted: "sparkle"
        case .calm: "heart.fill"
        case .tired: "moon.fill"
        case .low: "cloud.fill"
        }
    }

    var glowOpacity: Double {
        switch self {
        case .happy: 0.34
        case .calm: 0.27
        case .tired: 0.18
        case .low: 0.15
        case .glowing: 0.48
        case .delighted: 0.54
        }
    }

    var roomColors: [Color] {
        switch self {
        case .happy:
            [Color.celestialGold.opacity(0.22), Color.celestialPink.opacity(0.10), .clear]
        case .calm:
            [Color.celestialLavender.opacity(0.20), Color.blue.opacity(0.08), .clear]
        case .tired:
            [Color.indigo.opacity(0.31), Color.black.opacity(0.14), .clear]
        case .low:
            [Color(red: 0.18, green: 0.16, blue: 0.32).opacity(0.42), Color.purple.opacity(0.12), .clear]
        case .glowing:
            [Color.cyan.opacity(0.23), Color.celestialGold.opacity(0.16), .clear]
        case .delighted:
            [Color.celestialPink.opacity(0.28), Color.celestialGold.opacity(0.20), .clear]
        }
    }

    var roomBlendMode: BlendMode {
        switch self {
        case .tired, .low: .multiply
        default: .screen
        }
    }

    var particleCount: Int {
        switch self {
        case .low: 3
        case .tired, .calm: 4
        case .happy, .glowing: 6
        case .delighted: 8
        }
    }

    var motionDuration: Double {
        switch self {
        case .tired, .low: 4.8
        case .calm: 4.2
        case .happy: 3.2
        case .glowing: 2.7
        case .delighted: 2.3
        }
    }
}

extension AppStore {
    var starVisualMood: StarVisualMood {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let moodFlag = arguments.firstIndex(of: "--preview-star-mood"),
           arguments.indices.contains(moodFlag + 1),
           let previewMood = StarVisualMood(rawValue: arguments[moodFlag + 1]) {
            return previewMood
        }
        #endif
        return StarVisualMood.resolved(
            petMood: planet.mood,
            food: planet.food,
            gentleMode: isGentleModeToday
        )
    }
}

struct StyledStarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let wardrobe: StarWardrobe
    let mood: StarVisualMood
    var size: CGFloat = 180
    var isCelebrating = false

    @State private var isFloating = false

    init(
        wardrobe: StarWardrobe,
        mood: StarVisualMood = .happy,
        size: CGFloat = 180,
        isCelebrating: Bool = false
    ) {
        self.wardrobe = wardrobe
        self.mood = mood
        self.size = size
        self.isCelebrating = isCelebrating
    }

    // The large iPad version is visible across several dashboard screens.
    // Keep it visually rich but static so it never consumes display frames
    // while the user is scrolling or interacting with controls.
    private var shouldAnimate: Bool {
        !reduceMotion && horizontalSizeClass != .regular
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            mood.accentColor.opacity(mood.glowOpacity),
                            auraColor.opacity(mood.glowOpacity * 0.58),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: size * 0.59
                    )
                )
                .frame(width: size * 1.20, height: size * 1.20)
                .blur(radius: shouldAnimate ? size * 0.12 : size * 0.04)

            Image(systemName: wardrobe.displayedAura.glowSymbol)
                .font(.system(size: size * 0.72, weight: .thin))
                .foregroundStyle(mood.accentColor.opacity(mood.glowOpacity + 0.05))
                .symbolEffect(.pulse, options: .repeating, isActive: shouldAnimate)

            if wardrobe.followsTarotMeaning,
               let tarotAura = wardrobe.tarotAura {
                tarotStyleOverlay(for: tarotAura)
            }

            Image(lookAssetName)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: size, height: size)
                .shadow(color: mood.accentColor.opacity(0.50), radius: size * 0.12, y: size * 0.05)

            moodBadge

            if wardrobe.supportsAccessoryOverlay,
               wardrobe.selectedAccessory != .none {
                Image(systemName: wardrobe.selectedAccessory.symbol)
                    .font(.system(size: size * 0.16, weight: .bold))
                    .foregroundStyle(Color.celestialGold)
                    .frame(width: size * 0.27, height: size * 0.27)
                    .background(Color.celestialPlum.opacity(0.90), in: .circle)
                    .overlay { Circle().stroke(.white.opacity(0.42), lineWidth: 1) }
                    .shadow(color: .black.opacity(0.22), radius: 5, y: 3)
                    .offset(accessoryOffset)
            }
        }
        .frame(width: size * 1.16, height: size * 1.16)
        .offset(y: shouldAnimate ? (isFloating ? -4 : 4) : 0)
        .animation(
            shouldAnimate ? .easeInOut(duration: mood.motionDuration).repeatForever(autoreverses: true) : nil,
            value: isFloating
        )
        .animation(reduceMotion ? nil : .smooth(duration: 0.38), value: mood)
        .onAppear { isFloating = shouldAnimate }
    }

    private var moodBadge: some View {
        Image(systemName: mood.decorationSymbol)
            .font(.system(size: size * 0.145, weight: .semibold))
            .foregroundStyle(mood.accentColor)
            .frame(width: size * 0.29, height: size * 0.29)
            .background(.ultraThinMaterial, in: .circle)
            .overlay {
                Circle()
                    .stroke(mood.accentColor.opacity(0.52), lineWidth: max(1, size * 0.009))
            }
            .shadow(color: mood.accentColor.opacity(0.38), radius: size * 0.055, y: size * 0.025)
            .offset(x: size * 0.37, y: -size * 0.34)
            .symbolEffect(.pulse, options: .repeating, isActive: shouldAnimate)
            .accessibilityHidden(true)
    }

    private var lookAssetName: String {
        if wardrobe.displayedCollectionSkin == nil,
           wardrobe.displayedPersona == .classic,
           isCelebrating {
            return "StarPetCelebrate"
        }
        return wardrobe.displayedAssetName
    }

    private var auraColor: Color {
        color(for: wardrobe.displayedAura)
    }

    private func color(for aura: StarAura) -> Color {
        switch aura {
        case .classic: .celestialGold
        case .moonlit: .celestialLavender
        case .sunrise: .orange
        case .rose: .celestialPink
        case .nebula: .purple
        }
    }

    private func tarotStyleOverlay(for aura: StarAura) -> some View {
        let color = color(for: aura)
        return ZStack {
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [.clear, color.opacity(0.74), .clear, color.opacity(0.42), .clear],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: max(1.5, size * 0.014), dash: [size * 0.05, size * 0.04])
                )
                .frame(width: size * 0.88, height: size * 0.88)

            Image(systemName: aura.glowSymbol)
                .font(.system(size: size * 0.13, weight: .semibold))
                .foregroundStyle(color.opacity(0.88))
                .offset(x: -size * 0.38, y: -size * 0.20)

            Image(systemName: "sparkle")
                .font(.system(size: size * 0.11, weight: .semibold))
                .foregroundStyle(color.opacity(0.80))
                .offset(x: size * 0.37, y: size * 0.22)
        }
        .rotationEffect(.degrees(shouldAnimate && isFloating ? 5 : -5))
        .animation(
            shouldAnimate
                ? .easeInOut(duration: mood.motionDuration + 0.8).repeatForever(autoreverses: true)
                : nil,
            value: isFloating
        )
        .accessibilityHidden(true)
    }

    private var accessoryOffset: CGSize {
        switch wardrobe.selectedAccessory {
        case .none: .zero
        case .moonCrown: CGSize(width: 0, height: -size * 0.37)
        case .heartPin: CGSize(width: -size * 0.34, height: size * 0.12)
        case .magicWand: CGSize(width: size * 0.35, height: size * 0.13)
        case .cometCharm: CGSize(width: size * 0.32, height: -size * 0.22)
        }
    }
}

/// Lightweight ambience for any room using `StarHabitat`. It animates only
/// transform and opacity; Reduce Motion keeps the same mood palette and symbols
/// as a fully static composition.
struct StarHabitatMoodLayer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let mood: StarVisualMood

    @State private var driftsUp = false

    private let points: [CGPoint] = [
        CGPoint(x: 0.16, y: 0.22),
        CGPoint(x: 0.80, y: 0.18),
        CGPoint(x: 0.68, y: 0.39),
        CGPoint(x: 0.27, y: 0.48),
        CGPoint(x: 0.88, y: 0.61),
        CGPoint(x: 0.12, y: 0.70),
        CGPoint(x: 0.58, y: 0.13),
        CGPoint(x: 0.42, y: 0.67),
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: mood.roomColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(mood.roomBlendMode)

                RadialGradient(
                    colors: [mood.accentColor.opacity(mood.glowOpacity * 0.55), .clear],
                    center: .center,
                    startRadius: 4,
                    endRadius: min(proxy.size.width, proxy.size.height) * 0.48
                )
                .blendMode(.screen)

                ForEach(0..<mood.particleCount, id: \.self) { index in
                    Image(systemName: mood.ambientSymbol)
                        .font(.system(size: 9 + CGFloat(index % 3) * 3, weight: .semibold))
                        .foregroundStyle(mood.accentColor.opacity(0.40 + Double(index % 2) * 0.18))
                        .shadow(color: mood.accentColor.opacity(0.32), radius: 6)
                        .position(
                            x: proxy.size.width * points[index].x,
                            y: proxy.size.height * points[index].y
                        )
                        .offset(y: reduceMotion ? 0 : (driftsUp ? -5 : 5) * (index.isMultiple(of: 2) ? 1 : -1))
                        .opacity(reduceMotion ? 0.82 : (driftsUp ? 0.92 : 0.56))
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeInOut(duration: mood.motionDuration + Double(index) * 0.11)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.08),
                            value: driftsUp
                        )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { driftsUp = !reduceMotion }
        .onChange(of: reduceMotion) { _, value in
            driftsUp = !value
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.38), value: mood)
    }
}

/// Gives the seasonal rooms their own silhouette instead of relying on a tint
/// alone. The base room remains familiar, while a few restrained foreground
/// details make each limited theme immediately recognisable.
struct SeasonalRoomLayer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let theme: StarRoomTheme

    @State private var drifts = false

    private let points: [CGPoint] = [
        CGPoint(x: 0.10, y: 0.18), CGPoint(x: 0.24, y: 0.34),
        CGPoint(x: 0.42, y: 0.15), CGPoint(x: 0.61, y: 0.30),
        CGPoint(x: 0.78, y: 0.13), CGPoint(x: 0.91, y: 0.40),
        CGPoint(x: 0.18, y: 0.62), CGPoint(x: 0.53, y: 0.57),
        CGPoint(x: 0.83, y: 0.69), CGPoint(x: 0.36, y: 0.78),
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                signature(in: proxy.size)

                ForEach(0..<particleCount, id: \.self) { index in
                    Image(systemName: particleSymbol(for: index))
                        .font(.system(size: particleSize(for: index), weight: .semibold))
                        .foregroundStyle(particleColor.opacity(0.48 + Double(index % 3) * 0.12))
                        .shadow(color: particleColor.opacity(0.34), radius: 6)
                        .position(
                            x: proxy.size.width * points[index].x,
                            y: proxy.size.height * points[index].y
                        )
                        .offset(
                            x: reduceMotion ? 0 : (drifts ? 4 : -4) * (index.isMultiple(of: 2) ? 1 : -1),
                            y: reduceMotion ? 0 : (drifts ? -7 : 7)
                        )
                        .opacity(reduceMotion ? 0.78 : (drifts ? 0.92 : 0.48))
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeInOut(duration: 3.4 + Double(index) * 0.13)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.07),
                            value: drifts
                        )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { drifts = !reduceMotion }
        .onChange(of: reduceMotion) { _, value in drifts = !value }
    }

    @ViewBuilder
    private func signature(in size: CGSize) -> some View {
        switch theme {
        case .observatoryGarden:
            EmptyView()
        case .moonRabbitFestival:
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.celestialGold.opacity(0.80), Color.orange.opacity(0.18), .clear],
                            center: .center,
                            startRadius: 2,
                            endRadius: 58
                        )
                    )
                    .frame(width: 116, height: 116)
                Image(systemName: "hare.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color.celestialNight.opacity(0.56))
                    .offset(y: 14)
            }
            .position(x: size.width * 0.78, y: size.height * 0.24)
        case .halloweenGhostNight:
            ZStack {
                Ellipse()
                    .fill(Color.purple.opacity(0.20))
                    .blur(radius: 14)
                    .frame(width: size.width * 0.72, height: size.height * 0.30)
                Image(systemName: "theatermasks.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.34))
            }
            .position(x: size.width * 0.56, y: size.height * 0.30)
        case .christmasSnowRoom:
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [Color.white.opacity(0.25), Color.cyan.opacity(0.12), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blendMode(.screen)

                Ellipse()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: size.width * 0.78, height: size.height * 0.22)
                    .blur(radius: 5)
                    .offset(x: -size.width * 0.20, y: size.height * 0.10)

                HStack(alignment: .bottom) {
                    Image(systemName: "tree.fill")
                        .font(.system(size: min(size.height * 0.22, 62), weight: .light))
                    Spacer()
                    Image(systemName: "tree.fill")
                        .font(.system(size: min(size.height * 0.16, 46), weight: .light))
                }
                .foregroundStyle(Color.white.opacity(0.30))
                .padding(.horizontal, size.width * 0.08)
                .padding(.bottom, size.height * 0.05)
            }
        }
    }

    private var particleCount: Int {
        switch theme {
        case .observatoryGarden: 0
        case .moonRabbitFestival: 6
        case .halloweenGhostNight: 5
        case .christmasSnowRoom: 10
        }
    }

    private var particleColor: Color {
        switch theme {
        case .observatoryGarden: .clear
        case .moonRabbitFestival: .celestialGold
        case .halloweenGhostNight: .celestialLavender
        case .christmasSnowRoom: .white
        }
    }

    private func particleSymbol(for index: Int) -> String {
        switch theme {
        case .observatoryGarden: "sparkle"
        case .moonRabbitFestival: index.isMultiple(of: 3) ? "hare.fill" : "sparkle"
        case .halloweenGhostNight: index.isMultiple(of: 2) ? "theatermasks.fill" : "moon.stars.fill"
        case .christmasSnowRoom: "snowflake"
        }
    }

    private func particleSize(for index: Int) -> CGFloat {
        switch theme {
        case .observatoryGarden: 0
        case .moonRabbitFestival: index.isMultiple(of: 3) ? 15 : 10
        case .halloweenGhostNight: index.isMultiple(of: 2) ? 17 : 11
        case .christmasSnowRoom: 12 + CGFloat(index % 3) * 4
        }
    }
}
