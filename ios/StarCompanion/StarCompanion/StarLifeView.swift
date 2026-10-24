import SwiftUI

struct StarLifeView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var availableWidth: CGFloat = 0

    var body: some View {
        ScrollView {
            Group {
                if usesWideLayout {
                    HStack(alignment: .top, spacing: 26) {
                        VStack(spacing: 16) {
                            hero
                            dailySnapshot
                        }
                        .frame(width: 300)

                        featureSections
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(spacing: 20) {
                        hero
                        featureSections
                    }
                }
            }
            .frame(maxWidth: 1180)
            .padding(.horizontal, usesWideLayout ? 28 : 16)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
        }
        .background { CelestialBackdrop().ignoresSafeArea() }
        .navigationTitle(horizontalSizeClass == .regular ? "" : store.language.text("小星日常", "작은 별의 하루", "Little Star Life"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { width in
            availableWidth = width
        }
    }

    private var usesWideLayout: Bool {
        horizontalSizeClass == .regular
            && availableWidth >= 980
            && !dynamicTypeSize.isAccessibilitySize
    }

    private var usesTwoColumnGrid: Bool {
        horizontalSizeClass == .regular
            && availableWidth >= 700
            && !dynamicTypeSize.isAccessibilitySize
    }

    @ViewBuilder
    private var hero: some View {
        if usesWideLayout {
            VStack(spacing: 14) {
                starPortrait(size: 156)
                heroCopy(alignment: .center)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(22)
            .background(.white.opacity(0.09), in: .rect(cornerRadius: 28))
            .overlay { RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.12)) }
        } else if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 14) {
                starPortrait(size: 104)
                heroCopy(alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(.white.opacity(0.09), in: .rect(cornerRadius: 26))
            .overlay { RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.12)) }
        } else {
            HStack(spacing: 18) {
                starPortrait(size: 104)
                heroCopy(alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(.white.opacity(0.09), in: .rect(cornerRadius: 26))
            .overlay { RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.12)) }
        }
    }

    private func starPortrait(size: CGFloat) -> some View {
        StyledStarView(
            wardrobe: store.wardrobe,
            mood: store.starVisualMood,
            size: size
        )
        .accessibilityHidden(true)
    }

    private func heroCopy(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 7) {
            Text(store.language.text("把小日子，慢慢過成一顆星", "작은 하루를 천천히 별 하나로 만들어요", "Turn small days into a star, slowly"))
                .font(usesWideLayout ? .title2.bold() : .title3.bold())
            Text(store.starVisualMood.accessibilityText(in: store.language))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
            Label(
                store.language.text("\(store.starHome.stardust ?? 0) 星塵", "별가루 \(store.starHome.stardust ?? 0)개", "\(store.starHome.stardust ?? 0) Stardust"),
                systemImage: "sparkles"
            )
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(Color.celestialGold)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }

    private var dailySnapshot: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(store.language.text("今天的小宇宙", "오늘의 작은 우주", "Today's little universe"))
                .font(.headline)
            snapshotRow(
                symbol: store.starVisualMood.decorationSymbol,
                title: store.language.text("小星心情", "작은 별 기분", "Star mood"),
                value: store.starVisualMood.accessibilityText(in: store.language)
            )
            snapshotRow(
                symbol: "checkmark.circle.fill",
                title: store.language.text("本週約定", "이번 주 약속", "Weekly promises"),
                value: "\(store.currentWeeklyStory.completedTasks.count)/3"
            )
            snapshotRow(
                symbol: "rectangle.portrait.on.rectangle.portrait",
                title: store.language.text("收藏回信", "모은 답장", "Saved readings"),
                value: "\(store.readingHistory.count)"
            )
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(.white.opacity(0.07), in: .rect(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.10)) }
    }

    private func snapshotRow(symbol: String, title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Color.celestialGold)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold))
                Text(value).font(.caption2).foregroundStyle(.white.opacity(0.64))
            }
            Spacer(minLength: 4)
        }
        .accessibilityElement(children: .combine)
    }

    private var featureSections: some View {
        VStack(spacing: usesWideLayout ? 24 : 20) {
            featureSection(
                title: store.language.text("今晚與心情", "오늘 밤과 마음", "Tonight & feelings"),
                subtitle: store.language.text("先照顧今天的自己，再照顧小星。", "오늘의 나부터 돌보고 작은 별을 만나요.", "Care for yourself first, then spend a moment with Little Star.")
            ) {
                journeyLink(
                    title: store.language.text("睡前許願", "잠들기 전 소원", "Bedtime Wish"),
                    subtitle: bedtimeSubtitle,
                    status: bedtimeStatus,
                    symbol: "moon.stars.fill",
                    tint: .celestialLavender
                ) { BedtimeWishView() }

                journeyLink(
                    title: store.language.text("星星心情", "작은 별 기분", "Star Mood"),
                    subtitle: store.language.text("餵食、陪伴和小約定，會改變表情、光暈與房間光線。", "먹이, 교감과 작은 약속에 따라 표정, 후광과 방의 빛이 달라져요.", "Feeding, care, and small promises shape its expression, aura, and room light."),
                    status: moodStatus,
                    symbol: store.starVisualMood.decorationSymbol,
                    tint: store.starVisualMood.accentColor
                ) { StarMoodView() }

                journeyLink(
                    title: store.language.text("低潮模式", "쉬어 가는 모드", "Gentle Mode"),
                    subtitle: store.language.text("累的日子不設任務壓力，只留一句陪伴和一次輕互動。", "지친 날에는 할 일 없이 다정한 한마디와 조용한 교감 한 번만 남겨요.", "On tired days, remove task pressure and keep one kind sentence and gentle interaction."),
                    status: gentleModeStatus,
                    symbol: store.isGentleModeToday ? "moon.haze.fill" : "cloud.sun.fill",
                    tint: store.isGentleModeToday ? .celestialLavender : .celestialGold
                ) { GentleModeView() }
            }

            featureSection(
                title: store.language.text("故事與記錄", "이야기와 기록", "Stories & keepsakes"),
                subtitle: store.language.text("這週的成長，和每天抽到的牌，都會留在這裡。", "이번 주의 성장과 매일 뽑은 카드를 이곳에 간직해요.", "Keep this week's growth and every card you draw here.")
            ) {
                journeyLink(
                    title: store.language.text("每週星座小劇情", "주간 별자리 이야기", "Weekly Zodiac Story"),
                    subtitle: store.language.text("完成 3 個小約定，解鎖小星的新章節。", "작은 약속 3개를 완료해 새 이야기를 열어요.", "Complete three gentle promises to unlock a new chapter."),
                    status: weeklyStoryStatus,
                    symbol: "book.pages.fill",
                    tint: .celestialGold
                ) { WeeklyZodiacStoryView() }

                journeyLink(
                    title: store.language.text("卡牌收藏冊", "카드 컬렉션", "Card Album"),
                    subtitle: store.language.text("收藏當天的問題、牌義、回信與小星造型，慢慢變成運勢日記。", "그날의 질문, 카드 뜻, 답장과 별 모습을 모아 나만의 운세 일기를 만들어요.", "Save each question, card meaning, reply, and star look as your personal fortune journal."),
                    status: cardAlbumStatus,
                    symbol: "rectangle.portrait.on.rectangle.portrait",
                    tint: .celestialPink
                ) { StarCardAlbumView() }
            }

            featureSection(
                title: store.language.text("房間與朋友", "방과 친구", "Home & friends"),
                subtitle: store.language.text("佈置自己的小宇宙，也讓朋友安靜來坐坐。", "나만의 작은 우주를 꾸미고 친구를 조용히 초대해요.", "Shape your little universe and let friends visit at an easy pace.")
            ) {
                journeyLink(
                    title: store.language.text("家園拜訪", "홈 방문", "Home Visits"),
                    subtitle: store.language.text("留下星塵，看看朋友的房間，不排名也不競爭。", "별가루를 남기고 친구의 방을 둘러봐요. 순위나 경쟁은 없어요.", "Leave Stardust and visit friends without rankings or competition."),
                    status: homeVisitStatus,
                    symbol: "person.2.fill",
                    tint: .mint
                ) { HomeVisitsView() }

                journeyLink(
                    title: store.language.text("功能家具", "기능 가구", "Useful Furniture"),
                    subtitle: store.language.text("望遠鏡、月亮床和花園，不只好看，也會真的幫上忙。", "망원경, 달빛 침대와 정원은 예쁠 뿐 아니라 실제 효과도 있어요.", "The telescope, moon bed, and garden look lovely and offer real benefits."),
                    status: furnitureStatus,
                    symbol: "sofa.fill",
                    tint: .celestialPink
                ) { StarHomeStudioView(focus: .furniture) }

                journeyLink(
                    title: store.language.text("節日限定", "시즌 한정", "Seasonal Events"),
                    subtitle: store.language.text("中秋月兔、萬聖幽靈和聖誕雪房，到了季節就能帶回家。", "달토끼, 할로윈 유령과 크리스마스 눈꽃 방을 계절에 맞춰 만나 보세요.", "Meet Moon Rabbit, Halloween Ghost, and Christmas Snow rooms when their season arrives."),
                    status: seasonalStatus,
                    symbol: "party.popper.fill",
                    tint: .celestialGold
                ) { StarHomeStudioView(focus: .seasonal) }
            }
        }
    }

    private func featureSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title3.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
            }
            .foregroundStyle(.white)

            LazyVGrid(columns: featureColumns, alignment: .leading, spacing: 12) {
                content()
            }
        }
    }

    private var bedtimeSubtitle: String {
        if let wish = store.bedtimeWishes.first, wish.isReady(), wish.revealedAt == nil {
            return store.language.text("有一封星星回信等你拆開。", "별의 답장이 도착했어요.", "A reply from the stars is waiting for you.")
        }
        return store.language.text("寫一句話，明天回來收一封小提示。", "한마디를 남기고 내일 작은 힌트를 받아 보세요.", "Write one line and return tomorrow for a small reply." )
    }

    private func journeyLink<Destination: View>(
        title: String,
        subtitle: String,
        status: String,
        symbol: String,
        tint: Color,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: symbol)
                        .font(.title2)
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                    Spacer(minLength: 4)
                    Text(status)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.08), in: .capsule)
                }
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.66))
                Spacer(minLength: 2)
                Label(store.language.text("打開", "열기", "Open"), systemImage: "arrow.up.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.54))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: usesTwoColumnGrid ? 178 : 148, alignment: .leading)
            .background(.white.opacity(0.08), in: .rect(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.10)) }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(status). \(subtitle)")
        .accessibilityHint(store.language.text("點兩下打開", "두 번 탭하여 열기", "Double-tap to open"))
    }

    private var featureColumns: [GridItem] {
        if usesTwoColumnGrid {
            return [
                GridItem(.flexible(minimum: 250), spacing: 12, alignment: .top),
                GridItem(.flexible(minimum: 250), spacing: 12, alignment: .top),
            ]
        }
        return [GridItem(.flexible(), spacing: 12, alignment: .top)]
    }

    private var bedtimeStatus: String {
        if bedtimeWantsReply {
            return store.language.text("有回信", "답장 도착", "Reply ready")
        }
        return store.language.text("今晚", "오늘 밤", "Tonight")
    }

    private var bedtimeWantsReply: Bool {
        store.bedtimeWishes.contains { $0.isReady() && $0.revealedAt == nil }
    }

    private var gentleModeStatus: String {
        store.isGentleModeToday
            ? store.language.text("已開啟", "켜짐", "On today")
            : store.language.text("依需要開啟", "필요할 때", "When needed")
    }

    private var moodStatus: String {
        switch store.starVisualMood {
        case .happy: store.language.text("開心", "기분 좋아요", "Happy")
        case .calm: store.language.text("安心", "편안해요", "Calm")
        case .tired: store.language.text("有點睏", "조금 졸려요", "Sleepy")
        case .low: store.language.text("柔柔的", "부드러워요", "Soft today")
        case .glowing: store.language.text("發亮中", "빛나는 중", "Glowing")
        case .delighted: store.language.text("好開心", "아주 신나요", "Delighted")
        }
    }

    private var weeklyStoryStatus: String {
        let progress = store.currentWeeklyStory
        if progress.revealedAt != nil {
            return store.language.text("已解鎖", "열림", "Unlocked")
        }
        return "\(progress.completedTasks.count)/3"
    }

    private var cardAlbumStatus: String {
        store.language.text("\(store.readingHistory.count) 張", "\(store.readingHistory.count)장", "\(store.readingHistory.count) saved")
    }

    private var homeVisitStatus: String {
        let count = store.starHome.visits?.count ?? 0
        return count == 0
            ? store.language.text("等朋友來", "친구 기다리는 중", "Awaiting friends")
            : store.language.text("\(count) 次拜訪", "방문 \(count)회", "\(count) visits")
    }

    private var furnitureStatus: String {
        let count = store.starHome.ownedFurniture?.count ?? 0
        return store.language.text("已收藏 \(count)/3", "보유 \(count)/3", "Owned \(count)/3")
    }

    private var seasonalStatus: String {
        let theme = store.starHome.selectedRoomTheme ?? .observatoryGarden
        return theme.title(in: store.language)
    }
}

