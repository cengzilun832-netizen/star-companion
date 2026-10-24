import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case traditionalChinese = "zh-Hant"
    case korean = "ko"
    case english = "en"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }
    var displayName: String {
        switch self {
        case .traditionalChinese: "繁體中文"
        case .korean: "한국어"
        case .english: "English"
        }
    }

    func text(_ traditionalChinese: String, _ korean: String, _ english: String) -> String {
        switch self {
        case .traditionalChinese: traditionalChinese
        case .korean: korean
        case .english: english
        }
    }
}

struct DailyAccessPolicy {
    static func hasUsed(lastUsedStamp: String?, todayStamp: String) -> Bool {
        guard let lastUsedStamp else { return false }
        // Day stamps are ISO-ordered (`yyyy-MM-dd`). Treat a future stamp as
        // already used so moving the device clock backwards cannot mint an
        // extra non-member draw.
        return lastUsedStamp >= todayStamp
    }

    static func canUse(isMember: Bool, lastUsedStamp: String?, todayStamp: String) -> Bool {
        isMember || !hasUsed(lastUsedStamp: lastUsedStamp, todayStamp: todayStamp)
    }

    static func canReserve(
        isMember: Bool,
        lastUsedStamp: String?,
        todayStamp: String,
        hasMatchingReservation: Bool
    ) -> Bool {
        isMember || (!hasMatchingReservation && canUse(
            isMember: false,
            lastUsedStamp: lastUsedStamp,
            todayStamp: todayStamp
        ))
    }

    static func stampAfterRecording(
        isMember: Bool,
        lastUsedStamp: String?,
        todayStamp: String
    ) -> String? {
        isMember ? lastUsedStamp : todayStamp
    }
}

enum DailyAccessKind: String, Hashable {
    case guide
    case tarot
}

/// An in-flight reveal belongs to the account and calendar day where it
/// began. It is intentionally memory-only: cancelling or terminating an
/// unfinished ritual must not consume the user's daily allowance.
struct DailyAccessReservation: Identifiable, Hashable {
    let id: UUID
    let kind: DailyAccessKind
    let accountID: String
    let originatingDayStamp: String
    let wasMemberWhenReserved: Bool
}

enum StarAura: String, CaseIterable, Identifiable, Codable {
    case classic
    case moonlit
    case sunrise
    case rose
    case nebula

    var id: String { rawValue }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .classic: language.text("原生星光", "기본 별빛", "Classic glow")
        case .moonlit: language.text("月光藍", "달빛 블루", "Moonlit blue")
        case .sunrise: language.text("晨曦金", "새벽 골드", "Sunrise gold")
        case .rose: language.text("心動粉", "설렘 핑크", "Blushing rose")
        case .nebula: language.text("星雲紫", "성운 퍼플", "Nebula violet")
        }
    }

    var hueRotation: Double {
        switch self {
        case .classic, .sunrise: 0
        case .moonlit: 205
        case .rose: 320
        case .nebula: 258
        }
    }

    var glowSymbol: String {
        switch self {
        case .classic: "sparkles"
        case .moonlit: "moon.stars.fill"
        case .sunrise: "sun.max.fill"
        case .rose: "heart.fill"
        case .nebula: "hurricane"
        }
    }

    static func matchingTarot(symbol: String?) -> StarAura {
        guard let symbol else { return .nebula }
        if symbol.contains("sun") { return .sunrise }
        if symbol.contains("moon") || symbol.contains("cloud") { return .moonlit }
        if symbol.contains("heart") || symbol.contains("person.2") { return .rose }
        if symbol.contains("star") || symbol.contains("sparkle") { return .classic }
        return .nebula
    }
}

enum StarAccessory: String, CaseIterable, Identifiable, Codable {
    case none
    case moonCrown
    case heartPin
    case magicWand
    case cometCharm

    var id: String { rawValue }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .none: language.text("不戴配件", "장식 없음", "No accessory")
        case .moonCrown: language.text("月亮皇冠", "달 왕관", "Moon crown")
        case .heartPin: language.text("心心別針", "하트 핀", "Heart pin")
        case .magicWand: language.text("許願魔杖", "소원 마법봉", "Wish wand")
        case .cometCharm: language.text("彗星吊飾", "혜성 장식", "Comet charm")
        }
    }

    var symbol: String {
        switch self {
        case .none: "circle.slash"
        case .moonCrown: "moon.stars.fill"
        case .heartPin: "heart.fill"
        case .magicWand: "wand.and.stars"
        case .cometCharm: "sparkle"
        }
    }

    var price: Int {
        switch self {
        case .none: 0
        case .moonCrown: 80
        case .heartPin: 60
        case .magicWand: 120
        case .cometCharm: 100
        }
    }
}

enum StarPersona: String, CaseIterable, Identifiable, Codable {
    case classic
    case dreamPajamas
    case moonWitch
    case sakuraMist
    case cloudHanbok
    case planetRing
    case frogPrince
    case abyssalJelly
    case strawberryMousse
    case novaMecha
    case obsidianNight
    case auroraWhisper
    case prismAurora
    case azureButterfly
    case velvetEclipse
    case lunarTide
    case moonveil
    case frostNocturne
    case moonRabbit
    case halloweenGhost

    var id: String { rawValue }

