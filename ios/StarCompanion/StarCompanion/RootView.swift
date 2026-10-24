import StoreKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("xingban.ios.profile-setup-deferred.v1") private var profileSetupDeferred = false
    @State private var presentsDailyGate = DailyGatePolicy.shouldPresentOnLaunch
    @State private var profileSetupPresented = false
    @State private var selectedTab: Int

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let previewTab = arguments.firstIndex(of: "--preview-tab")
            .flatMap { index in arguments.indices.contains(index + 1) ? Int(arguments[index + 1]) : nil }
        _selectedTab = State(initialValue: min(max(previewTab ?? 0, 0), 4))
        #else
        _selectedTab = State(initialValue: 0)
        #endif
    }

    var body: some View {
        ZStack {
            if store.deletionIntent != nil {
                AccountDeletionProgressView()
            } else if presentsDailyGate {
                DailyGateView {
                    DailyGatePolicy.markPresented()
                    selectedTab = 0
                    presentsDailyGate = false
                }
                .transition(.opacity)
            } else {
                Group {
                    if store.user == nil {
                        WeChatLoginView()
                    } else {
                        MainTabView(selection: $selectedTab)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: store.user)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: presentsDailyGate)
        .environment(\.locale, store.language.locale)
        .sheet(isPresented: $profileSetupPresented, onDismiss: {
            if store.profile == nil { profileSetupDeferred = true }
        }) {
            PersonalizationSetupView(isOnboarding: true)
        }
        .sheet(item: Binding(
            get: { store.pendingHomeVisitLink },
            set: { if $0 == nil { store.dismissPendingHomeVisitLink() } }
        )) { link in
            HomeVisitExchangeSheet(link: link)
        }
        .sheet(isPresented: Binding(
            get: { store.pendingPlanetInviteCode != nil && store.account != nil && store.deletionIntent == nil && !presentsDailyGate },
            set: { if !$0 { store.pendingPlanetInviteCode = nil } }
        )) {
            InviteFriendSheet()
        }
        .alert(
            store.language.text("無法打開星星卡片", "별 카드를 열 수 없어요", "Couldn't open star card"),
            isPresented: Binding(
                get: { store.homeVisitLinkError != nil },
                set: { if !$0 { store.dismissHomeVisitLinkError() } }
            )
        ) {
            Button(store.language.text("知道了", "확인", "OK")) {
                store.dismissHomeVisitLinkError()
            }
        } message: {
            Text(store.homeVisitLinkError ?? "")
        }
        .alert(
            store.language.text("帳號資料已分開保留", "계정 데이터를 따로 보관했어요", "Account data kept separate"),
            isPresented: Binding(
                get: { store.accountDataNotice != nil },
                set: { if !$0 { store.dismissAccountDataNotice() } }
            )
        ) {
            if store.accountCloudSyncStatus == .conflict {
                Button(store.language.text("保留這部裝置", "이 기기 데이터 유지", "Keep This Device")) {
                    store.resolveAccountCloudConflictUsingThisDevice()
                }
                Button(
                    store.language.text("使用已同步版本", "동기화된 데이터 사용", "Use Synced Copy"),
                    role: .destructive
                ) {
                    store.resolveAccountCloudConflictUsingSyncedCopy()
                }
                Button(store.language.text("稍後決定", "나중에 결정", "Decide Later"), role: .cancel) {
                    store.dismissAccountDataNotice()
                }
            } else {
                Button(store.language.text("知道了", "확인", "OK")) {
                    store.dismissAccountDataNotice()
                }
            }
        } message: {
            Text(store.accountDataNotice ?? "")
        }
        .task { offerProfileSetupIfReady() }
        .onChange(of: store.user) { _, _ in offerProfileSetupIfReady() }
        .onChange(of: store.isAccountCloudBootstrapPending) { _, _ in
            offerProfileSetupIfReady()
        }
        .onChange(of: presentsDailyGate) { _, _ in offerProfileSetupIfReady() }
        .onChange(of: store.pendingHomeVisitLink) { _, link in
            if link != nil { profileSetupPresented = false }
        }
        .onChange(of: store.pendingPlanetInviteCode) { _, code in
            if code != nil { profileSetupPresented = false }
        }
        .onChange(of: store.deletionIntent) { _, intent in
            if intent != nil { profileSetupPresented = false }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active,
                  !presentsDailyGate,
                  DailyGatePolicy.shouldPresentToday
            else { return }

            selectedTab = 0
            presentsDailyGate = true
        }
    }

    private func offerProfileSetupIfReady() {
        #if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("--skip-profile-setup"),
              ProcessInfo.processInfo.environment["STARCOMPANION_SKIP_PROFILE_SETUP"] != "1"
        else { return }
        #endif
        guard store.user != nil,
              !store.isAccountCloudBootstrapPending,
              store.profile == nil,
              store.pendingHomeVisitLink == nil,
              store.pendingPlanetInviteCode == nil,
              store.deletionIntent == nil,
              !profileSetupDeferred,
              !presentsDailyGate
        else { return }
        profileSetupPresented = true
    }
}

private enum DailyGatePolicy {
    private static let storageKey = "starCompanion.dailyGate.v1"

    static var todayKey: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    static var shouldPresentToday: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--skip-daily-gate")
            || ProcessInfo.processInfo.environment["STARCOMPANION_SKIP_DAILY_GATE"] == "1" {
            return false
        }
        #endif
        return UserDefaults.standard.string(forKey: storageKey) != todayKey
    }

    static var shouldPresentOnLaunch: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--skip-daily-gate")
            || ProcessInfo.processInfo.environment["STARCOMPANION_SKIP_DAILY_GATE"] == "1" {
            return false
        }
        if ProcessInfo.processInfo.arguments.contains("--replay-daily-gate")
            || ProcessInfo.processInfo.environment["STARCOMPANION_REPLAY_DAILY_GATE"] == "1" {
            return true
        }
        #endif
        return shouldPresentToday
    }

    static func markPresented() {
        UserDefaults.standard.set(todayKey, forKey: storageKey)
    }
}

private enum DailyGateTheme: Int, CaseIterable {
    case moonGarden
    case roseNebula
    case sunriseObservatory
    case cometNight
    case loversConstellation
    case bestieAurora
    case crystalRain

