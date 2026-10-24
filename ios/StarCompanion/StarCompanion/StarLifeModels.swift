import Foundation

enum WeeklyJourneyTask: String, CaseIterable, Identifiable, Codable {
    case wish
    case care
    case play

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .wish: "moon.stars.fill"
        case .care: "heart.fill"
        case .play: "gamecontroller.fill"
        }
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .wish: language.text("把一句話交給星星", "별에게 한마디 남기기", "Leave one thought with the stars")
        case .care: language.text("陪伴或養顧小星", "작은 별 돌보기", "Care for Little Star")
        case .play: language.text("完成一個遊戲關卡", "게임 스테이지 하나 완료", "Clear one game stage")
        }
    }
}

struct BedtimeWish: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let text: String
    let readyDateStamp: String
    let replyTemplateID: WishReplyTemplate
    var revealedAt: Date?

    func isReady(on date: Date = .now, calendar: Calendar = .current) -> Bool {
        SharedPlanet.todayStamp(for: date, calendar: calendar) >= readyDateStamp
    }
}

enum WishReplyTemplate: String, CaseIterable, Codable {
    case tinyStep
    case quietAnswer
    case softBoundary
    case sharedLight
    case restFirst
    case openWindow

    func text(in language: AppLanguage) -> String {
        switch self {
        case .tinyStep: language.text("先做一件很小的事就好。星星看得見你正在往前。", "아주 작은 일 하나만 해도 괜찮아요. 별은 당신이 앞으로 가고 있는 걸 알아요.", "One tiny step is enough. The stars can see that you're moving forward.")
        case .quietAnswer: language.text("答案可能沒有發光，但你心裡那個很安靜的念頭，已經靠得很近。", "답이 빛나지는 않아도, 마음속 가장 조용한 생각이 이미 답에 가까워요.", "The answer may not glow. Your quietest thought is already close to it.")
        case .softBoundary: language.text("今天也可以把一點力氣留給自己。溫柔不等於什麼都答應。", "오늘은 힘을 조금 나를 위해 남겨 두세요. 다정함은 모든 것을 받아주는 뜻이 아니에요.", "Save a little energy for yourself today. Kindness doesn't mean saying yes to everything.")
        case .sharedLight: language.text("你想念的人也許正在某個時刻想起你。先送出一句簡單的問候吧。", "그리운 사람도 어느 순간 당신을 떠올릴지 몰라요. 짧은 안부를 먼저 보내 보세요.", "Someone you miss may be thinking of you too. Try sending a simple hello.")
        case .restFirst: language.text("今天的任務可以只是好好休息。月亮會替你守著還沒完成的事。", "오늘의 할 일은 잘 쉬는 것뿐이어도 돼요. 달이 아직 남은 일을 잠시 지켜줄거예요.", "Rest can be today's whole task. The moon will keep watch over what remains.")
        case .openWindow: language.text("今天會有一個小窗口打開。不用急著跳出去，先看看新的光從哪裡進來。", "오늘 작은 창문 하나가 열릴 거예요. 서두르지 말고 새로운 빛이 어디서 들어오는지 보세요.", "A small window will open today. Don't rush through it; notice where the new light enters.")
        }
    }
}

struct WeeklyStoryProgress: Codable, Equatable {
    var weekID: String
    var completedTasks: Set<WeeklyJourneyTask>
    var revealedAt: Date?

    var isUnlocked: Bool { completedTasks.count == WeeklyJourneyTask.allCases.count }

    static func current(for date: Date = .now, calendar: Calendar = .current) -> WeeklyStoryProgress {
        WeeklyStoryProgress(weekID: weekStamp(for: date, calendar: calendar), completedTasks: [], revealedAt: nil)
    }

    static func weekStamp(for date: Date = .now, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 0)
    }
}

/// Story copy is derived from the existing week identifier and birth-sign
/// profile, so older saved progress remains fully compatible. Nothing in this
/// type is persisted; changing the app language simply renders the same
/// chapter in another language.
struct WeeklyZodiacStoryContent: Equatable {
    let id: String
    let lockedTitle: String
    let title: String
    let body: String
    let ending: String