    var assetName: String {
        switch self {
        case .classic: "StarPet"
        case .dreamPajamas: "PersonaDreamPajamas"
        case .moonWitch: "PersonaMoonWitch"
        case .sakuraMist: "PersonaSakuraMist"
        case .cloudHanbok: "PersonaCloudHanbok"
        case .planetRing: "PersonaPlanetRing"
        case .frogPrince: "PersonaFrogPrince"
        case .abyssalJelly: "PersonaAbyssalJelly"
        case .strawberryMousse: "PersonaStrawberryMousse"
        case .novaMecha: "PersonaNovaMecha"
        case .obsidianNight: "PersonaObsidianNight"
        case .auroraWhisper: "PersonaAuroraWhisper"
        case .prismAurora: "PersonaPrismAurora"
        case .azureButterfly: "PersonaAzureButterfly"
        case .velvetEclipse: "PersonaVelvetEclipse"
        case .lunarTide: "PersonaLunarTide"
        case .moonveil: "PersonaMoonveil"
        case .frostNocturne: "PersonaFrostNocturne"
        case .moonRabbit: "PersonaMoonRabbit"
        case .halloweenGhost: "PersonaHalloweenGhost"
        }
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .classic: language.text("經典小星", "기본 별", "Classic")
        case .dreamPajamas: language.text("星眠睡衣", "별잠 파자마", "Dream Pajamas")
        case .moonWitch: language.text("月夜魔女", "달빛 마녀", "Moon Witch")
        case .sakuraMist: language.text("櫻霧初綻", "벚꽃 안개", "Sakura Mist")
        case .cloudHanbok: language.text("雲霞韓服", "구름 한복", "Cloud Hanbok")
        case .planetRing: language.text("行星銀環", "행성 고리", "Planet Ring")
        case .frogPrince: language.text("青蛙王子", "개구리 왕자", "Frog Prince")
        case .abyssalJelly: language.text("深海水母", "심해 해파리", "Abyssal Jelly")
        case .strawberryMousse: language.text("草莓慕斯", "딸기 무스", "Strawberry Mousse")
        case .novaMecha: language.text("星核機甲", "노바 메카", "Nova Mecha")
        case .obsidianNight: language.text("黑曜星夜", "흑요석 밤", "Obsidian Night")
        case .auroraWhisper: language.text("極光低語", "오로라 속삭임", "Aurora Whisper")
        case .prismAurora: language.text("虹光星旅", "프리즘 오로라", "Prism Aurora")
        case .azureButterfly: language.text("晴藍蝶夢", "푸른 나비꿈", "Azure Butterfly")
        case .velvetEclipse: language.text("緋夜月蝕", "벨벳 이클립스", "Velvet Eclipse")
        case .lunarTide: language.text("月潮水晶", "달빛 물결", "Lunar Tide")
        case .moonveil: language.text("月紗花冠", "달빛 베일", "Moonveil")
        case .frostNocturne: language.text("霜夜星座", "서리 녹턴", "Frost Nocturne")
        case .moonRabbit: language.text("中秋月兔星", "중추절 달토끼 별", "Moon Rabbit Star")
        case .halloweenGhost: language.text("萬聖幽靈星", "할로윈 유령 별", "Halloween Ghost Star")
        }
    }

    var price: Int {
        switch self {
        case .classic: 0
        case .dreamPajamas, .sakuraMist, .cloudHanbok: 180
        case .moonWitch, .planetRing, .frogPrince, .strawberryMousse: 240
        case .abyssalJelly, .auroraWhisper: 280
        case .novaMecha, .obsidianNight: 320
        case .prismAurora, .azureButterfly: 320
        case .lunarTide: 340
        case .velvetEclipse, .moonveil: 360
        case .frostNocturne: 380
        case .moonRabbit, .halloweenGhost: 280
        }
    }

    static var starterCases: [StarPersona] {
        // Keep this list stable: adding a shop or seasonal look must never
        // silently replace the persona already seeded for an existing account.
        [
            .classic, .dreamPajamas, .moonWitch, .sakuraMist,
            .cloudHanbok, .planetRing, .frogPrince, .abyssalJelly,
            .strawberryMousse, .novaMecha, .obsidianNight, .auroraWhisper,
        ]
    }

    var isSeasonal: Bool {
        self == .moonRabbit || self == .halloweenGhost
    }

    func isAvailable(on date: Date = .now, calendar: Calendar = .current) -> Bool {
        let month = calendar.component(.month, from: date)
        return switch self {
        case .moonRabbit: month == 9 || month == 10
        case .halloweenGhost: month == 10
        default: true
        }
    }

    func seasonalNote(in language: AppLanguage) -> String? {
        return switch self {
        case .moonRabbit: language.text("中秋限定・9–10 月", "중추절 한정 · 9–10월", "Mid-Autumn limited · Sep–Oct")
        case .halloweenGhost: language.text("萬聖限定・10 月", "할로윈 한정 · 10월", "Halloween limited · October")
        default: nil
        }
    }

    /// Full persona artwork already includes a complete outfit. The small SF
    /// Symbol accessories are reserved for the plain classic body so they do
    /// not collide visually with hats, rings, or costumes in the artwork.
    var supportsAccessoryOverlay: Bool { self == .classic }
}

struct StarWardrobe: Codable, Equatable {
    /// Shipped briefly as a generated shop item before its artwork was found
    /// to be identical to `PersonaMoonRabbit`. Keep the ID here so existing
    /// ownership is transferred instead of silently disappearing.
    private static let legacyJadeRabbitCollectionID = "collection.jade-rabbit"

    var selectedAura: StarAura
    var tarotAura: StarAura?
    var followsTarotMeaning: Bool
    var selectedAccessory: StarAccessory
    var ownedAccessories: Set<StarAccessory>
    var starCoins: Int
    var starTrailProgress: StarTrailProgress?
    var cometCatchProgress: StarTrailProgress?
    var selectedPersona: StarPersona?
    var ownedPersonas: Set<StarPersona>?
    /// Collection looks are namespaced string IDs so new artwork can be added
    /// by the catalog generator without changing this persisted Codable model.
    var selectedCollectionSkinID: String?
    var ownedCollectionSkinIDs: Set<String>?
    /// Selection provenance only; this is not an entitlement cache. StoreKit
    /// remains authoritative for whether the selected paid look may render.
    /// Optional keeps older account snapshots source-compatible.
    var selectedPersonaRequiresAllLooks: Bool? = nil
    var selectedCollectionSkinRequiresAllLooks: Bool? = nil
    var selectedAccessoryRequiresAllLooks: Bool? = nil

