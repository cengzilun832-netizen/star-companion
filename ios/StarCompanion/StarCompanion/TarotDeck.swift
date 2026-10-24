import Foundation

enum TarotOrientation: String, Codable, Hashable {
    case upright
    case reversed

    func title(in language: AppLanguage) -> String {
        switch self {
        case .upright: language.text("正位", "정방향", "Upright")
        case .reversed: language.text("逆位", "역방향", "Reversed")
        }
    }
}

struct TarotDrawResult {
    let cardID: String
    let cardName: String
    let cardSymbol: String
    let orientation: TarotOrientation
    let topicFrameVariant: Int
    let keywords: String
    let headline: String
    let message: String
}

enum TarotCardID: String, CaseIterable, Codable {
    case fool
    case magician
    case highPriestess
    case empress
    case emperor
    case hierophant
    case lovers
    case chariot
    case strength
    case hermit
    case wheelOfFortune
    case justice
    case hangedMan
    case death
    case temperance
    case devil
    case tower
    case star
    case moon
    case sun
    case judgement
    case world
}

enum TarotDeck {
    // Keep this explicit order aligned with `cards` and `englishCards`. The raw
    // values are persisted, so adding a card must never shift an existing ID.
    private static let cardIDsInDeckOrder: [TarotCardID] = [
        .fool, .magician, .highPriestess, .empress, .emperor, .hierophant,
        .lovers, .chariot, .strength, .hermit, .wheelOfFortune, .justice,
        .hangedMan, .death, .temperance, .devil, .tower, .star, .moon, .sun,
        .judgement, .world,
    ]

    private struct LocalizedCopy {
        let traditionalChinese: String
        let korean: String

        func value(in language: AppLanguage) -> String {
            switch language {
            case .traditionalChinese:
                traditionalChinese
            case .korean:
                korean
            case .english:
                preconditionFailure("English tarot copy must come from EnglishCard")
            }
        }
    }

    private struct Card {
        let name: LocalizedCopy
        let symbol: String
        let keywords: LocalizedCopy
        let uprightHeadline: LocalizedCopy
        let uprightMessage: LocalizedCopy
        let reversedHeadline: LocalizedCopy
        let reversedMessage: LocalizedCopy
    }

    private struct EnglishCard {
        let name: String
        let keywords: String
        let uprightHeadline: String
        let uprightMessage: String
        let reversedHeadline: String
        let reversedMessage: String
    }