    static var today: DailyGateTheme {
        let calendar = Calendar.current
        let day = calendar.ordinality(of: .day, in: .year, for: .now) ?? 0
        return allCases[abs(day) % allCases.count]
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .moonGarden: language.text("月光花園", "달빛 정원", "Moonlit Garden")
        case .roseNebula: language.text("玫瑰星雲", "장미 성운", "Rose Nebula")
        case .sunriseObservatory: language.text("晨曦天文台", "새벽 천문대", "Sunrise Observatory")
        case .cometNight: language.text("彗星之夜", "혜성의 밤", "Comet Night")
        case .loversConstellation: language.text("戀人星圖", "연인의 별자리", "Lovers' Constellation")
        case .bestieAurora: language.text("閨蜜極光", "우정의 오로라", "Bestie Aurora")
        case .crystalRain: language.text("水晶星雨", "수정 별비", "Crystal Starfall")
        }
    }

    func prompt(in language: AppLanguage) -> String {
        switch self {
        case .moonGarden: language.text("月光把今天的答案放在門後", "달빛이 오늘의 답을 문 뒤에 두었어요", "Moonlight left today's answer behind the gate")
        case .roseNebula: language.text("今天的溫柔，正在另一邊等你", "오늘의 다정함이 저편에서 기다려요", "Today's tenderness is waiting on the other side")
        case .sunriseObservatory: language.text("推開門，看看今天先亮起哪顆星", "문을 열고 오늘 어떤 별이 먼저 빛나는지 봐요", "Open the gate and see which star lights first")
        case .cometNight: language.text("彗星路過前，收下今天的小提示", "혜성이 지나가기 전에 오늘의 힌트를 받아요", "Catch today's little hint before the comet passes")
        case .loversConstellation: language.text("有一句想說的話，藏在今天的星圖裡", "하고 싶은 한마디가 오늘의 별자리에 숨어 있어요", "Something worth saying is hidden in today's stars")
        case .bestieAurora: language.text("今天適合把好心情分給重要的人", "오늘은 소중한 사람과 좋은 기분을 나눠요", "Today is good for sharing a bright mood with someone close")
        case .crystalRain: language.text("一顆新的願望，正落在門的另一邊", "새로운 소원이 문 너머로 내려오고 있어요", "A new wish is falling just beyond the gate")
        }
    }

    var symbol: String {
        switch self {
        case .moonGarden: "moon.stars.fill"
        case .roseNebula: "heart.fill"
        case .sunriseObservatory: "sun.max.fill"
        case .cometNight: "sparkles"
        case .loversConstellation: "heart.fill"
        case .bestieAurora: "person.2.fill"
        case .crystalRain: "diamond.fill"
        }
    }

    var decorativeSymbols: [String] {
        switch self {
        case .moonGarden: ["moon.stars.fill", "sparkle", "leaf.fill"]
        case .roseNebula: ["heart.fill", "sparkle", "camera.macro"]
        case .sunriseObservatory: ["sun.max.fill", "sparkle", "scope"]
        case .cometNight: ["sparkles", "paperplane.fill", "star.fill"]
        case .loversConstellation: ["heart.fill", "link", "star.fill"]
        case .bestieAurora: ["person.2.fill", "rainbow", "sparkle"]
        case .crystalRain: ["diamond.fill", "drop.fill", "sparkles"]
        }
    }

    var overlayColors: [Color] {
        switch self {
        case .moonGarden: [Color.blue.opacity(0.22), Color.purple.opacity(0.12), .clear]
        case .roseNebula: [Color.pink.opacity(0.24), Color.purple.opacity(0.12), .clear]
        case .sunriseObservatory: [Color.orange.opacity(0.22), Color.yellow.opacity(0.10), .clear]
        case .cometNight: [Color.indigo.opacity(0.24), Color.cyan.opacity(0.10), .clear]
        case .loversConstellation: [Color.pink.opacity(0.24), Color.red.opacity(0.08), .clear]
        case .bestieAurora: [Color.cyan.opacity(0.20), Color.mint.opacity(0.12), .clear]
        case .crystalRain: [Color.blue.opacity(0.22), Color.white.opacity(0.10), .clear]
        }
    }

    var accent: Color {
        switch self {
        case .moonGarden: .cyan
        case .roseNebula: .pink
        case .sunriseObservatory: .orange
        case .cometNight: .celestialGold
        case .loversConstellation: .pink
        case .bestieAurora: .mint
        case .crystalRain: .cyan
        }
    }

    var hueRotation: Angle {
        switch self {
        case .moonGarden: .degrees(18)
        case .roseNebula: .degrees(-8)
        case .sunriseObservatory: .degrees(-22)
        case .cometNight: .degrees(36)
        case .loversConstellation: .degrees(-16)
        case .bestieAurora: .degrees(62)
        case .crystalRain: .degrees(92)
        }
    }

    var saturation: Double {
        switch self {
        case .sunriseObservatory, .crystalRain: 0.88
        case .bestieAurora: 0.82
        default: 1.04
        }
    }

    var brightness: Double {
        switch self {
        case .cometNight: -0.08
        case .moonGarden: -0.03
        case .sunriseObservatory: 0.04
        default: 0
        }
    }
}