    var displayedAura: StarAura {
        followsTarotMeaning ? (tarotAura ?? selectedAura) : selectedAura
    }

    var displayedPersona: StarPersona {
        selectedPersona ?? .classic
    }

    var displayedCollectionSkin: StarSkinCatalogItem? {
        StarSkinCatalog.item(id: selectedCollectionSkinID)
    }

    var displayedLookID: String {
        displayedCollectionSkin?.id ?? displayedPersona.rawValue
    }

    var displayedAssetName: String {
        displayedCollectionSkin?.assetName ?? displayedPersona.assetName
    }

    var supportsAccessoryOverlay: Bool {
        displayedCollectionSkin == nil && displayedPersona.supportsAccessoryOverlay
    }

    var availablePersonas: Set<StarPersona> {
        var personas = ownedPersonas ?? [.classic]
        personas.insert(.classic)
        if selectedPersonaRequiresAllLooks != true {
            personas.insert(displayedPersona)
        }
        return personas
    }

    var availableCollectionSkinIDs: Set<String> {
        var skinIDs = ownedCollectionSkinIDs ?? []
        if let selectedCollectionSkinID, selectedCollectionSkinRequiresAllLooks != true {
            skinIDs.insert(selectedCollectionSkinID)
        }
        return skinIDs
    }

    func migrated(for accountID: String) -> StarWardrobe {
        var migrated = self
        let accountSeed = StarWardrobe.seeded(for: accountID)
        if migrated.selectedPersona == nil {
            migrated.selectedPersona = accountSeed.selectedPersona
        }
        if migrated.ownedPersonas == nil {
            migrated.ownedPersonas = accountSeed.ownedPersonas
        }
        migrated.ownedPersonas?.insert(.classic)
        if let selectedPersona = migrated.selectedPersona,
           migrated.selectedPersonaRequiresAllLooks != true {
            migrated.ownedPersonas?.insert(selectedPersona)
        }
        if migrated.ownedCollectionSkinIDs == nil {
            migrated.ownedCollectionSkinIDs = []
        }
        if let selectedCollectionSkinID = migrated.selectedCollectionSkinID,
           migrated.selectedCollectionSkinRequiresAllLooks != true {
            migrated.ownedCollectionSkinIDs?.insert(selectedCollectionSkinID)
        }
        if migrated.ownedCollectionSkinIDs?.contains(Self.legacyJadeRabbitCollectionID) == true {
            migrated.ownedCollectionSkinIDs?.remove(Self.legacyJadeRabbitCollectionID)
            migrated.ownedPersonas?.insert(.moonRabbit)
        }
        if migrated.selectedCollectionSkinID == Self.legacyJadeRabbitCollectionID {
            migrated.selectedCollectionSkinID = nil
            migrated.selectedPersona = .moonRabbit
        }
        return migrated
    }

    static func seeded(for accountID: String) -> StarWardrobe {
        let seed = accountID.utf8.reduce(UInt64(5381)) { value, byte in
            ((value << 5) &+ value) &+ UInt64(byte)
        }
        let auras = StarAura.allCases
        let starterAccessories: [StarAccessory] = [.moonCrown, .heartPin, .cometCharm]
        let aura = auras[Int(seed % UInt64(auras.count))]
        let accessory = starterAccessories[Int((seed >> 4) % UInt64(starterAccessories.count))]
        let mixedSeed = seed ^ (seed >> 32)
        let starterPersonas = StarPersona.starterCases
        let persona = starterPersonas[Int(mixedSeed % UInt64(starterPersonas.count))]

        return StarWardrobe(
            selectedAura: aura,
            tarotAura: nil,
            followsTarotMeaning: true,
            selectedAccessory: accessory,
            ownedAccessories: [.none, accessory],
            starCoins: 120,
            starTrailProgress: StarTrailProgress(),
            cometCatchProgress: StarTrailProgress(),
            selectedPersona: persona,
            ownedPersonas: [.classic, persona],
            selectedCollectionSkinID: nil,
            ownedCollectionSkinIDs: []
        )
    }
}

struct StarTrailProgress: Codable, Equatable {
    var highestUnlockedLevel = 1
    var completedLevels: Set<Int> = []

    func isUnlocked(_ level: Int) -> Bool {
        level <= highestUnlockedLevel
    }
}

enum PetMood: String, Codable, Equatable {
    case happy
    case glowing
    case affectionate
    case delighted
}

enum PlanetActivity: Codable, Equatable {
    case fed(actor: String, amount: Int)
    case petted(actor: String)
    case friendJoined
}

enum PetActionState: Equatable {
    case waiting
    case fed
    case taskCompleted
    case petted
}

struct WeChatUser: Codable, Equatable {
    let openID: String
    let displayName: String
    let canonicalAccountID: String?

    init(openID: String, displayName: String, canonicalAccountID: String? = nil) {
        self.openID = openID
        self.displayName = displayName
        self.canonicalAccountID = canonicalAccountID
    }

    init(account: AppAccount) {
        openID = account.providerSubject
        displayName = account.displayName
        canonicalAccountID = account.canonicalAccountID
    }

    var appAccount: AppAccount {
        AppAccount(
            provider: .weChat,
            providerSubject: openID,
            displayName: displayName,
            canonicalAccountID: canonicalAccountID
        )
    }