    static func draw(
        topicID: String,
        question: String,
        language: AppLanguage,
        date: Date = .now
    ) -> TarotDrawResult {
        precondition(
            cards.count == cardIDsInDeckOrder.count && englishCards.count == cards.count,
            "Tarot card IDs and localized decks must remain aligned"
        )
        let normalizedQuestion = question
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: language.locale)
        let seed = "\(SharedPlanet.todayStamp(for: date))|\(topicID)|\(normalizedQuestion)"
        let hash = stableHash(seed)
        let cardIndex = Int(hash % UInt64(cards.count))
        let orientation: TarotOrientation = ((hash >> 11) & 3) == 0 ? .reversed : .upright
        let topicFrameVariant = Int((hash >> 23) & 3)
        return localizedResult(
            cardID: cardIDsInDeckOrder[cardIndex].rawValue,
            orientation: orientation,
            topicID: topicID,
            topicFrameVariant: topicFrameVariant,
            language: language
        )!
    }

    static func localizedResult(
        cardID: String,
        orientation: TarotOrientation,
        topicID: String,
        topicFrameVariant: Int,
        language: AppLanguage
    ) -> TarotDrawResult? {
        guard let canonicalCard = TarotCardID(rawValue: cardID),
              let cardIndex = cardIDsInDeckOrder.firstIndex(of: canonicalCard),
              cards.indices.contains(cardIndex),
              englishCards.indices.contains(cardIndex),
              TarotTopicID(rawValue: topicID) != nil
        else { return nil }

        let card = cards[cardIndex]
        let normalizedVariant = max(0, min(topicFrameVariant, 3))
        if language == .english {
            let englishCard = englishCards[cardIndex]
            let headline = orientation == .upright
                ? englishCard.uprightHeadline
                : englishCard.reversedHeadline
            let message = orientation == .upright
                ? englishCard.uprightMessage
                : englishCard.reversedMessage

            return TarotDrawResult(
                cardID: canonicalCard.rawValue,
                cardName: englishCard.name,
                cardSymbol: card.symbol,
                orientation: orientation,
                topicFrameVariant: normalizedVariant,
                keywords: englishCard.keywords,
                headline: headline,
                message: message + " " + topicFrame(
                    topicID: topicID,
                    variant: normalizedVariant,
                    language: language
                )
            )
        }

        let headline = orientation == .upright ? card.uprightHeadline : card.reversedHeadline
        let message = orientation == .upright ? card.uprightMessage : card.reversedMessage
        return TarotDrawResult(
            cardID: canonicalCard.rawValue,
            cardName: card.name.value(in: language),
            cardSymbol: card.symbol,
            orientation: orientation,
            topicFrameVariant: normalizedVariant,
            keywords: card.keywords.value(in: language),
            headline: headline.value(in: language),
            message: message.value(in: language) + " " + topicFrame(
                topicID: topicID,
                variant: normalizedVariant,
                language: language
            )
        )
    }

    static func cardID(matchingLocalizedName legacyName: String) -> String? {
        for (index, cardID) in cardIDsInDeckOrder.enumerated() where cards.indices.contains(index) {
            if englishCards.indices.contains(index), englishCards[index].name == legacyName {
                return cardID.rawValue
            }
            let card = cards[index]
            if card.name.traditionalChinese == legacyName || card.name.korean == legacyName {
                return cardID.rawValue
            }
        }
        return nil
    }

    static func topicFrameVariant(
        matchingLocalizedDetail legacyDetail: String,
        cardID: String?,
        orientation: TarotOrientation?,
        topicID: String?
    ) -> Int? {
        guard let cardID, let orientation, let topicID else { return nil }
        let normalizedLegacy = legacyDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        for language in AppLanguage.allCases {
            for variant in 0..<4 {
                let candidate = localizedResult(
                    cardID: cardID,
                    orientation: orientation,
                    topicID: topicID,
                    topicFrameVariant: variant,
                    language: language
                )?.message.trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate == normalizedLegacy {
                    return variant
                }
            }
        }
        return nil
    }

    static func canonicalPresentation(
        matchingLocalizedHeadline legacyHeadline: String,
        detail legacyDetail: String,
        cardID: String?,
        topicID: String?
    ) -> (orientation: TarotOrientation, topicFrameVariant: Int)? {
        guard let cardID, let topicID else { return nil }
        let normalizedHeadline = legacyHeadline.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDetail = legacyDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        for orientation in [TarotOrientation.upright, .reversed] {
            for language in AppLanguage.allCases {
                for variant in 0..<4 {
                    guard let candidate = localizedResult(
                        cardID: cardID,
                        orientation: orientation,
                        topicID: topicID,
                        topicFrameVariant: variant,
                        language: language
                    ) else { continue }
                    if candidate.headline.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedHeadline,
                       candidate.message.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedDetail {
                        return (orientation, variant)
                    }
                }
            }
        }
        return nil
    }

    private static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }

    private static func topicFrame(topicID: String, variant: Int, language: AppLanguage) -> String {
        if language == .english {
            let frames: [String]
            switch topicID {
            case "wealth":
                frames = [
                    "Check your balance before deciding. Leave anything tempting in the cart overnight.",
                    "Review subscriptions and small charges today. That's often where forgotten spending hides.",
                    "If an opportunity appears, ask about the cost and deadline before agreeing.",
                    "Clear one bill or money task you've been putting off before looking for a new strategy.",
                ]
            case "love":
                frames = [
                    "Don't rely on guessing today. Ask one clear question without testing the other person.",
                    "Notice whether promises turn into action. What they do matters more than the mood.",
                    "If you want to reach out, send one simple message. The opening line doesn't need to be perfect.",
                    "If something hurt, start with what happened today. Leave old arguments out of it.",
                ]
            default:
                frames = [
                    "Start with the task you've been avoiding. Fifteen minutes still counts.",
                    "Your focus may drift this afternoon, so handle the important thing before lunch if you can.",
                    "If plans change, reorder the next few steps. The whole day doesn't need to unravel.",
                    "Take a little longer to reply today, especially to messages that put you on edge.",
                ]
            }
            return frames[variant % frames.count]
        }

        let frames: [LocalizedCopy]
        switch topicID {
        case "wealth":
            frames = [
                copy("今天先看帳戶再做決定。打算買的東西，放進購物車一晚。", "오늘은 계좌를 먼저 확인하고 결정하세요. 사고 싶은 것은 장바구니에 하루만 두세요."),
                copy("今天適合核對自動續費和小額支出。漏掉的通常就在這裡。", "오늘은 자동 결제와 소액 지출을 확인해 보세요. 놓친 돈은 보통 여기에 있어요."),
                copy("有新機會，先問清楚成本和期限。口頭承諾先不算。", "새로운 기회가 생기면 비용과 기한부터 확인하세요. 말뿐인 약속은 아직 계산에 넣지 마세요."),
                copy("先把一筆拖著沒處理的帳整理好。比找新方法有用。", "미뤄 둔 정산 하나부터 끝내세요. 새 방법을 찾는 것보다 도움이 돼요."),
            ]
        case "love":
            frames = [
                copy("今天別靠猜。想知道，就問一句不帶試探的話。", "오늘은 혼자 짐작하지 마세요. 궁금하다면 떠보지 말고 한마디 물어보세요."),
                copy("留意對方有沒有做到答應的事。行動比氣氛可靠。", "상대가 약속한 일을 지켰는지 보세요. 분위기보다 행동이 더 정확해요."),
                copy("如果想聯絡，就傳一則簡單訊息。不必想太多開場。", "연락하고 싶다면 짧은 메시지를 보내세요. 첫 문장을 너무 오래 고민하지 않아도 돼요."),
                copy("有點不開心就先說事實，別一次翻出以前的帳。", "서운하다면 지금 있었던 일부터 말하세요. 예전 일까지 한꺼번에 꺼내지는 마세요."),
            ]
        default:
            frames = [
                copy("今天先做最不想碰的那件事。做十五分鐘也算。", "오늘 가장 손대기 싫은 일부터 해보세요. 15분만 해도 괜찮아요."),
                copy("下午容易分心。重要的事盡量放到午餐前。", "오후에는 집중이 흐트러지기 쉬워요. 중요한 일은 점심 전에 해두세요."),
                copy("臨時有變動，先重新排一次順序，不用整天跟著亂。", "갑자기 일정이 바뀌면 순서만 다시 정하세요. 하루 전체를 흔들 필요는 없어요."),
                copy("今天適合慢一拍回覆，尤其是讓你不舒服的訊息。", "오늘은 답장을 한 박자 늦춰도 좋아요. 특히 마음을 불편하게 하는 메시지는요."),
            ]
        }
        return frames[variant % frames.count].value(in: language)
    }

    private static func copy(_ traditionalChinese: String, _ korean: String) -> LocalizedCopy {
        LocalizedCopy(traditionalChinese: traditionalChinese, korean: korean)
    }

    private static let englishCards: [EnglishCard] = [
        EnglishCard(
            name: "The Fool",
            keywords: "New beginnings · Freedom · Curiosity",
            uprightHeadline: "Take one small step",
            uprightMessage: "Try the new option, but keep the first move small and easy to undo.",
            reversedHeadline: "Look before you leap",
            reversedMessage: "Check the timing, budget, or way back before acting on impulse."
        ),
        EnglishCard(
            name: "The Magician",
            keywords: "Action · Resources · Creation",
            uprightHeadline: "You already have enough to begin",
            uprightMessage: "Use what is already in front of you and make a first version. The real questions will become clearer.",
            reversedHeadline: "Close a few tabs",
            reversedMessage: "Your energy is spread too thin. Keep one main goal for today."
        ),
        EnglishCard(
            name: "The High Priestess",
            keywords: "Intuition · Stillness · Insight",
            uprightHeadline: "You don't need to answer yet",
            uprightMessage: "Write down the first feeling that surfaced. It may make more sense later than everyone else's advice.",
            reversedHeadline: "That uneasy feeling matters",
            reversedMessage: "Write down the exact moment something felt off. The clue is probably in a small detail."
        ),
        EnglishCard(
            name: "The Empress",
            keywords: "Care · Abundance · Sensation",
            uprightHeadline: "Look after yourself first",
            uprightMessage: "Eat when you're hungry and stop when you're tired. Comfort may help you work better today.",
            reversedHeadline: "Give a little less today",
            reversedMessage: "Make room for a stretch of time when you don't reply. Your needs don't always belong at the end of the line."
        ),
        EnglishCard(
            name: "The Emperor",
            keywords: "Order · Boundaries · Responsibility",
            uprightHeadline: "Make the rules clear",
            uprightMessage: "Agree on who is doing what, by when, and what finished means. It will save a lot of guessing later.",
            reversedHeadline: "You don't have to manage everything",
            reversedMessage: "Leave one decision to someone else. It may not look exactly like your version, but it can move faster."
        ),
        EnglishCard(
            name: "The Hierophant",
            keywords: "Tradition · Guidance · Belief",
            uprightHeadline: "Borrow a method that already works",
            uprightMessage: "Ask someone experienced how they began. You don't need to invent the whole process yourself.",
            reversedHeadline: "Does that rule still fit?",
            reversedMessage: "‘Everyone does it’ isn't a reason. Keep what helps and adapt the rest to your life."
        ),
        EnglishCard(
            name: "The Lovers",
            keywords: "Connection · Choice · Honesty",
            uprightHeadline: "Choose the option that feels like you",
            uprightMessage: "If both choices seem fine, ask which one you would still want to stand behind six months from now.",
            reversedHeadline: "Name what you won't compromise on",
            reversedMessage: "Indecision often means two needs are colliding. Remove one condition that isn't truly necessary."
        ),
        EnglishCard(
            name: "The Chariot",
            keywords: "Direction · Will · Momentum",
            uprightHeadline: "Pick a direction, then move",
            uprightMessage: "Keep one main goal today. Put the other demands aside until it is done.",
            reversedHeadline: "Busy isn't always progress",
            reversedMessage: "If you're rushing but nothing is finishing, stop for ten minutes. The order may be the real problem."
        ),
        EnglishCard(
            name: "Strength",
            keywords: "Courage · Patience · Gentleness",
            uprightHeadline: "Try the gentle approach",
            uprightMessage: "Lower your voice for the difficult conversation. The more you want to persuade, the more space they need to finish speaking.",
            reversedHeadline: "You may just be tired",
            reversedMessage: "Eat, shower, or sleep first. Pushing through right now may only make the decision worse."
        ),
        EnglishCard(
            name: "The Hermit",
            keywords: "Solitude · Search · Wisdom",
            uprightHeadline: "Turn off notifications for half an hour",
            uprightMessage: "Find somewhere quiet and write down the three things bothering you most. Start with the first one.",
            reversedHeadline: "You've thought long enough—talk to someone",
            reversedMessage: "Choose someone who won't rush to fix it. Saying it out loud may show you exactly where you're stuck."
        ),
        EnglishCard(
            name: "Wheel of Fortune",
            keywords: "Change · Cycles · Timing",
            uprightHeadline: "Things are starting to move",
            uprightMessage: "A last-minute invitation or change of time may not be bad news. See whether the new timing works better.",
            reversedHeadline: "Work with today's rhythm",
            reversedMessage: "If you can't change the timing, change how you prepare. Do what you can and stop pushing for the result."
        ),
        EnglishCard(
            name: "Justice",
            keywords: "Facts · Balance · Choice",
            uprightHeadline: "List the facts first",
            uprightMessage: "Separate what you know, what you assume, and what you feel. Base today's decision on the first list.",
            reversedHeadline: "You may be seeing only one side",
            reversedMessage: "Find one piece of information that could challenge your current view. Decide after you've read it."
        ),
        EnglishCard(
            name: "The Hanged Man",
            keywords: "Pause · Perspective · Release",
            uprightHeadline: "Turn the question around",
            uprightMessage: "Ask yourself what outcome would still be acceptable if the original plan were no longer possible.",
            reversedHeadline: "Don't wait forever",
            reversedMessage: "Give this a final deadline. If there is still no answer, follow your backup plan."
        ),
        EnglishCard(
            name: "Death",
            keywords: "Ending · Change · Renewal",
            uprightHeadline: "It's time to close something out",
            uprightMessage: "Cancel one plan you won't attend or delete one draft you no longer need. Deal with an ending that has lingered.",
            reversedHeadline: "Let go of one small part",
            reversedMessage: "You don't have to release everything at once. Start with what takes the most space and gives the least back."
        ),
        EnglishCard(
            name: "Temperance",
            keywords: "Balance · Rhythm · Healing",
            uprightHeadline: "Adjust one thing at a time",
            uprightMessage: "Change one number in your sleep, spending, or workload. Too many changes at once won't last.",
            reversedHeadline: "Where is there too much?",
            reversedMessage: "Look at the last three days. Cut the most time-consuming, least useful thing in half."
        ),
        EnglishCard(
            name: "The Devil",
            keywords: "Attachment · Desire · Awareness",
            uprightHeadline: "Admit what is hard to give up",
            uprightMessage: "If you keep returning to something that doesn't fit, there may be a benefit you haven't named yet.",
            reversedHeadline: "Change one small habit",
            reversedMessage: "Choose one different response today: wait five minutes, buy one less thing, or say no once."
        ),
        EnglishCard(
            name: "The Tower",
            keywords: "Truth · Disruption · Rebuilding",
            uprightHeadline: "Plans changed—protect what matters",
            uprightMessage: "Protect the one thing you cannot afford to lose, whether it is time, money, or trust. Repair the rest later.",
            reversedHeadline: "Repair it before it breaks",
            reversedMessage: "You already know where things are unstable. Make one small fix today instead of waiting for the crash."
        ),
        EnglishCard(
            name: "The Star",
            keywords: "Hope · Healing · Trust",
            uprightHeadline: "Do one small thing that settles you",
            uprightMessage: "Reply to the overdue message, set the time, or gather what you need. Give hope somewhere concrete to land.",
            reversedHeadline: "You don't have to force optimism",
            reversedMessage: "If you're disappointed, say so. Get through today before deciding whether to continue tomorrow."
        ),
        EnglishCard(
            name: "The Moon",
            keywords: "Dreams · Intuition · Uncertainty",
            uprightHeadline: "You don't have enough information yet",
            uprightMessage: "You don't have to believe or challenge everything you hear today. Wait for a second source.",
            reversedHeadline: "Write fear and fact in separate columns",
            reversedMessage: "The worst case isn't always the most likely one. List three confirmed facts and look again."
        ),
        EnglishCard(
            name: "The Sun",
            keywords: "Clarity · Success · Energy",
            uprightHeadline: "Let yourself be seen today",
            uprightMessage: "Share what you've finished instead of polishing it out of sight. You can also tell someone plainly that you like them.",
            reversedHeadline: "Don't pretend you're fine",
            reversedMessage: "You don't have to keep the mood bright for everyone. If you're tired, leave early without dressing up the reason."
        ),
        EnglishCard(
            name: "Judgement",
            keywords: "Awakening · Response · Renewal",
            uprightHeadline: "This needs an answer",
            uprightMessage: "Leaving it unanswered is still an answer. Choose yes or no today instead of keeping it in drafts.",
            reversedHeadline: "Don't judge today by an old mistake",
            reversedMessage: "The situation has changed, and so have you. Decide using the information you have now."
        ),
        EnglishCard(
            name: "The World",
            keywords: "Completion · Integration · Wholeness",
            uprightHeadline: "You can finish this now",
            uprightMessage: "Send the final message, check off the last item, and stop. You don't need to add anything new today.",
            reversedHeadline: "One last check",
            reversedMessage: "The main work is done. Check names, dates, and amounts instead of rebuilding everything at the last minute."
        ),
    ]

    private static let cards: [Card] = [
        Card(
            name: copy("愚者", "바보"), symbol: "sparkles",
            keywords: copy("開始・自由・好奇", "시작 · 자유 · 호기심"),
            uprightHeadline: copy("先走一步看看", "먼저 첫걸음을 내디뎌요"),
            uprightMessage: copy("新選項可以試，但別一次押太大。先做一個能回頭的小測試。", "새로운 가능성이 당신을 부르고 있어요. 모든 준비가 완벽해질 때까지 기다리지 말고 호기심을 따라가 보세요."),
            reversedHeadline: copy("先看清楚再跳", "먼저 발밑을 확인해요"),
            reversedMessage: copy("行程、預算、退路，至少確認一樣。今天不適合只憑一時興起。", "자유는 무계획과 다르답니다. 위험을 먼저 확인하고 내디딜 가치가 있는 한 걸음을 골라 보세요.")
        ),
        Card(
            name: copy("魔術師", "마법사"), symbol: "wand.and.stars",
            keywords: copy("行動・資源・創造", "행동 · 자원 · 창조"),
            uprightHeadline: copy("手上的東西夠用了", "필요한 도구는 이미 있어요"),
            uprightMessage: copy("不用再等新工具。拿現有資料做出第一版，問題會比現在清楚。", "생각을 눈에 보이는 행동으로 바꿔 보세요. 당신이 가진 능력은 스스로 생각하는 것보다 충분해요."),
            reversedHeadline: copy("先收掉幾個分頁", "힘을 흩뜨리지 마세요"),
            reversedMessage: copy("同時做太多，哪一件都做不深。今天只留一個主要目標。", "너무 많은 방향을 한꺼번에 잡으면 힘이 약해져요. 시선을 거두어 한 가지부터 제대로 해보세요.")
        ),
        Card(
            name: copy("女祭司", "여사제"), symbol: "moon.stars.fill",
            keywords: copy("直覺・安靜・洞察", "직감 · 고요 · 통찰"),
            uprightHeadline: copy("先別急著回答", "답은 고요한 곳에 있어요"),
            uprightMessage: copy("第一個浮上來的感覺先記著。晚一點再看，它通常比別人的意見有用。", "당장 밖에서 답을 찾지 않아도 돼요. 처음 떠오른 감정이 수많은 의견보다 진실에 가까울 수 있어요."),
            reversedHeadline: copy("那個不對勁，不是多心", "불편한 마음을 외면하지 마세요"),
            reversedMessage: copy("把讓你卡住的那一刻寫下來。問題多半藏在一個很小的細節裡。", "이미 어딘가 어긋났다고 느꼈을 수 있어요. 그 불편함에 이름을 붙이면 흐릿함이 걷히기 시작해요.")
        ),
        Card(
            name: copy("皇后", "여황제"), symbol: "crown.fill",
            keywords: copy("滋養・豐盛・感受", "돌봄 · 풍요 · 감각"),
            uprightHeadline: copy("先把自己顧好", "좋은 것을 다정히 돌봐요"),
            uprightMessage: copy("餓了就吃，累了就停。今天把舒服放前面，效率反而不會差。", "자라날 가치가 있는 것은 시간과 공간, 다정함이 필요해요. 자신을 먼저 돌봐야 풍요도 머물 수 있어요."),
            reversedHeadline: copy("今天少照顧別人一點", "내 에너지부터 채워요"),
            reversedMessage: copy("先留一段不回訊息的時間。你的需要不用排在所有人後面。", "많은 사람을 돌보느라 자신의 필요를 잊었을지 몰라요. 오늘은 조금 덜 내어주어도 괜찮아요.")
        ),
        Card(
            name: copy("皇帝", "황제"), symbol: "shield.lefthalf.filled",
            keywords: copy("秩序・邊界・承擔", "질서 · 경계 · 책임"),
            uprightHeadline: copy("規則先說清楚", "분명한 경계를 세워요"),
            uprightMessage: copy("誰來做、何時交、做到哪裡，今天一次講明白。省得之後來回猜。", "분명한 규칙은 중요한 것을 지켜 줘요. 책임과 기한을 명확히 하면 상황이 안정될 거예요."),
            reversedHeadline: copy("不用每件事都管", "지나친 통제는 유연함을 잃게 해요"),
            reversedMessage: copy("留一項給別人決定。結果未必照你的版本走，但事情會動得比較快。", "모든 세부를 손에 쥘 필요는 없어요. 조정할 여백을 남기면 오히려 목표에 더 쉽게 닿아요.")
        ),
        Card(
            name: copy("教皇", "교황"), symbol: "book.closed.fill",
            keywords: copy("傳承・指引・信念", "전통 · 안내 · 신념"),
            uprightHeadline: copy("照成熟的方法做一次", "검증된 방법을 참고해요"),
            uprightMessage: copy("不知道怎麼開始，就找一個做過的人問步驟。今天不用自己發明整套流程。", "모든 답을 혼자 찾을 필요는 없어요. 믿을 만한 사람이나 검증된 방법에서 작은 등불을 빌려 보세요."),
            reversedHeadline: copy("這條規則還適合嗎？", "그 규칙이 나에게 맞는지 확인해요"),
            reversedMessage: copy("「大家都這樣」不算理由。留下有用的，其他照你的情況改。", "익숙함이 곧 정답은 아니에요. 정말 도움이 되는 부분만 남기고 남들이 한다는 이유뿐인 선택은 내려놓으세요.")
        ),
        Card(
            name: copy("戀人", "연인"), symbol: "heart.fill",
            keywords: copy("連結・選擇・真心", "연결 · 선택 · 진심"),
            uprightHeadline: copy("選那個比較像你的", "선택을 진심과 맞춰요"),
            uprightMessage: copy("兩個選項都不差時，想想半年後你比較願意為哪一個負責。", "중요한 것은 가장 완벽해 보이는 선택이 아니라 어떤 선택이 당신답게 만드는지예요."),
            reversedHeadline: copy("先排出不能退讓的事", "가치의 충돌부터 살펴요"),
            reversedMessage: copy("一直猶豫，通常是兩個要求撞在一起。先刪掉一個不必要的條件。", "망설임은 두 바람이 서로 당기기 때문일 수 있어요. 타협할 수 없는 핵심부터 분명히 해보세요.")
        ),
        Card(
            name: copy("戰車", "전차"), symbol: "arrow.up.forward.circle.fill",
            keywords: copy("方向・意志・前進", "방향 · 의지 · 전진"),
            uprightHeadline: copy("先定方向，再加速", "방향이 하나면 앞으로 갈 수 있어요"),
            uprightMessage: copy("今天只留一個主要目標。其他要求先放旁邊，做完再說。", "흩어진 힘을 한 길로 모아 보세요. 오늘은 분명한 결정을 내리고 움직이기 좋은 날이에요."),
            reversedHeadline: copy("忙，不一定有進度", "속도로 길 잃음을 감추지 마세요"),
            reversedMessage: copy("如果一直趕卻沒做完，先停十分鐘。你可能只是順序排錯了。", "빠르다고 더 가까워지는 것은 아니에요. 잠시 멈춰 목적지를 확인한 뒤 방향을 다시 잡으세요.")
        ),
        Card(
            name: copy("力量", "힘"), symbol: "pawprint.fill",
            keywords: copy("勇氣・耐心・溫柔", "용기 · 인내 · 다정함"),
            uprightHeadline: copy("今天用軟的", "부드러움이 힘보다 강해요"),
            uprightMessage: copy("難談的事先把音量放低。越想說服對方，越要讓對方把話講完。", "진짜 용기는 감정을 누르는 것이 아니라 그 감정을 안고도 앞으로 가는 힘이에요."),
            reversedHeadline: copy("你只是累了", "지친 마음부터 달래요"),
            reversedMessage: copy("先吃飯、洗澡、睡一覺。現在硬撐，判斷只會更差。", "당신이 약한 게 아니라 너무 오래 버틴 거예요. 휴식이 단단한 힘을 되돌려 줄 거예요.")
        ),
        Card(
            name: copy("隱者", "은둔자"), symbol: "lightbulb.fill",
            keywords: copy("獨處・尋找・智慧", "고독 · 탐색 · 지혜"),
            uprightHeadline: copy("關掉通知半小時", "혼자만의 시간이 답을 줘요"),
            uprightMessage: copy("找個不被打擾的地方，把最近最煩的三件事寫下來。先處理排第一的。", "잠시 소음에서 벗어나 무엇을 정말 남기고 싶은지 들어 보세요. 내면의 등불은 이미 켜져 있어요."),
            reversedHeadline: copy("想夠久了，找人聊聊", "너무 오래 자신을 가두지 마세요"),
            reversedMessage: copy("挑一個不急著教你怎麼做的人。把事情說出口，就會知道自己卡在哪裡。", "충분히 생각했어요. 이제는 작은 연결이 필요해요. 안전하다고 느끼는 사람에게 마음을 말해 보세요.")
        ),
        Card(
            name: copy("命運之輪", "운명의 수레바퀴"), symbol: "arrow.trianglehead.2.clockwise.rotate.90",
            keywords: copy("轉機・循環・時機", "전환 · 순환 · 타이밍"),
            uprightHeadline: copy("事情要開始動了", "전환점이 가까워지고 있어요"),
            uprightMessage: copy("臨時邀請或改期不一定是麻煩。先看看新時間是不是反而更合適。", "정체는 영원하지 않아요. 갑자기 찾아오는 제안과 우연, 새로운 선택지를 눈여겨보세요."),
            reversedHeadline: copy("今天先配合一下節奏", "잠시 흐름을 받아들여요"),
            reversedMessage: copy("改不了時間，就改準備方式。把能先做的做完，別一直催結果。", "어떤 변화는 재촉할 수 없어요. 통제할 수 있는 부분을 잘 해두고 나머지는 자연스럽게 움직이게 두세요.")
        ),
        Card(
            name: copy("正義", "정의"), symbol: "scalemass.fill",
            keywords: copy("事實・平衡・選擇", "사실 · 균형 · 선택"),
            uprightHeadline: copy("先把事實列出來", "사실과 균형으로 돌아가요"),
            uprightMessage: copy("把已知、猜測和情緒分成三欄。今天的決定只看第一欄。", "감정과 근거를 나누어 보고 오래도록 공정한 결정을 내려 보세요. 명확함이 평온을 가져와요."),
            reversedHeadline: copy("你可能只看了一邊", "편견이 판단을 흔들고 있어요"),
            reversedMessage: copy("找一條會推翻你原本想法的資料。看完再決定，會少很多後悔。", "자신에게 유리하거나 불리한 한쪽만 보고 있을 수 있어요. 빠진 정보를 채운 뒤 결정하세요.")
        ),
        Card(
            name: copy("倒吊人", "매달린 사람"), symbol: "figure.yoga",
            keywords: copy("暫停・轉念・放下", "멈춤 · 관점 · 내려놓음"),
            uprightHeadline: copy("把問題倒過來看", "관점을 바꾸면 출구가 보여요"),
            uprightMessage: copy("問問自己：如果今天不能照原計畫做，還有哪個結果可以接受？", "지금의 멈춤은 낭비가 아니에요. 기존 해법을 내려놓으면 새로운 관점이 자라나요."),
            reversedHeadline: copy("別再無限期等", "끝없는 기다림을 멈춰요"),
            reversedMessage: copy("替這件事設一個最後期限。到時沒有回覆，就照你的備案走。", "기다림이 더는 새 답을 주지 않아요. 기한을 정해 다시 선택권을 가져오세요.")
        ),
        Card(
            name: copy("死神", "죽음"), symbol: "leaf.fill",
            keywords: copy("結束・蛻變・更新", "끝 · 변화 · 새로움"),
            uprightHeadline: copy("該收尾了", "끝이 새로움을 위한 자리를 만들어요"),
            uprightMessage: copy("取消一個不會再去的約、刪掉一份不用的草稿。今天適合處理拖很久的結尾。", "어떤 단계는 이미 역할을 다했어요. 진심으로 작별해야 새로운 공간이 생겨나요."),
            reversedHeadline: copy("先丟掉一小部分", "놓는다고 모든 것을 잃는 건 아니에요"),
            reversedMessage: copy("一下子放不下也沒關係。先收掉最占空間、又最少用到的那一樣。", "필요한 것이 아니라 익숙함을 붙잡고 있을 수 있어요. 아주 작은 부분부터 놓아 보세요.")
        ),
        Card(
            name: copy("節制", "절제"), symbol: "slider.horizontal.3",
            keywords: copy("調和・節奏・療癒", "조화 · 리듬 · 회복"),
            uprightHeadline: copy("一次調一點就好", "천천히 조율할수록 단단해져요"),
            uprightMessage: copy("作息、花費或工作量，今天只改一個數字。改太多很快就會放棄。", "한 번에 전부 바꿀 필요는 없어요. 작지만 꾸준한 조정이 삶을 편안한 균형으로 돌려놔요."),
            reversedHeadline: copy("哪裡太多了？", "불균형은 소모를 줄이라는 신호예요"),
            reversedMessage: copy("看最近三天，哪件事最耗時間卻沒什麼結果。先把它減半。", "어딘가에 너무 많이 주거나 너무 적게 주고 있어요. 가장 소모적인 한 가지의 비중부터 줄여 보세요.")
        ),
        Card(
            name: copy("惡魔", "악마"), symbol: "link",
            keywords: copy("束縛・慾望・覺察", "속박 · 욕망 · 자각"),
            uprightHeadline: copy("先承認自己捨不得", "무엇이 나를 묶는지 바라봐요"),
            uprightMessage: copy("明知道不合適還一直回去，多半是某個好處沒放下。把那個好處說清楚。", "습관과 두려움, 유혹이 선택을 이끌고 있어요. 솔직히 바라보는 순간 사슬이 느슨해지기 시작해요."),
            reversedHeadline: copy("換個小習慣試試", "선택권을 되찾고 있어요"),
            reversedMessage: copy("今天只改一次反應：晚五分鐘回、少買一樣，或先拒絕一次。", "오래된 의존이 힘을 잃고 있어요. 작은 새 선택 하나로 이제 달라질 수 있음을 보여 주세요.")
        ),
        Card(
            name: copy("高塔", "탑"), symbol: "bolt.fill",
            keywords: copy("真相・震動・重建", "진실 · 충격 · 재건"),
            uprightHeadline: copy("計畫有變，先救重要的", "진실이 새로운 공간을 만들어요"),
            uprightMessage: copy("先保住時間、錢或關係裡最不能丟的那一項。其他安排晚點再補。", "갑작스러운 변화가 계획을 흔들 수 있지만 불안정한 부분도 드러내 줘요. 가장 중요한 핵심부터 지키세요."),
            reversedHeadline: copy("早點修，比撐到壞掉好", "약한 구조를 억지로 붙들지 마세요"),
            reversedMessage: copy("你已經知道哪裡不牢。今天先動一個小地方，別等問題自己爆開。", "어떤 일이 오래 버티지 못할 거라는 걸 이미 느꼈어요. 지금 먼저 조정하면 억지로 바뀌는 것보다 부드러워요.")
        ),
        Card(
            name: copy("星星", "별"), symbol: "star.fill",
            keywords: copy("希望・療癒・信任", "희망 · 치유 · 신뢰"),
            uprightHeadline: copy("先做一件讓你安心的小事", "작은 희망을 믿어도 좋아요"),
            uprightMessage: copy("回覆那封拖著的信、訂好時間，或把需要的資料找齊。希望要有一個落點。", "당장 완성되지는 않아도 방향이 밝아지고 있어요. 숨을 깊게 만드는 그 소망을 간직하세요."),
            reversedHeadline: copy("今天不用硬撐樂觀", "희망에 에너지를 채워요"),
            reversedMessage: copy("失望就承認失望。先把今天過完，明天再決定要不要繼續。", "실망 때문에 잠시 빛이 보이지 않아요. 억지로 낙관하지 말고 신뢰를 회복할 작은 일 하나부터 해보세요.")
        ),
        Card(
            name: copy("月亮", "달"), symbol: "moon.fill",
            keywords: copy("夢境・直覺・迷霧", "꿈 · 직감 · 안개"),
            uprightHeadline: copy("資訊還不夠，再等等", "직감이 말을 걸고 있어요"),
            uprightMessage: copy("今天聽到的話先別全信，也不用立刻反駁。等第二個來源再判斷。", "정보가 아직 모이는 중이에요. 행동하기 전에 관찰하고 반복되는 생각과 꿈, 우연한 만남을 눈여겨보세요."),
            reversedHeadline: copy("把害怕和事實分開寫", "두려움과 사실을 나눠 봐요"),
            reversedMessage: copy("最壞的情況不等於最可能的情況。列出已確認的三件事，再看一次。", "안개가 걷히고 있지만 불안이 최악의 상상을 키울 수 있어요. 확인된 사실을 적어 보면 답이 선명해져요.")
        ),
        Card(
            name: copy("太陽", "태양"), symbol: "sun.max.fill",
            keywords: copy("明亮・成功・活力", "빛 · 성공 · 활력"),
            uprightHeadline: copy("今天可以高調一點", "당신의 빛을 보여 주세요"),
            uprightMessage: copy("做完的事就拿出來，不用再改到沒人看見。也可以直接告訴對方你很喜歡。", "명확함과 활력이 돌아오고 있어요. 성과와 기쁨을 나누면 행복이 더 크게 번져요."),
            reversedHeadline: copy("不開心就別裝", "행복을 억지로 연기하지 않아도 돼요"),
            reversedMessage: copy("今天不用負責炒熱氣氛。累了就早點走，理由不用講得很漂亮。", "겉으로 밝다고 지칠 수 없는 건 아니에요. 작은 서운함을 인정해야 진짜 빛이 돌아올 자리가 생겨요.")
        ),
        Card(
            name: copy("審判", "심판"), symbol: "bell.fill",
            keywords: copy("覺醒・回應・更新", "깨어남 · 응답 · 갱신"),
            uprightHeadline: copy("這件事該回覆了", "마음속 부름에 응답해요"),
            uprightMessage: copy("拖著不答，其實也是一種回答。今天選「要」或「不要」，別再留在草稿裡。", "다음 걸음이 무엇인지 이미 알고 있어요. 이제 준비되었다고 인정하면 돼요. 과거를 족쇄가 아닌 경험으로 남기세요."),
            reversedHeadline: copy("別拿以前的失誤判今天", "과거로 자신을 정의하지 마세요"),
            reversedMessage: copy("情況變了，你也不是當時的你。先按現在手上的資訊做一次判斷。", "과거의 실수가 다시 선택하기 두렵게 만들 수 있어요. 지금의 당신에게는 그때 없던 이해가 있어요.")
        ),
        Card(
            name: copy("世界", "세계"), symbol: "globe.asia.australia.fill",
            keywords: copy("完成・整合・圓滿", "완성 · 통합 · 충만"),
            uprightHeadline: copy("可以收尾了", "하나의 여정이 완성되고 있어요"),
            uprightMessage: copy("把最後一封信寄出、最後一項勾掉，然後停手。今天不用再加新東西。", "걸어온 모든 발걸음이 하나의 그림으로 이어지고 있어요. 잠시 멈춰 자신의 성장을 인정해 주세요."),
            reversedHeadline: copy("還差最後一輪檢查", "완성 전에 마지막 정리가 필요해요"),
            reversedMessage: copy("大方向已經完成。只檢查名字、日期和金額，別在最後一刻整個重做。", "끝에 아주 가까워요. 놓친 세부를 돌아보고 채우면 편안하게 다음 장으로 갈 수 있어요.")
        )
    ]
}