struct StarMoodView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var feedback = 0
    @State private var availableWidth: CGFloat = 0

    var body: some View {
        ScrollView {
            Group {
                if usesWideLayout {
                    HStack(alignment: .top, spacing: 24) {
                        StarLifeHabitatPreview(height: 470)
                        moodPanel.frame(width: 390)
                    }
                } else {
                    VStack(spacing: 18) {
                        StarLifeHabitatPreview(height: 320)
                        moodPanel
                    }
                }
            }
            .frame(maxWidth: 1060)
            .padding(.horizontal, usesWideLayout ? 28 : 16)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
        }
        .background { CelestialBackdrop().ignoresSafeArea() }
        .navigationTitle(store.language.text("星星心情", "작은 별 기분", "Star Mood"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sensoryFeedback(.success, trigger: feedback)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { width in
            availableWidth = width
        }
    }

    private var usesWideLayout: Bool {
        horizontalSizeClass == .regular
            && availableWidth >= 800
            && !dynamicTypeSize.isAccessibilitySize
    }

    private var moodPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(store.starVisualMood.accessibilityText(in: store.language), systemImage: store.starVisualMood.decorationSymbol)
                .font(.title3.bold())
                .foregroundStyle(store.starVisualMood.accentColor)

            Text(store.language.text(
                "小星沒有心情分數。餵它、摸摸它，或一起完成小約定，表情、光暈和房間光線就會自然改變。",
                "작은 별의 기분에는 점수가 없어요. 먹이를 주고 쓰다듬거나 작은 약속을 함께 지키면 표정, 후광과 방의 빛이 자연스럽게 달라져요.",
                "Little Star's mood isn't a score. Feed it, spend a moment together, or keep a small promise and its expression, aura, and room light will change naturally."
            ))
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.72))
            .lineSpacing(4)

            VStack(spacing: 14) {
                moodMetric(
                    title: store.language.text("星糧", "별빛 먹이", "Starlight"),
                    value: "\(store.planet.food)/100",
                    progress: Double(store.planet.food) / 100
                )
                moodMetric(
                    title: store.language.text("今晚的陪伴", "오늘 밤의 돌봄", "Tonight's care"),
                    value: "\(store.planet.feedCount)/3",
                    progress: min(1, Double(store.planet.feedCount) / 3)
                )
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { careButton; feedButton }
                VStack(spacing: 10) { careButton; feedButton }
            }

            Text(store.actionMessage)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 26))
        .overlay { RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.10)) }
    }

    private func moodMetric(title: String, value: String, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(value).font(.subheadline.monospacedDigit())
            }
            ProgressView(value: progress)
                .tint(store.starVisualMood.accentColor)
        }
        .accessibilityElement(children: .combine)
    }

    private var careButton: some View {
        Button {
            let wasAvailable = !store.isGentleModeToday || store.canUseGentleInteraction
            store.petStar()
            if wasAvailable { feedback += 1 }
        } label: {
            Label(
                store.isGentleModeToday
                    ? store.language.text("輕輕抱一下", "조용히 안아 주기", "Give a gentle hug")
                    : store.language.text("摸摸小星", "작은 별 쓰다듬기", "Pet Little Star"),
                systemImage: "hand.tap.fill"
            )
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.glassProminent)
        .tint(Color.celestialPlum)
        .disabled(store.isGentleModeToday && !store.canUseGentleInteraction)
    }

    private var feedButton: some View {
        Button {
            guard store.canFeedPet else { return }
            store.feedPet()
            feedback += 1
        } label: {
            Label(store.language.text("餵一點星糧", "별빛 먹이 주기", "Feed starlight"), systemImage: "takeoutbag.and.cup.and.straw.fill")
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.glass)
        .disabled(!store.canFeedPet)
    }
}