    /// Existing WeChat records keep using their stable OpenID. A production
    /// authentication backend can later supply one provider-independent ID
    /// without changing any existing call site or invalidating old JSON.
    var canonicalLocalAccountID: String {
        if let canonical = canonicalAccountID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty {
            return "account:\(canonical)"
        }
        return "wechat:\(openID)"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum FortuneFocus: String, CaseIterable, Identifiable, Codable {
    case love
    case work
    case wealth
    case wellbeing

    var id: String { rawValue }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .love: language.text("愛情與關係", "사랑과 관계", "Love & relationships")
        case .work: language.text("工作與成長", "일과 성장", "Work & growth")
        case .wealth: language.text("財運與機會", "재물과 기회", "Money & opportunities")
        case .wellbeing: language.text("心情與能量", "마음과 에너지", "Mood & energy")
        }
    }

    var symbol: String {
        switch self {
        case .love: "heart.fill"
        case .work: "briefcase.fill"
        case .wealth: "sparkles"
        case .wellbeing: "leaf.fill"
        }
    }
}

enum ZodiacSign: Int, CaseIterable, Codable {
    case capricorn
    case aquarius
    case pisces
    case aries
    case taurus
    case gemini
    case cancer
    case leo
    case virgo
    case libra
    case scorpio
    case sagittarius

    static func sign(for date: Date, calendar: Calendar = .current) -> ZodiacSign {
        let parts = calendar.dateComponents([.month, .day], from: date)
        let value = (parts.month ?? 1) * 100 + (parts.day ?? 1)

        switch value {
        case 120..<219: return .aquarius
        case 219..<321: return .pisces
        case 321..<420: return .aries
        case 420..<521: return .taurus
        case 521..<622: return .gemini
        case 622..<723: return .cancer
        case 723..<823: return .leo
        case 823..<923: return .virgo
        case 923..<1024: return .libra
        case 1024..<1123: return .scorpio
        case 1123..<1222: return .sagittarius
        default: return .capricorn
        }
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .capricorn: language.text("摩羯座", "염소자리", "Capricorn")
        case .aquarius: language.text("水瓶座", "물병자리", "Aquarius")
        case .pisces: language.text("雙魚座", "물고기자리", "Pisces")
        case .aries: language.text("牡羊座", "양자리", "Aries")
        case .taurus: language.text("金牛座", "황소자리", "Taurus")
        case .gemini: language.text("雙子座", "쌍둥이자리", "Gemini")
        case .cancer: language.text("巨蟹座", "게자리", "Cancer")
        case .leo: language.text("獅子座", "사자자리", "Leo")
        case .virgo: language.text("處女座", "처녀자리", "Virgo")
        case .libra: language.text("天秤座", "천칭자리", "Libra")
        case .scorpio: language.text("天蠍座", "전갈자리", "Scorpio")
        case .sagittarius: language.text("射手座", "사수자리", "Sagittarius")
        }
    }

    var symbol: String {
        switch self {
        case .capricorn: "♑︎"
        case .aquarius: "♒︎"
        case .pisces: "♓︎"
        case .aries: "♈︎"
        case .taurus: "♉︎"
        case .gemini: "♊︎"
        case .cancer: "♋︎"
        case .leo: "♌︎"
        case .virgo: "♍︎"
        case .libra: "♎︎"
        case .scorpio: "♏︎"
        case .sagittarius: "♐︎"
        }
    }
}

struct BirthProfile: Codable, Equatable {
    var displayName: String
    var birthDate: Date
    var birthTimeMinutes: Int?
    var birthPlace: String
    var focuses: [FortuneFocus]

    var zodiac: ZodiacSign { ZodiacSign.sign(for: birthDate) }

    func birthTimeText(in language: AppLanguage) -> String {
        guard let birthTimeMinutes else {
            return language.text("未設定", "설정 안 함", "Not set")
        }
        let hours = birthTimeMinutes / 60
        let minutes = birthTimeMinutes % 60
        return String(format: "%02d:%02d", hours, minutes)
    }
}

enum DailyGuideVariant: Int, CaseIterable, Codable {
    case pauseBeforeConcluding
    case sayItClearly
    case leaveOneThingOut
    case tryAnotherRoute

    func title(in language: AppLanguage) -> String {
        switch self {
        case .pauseBeforeConcluding:
            language.text("先別急著下結論", "서둘러 결론 내리지 마세요", "Don't rush to a conclusion")
        case .sayItClearly:
            language.text("有話就說清楚", "할 말은 분명히 전해요", "Say what you mean")
        case .leaveOneThingOut:
            language.text("今天少排一件事", "오늘은 할 일을 하나 줄여요", "Take one thing off today's list")
        case .tryAnotherRoute:
            language.text("卡住時，換一條路", "막히면 다른 길을 택해요", "Try another route when you're stuck")
        }
    }

    func message(in language: AppLanguage) -> String {
        switch self {
        case .pauseBeforeConcluding:
            language.text(
                "不確定的事先放到下午再看。隔幾個小時，通常會少一點情緒，多一點線索。",
                "확실하지 않은 일은 오후에 다시 보세요. 몇 시간 지나면 감정은 줄고 단서는 더 잘 보여요.",
                "Leave uncertain things until this afternoon. A few hours may bring less emotion and more clues."
            )
        case .sayItClearly:
            language.text(
                "別等對方猜。把你在意的事講成一句完整的話，今天比較不容易誤會。",
                "상대가 알아서 눈치채길 기다리지 마세요. 마음에 걸리는 일을 한 문장으로 말하면 오해가 줄어요.",
                "Don't make them guess. Say what matters in one clear sentence and misunderstandings are less likely."
            )
        case .leaveOneThingOut:
            language.text(
                "待辦留三件就好。先做最麻煩的那件，剩下的時間會輕鬆很多。",
                "할 일은 세 가지만 남겨요. 가장 번거로운 것부터 끝내면 남은 시간이 훨씬 가벼워져요.",
                "Keep only three things on your list. Start with the awkward one and the rest of the day will feel lighter."
            )
        case .tryAnotherRoute:
            language.text(
                "原本的方法卡住就停一下。換個順序，或直接問一個熟悉這件事的人。",
                "하던 방식이 막히면 잠깐 멈추세요. 순서를 바꾸거나 이 일을 잘 아는 사람에게 바로 물어봐도 좋아요.",
                "If your usual way is stuck, pause. Change the order or ask someone who knows the terrain."
            )
        }
    }