    static func make(
        zodiac: ZodiacSign?,
        weekID: String,
        language: AppLanguage
    ) -> WeeklyZodiacStoryContent {
        let zodiacValue = zodiac?.rawValue ?? ZodiacSign.allCases.count
        let index = positiveModulo(
            weekSerial(for: weekID) + zodiacValue,
            divisor: WeeklyStoryChapter.all.count
        )
        let chapter = WeeklyStoryChapter.all[index]
        let opening = zodiac?.weeklyStoryOpening ?? .init(
            traditionalChinese: "今晚的星圖少了一顆名字。小星沒有急著補上，只先在旁邊畫了一個小小的座位給你。",
            korean: "오늘 밤 별자리에는 이름 하나가 비어 있어요. 작은 별은 서둘러 채우지 않고, 그 옆에 당신이 앉을 작은 자리를 먼저 그렸어요.",
            english: "Tonight's star map is missing one name. Little Star didn't rush to fill it in; first, it drew a small seat for you beside the empty space."
        )
        let zodiacName = zodiac?.title(in: language)
        let titlePrefix = zodiacName ?? language.text("小星", "작은 별", "Little Star")

        return WeeklyZodiacStoryContent(
            id: "\(weekID):\(zodiacValue):\(chapter.id)",
            lockedTitle: chapter.lockedTitle.text(in: language),
            title: language.text(
                "\(titlePrefix)與\(chapter.title.traditionalChinese)",
                "\(titlePrefix), \(chapter.title.korean)",
                "\(titlePrefix) and \(chapter.title.english)"
            ),
            body: opening.text(in: language) + " " + chapter.body.text(in: language),
            ending: chapter.ending.text(in: language)
        )
    }

    private static func weekSerial(for weekID: String) -> Int {
        let parts = weekID.components(separatedBy: "-W")
        if parts.count == 2,
           let year = Int(parts[0]),
           let week = Int(parts[1]) {
            // ISO years can contain week 53. This keeps adjacent ISO weeks on
            // adjacent story variants, including the W53 -> W01 boundary.
            return year * 53 + week
        }

        let fallback = weekID.utf8.reduce(UInt64(2_166_136_261)) { value, byte in
            (value ^ UInt64(byte)) &* 16_777_619
        }
        return Int(fallback % UInt64(Int.max))
    }

    private static func positiveModulo(_ value: Int, divisor: Int) -> Int {
        let remainder = value % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }
}

private struct WeeklyStoryLine {
    let traditionalChinese: String
    let korean: String
    let english: String

    func text(in language: AppLanguage) -> String {
        language.text(traditionalChinese, korean, english)
    }
}

private struct WeeklyStoryChapter {
    let id: String
    let lockedTitle: WeeklyStoryLine
    let title: WeeklyStoryLine
    let body: WeeklyStoryLine
    let ending: WeeklyStoryLine