struct GentleModeView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var feedback = 0
    @State private var availableWidth: CGFloat = 0

    var body: some View {
        ScrollView {
            Group {
                if usesWideLayout {
                    HStack(alignment: .top, spacing: 24) {
                        StarLifeHabitatPreview(height: 470)
                        gentlePanel.frame(width: 390)
                    }
                } else {
                    VStack(spacing: 18) {
                        StarLifeHabitatPreview(height: 320)
                        gentlePanel
                    }
                }
            }
            .frame(maxWidth: 1060)
            .padding(.horizontal, usesWideLayout ? 28 : 16)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
        }
        .background { CelestialBackdrop().ignoresSafeArea() }
        .navigationTitle(store.language.text("低潮模式", "쉬어 가는 모드", "Gentle Mode"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sensoryFeedback(.success, trigger: feedback)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { width in
            availableWidth = width
        }
    }

    private var usesWideLayout: Bool {
        horizontalSizeClass == .regular
            && availableWidth >= 800
            && !dynamicTypeSize.isAccessibilitySize
    }

    private var gentlePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(store.language.text("今天可以慢一點", "오늘은 천천히 가도 돼요", "Today can move slowly"), systemImage: "moon.haze.fill")
                .font(.title3.bold())
                .foregroundStyle(Color.celestialLavender)

            Text(store.language.text(
                "不用說明為什麼累。開啟後，今天不再催你完成任務，只會留下柔一點的房間、一句陪伴和一次輕輕互動。",
                "왜 지쳤는지 설명하지 않아도 돼요. 켜 두면 오늘은 할 일을 재촉하지 않고 부드러운 방, 다정한 한마디와 조용한 교감 한 번만 남겨요.",
                "You don't have to explain why you're tired. Turn this on to remove task pressure for today and keep only a softer room, one kind sentence, and one gentle interaction."
            ))
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.72))
            .lineSpacing(4)

            Toggle(isOn: Binding(get: { store.isGentleModeToday }, set: setGentleMode)) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.language.text("今天有點累", "오늘은 조금 지쳤어요", "I'm a little tired today"))
                        .font(.headline)
                    Text(store.isGentleModeToday
                         ? store.language.text("低潮模式已開啟", "쉬어 가는 모드가 켜졌어요", "Gentle Mode is on")
                         : store.language.text("只為今天開啟", "오늘 하루만 켜기", "Turn on for today only"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.60))
                }
            }
            .tint(Color.celestialPink)
            .padding(16)
            .background(.white.opacity(0.08), in: .rect(cornerRadius: 18))

            if store.isGentleModeToday {
                Text(store.language.text(
                    "你不用趕上誰。小星把月光調暗了一點，會在這裡陪你慢慢呼吸。",
                    "누구를 따라잡지 않아도 돼요. 작은 별이 달빛을 조금 낮추고 여기서 함께 천천히 숨 쉴게요.",
                    "You don't have to catch up with anyone. Little Star dimmed the moonlight and will breathe slowly beside you."
                ))
                .font(.body.weight(.medium))
                .foregroundStyle(Color.celestialGold)

                Button {
                    guard store.canUseGentleInteraction else { return }
                    store.petStar()
                    feedback += 1
                } label: {
                    Label(
                        store.canUseGentleInteraction
                            ? store.language.text("輕輕抱一下", "조용히 안아 주기", "Give a gentle hug")
                            : store.language.text("今天的擁抱已收好", "오늘의 포옹을 간직했어요", "Today's hug is safely kept"),
                        systemImage: store.canUseGentleInteraction ? "heart.fill" : "checkmark.circle.fill"
                    )
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.celestialPlum)
                .disabled(!store.canUseGentleInteraction)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 26))
        .overlay { RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.10)) }
    }

    private func setGentleMode(_ enabled: Bool) {
        store.setGentleMode(enabled)
        feedback += 1
    }
}