    func luckyColor(in language: AppLanguage) -> String {
        switch self {
        case .pauseBeforeConcluding:
            language.text("霧粉紫", "안개 핑크 퍼플", "Misty pink-purple")
        case .sayItClearly:
            language.text("月光藍", "달빛 블루", "Moonlight blue")
        case .leaveOneThingOut:
            language.text("星砂金", "별모래 골드", "Stardust gold")
        case .tryAnotherRoute:
            language.text("晚霞莓紅", "노을 베리 레드", "Sunset berry")
        }
    }

    static func infer(title: String, message: String, luckyColor: String) -> DailyGuideVariant? {
        allCases.first { variant in
            AppLanguage.allCases.contains { language in
                title == variant.title(in: language)
                    || message == variant.message(in: language)
                    || luckyColor == variant.luckyColor(in: language)
            }
        }
    }
}

enum DailyGuideArchiveCatalog {
    static let travelerID = "traveler"
    static let starCardID = "major.star"

    static func zodiacID(for sign: ZodiacSign?) -> String {
        sign.map { "zodiac.\($0.rawValue)" } ?? travelerID
    }

    static func zodiacTitle(for id: String, language: AppLanguage) -> String? {
        if id == travelerID {
            return language.text("旅行者", "여행자", "Traveler")
        }
        guard id.hasPrefix("zodiac."),
              let rawValue = Int(id.dropFirst("zodiac.".count)),
              let sign = ZodiacSign(rawValue: rawValue)
        else { return nil }
        return sign.title(in: language)
    }

    static func inferZodiacID(from legacyTitle: String) -> String? {
        for language in AppLanguage.allCases {
            if legacyTitle == language.text("旅行者", "여행자", "Traveler") {
                return travelerID
            }
            if let sign = ZodiacSign.allCases.first(where: { $0.title(in: language) == legacyTitle }) {
                return zodiacID(for: sign)
            }
        }
        return nil
    }

    static func cardTitle(for id: String, language: AppLanguage) -> String? {
        guard id == starCardID else { return nil }
        return language.text("星星", "별", "The Star")
    }

    static func inferCardID(from legacyTitle: String) -> String? {
        AppLanguage.allCases.contains {
            legacyTitle == cardTitle(for: starCardID, language: $0)
        } ? starCardID : nil
    }
}

struct DailyGuide: Identifiable, Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case id, dateStamp, zodiacName, cardName, title, message, luckyColor, luckyTime
        case zodiacID, cardID, variantID
    }

    let id: String
    let dateStamp: String
    let zodiacName: String
    let cardName: String
    let title: String
    let message: String
    let luckyColor: String
    let luckyTime: String
    let zodiacID: String?
    let cardID: String?
    let variantID: Int?

    init(
        id: String,
        dateStamp: String,
        zodiacName: String,
        cardName: String,
        title: String,
        message: String,
        luckyColor: String,
        luckyTime: String,
        zodiacID: String? = nil,
        cardID: String? = nil,
        variantID: Int? = nil
    ) {
        self.id = id
        self.dateStamp = dateStamp
        self.zodiacName = zodiacName
        self.cardName = cardName
        self.title = title
        self.message = message
        self.luckyColor = luckyColor
        self.luckyTime = luckyTime
        self.zodiacID = zodiacID
        self.cardID = cardID
        self.variantID = variantID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            dateStamp: try container.decode(String.self, forKey: .dateStamp),
            zodiacName: try container.decode(String.self, forKey: .zodiacName),
            cardName: try container.decode(String.self, forKey: .cardName),
            title: try container.decode(String.self, forKey: .title),
            message: try container.decode(String.self, forKey: .message),
            luckyColor: try container.decode(String.self, forKey: .luckyColor),
            luckyTime: try container.decode(String.self, forKey: .luckyTime),
            zodiacID: try container.decodeIfPresent(String.self, forKey: .zodiacID),
            cardID: try container.decodeIfPresent(String.self, forKey: .cardID),
            variantID: try container.decodeIfPresent(Int.self, forKey: .variantID)
        )
    }

    func canonicalized() -> DailyGuide {
        let resolvedVariant = variantID.flatMap(DailyGuideVariant.init(rawValue:))
            ?? DailyGuideVariant.infer(title: title, message: message, luckyColor: luckyColor)
        return DailyGuide(
            id: id,
            dateStamp: dateStamp,
            zodiacName: zodiacName,
            cardName: cardName,
            title: title,
            message: message,
            luckyColor: luckyColor,
            luckyTime: luckyTime,
            zodiacID: zodiacID ?? DailyGuideArchiveCatalog.inferZodiacID(from: zodiacName),
            cardID: cardID ?? DailyGuideArchiveCatalog.inferCardID(from: cardName),
            variantID: resolvedVariant?.rawValue
        )
    }

    func localizedZodiacName(in language: AppLanguage) -> String {
        let resolvedID = zodiacID ?? DailyGuideArchiveCatalog.inferZodiacID(from: zodiacName)
        return resolvedID.flatMap { DailyGuideArchiveCatalog.zodiacTitle(for: $0, language: language) }
            ?? zodiacName
    }

    func localizedCardName(in language: AppLanguage) -> String {
        let resolvedID = cardID ?? DailyGuideArchiveCatalog.inferCardID(from: cardName)
        return resolvedID.flatMap { DailyGuideArchiveCatalog.cardTitle(for: $0, language: language) }
            ?? cardName
    }

    func localizedTitle(in language: AppLanguage) -> String {
        resolvedVariant?.title(in: language) ?? title
    }

    func localizedMessage(in language: AppLanguage) -> String {
        resolvedVariant?.message(in: language) ?? message
    }

    func localizedLuckyColor(in language: AppLanguage) -> String {
        resolvedVariant?.luckyColor(in: language) ?? luckyColor
    }

    private var resolvedVariant: DailyGuideVariant? {
        variantID.flatMap(DailyGuideVariant.init(rawValue:))
            ?? DailyGuideVariant.infer(title: title, message: message, luckyColor: luckyColor)
    }
}