    static let all: [WeeklyStoryChapter] = [
        WeeklyStoryChapter(
            id: "sleeping-compass",
            lockedTitle: .init(
                traditionalChinese: "指南針今天不說話",
                korean: "오늘은 나침반이 말이 없어요",
                english: "The Compass Is Quiet Today"
            ),
            title: .init(
                traditionalChinese: "睡著的指南針",
                korean: "잠든 나침반",
                english: "the Sleeping Compass"
            ),
            body: .init(
                traditionalChinese: "望遠鏡旁的指南針忽然不轉了。小星試過敲一敲、吹一吹，最後把這週完成的三件小事排在桌上。原來方向沒有不見，只是藏在走過的路裡。",
                korean: "망원경 옆 나침반이 갑자기 멈췄어요. 작은 별은 톡톡 두드리고 입김도 불어 봤지만, 결국 이번 주에 지킨 세 가지 작은 약속을 책상 위에 놓았어요. 방향은 사라진 게 아니라 지나온 길 속에 숨어 있었어요.",
                english: "The compass beside the telescope suddenly stopped. Little Star tapped it and blew on it, then placed this week's three small promises across the desk. The direction hadn't vanished; it was tucked inside the path already traveled."
            ),
            ending: .init(
                traditionalChinese: "下一步不用很遠，先走到看得見的那顆星。",
                korean: "다음 걸음은 멀지 않아도 돼요. 지금 보이는 별까지 가 봐요.",
                english: "The next step doesn't have to be far. Walk toward the star you can already see."
            )
        ),
        WeeklyStoryChapter(
            id: "pocket-planet",
            lockedTitle: .init(
                traditionalChinese: "口袋裡好像有東西在發亮",
                korean: "주머니 안에서 무언가 반짝여요",
                english: "Something Is Glowing in a Pocket"
            ),
            title: .init(
                traditionalChinese: "口袋裡的小行星",
                korean: "주머니 속 작은 행성",
                english: "the Pocket-Sized Planet"
            ),
            body: .init(
                traditionalChinese: "小星整理外套時，從口袋摸出三顆圓圓的光。一顆裝著願望，一顆留著被照顧過的溫度，最後一顆還在笑。三顆光碰在一起，變成了指甲大小的小行星。",
                korean: "작은 별이 외투를 정리하다 주머니에서 동그란 빛 세 개를 찾았어요. 하나에는 소원이, 하나에는 돌봄의 온기가, 마지막 하나에는 게임을 마친 웃음이 들어 있었어요. 세 빛은 맞닿자 손톱만 한 행성이 되었어요.",
                english: "While tidying its coat, Little Star found three round lights in a pocket. One held a wish, one kept the warmth of being cared for, and the last was still laughing after a game. When they touched, they became a planet no bigger than a fingernail."
            ),
            ending: .init(
                traditionalChinese: "小星把口袋扣好。明天出門時，它還會帶著這三顆光。",
                korean: "작은 별은 주머니 단추를 꼭 잠갔어요. 내일도 세 빛을 데리고 나갈 거래요.",
                english: "Little Star fastened the pocket. It plans to carry all three lights again tomorrow."
            )
        ),
        WeeklyStoryChapter(
            id: "late-comet",
            lockedTitle: .init(
                traditionalChinese: "有顆彗星還沒趕到",
                korean: "아직 도착하지 않은 혜성이 있어요",
                english: "One Comet Hasn't Arrived Yet"
            ),
            title: .init(
                traditionalChinese: "慢半拍的彗星",
                korean: "한 박자 늦은 혜성",
                english: "the Late Little Comet"
            ),
            body: .init(
                traditionalChinese: "小星等著約好的彗星，坐在窗邊等到打起瞌睡。你們這週完成的三個約定依次亮起後，遠處終於有一條短短的尾巴匆忙跑來。它說，自己一路看著那三盞光，才沒有迷路。",
                korean: "작은 별은 약속한 혜성을 기다리며 창가에서 졸기 시작했어요. 당신과 지킨 세 가지 약속이 차례로 빛나자, 멀리서 꼬리가 짧은 혜성이 헐레벌떡 달려왔어요. 길을 잃지 않도록 그 빛을 보고 왔대요.",
                english: "Little Star waited by the window for a comet until it began to doze. When your three promises lit one after another, a short-tailed comet finally hurried in from far away. It said those three lights kept it from getting lost."
            ),
            ending: .init(
                traditionalChinese: "彗星遲到了。小星還是很得意，因為自己真的等到了。",
                korean: "혜성은 늦었어요. 그래도 작은 별은 끝까지 기다린 일을 무척 자랑스러워했어요.",
                english: "The comet was late. Little Star was still proud that it had truly waited."
            )
        ),
        WeeklyStoryChapter(
            id: "observatory-rain",
            lockedTitle: .init(
                traditionalChinese: "觀測台正在下雨",
                korean: "오늘 관측소에는 비가 와요",
                english: "Rain Is Falling on the Observatory"
            ),
            title: .init(
                traditionalChinese: "屋頂上的星星雨",
                korean: "지붕 위의 별비",
                english: "the Starlight Rain"
            ),
            body: .init(
                traditionalChinese: "雲把望遠鏡遮住了，今晚一顆星也看不見。小星垂著頭走下階梯，卻在三個水窪裡看見亮光。這週完成的三個小約定，正好一個映在一個裡面。",
                korean: "구름이 망원경을 가려 오늘은 별을 하나도 볼 수 없었어요. 작은 별이 풀이 죽어 계단을 내려가다 물웅덩이 세 개에서 반짝이는 빛을 발견했어요. 이번 주의 세 약속이 하나씩 빗물에 비치고 있었어요.",
                english: "Clouds covered the telescope, and not one star was visible. Little Star trudged down the steps and found three lights in three puddles. Each one reflected a small promise completed this week."
            ),
            ending: .init(
                traditionalChinese: "小星踩進最亮的水窪。襪子濕了，卻笑得很大聲。",
                korean: "작은 별은 가장 밝은 물웅덩이를 밟았어요. 양말은 젖었지만 웃음은 아주 컸어요.",
                english: "Little Star stepped into the brightest puddle. Its socks got wet, and it laughed very loudly."
            )
        ),
        WeeklyStoryChapter(
            id: "moon-train-seat",
            lockedTitle: .init(
                traditionalChinese: "月亮列車多留了一個座位",
                korean: "달빛 열차에 빈자리가 하나 있어요",
                english: "The Moon Train Saved One Seat"
            ),
            title: .init(
                traditionalChinese: "月亮列車的空位",
                korean: "달빛 열차의 빈자리",
                english: "the Empty Seat on the Moon Train"
            ),
            body: .init(
                traditionalChinese: "車掌問那個空位要留給誰，小星把這週收集的三個約定當成車票遞出去。它說，這是留給那個說了願望、照顧過彼此，也認真玩完一局的我們。",
                korean: "차장이 빈자리의 주인을 묻자 작은 별은 이번 주에 모은 약속 세 장을 표처럼 내밀었어요. 그리고 그 자리는 소원을 말하고, 서로를 돌보고, 한 판을 끝까지 마친 우리 자리라고 대답했어요.",
                english: "When the conductor asked who the empty seat was for, Little Star offered this week's three promises as tickets. It said the seat belonged to the two of you who shared a wish, cared for each other, and finished a game."
            ),
            ending: .init(
                traditionalChinese: "列車開動以後，那個座位一直暖暖的。",
                korean: "열차가 출발한 뒤에도 그 자리는 오래도록 따뜻했어요.",
                english: "Long after the train set off, the seat stayed warm."
            )
        ),
        WeeklyStoryChapter(
            id: "unnamed-star-sprout",
            lockedTitle: .init(
                traditionalChinese: "花盆裡埋著一點亮光",
                korean: "화분 속에 작은 빛이 묻혀 있어요",
                english: "A Small Light Is Buried in the Pot"
            ),
            title: .init(
                traditionalChinese: "還沒取名的星芽",
                korean: "아직 이름 없는 별싹",
                english: "the Star Sprout Without a Name"
            ),
            body: .init(
                traditionalChinese: "小星把上週撿到的種子埋進花盆，每天都趴在旁邊看。它一直沒有動靜，直到第三個小約定完成，一片淡紫色的葉子才從土裡探出頭。",
                korean: "작은 별은 지난주에 주운 씨앗을 화분에 심고 매일 들여다봤어요. 아무 소식이 없더니 세 번째 약속을 마친 순간, 흙 사이로 연보라빛 잎 하나가 고개를 내밀었어요.",
                english: "Little Star planted a seed it found last week and checked the pot every day. Nothing happened until the third small promise was complete, when one pale violet leaf poked through the soil."
            ),
            ending: .init(
                traditionalChinese: "小星決定先不取名字。等它再長一片葉子，再問一次。",
                korean: "작은 별은 이름을 조금 더 기다리기로 했어요. 잎이 한 장 더 자라면 다시 물어볼 거래요.",
                english: "Little Star decided to wait before naming it. It will ask again after one more leaf grows."
            )
        ),
    ]
}

