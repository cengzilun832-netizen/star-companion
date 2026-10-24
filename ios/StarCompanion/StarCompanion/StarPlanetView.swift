import SwiftUI

struct StarPlanetView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var invitePresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if horizontalSizeClass == .regular {
                    VStack(spacing: 18) {
                        memberRail
                            .clipShape(.rect(cornerRadius: 18))

                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 26) {
                                habitatCard

                                carePanel
                                    .frame(width: 380)
                                    .clipShape(.rect(cornerRadius: 28))
                                    .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
                            }
                            .frame(minWidth: 850, maxWidth: 1080)

                            VStack(spacing: 22) {
                                habitatCard
                                carePanel
                                    .frame(maxWidth: 700)
                                    .clipShape(.rect(cornerRadius: 28))
                            }
                        }

                        BondRitualCard()
                            .frame(maxWidth: 1080)
                    }
                    .frame(maxWidth: 1180)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
                } else {
                    LazyVStack(spacing: 0) {
                        memberRail

                        habitat

                        carePanel
                            .offset(y: -20)
                            .padding(.bottom, -20)

                        BondRitualCard()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                    }
                }
            }
            .contentMargins(
                .bottom,
                horizontalSizeClass == .regular ? 24 : 104,
                for: .scrollContent
            )
            .background(Color.starPaper)
            .refreshable { await store.refreshSharedPlanet() }
            .navigationTitle(
                horizontalSizeClass == .regular
                    ? ""
                    : store.language.text("我們的星球", "우리의 별", "Our Planet")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        StarLifeView()
                    } label: {
                        Image(systemName: "moon.stars.fill")
                    }
                    .accessibilityLabel(store.language.text("小星日常", "작은 별의 하루", "Little Star life"))

                    NavigationLink {
                        StarWardrobeView()
                    } label: {
                        Image(systemName: "tshirt.fill")
                    }
                    .accessibilityLabel(store.language.text("裝扮小星", "별 꾸미기", "Dress up Little Star"))

                    NavigationLink {
                        PlanetSettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $invitePresented) {
                InviteFriendSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .task { await store.refreshSharedPlanet() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshSharedPlanet() } }
        }
    }

    private var memberRail: some View {
        HStack(spacing: 11) {
            HStack(spacing: -7) {
                ForEach(store.visiblePlanetMembers) { member in
                    Image(memberAsset(for: member))
                        .resizable().scaledToFit()
                        .frame(width: 40, height: 40)
                        .background(Color.starAvatar, in: .circle)
                        .overlay { Circle().stroke(Color.starPaper, lineWidth: 1) }
                        .accessibilityLabel(displayName(for: member.name))
                }
            }
            Text(residenceCopy)
                .font(.caption2)
                .foregroundStyle(Color.starMuted)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                invitePresented = true
            } label: {
                Label(store.language.text("邀請朋友", "친구 초대", "Invite a friend"), systemImage: "plus")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
            }
            .celestialGlassButtonStyle()
            .tint(Color.starPlum)
            .accessibilityLabel(store.language.text("邀請朋友", "친구 초대", "Invite a friend"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.starPaper)
    }

    private var habitat: some View {
        GeometryReader { proxy in
            ZStack {
                Image("StarHabitat")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                SeasonalRoomLayer(theme: store.starHome.selectedRoomTheme ?? .observatoryGarden)
                    .frame(width: proxy.size.width, height: proxy.size.height)

                StarHabitatMoodLayer(mood: store.starVisualMood)
                    .frame(width: proxy.size.width, height: proxy.size.height)

                StyledStarView(
                    wardrobe: store.wardrobe,
                    mood: store.starVisualMood,
                    size: horizontalSizeClass == .regular
                        ? (store.isCelebrating ? 250 : 226)
                        : (store.isCelebrating ? 168 : 152),
                    isCelebrating: store.isCelebrating
                )
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.62),
                        value: store.isCelebrating
                    )
            }
        }
        .frame(height: horizontalSizeClass == .regular ? 590 : 300)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            store.language.text("小星的星空家園，", "작은 별의 우주 정원, ", "Little Star's celestial home, ")
                + store.starVisualMood.accessibilityText(in: store.language)
                + store.language.text("。", ". ", ". ")
                + store.actionMessage
        )
    }

    private var habitatCard: some View {
        habitat
            .clipShape(.rect(cornerRadius: 28))
            .shadow(color: .black.opacity(0.10), radius: 20, y: 8)
    }

    private var carePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(dateCopy)
                Spacer()
                Label(store.visiblePlanetRelationship.title(in: store.language), systemImage: store.visiblePlanetRelationship.symbol)
                    .labelStyle(.titleAndIcon)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.starRoseMuted)

            Text(storyTitle)
                .font(.custom("Songti SC", size: 27, relativeTo: .title2).weight(.semibold))
                .foregroundStyle(Color.starInk)
                .padding(.top, 10)

            Text(storyBody)
                .font(.subheadline)
                .foregroundStyle(Color.starMuted)
                .lineSpacing(5)
                .padding(.top, 8)

            HStack(spacing: 8) {
                Image(systemName: "takeoutbag.and.cup.and.straw")
                Text(activityCopy).lineLimit(2)
            }
            .font(.caption2)
            .foregroundStyle(Color.starMuted)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Divider().foregroundStyle(Color.starLine) }

            HStack(alignment: .firstTextBaseline) {
                Text(store.language.text("星糧", "별빛 먹이", "Starlight")).font(.caption.weight(.semibold))
                Spacer()
                Text("\(store.planet.food)")
                    .font(.custom("New York", size: 28, relativeTo: .title2))
                Text("/100").font(.caption2).foregroundStyle(Color.starMuted)
            }
            .foregroundStyle(Color.starPlum)
            .padding(.top, 4)

            ProgressView(value: Double(store.planet.food), total: 100)
                .tint(Color.starRoseMuted)
                .padding(.top, 4)

            Text(foodProgressCopy)
                .font(.caption2)
                .foregroundStyle(Color.starMuted.opacity(0.8))
                .padding(.top, 7)

            if store.isGentleModeToday {
                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        store.language.text(
                            "今天不需要把自己變得更好。先和小星安靜地待一會兒就好。",
                            "오늘은 더 나아지려고 애쓰지 않아도 돼요. 작은 별과 잠시 조용히 머물러 보세요.",
                            "You don't need to improve anything today. Just sit quietly with Little Star for a while."
                        ),
                        systemImage: "moon.haze.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(Color.starPlum)
                    petActionButton.disabled(!store.canUseGentleInteraction)
                    if !store.canUseGentleInteraction {
                        Text(store.language.text("今天的輕輕擁抱已經收好了。", "오늘의 조용한 포옹을 잘 간직했어요.", "Today's gentle hug is safely tucked away."))
                            .font(.caption)
                            .foregroundStyle(Color.starMuted)
                    }
                }
                .padding(.top, 20)
            } else {
            Group {
                if horizontalSizeClass == .regular {
                    VStack(spacing: 10) {
                        petActionButton
                        feedActionButton
                    }
                } else {
                    HStack(spacing: 12) {
                        petActionButton
                        feedActionButton
                    }
                }
            }
            .padding(.top, 20)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.language.text("今晚的約定", "오늘 밤의 약속", "Tonight's promise"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.starRoseMuted)
                    HStack(spacing: 10) {
                        Text(store.language.text("今天餵小星 3 次", "오늘 별빛 먹이 3번 주기", "Feed Little Star 3 times today")).font(.subheadline.weight(.semibold))
                        Text("\(store.planet.feedCount)/3").font(.caption2).foregroundStyle(Color.starMuted)
                    }
                }
                Spacer()
                Text(store.planet.taskCompleted
                     ? store.language.text("已完成", "완료", "Done")
                     : store.language.text("+10 星糧", "+10 별빛", "+10 starlight"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(store.planet.taskCompleted ? Color.starGreen : Color.starRoseMuted)
                Image(systemName: store.planet.taskCompleted ? "checkmark" : "chevron.right")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(Color.starPlum)
            .padding(.vertical, 15)
            .overlay(alignment: .top) { Divider().foregroundStyle(Color.starLine) }
            .overlay(alignment: .bottom) { Divider().foregroundStyle(Color.starLine) }
            .padding(.top, 22)
            }
        }
        .padding(.horizontal, 25)
        .padding(.top, 24)
        .padding(.bottom, 30)
        .background(Color.starPaper)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 27, topTrailingRadius: 27))
    }

    private var residenceCopy: String {
        if store.isLoadingPlanet { return store.language.text("正在查看誰在星球上…", "별의 친구를 확인하고 있어요…", "Checking who's on your planet…") }
        if store.planetServiceError != nil { return store.language.text("暫時無法更新成員，下拉重試", "멤버를 업데이트하지 못했어요. 당겨서 다시 시도하세요", "Couldn't refresh members. Pull to retry") }
        let companions = store.visiblePlanetMembers.filter { !$0.isCurrentUser }.map(\.name)
        return companions.isEmpty
            ? store.language.text("這顆星球正在等待新朋友", "이 별은 새로운 친구를 기다리고 있어요", "This planet is waiting for a new friend")
            : store.language.text(
                "你和\(companions.joined(separator: "、"))一起住在這裡",
                "\(companions.joined(separator: ", "))와 이 별에서 함께 살아요",
                "You share this planet with \(companions.joined(separator: ", "))"
            )
    }

    private func memberAsset(for member: PlanetMember) -> String {
        if member.isCurrentUser { return store.wardrobe.displayedAssetName }
        let personaID = store.sharedMembership?.members.first { $0.accountID == member.id }?.personaID
        return StarSkinCatalog.item(id: personaID)?.assetName
            ?? personaID.flatMap(StarPersona.init(rawValue:))?.assetName ?? "StarPet"
    }

    private var storyTitle: String {
        if store.isGentleModeToday {
            return store.language.text("今天就安靜地待在這裡", "오늘은 그저 조용히 머물러요", "Let's simply stay here today")
        }
        return switch store.starVisualMood {
        case .low: store.language.text("今天就安靜地待在這裡", "오늘은 그저 조용히 머물러요", "Let's simply stay here today")
        case .tired: store.language.text("小星想先打個小盹", "작은 별이 잠깐 눈을 붙이고 싶대요", "Little Star would like a short nap")
        case .calm: store.language.text("它安靜地靠在你身邊", "작은 별이 조용히 곁에 기대어 있어요", "It is resting quietly beside you")
        case .glowing: store.language.text("小星正在慢慢發亮", "작은 별이 천천히 빛나고 있어요", "Little Star is starting to glow")
        case .delighted: store.language.text("今晚的星星收好了", "오늘 밤의 별빛을 잘 간직했어요", "Tonight's starlight is tucked away")
        case .happy: store.language.text("小星今天很開心", "작은 별은 오늘 행복해요", "Little Star is happy today")
        }
    }

    private var storyBody: String {
        if store.isGentleModeToday {
            return store.language.text("你不用解釋今天為什麼累。小星把月光調暗了一點，陪你慢慢呼吸。", "오늘 왜 힘든지 설명하지 않아도 돼요. 작은 별이 달빛을 조금 어둡게 하고 당신과 천천히 숨 쉬어요.", "You don't need to explain why you're tired. Little Star dimmed the moonlight and is breathing slowly with you.")
        }
        return switch store.starVisualMood {
        case .low: store.language.text("你不用解釋今天為什麼累。小星把月光調暗了一點，陪你慢慢呼吸。", "오늘 왜 힘든지 설명하지 않아도 돼요. 작은 별이 달빛을 조금 어둡게 하고 당신과 천천히 숨 쉬어요.", "You don't need to explain why you're tired. Little Star dimmed the moonlight and is breathing slowly with you.")
        case .tired: store.language.text("星光今天走得慢一點。陪它休息一會兒，等有精神了再出發。", "오늘은 별빛도 조금 천천히 흘러요. 잠시 함께 쉬었다가 기운이 돌아오면 다시 출발해요.", "The starlight is moving slowly today. Rest together for a while, then continue when energy returns.")
        case .calm: store.language.text("小星輕輕靠過來，像是在說：今天也辛苦了。", "작은 별이 살며시 다가와 오늘도 수고했다고 말해 주는 것 같아요.", "Little Star leans in, as if to say: you did well today.")
        case .glowing: store.language.text("你餵它的那一點星光，好像也讓今晚變得更溫柔了。", "당신이 건넨 별빛 덕분에 오늘 밤도 조금 더 다정해졌어요.", "That little bit of starlight you gave it made tonight feel softer too.")
        case .delighted: store.language.text("你完成了今天的約定。明天再來看看它吧。", "오늘의 약속을 지켰어요. 내일도 작은 별을 만나러 와요.", "You kept today's promise. Come see it again tomorrow.")
        case .happy: store.language.text("它剛剛繞著月亮飛了兩圈，現在想安靜地陪你待一會兒。", "방금 달 주위를 두 바퀴 돌고 와서, 이제 조용히 당신 곁에 있고 싶대요.", "It just flew around the moon twice. Now it wants to sit quietly with you.")
        }
    }

    private var activityCopy: String {
        switch store.planet.activity {
        case let .fed(actor, amount) where actor == "me" || actor == store.user?.displayName:
            return store.language.text(
                "\(displayName(for: actor))剛剛餵了 \(amount) 顆星糧",
                "\(displayName(for: actor)) 님이 방금 별빛 먹이 \(amount)개를 주었어요",
                "\(displayName(for: actor)) just gave \(amount) starlight snacks"
            )
        case let .petted(actor) where actor == "me" || actor == store.user?.displayName:
            return store.language.text("\(displayName(for: actor))剛剛陪了陪小星", "\(displayName(for: actor)) 님이 작은 별을 쓰다듬었어요", "\(displayName(for: actor)) just spent a moment with Little Star")
        default:
            // Old local snapshots contain demonstration activity from Xiaoyu.
            // Membership alone doesn't make that activity a verified shared event.
            return store.language.text("小星正在等你來陪它", "작은 별이 당신을 기다리고 있어요", "Little Star is waiting for you")
        }
    }

    private func displayName(for actor: String) -> String {
        switch actor {
        case "xiaoyu": store.language.text("小雨", "샤오위", "Xiaoyu")
        case "me": store.language.text("我", "나", "Me")
        case "new-friend": store.language.text("新朋友", "새 친구", "New friend")
        default: actor
        }
    }

    private var dateCopy: String {
        let formatter = DateFormatter()
        formatter.locale = store.language.locale
        switch store.language {
        case .traditionalChinese: formatter.dateFormat = "M月d日・EEEE"
        case .korean: formatter.dateFormat = "M월 d일 · EEEE"
        case .english: formatter.dateFormat = "EEEE, MMM d"
        }
        return formatter.string(from: .now)
    }

    private var foodProgressCopy: String {
        if store.planet.food == 100 {
            return store.language.text("小星今天已經充滿星光。", "작은 별이 오늘의 별빛을 가득 채웠어요.", "Little Star is full of starlight today.")
        }
        return store.language.text(
            "再收集 \(100 - store.planet.food) 點，小星就會長出新的光。",
            "\(100 - store.planet.food) 포인트를 더 모으면 새로운 빛이 피어나요.",
            "Collect \(100 - store.planet.food) more points and Little Star will grow a new glow."
        )
    }

    private var petActionButton: some View {
        Button(action: store.petStar) {
            PremiumActionLabel(
                title: store.language.text("陪小星一會兒", "작은 별 쓰다듬기", "Spend a moment together"),
                systemImage: "heart.fill"
            )
        }
        .celestialGlassButtonStyle(prominent: true)
        .tint(Color.starPlum)
        .controlSize(.large)
    }

    private var feedActionButton: some View {
        Button(action: store.feedPet) {
            PremiumActionLabel(
                title: store.language.text("餵一顆星糧", "별빛 먹이 주기", "Feed one starlight snack"),
                systemImage: "takeoutbag.and.cup.and.straw"
            )
        }
        .celestialGlassButtonStyle()
        .tint(Color.starRoseMuted)
        .controlSize(.large)
        .disabled(!store.canFeedPet)
    }
}