enum TarotTopicID: String, CaseIterable, Codable {
    case wealth
    case love
    case today

    func title(in language: AppLanguage) -> String {
        switch self {
        case .wealth: language.text("財運", "재물", "Money")
        case .love: language.text("桃花", "인연", "Love")
        case .today: language.text("當日運勢", "오늘", "Today")
        }
    }

    func defaultQuestion(in language: AppLanguage) -> String {
        language.text(
            "今天的\(title(in: language))要注意什麼？",
            "오늘 \(title(in: language))에서 무엇을 조심해야 할까요?",
            "What should I notice about \(title(in: language)) today?"
        )
    }

    static func resolve(canonicalID: String?, englishTitle: String, localizedTitle: String) -> TarotTopicID? {
        if let canonicalID, let topic = TarotTopicID(rawValue: canonicalID) {
            return topic
        }
        switch englishTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "wealth", "money": return .wealth
        case "love": return .love
        case "today": return .today
        default: break
        }
        return allCases.first { topic in
            AppLanguage.allCases.contains { topic.title(in: $0) == localizedTitle }
        }
    }

    func matchesDefaultQuestion(_ value: String) -> Bool {
        AppLanguage.allCases.contains { value == defaultQuestion(in: $0) }
    }
}

struct TarotReadingRecord: Identifiable, Codable, Equatable, Hashable {
    private enum CodingKeys: String, CodingKey {
        case id, createdAt, topicTitle, topicEnglish, question, cardName, answer, detail
        case orientation, cardSymbol, keywords, appearanceSnapshot
        case topicID, cardID, topicFrameVariant, userQuestion, usesDefaultQuestion
    }

    let id: UUID
    let createdAt: Date
    let topicTitle: String
    let topicEnglish: String
    let question: String
    let cardName: String
    let answer: String
    let detail: String
    let orientation: TarotOrientation?
    let cardSymbol: String?
    let keywords: String?
    let appearanceSnapshot: StarAppearanceSnapshot?
    let topicID: String?
    let cardID: String?
    let topicFrameVariant: Int?
    let userQuestion: String?
    let usesDefaultQuestion: Bool?