struct StarCardAlbumView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var searchText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                albumIntro
                if store.readingHistory.isEmpty {
                    emptyState
                } else if filteredReadings.isEmpty {
                    noResults
                } else {
                    LazyVGrid(columns: albumColumns, spacing: 14) {
                        ForEach(filteredReadings) { reading in
                            albumCard(reading)
                        }
                    }
                }
            }
            .frame(maxWidth: 1080)
            .padding(.horizontal, horizontalSizeClass == .regular ? 28 : 16)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
        }
        .background { CelestialBackdrop().ignoresSafeArea() }
        .navigationTitle(store.language.text("卡牌收藏冊", "카드 컬렉션", "Card Album"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: store.language.text("搜尋問題、牌或回信", "질문, 카드 또는 답장 검색", "Search questions, cards, or replies")
        )
    }

    private var filteredReadings: [TarotReadingRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.readingHistory }
        return store.readingHistory.filter {
            $0.topicTitle.localizedCaseInsensitiveContains(query)
                || $0.question.localizedCaseInsensitiveContains(query)
                || $0.cardName.localizedCaseInsensitiveContains(query)
                || $0.answer.localizedCaseInsensitiveContains(query)
        }
    }

    private var albumColumns: [GridItem] {
        [GridItem(.adaptive(minimum: horizontalSizeClass == .regular ? 310 : 280), spacing: 14, alignment: .top)]
    }

    private var albumIntro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(store.language.text("每天留下一頁", "매일 한 페이지씩", "Keep one page from each day"), systemImage: "book.closed.fill")
                .font(.title3.bold())
                .foregroundStyle(Color.celestialGold)
            Text(store.language.text(
                "每次抽牌都會留下當天的問題、答案和小星造型。沒有連續天數，也不用補進度。",
                "카드를 뽑을 때마다 그날의 질문, 답과 작은 별 모습이 남아요. 연속 기록이나 밀린 진도는 없어요.",
                "Every draw keeps that day's question, answer, and Little Star look. There are no streaks and nothing to catch up on."
            ))
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.68))
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 24))
    }

    private func albumCard(_ reading: TarotReadingRecord) -> some View {
        NavigationLink {
            ReadingDetailView(reading: reading)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                if let snapshot = reading.appearanceSnapshot {
                    SnapshotStarView(snapshot: snapshot, size: 68)
                } else {
                    Image(systemName: reading.cardSymbol ?? "sparkles")
                        .font(.title2)
                        .foregroundStyle(Color.celestialGold)
                        .frame(width: 68, height: 68)
                        .background(.white.opacity(0.08), in: .circle)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(reading.cardTitle(in: store.language))
                        .font(.caption.bold())
                        .foregroundStyle(Color.celestialGold)
                    Text(reading.answer)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(reading.question)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.64))
                    Text(reading.createdAt.formatted(.dateTime.year().month().day().locale(store.language.locale)))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.48))
                }
                Spacer(minLength: 0)
            }
            .padding(17)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            .background(.white.opacity(0.08), in: .rect(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.10)) }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(store.language.text("點兩下閱讀完整牌義", "두 번 탭하여 전체 카드 뜻 읽기", "Double-tap to read the full card meaning"))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(store.language.text("收藏冊還是空的", "아직 모은 카드가 없어요", "Your album is still empty"), systemImage: "rectangle.portrait.on.rectangle.portrait")
        } description: {
            Text(store.language.text("完成一次抽牌後，第一頁就會自己留在這裡。", "카드를 한 번 뽑으면 첫 페이지가 이곳에 남아요.", "Finish one card draw and the first page will appear here."))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var noResults: some View {
        ContentUnavailableView.search(text: searchText)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 320)
    }
}