private struct DailyGateView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animationStarted = false
    @State private var unlockProgress: CGFloat = 0
    @State private var doorProgress: CGFloat = 0
    @State private var enterProgress: CGFloat = 0
    @State private var hapticTrigger = 0
    @State private var transitionTask: Task<Void, Never>?

    private let theme: DailyGateTheme

    let onComplete: () -> Void

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "--preview-gate-theme"),
           arguments.indices.contains(flag + 1),
           let rawValue = Int(arguments[flag + 1]),
           let previewTheme = DailyGateTheme(rawValue: rawValue) {
            theme = previewTheme
        } else {
            theme = .today
        }
        #else
        theme = .today
        #endif
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("MagicDoorOpen")
                    .resizable()
                    .scaledToFill()
                    .hueRotation(theme.hueRotation)
                    .saturation(theme.saturation)
                    .brightness(theme.brightness)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(1 + enterProgress * 3.35, anchor: UnitPoint(x: 0.5, y: 0.43))
                    .opacity(doorProgress)
                    .clipped()

                Image("MagicDoorClosed")
                    .resizable()
                    .scaledToFill()
                    .hueRotation(theme.hueRotation)
                    .saturation(theme.saturation)
                    .brightness(theme.brightness)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .opacity(max(0, 1 - doorProgress * 2.4))
                    .clipped()

                LinearGradient(
                    colors: theme.overlayColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.softLight)
                .opacity(max(0, 1 - enterProgress * 0.9))
                .allowsHitTesting(false)

                dailyThemeDecorations(in: proxy.size)

                doorLeaves(in: proxy.size)

                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.yellow.opacity(0.92))
                    .shadow(color: .yellow.opacity(0.72), radius: 12)
                    .scaleEffect(0.5 + unlockProgress * 0.85)
                    .opacity(unlockProgress * max(0, 1 - doorProgress * 1.6))
                    .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.437)
                    .allowsHitTesting(false)

                RadialGradient(
                    colors: [.white.opacity(0.88), .yellow.opacity(0.16), .clear],
                    center: UnitPoint(x: 0.5, y: 0.44),
                    startRadius: 4,
                    endRadius: proxy.size.width * (0.22 + enterProgress * 0.68)
                )
                .opacity(max(doorProgress * 0.72, enterProgress))
                .blendMode(.screen)
                .allowsHitTesting(false)

                gateChrome(in: proxy.size)
                    .padding(.horizontal, proxy.size.width > proxy.size.height ? 40 : 24)
                    .padding(.top, max(proxy.safeAreaInsets.top, 14))
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom, 22))
                    .opacity(max(0, 1 - unlockProgress * 1.35))

                Color.white
                    .opacity(enterProgress * 0.78)
                    .allowsHitTesting(false)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color(red: 0.92, green: 0.84, blue: 0.91))
            .ignoresSafeArea()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(store.language.text("每日魔法門", "매일의 마법 문", "Daily magic gate"))
        .onDisappear { transitionTask?.cancel() }
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
    }

    private func gateChrome(in size: CGSize) -> some View {
        let isLandscape = size.width > size.height
        let actionWidth = isLandscape ? min(size.width * 0.48, 560) : .infinity

        return VStack {
            VStack(spacing: isLandscape ? 3 : 7) {
                Label(theme.title(in: store.language), systemImage: theme.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: .capsule)
                Text(store.language.text("星伴", "별친구", "STAR COMPANION"))
                    .font(isLandscape ? .title.bold() : .largeTitle.bold())
                    .tracking(isLandscape ? 2 : 3)
                Text(
                    Date.now.formatted(
                        .dateTime
                            .month(.wide)
                            .day()
                            .weekday(.wide)
                            .locale(store.language.locale)
                    )
                )
                    .font(isLandscape ? .caption : .subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, isLandscape ? 18 : 22)
            .padding(.vertical, isLandscape ? 10 : 12)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 22))
            .shadow(color: .white.opacity(0.30), radius: 12)

            Spacer()

            VStack(spacing: isLandscape ? 7 : 12) {
                Text(store.language.text("今天也來看看", "오늘도 보러 왔네요", "Come see what today holds"))
                    .font(isLandscape ? .headline.bold() : .title2.bold())
                Text(store.language.text("推開門，就是今天的運勢", "문을 열면 오늘의 운세가 펼쳐져요", "Open the gate to reveal today's fortune"))
                    .font(isLandscape ? .caption : .subheadline)
                    .foregroundStyle(.secondary)

                Text(theme.prompt(in: store.language))
                    .font(isLandscape ? .caption2 : .caption)
                    .foregroundStyle(Color(red: 0.36, green: 0.24, blue: 0.42).opacity(0.72))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Button(action: openDoor) {
                    Label(store.language.text("推開魔法門", "마법 문 열기", "Open the magic gate"), systemImage: "sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: isLandscape ? 48 : 54)
                }
                .buttonStyle(.glassProminent)
                .tint(Color(red: 0.75, green: 0.34, blue: 0.48))
                .disabled(animationStarted)
                .accessibilityHint(store.language.text("打開今天的魔法門並進入星伴", "오늘의 마법 문을 열고 별친구에 들어가요", "Open today's magic gate and enter Star Companion"))
            }
            .frame(maxWidth: actionWidth)
            .foregroundStyle(Color(red: 0.28, green: 0.18, blue: 0.34))
        }
        .overlay(alignment: .topTrailing) {
            Button(action: skipGate) {
                Label(
                    store.language.text("略過", "건너뛰기", "Skip"),
                    systemImage: "xmark"
                )
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
            }
            .buttonStyle(.glass)
            .accessibilityHint(store.language.text("略過每日魔法門並直接進入星伴", "매일의 마법 문을 건너뛰고 바로 별친구로 이동해요", "Skip the daily magic gate and enter Star Companion"))
        }
    }

    private func dailyThemeDecorations(in size: CGSize) -> some View {
        let positions = [
            CGPoint(x: size.width * 0.15, y: size.height * 0.25),
            CGPoint(x: size.width * 0.84, y: size.height * 0.31),
            CGPoint(x: size.width * 0.78, y: size.height * 0.18),
        ]

        return ZStack {
            ForEach(Array(theme.decorativeSymbols.enumerated()), id: \.offset) { index, symbol in
                Image(systemName: symbol)
                    .font(.system(size: [24, 16, 18][index], weight: .light))
                    .position(positions[index])
            }
        }
        .foregroundStyle(theme.accent.opacity(0.72))
        .opacity(max(0, 1 - unlockProgress * 1.25))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func doorLeaves(in size: CGSize) -> some View {
        if doorProgress > 0 {
            let doorX = size.width * 0.29
            let doorY = size.height * 0.243
            let doorWidth = size.width * 0.42
            let doorHeight = size.height * 0.375
            let halfWidth = doorWidth / 2

            ZStack {
                leaf(
                    size: size,
                    cropX: doorX,
                    width: halfWidth,
                    height: doorHeight,
                    angle: -82 * doorProgress,
                    anchor: .leading
                )
                .position(x: doorX + halfWidth / 2, y: doorY + doorHeight / 2)

                leaf(
                    size: size,
                    cropX: doorX + halfWidth,
                    width: halfWidth,
                    height: doorHeight,
                    angle: 82 * doorProgress,
                    anchor: .trailing
                )
                .position(x: doorX + halfWidth + halfWidth / 2, y: doorY + doorHeight / 2)
            }
            .opacity(max(0, 1 - enterProgress * 1.15))
            .allowsHitTesting(false)
        }
    }

    private func leaf(
        size: CGSize,
        cropX: CGFloat,
        width: CGFloat,
        height: CGFloat,
        angle: Double,
        anchor: UnitPoint
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Image("MagicDoorClosed")
                .resizable()
                .scaledToFill()
                .hueRotation(theme.hueRotation)
                .saturation(theme.saturation)
                .brightness(theme.brightness)
                .frame(width: size.width, height: size.height)
                .offset(x: -cropX, y: -size.height * 0.243)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), anchor: anchor, perspective: 0.72)
        .shadow(color: .black.opacity(Double(doorProgress) * 0.18), radius: 7, x: angle < 0 ? 7 : -7)
    }

    private func openDoor() {
        guard !animationStarted else { return }

        animationStarted = true
        hapticTrigger += 1

        if reduceMotion {
            transitionTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .milliseconds(120))
                } catch {
                    return
                }
                onComplete()
            }
            return
        }

        transitionTask?.cancel()
        transitionTask = Task { @MainActor in
            withAnimation(.easeOut(duration: 0.18)) {
                unlockProgress = 1
            }
            do {
                try await Task.sleep(for: .milliseconds(160))
            } catch {
                return
            }

            withAnimation(.timingCurve(0.2, 0.76, 0.22, 1, duration: 0.62)) {
                doorProgress = 1
            }
            do {
                try await Task.sleep(for: .milliseconds(390))
            } catch {
                return
            }

            withAnimation(.timingCurve(0.28, 0.02, 0.14, 1, duration: 0.56)) {
                enterProgress = 1
            }
            do {
                try await Task.sleep(for: .milliseconds(570))
            } catch {
                return
            }
            onComplete()
        }
    }

    private func skipGate() {
        transitionTask?.cancel()
        animationStarted = true
        onComplete()
    }
}