    init(
        id: UUID,
        createdAt: Date,
        topicTitle: String,
        topicEnglish: String,
        question: String,
        cardName: String,
        answer: String,
        detail: String,
        orientation: TarotOrientation? = nil,
        cardSymbol: String? = nil,
        keywords: String? = nil,
        appearanceSnapshot: StarAppearanceSnapshot? = nil,
        topicID: String? = nil,
        cardID: String? = nil,
        topicFrameVariant: Int? = nil,
        userQuestion: String? = nil,
        usesDefaultQuestion: Bool? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.topicTitle = topicTitle
        self.topicEnglish = topicEnglish
        self.question = question
        self.cardName = cardName
        self.answer = answer
        self.detail = detail
        self.orientation = orientation
        self.cardSymbol = cardSymbol
        self.keywords = keywords
        self.appearanceSnapshot = appearanceSnapshot
        self.topicID = topicID
        self.cardID = cardID
        self.topicFrameVariant = topicFrameVariant
        self.userQuestion = userQuestion
        self.usesDefaultQuestion = usesDefaultQuestion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            topicTitle: try container.decode(String.self, forKey: .topicTitle),
            topicEnglish: try container.decode(String.self, forKey: .topicEnglish),
            question: try container.decode(String.self, forKey: .question),
            cardName: try container.decode(String.self, forKey: .cardName),
            answer: try container.decode(String.self, forKey: .answer),
            detail: try container.decode(String.self, forKey: .detail),
            orientation: try container.decodeIfPresent(TarotOrientation.self, forKey: .orientation),
            cardSymbol: try container.decodeIfPresent(String.self, forKey: .cardSymbol),
            keywords: try container.decodeIfPresent(String.self, forKey: .keywords),
            appearanceSnapshot: try container.decodeIfPresent(StarAppearanceSnapshot.self, forKey: .appearanceSnapshot),
            topicID: try container.decodeIfPresent(String.self, forKey: .topicID),
            cardID: try container.decodeIfPresent(String.self, forKey: .cardID),
            topicFrameVariant: try container.decodeIfPresent(Int.self, forKey: .topicFrameVariant),
            userQuestion: try container.decodeIfPresent(String.self, forKey: .userQuestion),
            usesDefaultQuestion: try container.decodeIfPresent(Bool.self, forKey: .usesDefaultQuestion)
        )
    }

    func withAppearanceSnapshot(_ snapshot: StarAppearanceSnapshot) -> TarotReadingRecord {
        TarotReadingRecord(
            id: id,
            createdAt: createdAt,
            topicTitle: topicTitle,
            topicEnglish: topicEnglish,
            question: question,
            cardName: cardName,
            answer: answer,
            detail: detail,
            orientation: orientation,
            cardSymbol: cardSymbol,
            keywords: keywords,
            appearanceSnapshot: snapshot,
            topicID: topicID,
            cardID: cardID,
            topicFrameVariant: topicFrameVariant,
            userQuestion: userQuestion,
            usesDefaultQuestion: usesDefaultQuestion
        )
    }

    func canonicalized() -> TarotReadingRecord {
        let topic = resolvedTopic
        let resolvedCardID = cardID ?? TarotDeck.cardID(matchingLocalizedName: cardName)
        let resolvedDefaultQuestion = usesDefaultQuestion
            ?? topic?.matchesDefaultQuestion(question)
            ?? false
        let resolvedUserQuestion = userQuestion
            ?? (resolvedDefaultQuestion ? nil : question)
        let inferredPresentation = TarotDeck.canonicalPresentation(
            matchingLocalizedHeadline: answer,
            detail: detail,
            cardID: resolvedCardID,
            topicID: topic?.rawValue
        )
        let resolvedOrientation = orientation ?? inferredPresentation?.orientation
        let resolvedFrameVariant = topicFrameVariant.flatMap { (0..<4).contains($0) ? $0 : nil }
            ?? TarotDeck.topicFrameVariant(
                matchingLocalizedDetail: detail,
                cardID: resolvedCardID,
                orientation: resolvedOrientation,
                topicID: topic?.rawValue
            )
            ?? inferredPresentation?.topicFrameVariant

        return TarotReadingRecord(
            id: id,
            createdAt: createdAt,
            topicTitle: topicTitle,
            topicEnglish: topicEnglish,
            question: question,
            cardName: cardName,
            answer: answer,
            detail: detail,
            orientation: resolvedOrientation,
            cardSymbol: cardSymbol,
            keywords: keywords,
            appearanceSnapshot: appearanceSnapshot,
            topicID: topic?.rawValue,
            cardID: resolvedCardID,
            topicFrameVariant: resolvedFrameVariant,
            userQuestion: resolvedUserQuestion,
            usesDefaultQuestion: resolvedDefaultQuestion
        )
    }

    func localizedTopicTitle(in language: AppLanguage) -> String {
        resolvedTopic?.title(in: language) ?? topicTitle
    }

    func localizedQuestion(in language: AppLanguage) -> String {
        if resolvedUsesDefaultQuestion, let topic = resolvedTopic {
            return topic.defaultQuestion(in: language)
        }
        return userQuestion ?? question
    }

    func localizedAnswer(in language: AppLanguage) -> String {
        localizedDraw(in: language)?.headline ?? answer
    }

    func localizedDetail(in language: AppLanguage) -> String {
        localizedDraw(in: language)?.message ?? detail
    }

    func localizedKeywords(in language: AppLanguage) -> String? {
        localizedDraw(in: language)?.keywords ?? keywords
    }

    func cardTitle(in language: AppLanguage) -> String {
        let localizedName = localizedDraw(in: language)?.cardName ?? cardName
        guard let orientation = resolvedOrientation else { return localizedName }
        return "\(localizedName)・\(orientation.title(in: language))"
    }

    func shareText(in language: AppLanguage) -> String {
        let localizedKeywords = localizedKeywords(in: language)
        let keywordLine = localizedKeywords.map {
            language.text("關鍵字：\($0)\n", "키워드: \($0)\n", "Keywords: \($0)\n")
        } ?? ""
        let localizedTopic = localizedTopicTitle(in: language)
        let localizedQuestion = localizedQuestion(in: language)
        let localizedAnswer = localizedAnswer(in: language)
        let localizedDetail = localizedDetail(in: language)
        return language.text(
            "今日抽牌｜\(localizedTopic)\n問題：\(localizedQuestion)\n塔羅：\(cardTitle(in: language))\n\(keywordLine)\(localizedAnswer)\n\(localizedDetail)\n\n內容僅供娛樂與自我探索。",
            "오늘의 카드 | \(localizedTopic)\n질문: \(localizedQuestion)\n타로: \(cardTitle(in: language))\n\(keywordLine)\(localizedAnswer)\n\(localizedDetail)\n\n내용은 오락과 자기 탐색을 위한 것이에요.",
            "Today's card | \(localizedTopic)\nQuestion: \(localizedQuestion)\nTarot: \(cardTitle(in: language))\n\(keywordLine)\(localizedAnswer)\n\(localizedDetail)\n\nFor entertainment and self-reflection only."
        )
    }

    private var resolvedTopic: TarotTopicID? {
        TarotTopicID.resolve(
            canonicalID: topicID,
            englishTitle: topicEnglish,
            localizedTitle: topicTitle
        )
    }

    private var resolvedUsesDefaultQuestion: Bool {
        usesDefaultQuestion
            ?? resolvedTopic?.matchesDefaultQuestion(question)
            ?? false
    }

    private var resolvedOrientation: TarotOrientation? {
        orientation ?? TarotDeck.canonicalPresentation(
            matchingLocalizedHeadline: answer,
            detail: detail,
            cardID: cardID ?? TarotDeck.cardID(matchingLocalizedName: cardName),
            topicID: resolvedTopic?.rawValue
        )?.orientation
    }

    private func localizedDraw(in language: AppLanguage) -> TarotDrawResult? {
        guard let cardID = cardID ?? TarotDeck.cardID(matchingLocalizedName: cardName),
              let orientation = resolvedOrientation,
              let topicID = resolvedTopic?.rawValue,
              let frameVariant = topicFrameVariant.flatMap({ (0..<4).contains($0) ? $0 : nil })
                ?? TarotDeck.topicFrameVariant(
                    matchingLocalizedDetail: detail,
                    cardID: cardID,
                    orientation: orientation,
                    topicID: topicID
                )
        else { return nil }
        return TarotDeck.localizedResult(
            cardID: cardID,
            orientation: orientation,
            topicID: topicID,
            topicFrameVariant: frameVariant,
            language: language
        )
    }
}

struct PlanetMember: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let symbol: String
    let isCurrentUser: Bool
}

enum BondMood: String, CaseIterable, Identifiable, Codable {
    case glowing
    case soft
    case tired
    case missYou