private struct PremiumActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
            Text(title)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
    }
}

private extension Color {
    static let starPaper = Color(red: 1.00, green: 0.992, blue: 0.976)
    static let starAvatar = Color(red: 0.92, green: 0.89, blue: 0.91)
    static let starInk = Color(red: 0.25, green: 0.18, blue: 0.24)
    static let starPlum = Color(red: 0.29, green: 0.21, blue: 0.28)
    static let starRoseMuted = Color(red: 0.63, green: 0.44, blue: 0.53)
    static let starMuted = Color(red: 0.49, green: 0.43, blue: 0.47)
    static let starLine = Color(red: 0.93, green: 0.89, blue: 0.90)
    static let starGreen = Color(red: 0.42, green: 0.49, blue: 0.42)
}

private struct PlanetSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var leavePresented = false

    var body: some View {
        Form {
            Section(store.language.text("共享星球", "공유 별", "Shared Planet")) {
                Picker(
                    store.language.text("關係空間", "관계 공간", "Relationship space"),
                    selection: Binding(
                        get: { store.visiblePlanetRelationship },
                        set: store.setRelationship
                    )
                ) {
                    ForEach(StarRelationship.allCases) { relationship in
                        Label(relationship.title(in: store.language), systemImage: relationship.symbol)
                            .tag(relationship)
                    }
                }
                .disabled(store.sharedMembership != nil)
                LabeledContent(
                    store.language.text("成員", "멤버", "Members"),
                    value: store.language.text("\(store.visiblePlanetMembers.count) 人", "\(store.visiblePlanetMembers.count)명", "\(store.visiblePlanetMembers.count) people")
                )
                LabeledContent(
                    store.language.text("同步方式", "동기화", "Sync"),
                    value: store.canUseAccountActions
                        ? store.language.text("成員透過帳號服務更新", "계정 서비스에서 멤버 업데이트", "Members updated from account service")
                        : store.language.text("本機預覽", "기기 미리보기", "Local preview")
                )
                if store.sharedMembership != nil {
                    Button(store.language.text("退出這顆星球", "이 별에서 나가기", "Leave this planet"), role: .destructive) { leavePresented = true }
                        .disabled(store.isUpdatingPlanet)
                }
                if let error = store.planetServiceError { Text(error).foregroundStyle(.red) }
            }
            Section(store.language.text("每日雙星", "매일 두 별", "Two of Us")) {
                LabeledContent(
                    store.language.text("今日狀態", "오늘의 상태", "Today's status"),
                    value: store.hasBondCheckInToday
                        ? (store.planet.bondMood?.title(in: store.language) ?? "")
                        : store.language.text("尚未留下", "아직 남기지 않음", "Not added yet")
                )
                Text(store.language.text(
                    "心情與留言會保存在目前帳號。正式帳號會同步到你自己的裝置，但不會自動傳給對方。",
                    "마음과 메시지는 현재 계정에 보관됩니다. 정식 계정은 본인의 기기들과 동기화하지만 상대에게 자동으로 전송하지 않아요.",
                    "Moods and notes are saved to the current account. Verified accounts sync them across your own devices, but they aren't sent to the other person automatically."
                ))
                .foregroundStyle(.secondary)
            }
            Section(store.language.text("邀請朋友", "친구 초대", "Inviting friends")) {
                Text(store.language.text(
                    "把邀請連結分享給朋友，或請朋友貼上邀請碼。加入需要雙方登入正式帳號；目前一顆星球最多兩人。",
                    "초대 링크를 공유하거나 친구에게 코드를 붙여 넣도록 해 주세요. 둘 다 정식 계정으로 로그인해야 하며 한 별에는 두 명까지 함께 살 수 있어요.",
                    "Share an invitation link or ask your friend to paste its code. Both people need verified accounts. A planet currently holds up to two people."
                ))
            }
        }
        .navigationTitle(store.language.text("星球設定", "별 설정", "Planet Settings"))
        .confirmationDialog(store.language.text("退出這顆星球？", "이 별에서 나갈까요?", "Leave this planet?"), isPresented: $leavePresented, titleVisibility: .visible) {
            Button(store.language.text("退出星球", "별에서 나가기", "Leave planet"), role: .destructive) { Task { _ = await store.leaveSharedPlanet() } }
        } message: {
            Text(store.language.text("你建立的未用邀請會失效。你和朋友各自的私人資料都會保留。", "사용하지 않은 초대는 무효가 됩니다. 두 사람의 개인 데이터는 유지돼요.", "Your unused invitations will stop working. Both people's private data will be kept."))
        }
    }
}