private extension ZodiacSign {
    var weeklyStoryOpening: WeeklyStoryLine {
        switch self {
        case .capricorn:
            .init(
                traditionalChinese: "摩羯座在山坡上排好六塊小石頭。小星想一次跳到頂，你卻陪它從最矮的那塊開始。",
                korean: "염소자리가 언덕길에 작은 돌 여섯 개를 가지런히 놓았어요. 작은 별은 단숨에 꼭대기까지 뛰고 싶어 했지만, 당신은 가장 낮은 돌부터 함께 밟았어요.",
                english: "Capricorn lined six small stones along the hill. Little Star wanted to leap straight to the top, but you started together on the lowest one."
            )
        case .aquarius:
            .init(
                traditionalChinese: "水瓶座把一瓶藍色的風擱在窗邊。瓶塞一打開，房裡那些太久沒動的想法全飄了起來。",
                korean: "물병자리가 파란 바람 한 병을 창가에 두었어요. 마개를 열자 방 안에서 오래 멈춰 있던 생각들이 하나둘 떠올랐어요.",
                english: "Aquarius left a bottle of blue wind by the window. When the cork came out, ideas that had sat still for too long began floating around the room."
            )
        case .pisces:
            .init(
                traditionalChinese: "雙魚座的星河漂來一封字跡暈開的信。小星看不清每個字，卻先讀懂了那份想念。",
                korean: "물고기자리의 별강에서 글씨가 번진 편지 한 통이 떠내려왔어요. 작은 별은 모든 글자를 읽지는 못했지만, 그리운 마음은 먼저 알아봤어요.",
                english: "A letter with blurred ink drifted down Pisces' starry river. Little Star couldn't read every word, but it understood the missing-someone part first."
            )
        case .aries:
            .init(
                traditionalChinese: "牡羊座提早點亮了起跑燈。小星衝出去兩步，又回頭拉住你的手，這次它想和你一起到。",
                korean: "양자리가 출발 신호를 조금 일찍 켰어요. 두 걸음 먼저 달려간 작은 별은 다시 돌아와 당신의 손을 잡았어요. 이번에는 같이 도착하고 싶대요.",
                english: "Aries switched on the starting light early. Little Star dashed two steps ahead, then came back for your hand. This time, it wanted to arrive together."
            )
        case .taurus:
            .init(
                traditionalChinese: "金牛座把熱牛奶和一小塊餅乾放在月亮盤上。小星原本急著趕路，聞到香氣後決定先坐五分鐘。",
                korean: "황소자리가 따뜻한 우유와 작은 쿠키를 달빛 접시에 올려 두었어요. 서둘러 길을 나서려던 작은 별은 고소한 냄새를 맡고 딱 5분만 앉기로 했어요.",
                english: "Taurus set warm milk and a small cookie on a moon-shaped plate. Little Star had been rushing out, but the smell convinced it to sit for five minutes first."
            )
        case .gemini:
            .init(
                traditionalChinese: "雙子座送來兩張答案完全不同的紙條。小星讀完沒有選邊，只把兩張都折進口袋裡。",
                korean: "쌍둥이자리가 서로 전혀 다른 답이 적힌 쪽지 두 장을 보냈어요. 작은 별은 어느 쪽도 고르지 않고 둘 다 접어 주머니에 넣었어요.",
                english: "Gemini sent two notes with completely different answers. Little Star chose neither; it folded both and slipped them into a pocket."
            )
        case .cancer:
            .init(
                traditionalChinese: "巨蟹座在門邊掛了一盞小燈，只照回家的那一段路。小星晚歸時，一眼就找到你留的位置。",
                korean: "게자리가 문 옆에 집으로 돌아오는 길만 비추는 작은 등을 달았어요. 늦게 돌아온 작은 별은 당신이 남겨 둔 자리를 한눈에 찾았어요.",
                english: "Cancer hung a small lamp beside the door, lighting only the last stretch home. When Little Star returned late, it immediately found the place you had saved."
            )
        case .leo:
            .init(
                traditionalChinese: "獅子座把舞台燈分了一半給小星。它第一次沒有躲在幕後，還記得把最亮的位置留給你。",
                korean: "사자자리가 무대 조명의 절반을 작은 별에게 나눠 줬어요. 작은 별은 처음으로 커튼 뒤에 숨지 않았고, 가장 밝은 자리는 당신에게 남겨 두었어요.",
                english: "Leo gave Little Star half the stage lights. For once it didn't hide behind the curtain, and it remembered to save the brightest spot for you."
            )
        case .virgo:
            .init(
                traditionalChinese: "處女座在星圖角落發現一個小墨點。小星擦了半天沒擦掉，索性在旁邊畫了一朵花。",
                korean: "처녀자리가 별자리 지도 구석에서 작은 잉크 자국을 발견했어요. 작은 별은 한참 지워도 없어지지 않자, 바로 옆에 꽃 한 송이를 그렸어요.",
                english: "Virgo found a small ink spot in the corner of the star map. Little Star rubbed at it for ages, then simply drew a flower beside it."
            )
        case .libra:
            .init(
                traditionalChinese: "天秤座的銀色秤盤一邊放著約定，一邊放著休息。小星看了很久，最後兩邊都沒有拿走。",
                korean: "천칭자리의 은빛 저울에는 한쪽에 약속이, 다른 쪽에 휴식이 놓여 있었어요. 작은 별은 오래 바라보다가 결국 어느 쪽도 내려놓지 않았어요.",
                english: "Libra's silver scales held a promise on one side and rest on the other. Little Star watched for a long time and finally left both exactly where they were."
            )
        case .scorpio:
            .init(
                traditionalChinese: "天蠍座把一句沒說出口的話收進黑曜石盒。小星沒有追問，只在盒子旁放了一顆暖暖的燈。",
                korean: "전갈자리가 꺼내지 못한 말 한마디를 흑요석 상자에 넣었어요. 작은 별은 묻지 않고 상자 옆에 따뜻한 등을 하나 두었어요.",
                english: "Scorpio tucked an unsaid sentence into an obsidian box. Little Star didn't ask questions; it placed a warm lamp beside the box."
            )
        case .sagittarius:
            .init(
                traditionalChinese: "射手座寄來一張沒有終點的星際車票。小星先圈起一個陌生站名，說走到那裡再決定下一站。",
                korean: "사수자리가 종착역이 없는 우주 열차표를 보냈어요. 작은 별은 낯선 역 하나에 동그라미를 치고, 거기 도착한 뒤 다음 역을 정하자고 했어요.",
                english: "Sagittarius sent a space-train ticket with no final stop. Little Star circled one unfamiliar station and said the next choice could wait until you got there."
            )
        }
    }
}