    var id: String { rawValue }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .glowing: language.text("閃閃發亮", "반짝반짝", "Glowing")
        case .soft: language.text("軟綿綿", "포근포근", "Cozy")
        case .tired: language.text("有點累", "조금 지쳤어요", "A little tired")
        case .missYou: language.text("想念你", "보고 싶어요", "Missing you")
        }
    }

    var symbol: String {
        switch self {
        case .glowing: "sparkles"
        case .soft: "cloud.fill"
        case .tired: "moon.zzz.fill"
        case .missYou: "heart.fill"
        }
    }
}

struct BondMemory: Identifiable, Codable, Equatable {
    let dateStamp: String
    let relationship: StarRelationship
    let mood: BondMood
    let note: String?

    var id: String { "\(relationship.rawValue)-\(dateStamp)" }
}

struct SharedPlanet: Codable, Equatable {
    var food = 72
    var feedCount = 2
    var taskDate = Self.todayStamp()
    var taskRewardClaimed = false
    var mood = PetMood.happy
    var activity = PlanetActivity.fed(actor: "xiaoyu", amount: 8)
    var relationship: StarRelationship?
    var bondCheckInDate: String?
    var bondMood: BondMood?
    var bondNote: String?
    var bondMemories: [BondMemory]?
    var members: [PlanetMember] = [
        PlanetMember(id: "me", name: "me", symbol: "sparkles", isCurrentUser: true),
        PlanetMember(id: "xiaoyu", name: "xiaoyu", symbol: "moon.fill", isCurrentUser: false),
    ]

    var taskCompleted: Bool { feedCount >= 3 }
    var currentRelationship: StarRelationship { relationship ?? .friend }

    static func todayStamp(for date: Date = .now, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

enum StarRelationship: String, CaseIterable, Identifiable, Codable, Sendable {
    case friend
    case bestie
    case couple

    var id: String { rawValue }
    func title(in language: AppLanguage) -> String {
        switch self {
        case .friend: language.text("星星好友", "별 친구", "Star friends")
        case .bestie: language.text("星星閨蜜", "별빛 베스트 프렌드", "Star besties")
        case .couple: language.text("星星情侶", "별빛 커플", "Star couple")
        }
    }
    var symbol: String {
        switch self {
        case .friend: "sparkles"
        case .bestie: "moon.stars.fill"
        case .couple: "heart.fill"
        }
    }
    func subtitle(in language: AppLanguage) -> String {
        switch self {
        case .friend: language.text("一起養星，彼此陪伴", "함께 별을 키우며 서로를 곁에 두어요", "Raise a star and stay close")
        case .bestie: language.text("收藏彼此的小宇宙", "서로의 작은 우주를 간직해요", "Keep a little piece of each other's universe")
        case .couple: language.text("一起記住兩個人的星光", "두 사람만의 별빛을 함께 기억해요", "Keep the starlight you share")
        }
    }

    func dailyPrompt(in language: AppLanguage, date: Date = .now) -> String {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 0
        let traditionalChinese: [String]
        let korean: [String]
        let english: [String]

        switch self {
        case .friend:
            traditionalChinese = [
                "今天想一起完成哪一個小願望？",
                "最近有什麼新鮮事想第一個告訴對方？",
                "如果今晚一起散步，最想聊什麼？",
                "今天可以怎樣替彼此加一點星光？",
            ]
            korean = [
                "오늘 함께 이루고 싶은 작은 소원은 무엇인가요?",
                "요즘 가장 먼저 서로에게 알려 주고 싶은 일은 무엇인가요?",
                "오늘 밤 같이 산책한다면 무슨 이야기를 하고 싶나요?",
                "오늘 서로에게 어떤 별빛을 더해 줄 수 있을까요?",
            ]
            english = [
                "What small wish would you like to make happen together today?",
                "What's the first new thing you'd like to tell each other?",
                "If you took a walk tonight, what would you want to talk about?",
                "How could you add a little starlight to each other's day?",
            ]
        case .bestie:
            traditionalChinese = [
                "今天最想和她分享哪一個瞬間？",
                "最近哪件小事讓你想到她？",
                "如果現在見面，第一句會說什麼？",
                "今天想偷偷送她哪一種好心情？",
            ]
            korean = [
                "오늘 가장 나누고 싶은 순간은 무엇인가요?",
                "최근 어떤 작은 일이 친구를 떠올리게 했나요?",
                "지금 만난다면 첫마디로 무엇을 말하고 싶나요?",
                "오늘 친구에게 어떤 좋은 기분을 몰래 보내고 싶나요?",
            ]
            english = [
                "Which moment from today do you most want to share with her?",
                "What small thing recently made you think of her?",
                "If you met right now, what would you say first?",
                "What good feeling would you secretly send her today?",
            ]
        case .couple:
            traditionalChinese = [
                "今天最想對對方說的一句話是什麼？",
                "今天哪個瞬間讓你覺得被愛著？",
                "下一次約會想一起做哪件小事？",
                "今天想給對方哪一種擁抱？",
            ]
            korean = [
                "오늘 서로에게 가장 하고 싶은 한마디는 무엇인가요?",
                "오늘 어떤 순간에 사랑받고 있다고 느꼈나요?",
                "다음 데이트에서 함께 하고 싶은 작은 일은 무엇인가요?",
                "오늘 서로에게 어떤 포옹을 건네고 싶나요?",
            ]
            english = [
                "What's the one thing you most want to say to each other today?",
                "Which moment today made you feel loved?",
                "What little thing would you like to do on your next date?",
                "What kind of hug would you give each other today?",
            ]
        }

        let index = day % traditionalChinese.count
        return language.text(traditionalChinese[index], korean[index], english[index])
    }
    var isAvailable: Bool { true }
}