private struct MainTabView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: Int

    @ViewBuilder
    var body: some View {
        #if DEBUG
        if hasStandalonePreviewRoute {
            standalonePreviewShell
        } else {
            adaptiveTabs
        }
        #else
        adaptiveTabs
        #endif
    }

    /// Keeps one `TabView` alive while the surrounding navigation chrome adapts.
    /// This preserves each tab's NavigationStack and local view state when an
    /// iPad window crosses the regular/compact size-class boundary.
    private var adaptiveTabs: some View {
        ZStack {
            if horizontalSizeClass == .regular {
                CelestialBackdrop()
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                if horizontalSizeClass == .regular {
                    topNavigationBar
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                }

                tabContent
            }
        }
    }

    private var topNavigationBar: some View {
        HStack {
            Spacer(minLength: 0)
            GlassEffectContainer(spacing: 7) {
                HStack(spacing: 7) {
                    topNavigationButton(
                        index: 0,
                        title: store.language.text("今日", "오늘", "Today"),
                        symbol: "sparkles"
                    )
                    topNavigationButton(
                        index: 1,
                        title: store.language.text("塔羅", "타로", "Tarot"),
                        symbol: "rectangle.portrait.on.rectangle.portrait"
                    )
                    topNavigationButton(
                        index: 2,
                        title: store.language.text("星寵", "별친구", "Star Pet"),
                        symbol: "star.fill"
                    )
                    topNavigationButton(
                        index: 3,
                        title: store.language.text("闖關", "게임", "Play"),
                        symbol: "gamecontroller.fill"
                    )
                    topNavigationButton(
                        index: 4,
                        title: store.language.text("我的", "프로필", "Profile"),
                        symbol: "person.crop.circle"
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private var tabContent: some View {
        TabView(selection: $selection) {
            TodayFortuneView { selection = 1 }
                .toolbarVisibility(tabBarVisibility, for: .tabBar)
                .tabItem { Label(store.language.text("今日", "오늘", "Today"), systemImage: "sparkles") }
                .tag(0)

            AskUniverseView()
                .toolbarVisibility(tabBarVisibility, for: .tabBar)
                .tabItem { Label(store.language.text("問問", "우주", "Ask"), systemImage: "bubble.left.and.text.bubble.right") }
                .tag(1)

            StarPlanetView()
                .toolbarVisibility(tabBarVisibility, for: .tabBar)
                .tabItem { Label(store.language.text("星寵", "별친구", "Star Pet"), systemImage: "star.fill") }
                .tag(2)

            GameHubView()
                .toolbarVisibility(tabBarVisibility, for: .tabBar)
                .tabItem { Label(store.language.text("闖關", "게임", "Play"), systemImage: "gamecontroller.fill") }
                .tag(3)

            ProfileView()
                .toolbarVisibility(tabBarVisibility, for: .tabBar)
                .tabItem { Label(store.language.text("我的", "프로필", "Profile"), systemImage: "person.crop.circle") }
                .tag(4)
        }
        .tint(Color("AccentColor"))
        .tabBarMinimizeBehavior(.onScrollDown)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private var tabBarVisibility: Visibility {
        horizontalSizeClass == .regular ? .hidden : .automatic
    }

    #if DEBUG
    private var hasStandalonePreviewRoute: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--preview-star-life")
            || arguments.contains("--preview-bedtime-wish")
            || arguments.contains("--preview-weekly-story")
            || arguments.contains("--preview-star-home")
            || arguments.contains("--preview-home-visits")
            || arguments.contains("--preview-wardrobe")
    }

    private var standalonePreviewShell: some View {
        ZStack {
            if horizontalSizeClass == .regular {
                CelestialBackdrop()
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                if horizontalSizeClass == .regular {
                    topNavigationBar
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                }

                standalonePreviewDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var standalonePreviewDetail: some View {
        if ProcessInfo.processInfo.arguments.contains("--preview-star-life") {
            NavigationStack { StarLifeView() }
        } else if ProcessInfo.processInfo.arguments.contains("--preview-bedtime-wish") {
            NavigationStack { BedtimeWishView() }
        } else if ProcessInfo.processInfo.arguments.contains("--preview-weekly-story") {
            NavigationStack { WeeklyZodiacStoryView() }
        } else if ProcessInfo.processInfo.arguments.contains("--preview-star-home") {
            NavigationStack { StarHomeStudioView() }
        } else if ProcessInfo.processInfo.arguments.contains("--preview-home-visits") {
            NavigationStack { HomeVisitsView() }
        } else if ProcessInfo.processInfo.arguments.contains("--preview-wardrobe") {
            NavigationStack { StarWardrobeView() }
        } else {
            EmptyView()
        }
    }
    #endif

    @ViewBuilder
    private func topNavigationButton(index: Int, title: String, symbol: String) -> some View {
        let isSelected = selection == index

        if isSelected {
            Button {
                selectTab(index)
            } label: {
                topNavigationLabel(title: title, symbol: symbol, isSelected: true)
            }
            .celestialGlassButtonStyle(prominent: true)
            .buttonBorderShape(.capsule)
            .tint(Color("AccentColor"))
            .accessibilityAddTraits(.isSelected)
            .accessibilityLabel(title)
        } else {
            Button {
                selectTab(index)
            } label: {
                topNavigationLabel(title: title, symbol: symbol, isSelected: false)
            }
            .celestialGlassButtonStyle()
            .buttonBorderShape(.capsule)
            .accessibilityLabel(title)
        }
    }

    @ViewBuilder
    private func topNavigationLabel(title: String, symbol: String, isSelected: Bool) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 50, height: 50)
                .foregroundStyle(isSelected ? .white : .primary)
        } else {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .frame(minHeight: 44)
                .foregroundStyle(isSelected ? .white : .primary)
        }
    }

    private func selectTab(_ index: Int) {
        if reduceMotion {
            selection = index
        } else {
            withAnimation(.snappy(duration: 0.26)) {
                selection = index
            }
        }
    }
}

private struct AccountDeletionSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmationPresented = false
    @State private var subscriptionsPresented = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(store.language.text("刪除後，帳號和保存在服務上的出生資料、收藏、抽牌與遊戲進度都會移除，這部裝置也會清除該帳號的資料。此操作無法復原。", "계정과 서버의 출생 정보, 저장한 내용, 카드 기록과 게임 진행 정보를 삭제하고 이 기기의 해당 계정 데이터도 지웁니다. 되돌릴 수 없어요.", "This permanently deletes your account, birth details, saved content, readings, and game progress from the service, and clears this account's data from this device. This cannot be undone."))
                    Text(store.language.text("你會退出共享星球，未使用的邀請也會失效；朋友自己的帳號和私人資料會保留。其他離線裝置的本機副本需在該裝置清除。", "공유 별에서 나가고 사용하지 않은 초대도 무효가 됩니다. 친구의 계정과 개인 데이터는 유지됩니다. 다른 오프라인 기기의 복사본은 해당 기기에서 지워 주세요.", "You'll leave your shared planet and your unused invitations will stop working. Your friend's account and private data are kept. Copies on other offline devices must be cleared on those devices."))
                }
                Section(store.language.text("購買與訂閱", "구매와 구독", "Purchases and subscriptions")) {
                    Text(store.language.text("刪除帳號不會取消 Apple 訂閱或自動退款。你可以先管理訂閱，也可以直接刪除帳號。一次購買的造型權益仍由 App Store 帳號管理。", "계정 삭제는 Apple 구독을 취소하거나 자동 환불하지 않습니다. 먼저 구독을 관리하거나 바로 삭제할 수 있어요. 일회성 모습 구매는 App Store 계정에서 관리합니다.", "Deleting your account doesn't cancel Apple subscriptions or issue refunds. You can manage subscriptions first or delete your account now. One-time look purchases remain managed by your App Store account."))
                    Button(store.language.text("管理 Apple 訂閱", "Apple 구독 관리", "Manage Apple subscriptions")) { subscriptionsPresented = true }
                }
                if let error = store.deletionError { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Button(store.language.text("永久刪除帳號", "계정 영구 삭제", "Permanently delete account"), role: .destructive) { confirmationPresented = true }
                        .disabled(store.isDeletingAccount)
                    if store.isDeletingAccount { ProgressView() }
                }
            }
            .navigationTitle(store.language.text("刪除帳號", "계정 삭제", "Delete account"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.language.text("取消", "취소", "Cancel")) { dismiss() }.disabled(store.isDeletingAccount)
                }
            }
            .manageSubscriptionsSheet(isPresented: $subscriptionsPresented)
            .interactiveDismissDisabled(store.isDeletingAccount)
            .confirmationDialog(store.language.text("確定永久刪除帳號？", "계정을 영구 삭제할까요?", "Permanently delete your account?"), isPresented: $confirmationPresented, titleVisibility: .visible) {
                Button(store.language.text("確認刪除", "삭제 확인", "Confirm deletion"), role: .destructive) {
                    Task { await store.deleteAccountPermanently() }
                }
            }
            .onChange(of: store.deletionIntent) { _, intent in if intent != nil { dismiss() } }
        }
    }
}