enum StarFurniture: String, CaseIterable, Identifiable, Codable {
    case telescope
    case moonBed
    case stardustGarden

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .telescope: "scope"
        case .moonBed: "moon.zzz.fill"
        case .stardustGarden: "camera.macro"
        }
    }
    var price: Int {
        switch self {
        case .telescope: 80
        case .moonBed: 120
        case .stardustGarden: 100
        }
    }
    func title(in language: AppLanguage) -> String {
        switch self {
        case .telescope: language.text("星象望遠鏡", "별자리 망원경", "Celestial Telescope")
        case .moonBed: language.text("月亮雲床", "달빛 구름 침대", "Moon Cloud Bed")
        case .stardustGarden: language.text("星塵花園", "별가루 정원", "Stardust Garden")
        }
    }
    func effect(in language: AppLanguage) -> String {
        switch self {
        case .telescope: language.text("抽牌時會出現更多星象光軌。", "카드를 뽑을 때 별자리 빛 연출이 풍성해져요.", "Adds richer constellation trails to card draws.")
        case .moonBed: language.text("隔天可多養一次小星。", "다음 날 작은 별에게 한 번 더 먹일 수 있어요.", "Allows one extra feeding the next day.")
        case .stardustGarden: language.text("每天長出 12 點星塵。", "매일 별가루 12개가 자라요.", "Grows 12 Stardust each day.")
        }
    }
}