private struct StarLifeHabitatPreview: View {
    @EnvironmentObject private var store: AppStore
    let height: CGFloat

    var body: some View {
        ZStack {
            Image("StarHabitat")
                .resizable()
                .scaledToFill()
            SeasonalRoomLayer(theme: store.starHome.selectedRoomTheme ?? .observatoryGarden)
            StarHabitatMoodLayer(mood: store.starVisualMood)
            StyledStarView(wardrobe: store.wardrobe, mood: store.starVisualMood, size: min(210, height * 0.48))
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .clipShape(.rect(cornerRadius: 28))
        .overlay { RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.12)) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            store.language.text("小星的房間。", "작은 별의 방. ", "Little Star's room. ")
                + store.starVisualMood.accessibilityText(in: store.language)
        )
    }
}

struct BedtimeWishView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft = ""
    @State private var feedback = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Label(store.language.text("今晚想交給星星什麼？", "오늘 밤 별에게 무엇을 남길까요?", "What would you like to leave with the stars tonight?"), systemImage: "moon.stars.fill")
                        .font(.title3.bold())
                    TextField(store.language.text("寫下一句話…", "한마디를 적어 보세요…", "Write one line…"), text: $draft, axis: .vertical)
                        .lineLimit(3...6)
                        .textFieldStyle(.plain)
                        .padding(14)
                        .background(.white.opacity(0.10), in: .rect(cornerRadius: 16))
                    Button {
                        if store.submitBedtimeWish(draft) {
                            draft = ""
                            feedback += 1
                        }
                    } label: {
                        Label(store.language.text("放進今晚的星空", "오늘 밤 하늘에 보내기", "Send it into tonight's sky"), systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.celestialPlum)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(20)
                .background(.white.opacity(0.08), in: .rect(cornerRadius: 24))

                ForEach(store.bedtimeWishes) { wish in
                    wishCard(wish)
                }
            }
            .frame(maxWidth: 720)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white)
        .background { CelestialBackdrop().ignoresSafeArea() }
        .navigationTitle(store.language.text("睡前許願", "잠들기 전 소원", "Bedtime Wish"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sensoryFeedback(.success, trigger: feedback)
    }

    private func wishCard(_ wish: BedtimeWish) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("「\(wish.text)」")
                .font(.body.weight(.medium))
            if wish.revealedAt != nil {
                Divider().overlay(.white.opacity(0.14))
                Label(wish.replyTemplateID.text(in: store.language), systemImage: "envelope.open.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.celestialGold)
            } else if wish.isReady() {
                Button {
                    if store.revealWish(id: wish.id) { feedback += 1 }
                } label: {
                    Label(store.language.text("拆開星星回信", "별의 답장 열기", "Open the star's reply"), systemImage: "envelope.badge.fill")
                }
                .buttonStyle(.glassProminent)
                .tint(Color.celestialPlum)
            } else {
                Label(store.language.text("星星正在寫回信，明天再來。", "별이 답장을 쓰고 있어요. 내일 다시 와요.", "The stars are writing back. Return tomorrow."), systemImage: "hourglass")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 20))
    }
}