private struct AccountDeletionProgressView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.crop.circle.badge.minus").font(.largeTitle).accessibilityHidden(true)
            Text(store.language.text("正在完成帳號刪除", "계정 삭제 완료 중", "Finishing account deletion")).font(.title2.bold())
            Text(store.language.text("請保持網路連線。若剛才中斷，可以從這裡繼續；資料同步已暫停。", "연결을 유지해 주세요. 중단되었다면 여기서 계속할 수 있어요. 동기화는 멈췄습니다.", "Stay connected. If the request was interrupted, you can continue here. Data sync is paused."))
                .foregroundStyle(.secondary)
            if store.isDeletingAccount { ProgressView() }
            if let error = store.deletionError { Text(error).foregroundStyle(.red) }
            Button(store.language.text("重試", "다시 시도", "Retry")) { Task { await store.deleteAccountPermanently() } }
                .buttonStyle(.borderedProminent).disabled(store.isDeletingAccount)
        }
        .multilineTextAlignment(.center)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

private struct ProfileView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var membershipStore: MembershipStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var profileEditorPresented = false
    @State private var deleteConfirmationPresented = false
    @State private var deleteAllDataConfirmationPresented = false
    @State private var deleteAccountPresented = false
    @State private var subscriptionPresented = false
    @State private var manageSubscriptionsPresented = false

    init() {
        #if DEBUG
        _subscriptionPresented = State(
            initialValue: ProcessInfo.processInfo.arguments.contains("--preview-subscription")
        )
        #endif
    }

    var body: some View {
        NavigationStack {
            Group {
                if horizontalSizeClass == .regular {
                    regularProfileDashboard
                } else {
                    compactProfileList
                }
            }
            .navigationTitle(
                horizontalSizeClass == .regular
                    ? ""
                    : store.language.text("我的", "내 프로필", "Profile")
            )
            .sheet(isPresented: $profileEditorPresented) {
                PersonalizationSetupView(isOnboarding: false)
            }
            .sheet(isPresented: $subscriptionPresented) {
                SubscriptionView()
            }
            .sheet(isPresented: $deleteAccountPresented) {
                AccountDeletionSheet()
            }
            .manageSubscriptionsSheet(isPresented: $manageSubscriptionsPresented)
            .confirmationDialog(
                store.language.text("刪除出生資料？", "출생 정보를 삭제할까요?", "Delete birth details?"),
                isPresented: $deleteConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button(store.language.text("刪除", "삭제", "Delete"), role: .destructive, action: store.deleteProfile)
                Button(store.language.text("取消", "취소", "Cancel"), role: .cancel) {}
            } message: {
                Text(store.language.text(
                    "這會從目前帳號移除出生資料；正式帳號同步後，其他裝置也會更新。登入帳號與共享星球不受影響。",
                    "현재 계정에서 출생 정보를 삭제합니다. 정식 계정이 동기화되면 다른 기기에도 변경 내용이 반영됩니다. 로그인 계정과 공유 별은 영향을 받지 않아요.",
                    "This removes birth details from the current account. After a verified account syncs, the change also appears on other devices. Your sign-in and shared planet are unaffected."
                ))
            }
            .alert(store.language.text("無法開啟提醒", "알림을 켤 수 없어요", "Unable to enable reminders"), isPresented: Binding(
                get: { store.reminderError != nil },
                set: { if !$0 { store.reminderError = nil } }
            )) {
                Button(store.language.text("知道了", "확인", "OK"), role: .cancel) {
                    store.reminderError = nil
                }
            } message: {
                Text(store.reminderError ?? "")
            }
            .confirmationDialog(
                store.language.text("刪除所有本機個人資料？", "기기의 모든 개인 정보를 삭제할까요?", "Delete all local personal data?"),
                isPresented: $deleteAllDataConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button(store.language.text("永久刪除", "영구 삭제", "Delete permanently"), role: .destructive) {
                    store.deleteAllLocalPersonalData()
                }
                Button(store.language.text("取消", "취소", "Cancel"), role: .cancel) {}
            } message: {
                Text(store.language.text(
                    "這會永久清除這部裝置上的登入憑證、出生資料、收藏、抽牌紀錄、星球、連續天數與提醒。正式帳號保存在服務上的副本不會刪除，重新登入後可能再次下載。",
                    "이 기기의 로그인 정보, 출생 정보, 저장한 메시지, 카드 기록, 별, 연속 일수와 알림을 영구적으로 삭제합니다. 정식 계정의 서비스 복사본은 삭제되지 않으며, 다시 로그인하면 재다운로드될 수 있습니다.",
                    "This permanently clears the sign-in credential, birth profile, saved guidance, readings, planet data, streak, and reminders from this device. It doesn't delete the service copy for a verified account, which may download again after you sign in."
                ))
            }
            .alert(
                store.language.text("無法更新訂閱", "구독을 업데이트할 수 없어요", "Unable to update subscription"),
                isPresented: Binding(
                    get: { membershipStore.lastErrorDescription != nil },
                    set: { if !$0 { membershipStore.lastErrorDescription = nil } }
                )
            ) {
                Button(store.language.text("知道了", "확인", "OK"), role: .cancel) {
                    membershipStore.lastErrorDescription = nil
                }
            } message: {
                Text(membershipStore.lastErrorDescription ?? "")
            }
        }
    }

    private var compactProfileList: some View {
        List {
                Section {
                    ProfileSummaryCard()
                }
                Section(store.language.text("星光會員", "별빛 멤버십", "Starlight Membership")) {
                    membershipCompactContent
                }
                Section(store.language.text("每日旅程", "매일의 여정", "Daily Journey")) {
                    LabeledContent {
                        Text(store.language.text("\(store.visitStreak) 天", "\(store.visitStreak)일", "\(store.visitStreak) days"))
                            .font(.headline)
                            .foregroundStyle(Color("AccentColor"))
                    } label: {
                        Label(store.language.text("連續相遇", "연속 만남", "Visit streak"), systemImage: "flame.fill")
                    }

                    NavigationLink {
                        SavedGuidesView()
                    } label: {
                        LabeledContent {
                            Text("\(store.savedGuides.count)")
                        } label: {
                            Label(store.language.text("收藏的指引", "저장한 메시지", "Saved guidance"), systemImage: "bookmark.fill")
                        }
                    }

                    NavigationLink {
                        ReadingHistoryView()
                    } label: {
                        LabeledContent {
                            Text("\(store.readingHistory.count)")
                        } label: {
                            Label(store.language.text("抽牌紀錄", "카드 기록", "Card readings"), systemImage: "rectangle.portrait.on.rectangle.portrait")
                        }
                    }

                    Toggle(isOn: Binding(
                        get: { store.reminderEnabled },
                        set: { enabled in Task { await store.setReminderEnabled(enabled) } }
                    )) {
                        Label(store.language.text("每日星光提醒", "매일 별빛 알림", "Daily starlight reminder"), systemImage: "bell.fill")
                    }

                    if store.reminderEnabled {
                        DatePicker(
                            store.language.text("提醒時間", "알림 시간", "Reminder time"),
                            selection: reminderTimeBinding,
                            displayedComponents: .hourAndMinute
                        )
                    }
                }
                Section(store.language.text("個人星象", "개인 별자리", "Personal Chart")) {
                    if let profile = store.profile {
                        LabeledContent(
                            store.language.text("生日", "생일", "Birthday"),
                            value: profile.birthDate.formatted(.dateTime.year().month().day().locale(store.language.locale))
                        )
                        LabeledContent(
                            store.language.text("出生時間", "출생 시간", "Birth time"),
                            value: profile.birthTimeText(in: store.language)
                        )
                        if !profile.birthPlace.isEmpty {
                            LabeledContent(store.language.text("出生城市", "출생 도시", "Birth city"), value: profile.birthPlace)
                        }
                        LabeledContent(
                            store.language.text("關注主題", "관심 주제", "Focus areas"),
                            value: profile.focuses.isEmpty
                                ? store.language.text("未設定", "설정 안 함", "Not set")
                                : profile.focuses.map { $0.title(in: store.language) }.joined(separator: focusSeparator)
                        )
                        Button(store.language.text("編輯出生資料", "출생 정보 편집", "Edit birth details"), systemImage: "pencil") {
                            profileEditorPresented = true
                        }
                        Button(store.language.text("刪除出生資料", "출생 정보 삭제", "Delete birth details"), systemImage: "trash", role: .destructive) {
                            deleteConfirmationPresented = true
                        }
                    } else {
                        Button(store.language.text("建立我的出生資料", "내 출생 정보 만들기", "Create my birth profile"), systemImage: "sparkles") {
                            profileEditorPresented = true
                        }
                    }
                }
                Section(store.language.text("語言", "언어", "Language")) {
                    Picker(store.language.text("介面語言", "앱 언어", "App language"), selection: Binding(
                        get: { store.language },
                        set: store.setLanguage
                    )) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                }
                Section(store.language.text("登入帳號", "로그인 계정", "Signed-in Account")) {
                    LabeledContent(
                        store.language.text("登入方式", "로그인 방법", "Sign-in method"),
                        value: store.authProvider?.title(in: store.language) ?? ""
                    )
                    LabeledContent(store.language.text("暱稱", "닉네임", "Display name"), value: store.user?.displayName ?? "")
                    Button(store.language.text("登出", "로그아웃", "Sign out"), role: .destructive, action: store.logout)
                }
                Section(store.language.text("一起把星伴變好", "함께 더 좋게", "Help Us Improve")) {
                    NavigationLink {
                        StarFeedbackView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(store.language.text("給小星的回饋", "꼬꼬마 별에게 남기기", "Send Little Star feedback"))
                                Text(store.language.text("想加什麼、哪裡不順手，都可以說。", "추가할 기능이나 불편한 점을 알려 주세요.", "Tell us what you want next or what feels awkward."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "star.bubble.fill")
                                .foregroundStyle(Color("AccentColor"))
                        }
                    }
                }
                Section(store.language.text("隱私承諾", "개인정보 보호", "Privacy Promise")) {
                    Label {
                        Text(store.language.text(
                            "正式帳號會把帳號識別資料、運勢、抽牌、出生資料與星星進度保存在星伴帳號服務，讓資料跟著帳號走；本機預覽不會上傳。星伴不出售資料，也不用於跨 App 或網站追蹤。",
                            "정식 계정은 계정 식별 정보, 운세, 카드 기록, 출생 정보와 별 진행 정보를 별동무 계정 서비스에 보관하여 데이터가 계정을 따라가게 합니다. 기기 미리보기는 업로드하지 않아요. 별동무는 데이터를 판매하거나 다른 앱·웹사이트에서 추적하는 데 쓰지 않습니다.",
                            "Verified accounts store the account identifier, fortunes, readings, birth details, and star progress in the Star Companion account service so the data follows the account. Local previews don't upload them. Star Companion doesn't sell this data or use it to track you across apps or websites."
                        ))
                    } icon: {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(Color("AccentColor"))
                    }
                    Button(
                        store.language.text("刪除所有本機個人資料", "기기의 모든 개인 정보 삭제", "Delete all local personal data"),
                        systemImage: "trash",
                        role: .destructive
                    ) {
                        deleteAllDataConfirmationPresented = true
                    }
                    Button(store.language.text("刪除帳號", "계정 삭제", "Delete account"), systemImage: "person.crop.circle.badge.minus", role: .destructive) {
                        deleteAccountPresented = true
                    }
                    .disabled(!store.canUseAccountActions)
                }
                Section(store.language.text("帳號驗證", "계정 확인", "Account Verification")) {
                    Text(store.language.text(
                        "Apple、手機與微信登入都會清楚標示目前狀態。尚未連接服務時，不會顯示為已完成驗證。",
                        "Apple, 휴대폰, WeChat 로그인은 현재 상태를 명확하게 보여 줍니다. 서비스가 아직 연결되지 않았다면 인증 완료로 표시하지 않아요.",
                        "Apple, phone, and WeChat sign-in clearly show their current status. An unconfigured service is never shown as verified."
                    ))
                        .foregroundStyle(.secondary)
                }
            }
    }

    private var regularProfileDashboard: some View {
        ScrollView {
            VStack(spacing: 22) {
                HStack(alignment: .top, spacing: 22) {
                    ProfileSummaryCard()
                        .frame(maxWidth: .infinity)

                    profilePanel(
                        title: store.language.text("每日旅程", "매일의 여정", "Daily journey"),
                        symbol: "sparkles"
                    ) {
                        journeyDashboardContent
                    }
                    .frame(maxWidth: .infinity)
                }

                membershipDashboardBanner

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 22), GridItem(.flexible(), spacing: 22)],
                    alignment: .leading,
                    spacing: 22
                ) {
                    profilePanel(
                        title: store.language.text("個人星象", "개인 별자리", "Personal chart"),
                        symbol: "moon.stars.fill"
                    ) {
                        personalDashboardContent
                    }

                    profilePanel(
                        title: store.language.text("語言與帳號", "언어와 계정", "Language & account"),
                        symbol: "person.crop.circle.fill"
                    ) {
                        preferencesDashboardContent
                    }

                    profilePanel(
                        title: store.language.text("給小星的回饋", "꼬꼬마 별에게 남기기", "Feedback for Little Star"),
                        symbol: "star.bubble.fill"
                    ) {
                        feedbackDashboardContent
                    }

                    profilePanel(
                        title: store.language.text("隱私承諾", "개인정보 보호", "Privacy promise"),
                        symbol: "hand.raised.fill"
                    ) {
                        privacyDashboardContent
                    }
                }
            }
            .frame(maxWidth: 1180)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .background {
            ZStack {
                Color(red: 0.965, green: 0.955, blue: 0.985)
                RadialGradient(
                    colors: [Color.celestialPink.opacity(0.16), .clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 720
                )
            }
            .ignoresSafeArea()
        }
    }

    private var membershipCompactContent: some View {
        Group {
            if store.hasMembership {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.language.text("星光會員已啟用", "별빛 멤버십 사용 중", "Starlight Membership is active"))
                        Text(store.language.text("塔羅與今日指引不限次數", "타로와 오늘의 메시지를 무제한으로", "Unlimited tarot and daily guidance"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "star.circle.fill")
                        .foregroundStyle(Color.celestialGold)
                }

                Button(store.language.text("管理訂閱", "구독 관리", "Manage subscription"), systemImage: "gearshape") {
                    manageSubscriptionsPresented = true
                }
            } else {
                Button {
                    subscriptionPresented = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.language.text("解鎖不限次數", "무제한 이용 열기", "Unlock unlimited readings"))
                            Text(store.language.text("每天都能自由重翻與重新抽牌", "매일 자유롭게 다시 펼치고 뽑아 보세요", "Replay guidance and draw again whenever you like"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color("AccentColor"))
                    }
                }
            }
        }
    }

    private var membershipDashboardBanner: some View {
        HStack(spacing: 18) {
            Image("LuckyStarCelebrate")
                .resizable()
                .scaledToFit()
                .frame(width: 86, height: 86)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Label(
                    store.hasMembership
                        ? store.language.text("星光會員已啟用", "별빛 멤버십 사용 중", "Starlight Membership is active")
                        : store.language.text("想多問小星幾次？", "작은 별에게 더 물어볼까요?", "Want a little more starlight?"),
                    systemImage: store.hasMembership ? "checkmark.seal.fill" : "star.fill"
                )
                .font(.title3.bold())
                .foregroundStyle(Color.celestialGold)

                Text(store.hasMembership
                     ? store.language.text("今天的塔羅與指引都可以不限次數使用。", "오늘의 타로와 메시지를 무제한으로 이용할 수 있어요.", "Tarot and today's guidance are unlimited for you.")
                     : store.language.text("加入會員後，翻牌與抽牌不再受每日一次限制。", "멤버십에 가입하면 하루 한 번 제한 없이 카드를 펼치고 뽑을 수 있어요.", "Membership removes the once-a-day limit from guidance and tarot."))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.74))
            }

            Spacer(minLength: 18)

            Button {
                if store.hasMembership {
                    manageSubscriptionsPresented = true
                } else {
                    subscriptionPresented = true
                }
            } label: {
                Label(
                    store.hasMembership
                        ? store.language.text("管理訂閱", "구독 관리", "Manage")
                        : store.language.text("看看會員方案", "멤버십 보기", "See membership"),
                    systemImage: store.hasMembership ? "gearshape" : "sparkles"
                )
                .font(.headline)
                .frame(minHeight: 48)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(Color.celestialPink)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background { CelestialCardBackground() }
        .clipShape(.rect(cornerRadius: 26))
        .overlay {
            RoundedRectangle(cornerRadius: 26)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
    }

    private var journeyDashboardContent: some View {
        VStack(spacing: 0) {
            dashboardValueRow(
                title: store.language.text("連續相遇", "연속 만남", "Visit streak"),
                value: store.language.text("\(store.visitStreak) 天", "\(store.visitStreak)일", "\(store.visitStreak) days"),
                symbol: "flame.fill"
            )
            Divider()
            NavigationLink { SavedGuidesView() } label: {
                dashboardValueRow(
                    title: store.language.text("收藏的指引", "저장한 메시지", "Saved guidance"),
                    value: "\(store.savedGuides.count)",
                    symbol: "bookmark.fill",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            Divider()
            NavigationLink { ReadingHistoryView() } label: {
                dashboardValueRow(
                    title: store.language.text("抽牌紀錄", "카드 기록", "Card readings"),
                    value: "\(store.readingHistory.count)",
                    symbol: "rectangle.portrait.on.rectangle.portrait",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            Divider()
            Toggle(isOn: Binding(
                get: { store.reminderEnabled },
                set: { enabled in Task { await store.setReminderEnabled(enabled) } }
            )) {
                Label(store.language.text("每日星光提醒", "매일 별빛 알림", "Daily starlight reminder"), systemImage: "bell.fill")
            }
            .tint(Color("AccentColor"))
            .padding(.vertical, 13)

            if store.reminderEnabled {
                Divider()
                DatePicker(
                    store.language.text("提醒時間", "알림 시간", "Reminder time"),
                    selection: reminderTimeBinding,
                    displayedComponents: .hourAndMinute
                )
                .padding(.top, 13)
            }
        }
    }

    @ViewBuilder
    private var personalDashboardContent: some View {
        if let profile = store.profile {
            VStack(spacing: 0) {
                dashboardValueRow(
                    title: store.language.text("生日", "생일", "Birthday"),
                    value: profile.birthDate.formatted(.dateTime.year().month().day().locale(store.language.locale)),
                    symbol: "calendar"
                )
                Divider()
                dashboardValueRow(
                    title: store.language.text("出生時間", "출생 시간", "Birth time"),
                    value: profile.birthTimeText(in: store.language),
                    symbol: "clock.fill"
                )
                if !profile.birthPlace.isEmpty {
                    Divider()
                    dashboardValueRow(
                        title: store.language.text("出生城市", "출생 도시", "Birth city"),
                        value: profile.birthPlace,
                        symbol: "location.fill"
                    )
                }
                Divider()
                dashboardValueRow(
                    title: store.language.text("關注主題", "관심 주제", "Focus areas"),
                    value: profile.focuses.isEmpty
                        ? store.language.text("未設定", "설정 안 함", "Not set")
                        : profile.focuses.map { $0.title(in: store.language) }.joined(separator: focusSeparator),
                    symbol: "scope"
                )
                Divider()
                HStack(spacing: 12) {
                    Button(store.language.text("編輯資料", "정보 편집", "Edit details"), systemImage: "pencil") {
                        profileEditorPresented = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color("AccentColor"))

                    Button(store.language.text("刪除", "삭제", "Delete"), systemImage: "trash", role: .destructive) {
                        deleteConfirmationPresented = true
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 16)
            }
        } else {
            Button {
                profileEditorPresented = true
            } label: {
                Label(store.language.text("建立我的出生資料", "내 출생 정보 만들기", "Create my birth profile"), systemImage: "sparkles")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("AccentColor"))
        }
    }

    private var preferencesDashboardContent: some View {
        VStack(spacing: 0) {
            HStack {
                Label(store.language.text("介面語言", "앱 언어", "App language"), systemImage: "character.bubble.fill")
                Spacer()
                Picker(store.language.text("介面語言", "앱 언어", "App language"), selection: Binding(
                    get: { store.language },
                    set: store.setLanguage
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .labelsHidden()
            }
            .padding(.vertical, 13)
            Divider()
            dashboardValueRow(
                title: store.language.text("暱稱", "닉네임", "Display name"),
                value: store.user?.displayName ?? "",
                symbol: "bubble.left.fill"
            )
            Divider()
            dashboardValueRow(
                title: store.language.text("登入方式", "로그인 방법", "Sign-in method"),
                value: store.authProvider?.title(in: store.language) ?? "",
                symbol: "person.badge.key.fill"
            )
            Divider()
            Button(store.language.text("登出", "로그아웃", "Sign out"), systemImage: "rectangle.portrait.and.arrow.right", role: .destructive, action: store.logout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 16)
        }
    }

    private var feedbackDashboardContent: some View {
        NavigationLink {
            StarFeedbackView()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "paperplane.fill")
                    .font(.title2)
                    .foregroundStyle(Color("AccentColor"))
                    .frame(width: 48, height: 48)
                    .background(Color.celestialPink.opacity(0.18), in: .circle)
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.language.text("想加什麼，都可以直接告訴我們", "원하는 기능을 편하게 알려 주세요", "Tell us what you'd love to see next"))
                        .font(.headline)
                    Text(store.language.text("哪裡不順手、希望怎麼改，小星都會好好看。", "불편한 점과 바라는 변화를 작은 별이 잘 읽을게요.", "Little Star reads every idea, rough edge, and wish."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private var privacyDashboardContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text(store.language.text(
                    "正式帳號的識別資料、運勢、抽牌、出生資料與進度會保存在星伴帳號服務，用來登入、同步與個人化內容。本機預覽不會上傳；主動分享時，所選內容才會交給 iOS 分享服務。",
                    "정식 계정의 식별 정보, 운세, 카드 기록, 출생 정보와 진행 정보는 로그인, 동기화와 개인화된 콘텐츠를 위해 별동무 계정 서비스에 보관됩니다. 기기 미리보기는 업로드하지 않으며, 직접 공유할 때만 선택한 내용이 iOS 공유 서비스로 전달됩니다.",
                    "Verified-account identifiers, fortunes, readings, birth details, and progress are stored in the Star Companion account service for sign-in, syncing, and personalized content. Local previews don't upload them. Content reaches iOS sharing services only when you choose to share it."
                ))
            } icon: {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(Color("AccentColor"))
            }
            .font(.subheadline)

            Button(
                store.language.text("刪除所有本機個人資料", "기기의 모든 개인 정보 삭제", "Delete all local personal data"),
                systemImage: "trash",
                role: .destructive
            ) {
                deleteAllDataConfirmationPresented = true
            }
            .buttonStyle(.bordered)

            Button(store.language.text("刪除帳號", "계정 삭제", "Delete account"), systemImage: "person.crop.circle.badge.minus", role: .destructive) {
                deleteAccountPresented = true
            }
            .buttonStyle(.bordered)
            .disabled(!store.canUseAccountActions)

            Text(store.language.text(
                "預覽帳號會清楚標示驗證層級；伺服器未配置時，不會假裝已完成正式驗證。",
                "미리보기 계정은 인증 수준을 명확히 표시하며, 서버가 설정되지 않은 상태를 정식 인증으로 가장하지 않아요.",
                "Preview accounts clearly show their verification level; an unconfigured server flow is never presented as production-verified."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func profilePanel<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(Color("AccentColor"))
            Divider()
            content()
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 26))
        .overlay {
            RoundedRectangle(cornerRadius: 26)
                .stroke(.white.opacity(0.72), lineWidth: 1)
        }
    }

    private func dashboardValueRow(
        title: String,
        value: String,
        symbol: String,
        showsChevron: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Color("AccentColor"))
                .frame(width: 22)
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.subheadline)
        .contentShape(.rect)
        .padding(.vertical, 13)
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding {
            Calendar.current.date(
                from: DateComponents(
                    hour: store.reminderTimeMinutes / 60,
                    minute: store.reminderTimeMinutes % 60
                )
            ) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            store.setReminderTime(minutes: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        }
    }

    private var focusSeparator: String {
        store.language == .traditionalChinese ? "、" : ", "
    }
}