enum StarRoomTheme: String, CaseIterable, Identifiable, Codable {
    case observatoryGarden
    case moonRabbitFestival
    case halloweenGhostNight
    case christmasSnowRoom

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .observatoryGarden: "sparkles"
        case .moonRabbitFestival: "hare.fill"
        case .halloweenGhostNight: "theatermasks.fill"
        case .christmasSnowRoom: "snowflake"
        }
    }
    func title(in language: AppLanguage) -> String {
        switch self {
        case .observatoryGarden: language.text("星象花園", "별자리 정원", "Observatory Garden")
        case .moonRabbitFestival: language.text("中秋月兔庭院", "중추절 달토끼 마당", "Moon Rabbit Festival")
        case .halloweenGhostNight: language.text("萬聖幽靈星夜", "할로윈 유령 별밤", "Halloween Ghost Night")
        case .christmasSnowRoom: language.text("聖誕雪花房間", "크리스마스 눈꽃 방", "Christmas Snow Room")
        }
    }
    func isInSeason(on date: Date = .now, calendar: Calendar = .current) -> Bool {
        let month = calendar.component(.month, from: date)
        return switch self {
        case .observatoryGarden: true
        case .moonRabbitFestival: month == 9 || month == 10
        case .halloweenGhostNight: month == 10
        case .christmasSnowRoom: month == 12
        }
    }
}