struct WeeklyZodiacStoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var rewardFeedback = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                StyledStarView(
                    wardrobe: store.wardrobe,
                    mood: store.starVisualMood,
                    size: 164,
                    isCelebrating: progress.revealedAt != nil
                )
                Text(store.profile?.zodiac.title(in: store.language) ?? store.language.text("這週的星座", "이번 주 별자리", "This week's constellation"))
                    .font(.caption.bold())
                    .tracking(1.2)
                    .foregroundStyle(Color.celestialGold)
                Text(storyTitle)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    ForEach(WeeklyJourneyTask.allCases) { task in
                        HStack(spacing: 12) {
                            Image(systemName: task.symbol)
                                .foregroundStyle(progress.completedTasks.contains(task) ? Color.celestialGold : .white.opacity(0.45))
                                .frame(width: 30)
                            Text(task.title(in: store.language))
                            Spacer()
                            Image(systemName: progress.completedTasks.contains(task) ? "checkmark.circle.fill" : "circle")
                        }
                        .padding(13)
                        .background(.white.opacity(0.08), in: .rect(cornerRadius: 15))
                    }
                }

                if progress.revealedAt != nil {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(story.body)
                            .font(.body)
                            .lineSpacing(6)
                            .foregroundStyle(.white.opacity(0.80))

                        Divider()
                            .overlay(.white.opacity(0.12))

                        Label(story.ending, systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.celestialGold)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.09), in: .rect(cornerRadius: 22))
                } else if progress.isUnlocked {
                    Button {
                        if store.revealWeeklyStory() { rewardFeedback += 1 }
                    } label: {
                        Label(store.language.text("解鎖這週的新章節＋40 星幣", "이번 주 이야기 열기 +40 별 코인", "Unlock this week's chapter +40 Star Coins"), systemImage: "book.fill")
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.celestialPlum)
                } else {
                    Text(store.language.text("不用趕，這週遇見這三個小瞬間就好。", "서두르지 않아도 돼요. 이번 주에 이 세 가지 순간을 만나면 돼요.", "No rush. Simply meet these three small moments sometime this week."))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: 660)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background { CelestialBackdrop().ignoresSafeArea() }
        .navigationTitle(store.language.text("每週小劇情", "주간 이야기", "Weekly Story"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sensoryFeedback(.success, trigger: rewardFeedback)
    }

    private var progress: WeeklyStoryProgress { store.currentWeeklyStory }
    private var story: WeeklyZodiacStoryContent {
        .make(
            zodiac: store.profile?.zodiac,
            weekID: progress.weekID,
            language: store.language
        )
    }
    private var storyTitle: String {
        progress.revealedAt == nil ? story.lockedTitle : story.title
    }
}

enum StarHomeStudioFocus: Equatable {
    case all
    case furniture
    case seasonal
}

struct StarHomeStudioView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var feedback = 0
    @State private var availableWidth: CGFloat = 0
    let focus: StarHomeStudioFocus

    init(focus: StarHomeStudioFocus = .all) {
        self.focus = focus
    }

    var body: some View {
        ScrollView {
            Group {
                if usesWideLayout {
                    HStack(alignment: .top, spacing: 24) {
                        previewPanel
                            .frame(maxWidth: .infinity)
                        studioControls
                            .frame(width: 430)
                    }
                } else {
                    VStack(spacing: 18) {
                        previewPanel
                        studioControls
                    }
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: 1080)
            .padding(.horizontal, usesWideLayout ? 28 : 16)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
        }
        .background { CelestialBackdrop().ignoresSafeArea() }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sensoryFeedback(.success, trigger: feedback)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { width in
            availableWidth = width
        }
    }

    private var usesWideLayout: Bool {
        horizontalSizeClass == .regular
            && availableWidth >= 960
            && !dynamicTypeSize.isAccessibilitySize
    }

    private var navigationTitle: String {
        switch focus {
        case .all: store.language.text("房間與家具", "방과 가구", "Room & Furniture")
        case .furniture: store.language.text("功能家具", "기능 가구", "Useful Furniture")
        case .seasonal: store.language.text("節日限定", "시즌 한정", "Seasonal Events")
        }
    }

    private var previewPanel: some View {
        VStack(spacing: 14) {
            roomPreview
            HStack(spacing: 10) {
                Label(
                    store.language.text("\(store.starHome.stardust ?? 0) 星塵", "별가루 \(store.starHome.stardust ?? 0)개", "\(store.starHome.stardust ?? 0) Stardust"),
                    systemImage: "sparkles"
                )
                .font(.headline.monospacedDigit())
                .foregroundStyle(Color.celestialGold)
                Spacer(minLength: 0)
                Text((store.starHome.selectedRoomTheme ?? .observatoryGarden).title(in: store.language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.66))
                    .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var studioControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            if focus != .seasonal {
                furnitureSection
            }
            if focus == .all {
                Divider().overlay(.white.opacity(0.12)).padding(.vertical, 4)
            }
            if focus != .furniture {
                seasonalSection
            }
        }
    }

    private var furnitureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: store.language.text("有作用的家具", "효과가 있는 가구", "Furniture with a purpose"),
                subtitle: store.language.text("買下後可以自由擺放或收起，效果會照常寫在每件家具下面。", "구매 후 자유롭게 배치하거나 보관할 수 있고, 각 가구의 효과는 아래에서 확인할 수 있어요.", "Once owned, furniture can be placed or stored anytime. Each effect is shown below.")
            )

            ForEach(StarFurniture.allCases) { furniture in
                furnitureRow(furniture)
            }

            if store.canHarvestGarden {
                Button {
                    if store.harvestGarden() { feedback += 1 }
                } label: {
                    Label(store.language.text("收集今天的 12 點星塵", "오늘의 별가루 12개 받기", "Collect today's 12 Stardust"), systemImage: "sparkles")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.celestialPlum)
            }
        }
    }

    private var seasonalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: store.language.text("節日房間", "시즌 한정 방", "Seasonal rooms"),
                subtitle: store.language.text("活動季節到了就能免費收藏；錯過也不會失去已經帶回家的房間。", "이벤트 시즌에는 무료로 받을 수 있고, 시즌이 지나도 이미 모은 방은 그대로 남아요.", "Collect a room free during its season. Any room already collected stays yours afterward.")
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                ForEach(StarRoomTheme.allCases) { theme in
                    roomThemeCard(theme)
                }
            }
        }
    }

    private var roomPreview: some View {
        ZStack {
            Image("StarHabitat")
                .resizable()
                .scaledToFill()
                .overlay(themeOverlay)
            SeasonalRoomLayer(theme: store.starHome.selectedRoomTheme ?? .observatoryGarden)
            StarHabitatMoodLayer(mood: store.starVisualMood)
            StyledStarView(wardrobe: store.wardrobe, mood: store.starVisualMood, size: 150)
            furnitureSymbols
        }
        .frame(height: usesWideLayout ? 470 : 310)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(.rect(cornerRadius: 26))
        .overlay(alignment: .topLeading) {
            Label((store.starHome.selectedRoomTheme ?? .observatoryGarden).title(in: store.language), systemImage: (store.starHome.selectedRoomTheme ?? .observatoryGarden).symbol)
                .font(.caption.bold())
                .padding(10)
                .background(.black.opacity(0.34), in: .capsule)
                .padding(14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            (store.starHome.selectedRoomTheme ?? .observatoryGarden).title(in: store.language)
                + store.language.text("，小星的房間。", ", 작은 별의 방. ", ", Little Star's room. ")
                + store.starVisualMood.accessibilityText(in: store.language)
        )
    }

    @ViewBuilder private var themeOverlay: some View {
        switch store.starHome.selectedRoomTheme ?? .observatoryGarden {
        case .observatoryGarden: Color.clear
        case .moonRabbitFestival: Color.orange.opacity(0.16).blendMode(.screen)
        case .halloweenGhostNight: Color.purple.opacity(0.28).blendMode(.multiply)
        case .christmasSnowRoom: Color.cyan.opacity(0.18).blendMode(.screen)
        }
    }

    private var furnitureSymbols: some View {
        ZStack {
            ForEach(Array(store.placedFurniture.enumerated()), id: \.element) { index, furniture in
                Image(systemName: furniture.symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.celestialGold)
                    .padding(12)
                    .background(.black.opacity(0.38), in: .circle)
                    .offset(x: CGFloat(index - 1) * 105, y: 92)
            }
        }
    }

    private func furnitureRow(_ furniture: StarFurniture) -> some View {
        let owned = store.starHome.ownedFurniture?.contains(furniture) == true
        let placed = store.placedFurniture.contains(furniture)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                furnitureIdentity(furniture)
                Spacer(minLength: 8)
                furnitureAction(furniture, owned: owned, placed: placed)
            }

            VStack(alignment: .leading, spacing: 12) {
                furnitureIdentity(furniture)
                furnitureAction(furniture, owned: owned, placed: placed)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 20))
    }

    private func furnitureIdentity(_ furniture: StarFurniture) -> some View {
        HStack(spacing: 14) {
            Image(systemName: furniture.symbol)
                .font(.title2)
                .foregroundStyle(Color.celestialGold)
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.08), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(furniture.title(in: store.language)).font(.headline)
                Text(furniture.effect(in: store.language))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.64))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func furnitureAction(_ furniture: StarFurniture, owned: Bool, placed: Bool) -> some View {
        Button {
            if owned {
                store.setFurniture(furniture, placed: !placed)
                feedback += 1
            } else if store.purchaseFurniture(furniture) {
                store.setFurniture(furniture, placed: true)
                feedback += 1
            }
        } label: {
            Text(owned
                 ? (placed ? store.language.text("收起", "치우기", "Store") : store.language.text("擺上", "배치", "Place"))
                 : "✦ \(furniture.price)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .frame(minWidth: 58, minHeight: 44)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(
            owned
                ? (placed
                   ? store.language.text("收起\(furniture.title(in: store.language))", "\(furniture.title(in: store.language)) 치우기", "Store \(furniture.title(in: store.language))")
                   : store.language.text("擺上\(furniture.title(in: store.language))", "\(furniture.title(in: store.language)) 배치", "Place \(furniture.title(in: store.language))"))
                : store.language.text("用 \(furniture.price) 星塵購買\(furniture.title(in: store.language))", "별가루 \(furniture.price)개로 \(furniture.title(in: store.language)) 구매", "Buy \(furniture.title(in: store.language)) for \(furniture.price) Stardust")
        )
    }

    private func roomThemeStatus(_ theme: StarRoomTheme, owned: Bool, selected: Bool) -> String {
        if selected { return store.language.text("使用中", "사용 중", "In use") }
        if owned { return store.language.text("已收藏", "소장 중", "Collected") }
        if theme.isInSeason() { return store.language.text("當季免費收藏", "시즌 무료 받기", "Free this season") }
        return store.language.text("尚未到來", "아직 기간이 아니에요", "Not in season")
    }

    private func roomThemeHint(_ theme: StarRoomTheme, owned: Bool, selected: Bool) -> String {
        if selected { return store.language.text("目前正在使用", "현재 사용 중", "Currently in use") }
        if owned { return store.language.text("點兩下使用這個房間", "두 번 탭하여 이 방 사용", "Double-tap to use this room") }
        if theme.isInSeason() { return store.language.text("點兩下免費收藏並使用", "두 번 탭하여 무료로 받고 사용", "Double-tap to collect and use for free") }
        return store.language.text("活動季節到了才可收藏", "이벤트 시즌에 받을 수 있어요", "Available to collect during its season")
    }

    private func roomThemeCard(_ theme: StarRoomTheme) -> some View {
        let owned = store.starHome.ownedRoomThemes?.contains(theme) == true
        let selected = store.starHome.selectedRoomTheme == theme
        let status = roomThemeStatus(theme, owned: owned, selected: selected)
        return Button {
            if owned {
                store.selectRoomTheme(theme)
                feedback += 1
            } else if store.claimSeasonalRoom(theme) {
                feedback += 1
            }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: theme.symbol).font(.title2).foregroundStyle(Color.celestialGold)
                Text(theme.title(in: store.language)).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.celestialPink : .white.opacity(0.62))
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 140)
            .background(selected ? Color.celestialPlum.opacity(0.76) : .white.opacity(0.07), in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(!owned && !theme.isInSeason())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(theme.title(in: store.language)). \(status)")
        .accessibilityHint(roomThemeHint(theme, owned: owned, selected: selected))
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.bold())
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct HomeVisitsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var feedback = 0
    @State private var sharesAlias = false
    @State private var cardURL: URL?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                roomPreview

                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        store.language.text("是一場拜訪，不是一場比賽", "방문일 뿐, 경쟁이 아니에요", "A visit, not a competition"),
                        systemImage: "hand.raised.fill"
                    )
                    .font(.title3.bold())
                    Text(store.language.text(
                        "沒有排名，也不能拿走別人的東西。朋友只會看見你主動公開的房間，再留下一小撮星塵。",
                        "순위도 없고 다른 사람의 물건을 가져갈 수도 없어요. 친구는 당신이 공개한 방만 보고 작은 별가루를 남겨요.",
                        "There are no rankings and nothing can be taken. Friends only see rooms you choose to share and may leave a little Stardust."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
                    .lineSpacing(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(.white.opacity(0.08), in: .rect(cornerRadius: 22))

                VStack(alignment: .leading, spacing: 12) {
                    Text(store.language.text("把房間做成訪客卡", "방을 방문 카드로 만들기", "Turn this room into a visit card"))
                        .font(.headline)
                    Text(store.language.text(
                        "卡片只包含目前的小星造型、房間主題與已擺家具，有效七天。",
                        "카드에는 현재 별 모습, 방 테마와 배치한 가구만 담기며 7일 동안 유효해요.",
                        "The card contains only the current star look, room theme, and placed furniture. It stays valid for seven days."
                    ))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.64))

                    Toggle(isOn: $sharesAlias) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.language.text("在卡片上顯示我的暱稱", "카드에 내 별명 표시", "Show my nickname on the card"))
                                .font(.subheadline.weight(.semibold))
                            Text(store.language.text("預設不顯示，可以匿名邀請朋友。", "기본값은 꺼짐이며 익명으로 초대할 수 있어요.", "Off by default, so you can invite friends anonymously."))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.56))
                        }
                    }
                    .tint(Color.celestialPink)

                    if let shareURL = cardURL {
                        ShareLink(item: shareURL) {
                            Label(store.language.text("分享七天訪客卡", "7일 방문 카드 공유", "Share 7-day visit card"), systemImage: "square.and.arrow.up.fill")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Color.celestialPlum)

                        Button {
                            cardURL = nil
                        } label: {
                            Text(store.language.text("重新建立卡片", "카드 다시 만들기", "Create a new card"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                    } else {
                        Button {
                            cardURL = store.makeHomeVisitCardURL(sharesAlias: sharesAlias)
                            if cardURL != nil { feedback += 1 }
                        } label: {
                            Label(store.language.text("預覽並準備訪客卡", "방문 카드 준비하기", "Preview and prepare visit card"), systemImage: "person.crop.circle.badge.plus")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Color.celestialPlum)
                    }

                    Label {
                        Text(store.language.text(
                            "訪客卡本身只會在你按下分享後交給所選服務。正式帳號會同步卡片有效期與防止重複領取的紀錄，不會自動分享卡片內容。",
                            "방문 카드 자체는 공유를 누른 후에만 선택한 서비스로 전달됩니다. 정식 계정은 카드 유효 기간과 중복 수령 방지 기록을 동기화하지만 카드 내용을 자동으로 공유하지 않습니다.",
                            "The visit card itself goes to the service you choose only after you tap Share. Verified accounts sync the card expiry and anti-duplicate redemption records, but the card content isn't shared automatically."
                        ))
                    } icon: {
                        Image(systemName: "hand.raised.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(.white.opacity(0.08), in: .rect(cornerRadius: 22))

                VStack(alignment: .leading, spacing: 12) {
                    Text(store.language.text("最近留下的星塵", "최근에 남겨진 별가루", "Recent Stardust"))
                        .font(.headline)
                if (store.starHome.visits ?? []).isEmpty {
                    Text(store.language.text("還沒有人來過，房間正安靜地等朋友。", "아직 방문한 친구가 없어요. 방이 조용히 기다리고 있어요.", "No one has visited yet. The room is quietly waiting for a friend."))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.64))
                } else {
                    ForEach(store.starHome.visits ?? []) { visit in
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color.celestialGold)
                                .frame(width: 38, height: 38)
                                .background(.white.opacity(0.08), in: .circle)
                            Text(visit.visitorAlias)
                            Spacer()
                            Text("+✦\(visit.stardustAmount)")
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(Color.celestialPink)
                        }
                        .padding(14)
                        .background(.white.opacity(0.06), in: .rect(cornerRadius: 16))
                    }
                }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(.white.opacity(0.08), in: .rect(cornerRadius: 22))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: horizontalSizeClass == .regular ? 860 : 720)
            .padding(.horizontal, horizontalSizeClass == .regular ? 28 : 16)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
        }
        .background { CelestialBackdrop().ignoresSafeArea() }
        .navigationTitle(store.language.text("家園拜訪", "홈 방문", "Home Visits"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sensoryFeedback(.success, trigger: feedback)
        .onChange(of: sharesAlias) { _, _ in cardURL = nil }
    }

    private var roomPreview: some View {
        ZStack {
            Image("StarHabitat")
                .resizable()
                .scaledToFill()
                .overlay(.black.opacity(0.12))
            SeasonalRoomLayer(theme: store.starHome.selectedRoomTheme ?? .observatoryGarden)
            StarHabitatMoodLayer(mood: store.starVisualMood)
            StyledStarView(
                wardrobe: store.wardrobe,
                mood: store.starVisualMood,
                size: horizontalSizeClass == .regular ? 150 : 112
            )
            VStack {
                Spacer()
                Text(store.language.text("歡迎來小星的房間", "작은 별의 방에 어서 와요", "Welcome to Little Star's room"))
                    .font(.headline)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                    .background(.black.opacity(0.36), in: .capsule)
                    .padding(16)
            }
        }
        .frame(height: horizontalSizeClass == .regular ? 310 : 240)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: 26))
        .overlay { RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.12)) }
    }
}