struct HomeVisitRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let visitorAlias: String
    let visitedAt: Date
    let stardustAmount: Int
    let receiptID: UUID?
    let reactionID: String?

    init(
        id: UUID,
        visitorAlias: String,
        visitedAt: Date,
        stardustAmount: Int,
        receiptID: UUID? = nil,
        reactionID: String? = nil
    ) {
        self.id = id
        self.visitorAlias = visitorAlias
        self.visitedAt = visitedAt
        self.stardustAmount = stardustAmount
        self.receiptID = receiptID
        self.reactionID = reactionID
    }
}

struct StarHomeState: Codable, Equatable {
    var stardust: Int?
    var ownedFurniture: Set<StarFurniture>?
    var placedFurniture: Set<StarFurniture>?
    var selectedRoomTheme: StarRoomTheme?
    var ownedRoomThemes: Set<StarRoomTheme>?
    var visits: [HomeVisitRecord]?
    var lastGardenHarvestDate: String?
    var moonBedBonusDate: String?
    var moonBedBonusUsedDate: String?

    static let starter = StarHomeState(
        stardust: 60,
        ownedFurniture: [],
        placedFurniture: [],
        selectedRoomTheme: .observatoryGarden,
        ownedRoomThemes: [.observatoryGarden],
        visits: [],
        lastGardenHarvestDate: nil,
        moonBedBonusDate: nil,
        moonBedBonusUsedDate: nil
    )
}

struct GentleDayState: Codable, Equatable {
    var selectedDateStamp: String?
    var interactionUsedDateStamp: String?
}

struct StarLifeState: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int?
    var wishes: [BedtimeWish]?
    var weeklyStory: WeeklyStoryProgress?
    var home: StarHomeState?
    var gentleDay: GentleDayState?
    var visitExchange: HomeVisitExchangeState? = nil

    static func seeded() -> StarLifeState {
        StarLifeState(
            schemaVersion: currentSchemaVersion,
            wishes: [],
            weeklyStory: .current(),
            home: .starter,
            gentleDay: GentleDayState(),
            visitExchange: .seeded()
        )
    }

    func migrated(now: Date = .now, calendar: Calendar = .current) -> StarLifeState {
        var state = self
        state.schemaVersion = Self.currentSchemaVersion
        state.wishes = Array((state.wishes ?? []).prefix(90))
        let currentWeek = WeeklyStoryProgress.weekStamp(for: now, calendar: calendar)
        if state.weeklyStory?.weekID != currentWeek {
            state.weeklyStory = .current(for: now, calendar: calendar)
        }
        var home = state.home ?? .starter
        home.stardust = min(9_999, max(0, home.stardust ?? 0))
        home.ownedFurniture = home.ownedFurniture ?? []
        home.placedFurniture = (home.placedFurniture ?? []).intersection(home.ownedFurniture ?? [])
        home.selectedRoomTheme = home.selectedRoomTheme ?? .observatoryGarden
        home.ownedRoomThemes = home.ownedRoomThemes ?? [.observatoryGarden]
        home.ownedRoomThemes?.insert(.observatoryGarden)
        home.visits = Array((home.visits ?? []).prefix(30))
        state.home = home
        state.gentleDay = state.gentleDay ?? GentleDayState()
        state.visitExchange = (state.visitExchange ?? .seeded()).migrated(now: now, calendar: calendar)
        return state
    }
}

struct StarAppearanceSnapshot: Codable, Equatable, Hashable {
    var personaID: String?
    var auraID: String?
    var accessoryID: String?
    var roomThemeID: String?
    var moodID: String?
}
