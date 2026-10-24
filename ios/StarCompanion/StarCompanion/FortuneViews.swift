import Foundation
import SwiftUI

struct TodayFortuneView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedFortuneID: String?
    @State private var guidePresented = false
    @State private var guideReservation: DailyAccessReservation?

    let onAskUniverse: () -> Void

    private var fortunes: [DailyFortune] {
        [
            DailyFortune(
                id: "love",
                title: store.language.text("愛情", "사랑", "Love"),
                score: score(at: 0),
                symbol: "heart.fill",
                note: store.language.text("把真心說得輕一點，對方反而聽得更清楚。", "진심을 부드럽게 전하면 상대의 마음에도 더 선명하게 닿아요.", "Say what you mean gently. It may land more clearly that way.")
            ),
            DailyFortune(
                id: "work",
                title: store.language.text("工作", "일", "Work"),
                score: score(at: 1),
                symbol: "briefcase.fill",
                note: store.language.text("先完成最小的一步，卡住的事會開始轉動。", "가장 작은 한 걸음부터 마치면 막혀 있던 일이 움직이기 시작해요.", "Finish the smallest step first. The stuck parts will start moving.")
            ),
            DailyFortune(
                id: "money",
                title: store.language.text("財運", "재물", "Money"),
                score: score(at: 2),
                symbol: "sparkle",
                note: store.language.text("適合整理支出，不適合因情緒臨時購物。", "지출을 정리하기 좋은 날이에요. 기분에 따른 충동구매는 미뤄 두세요.", "A good day to review spending, not to shop on impulse.")
            ),
            DailyFortune(
                id: "mood",
                title: store.language.text("心情", "마음", "Mood"),
                score: score(at: 3),
                symbol: "cloud.fill",
                note: store.language.text("留一段不被打擾的時間，靈感會自己出現。", "방해받지 않는 시간을 남겨 두면 영감이 스스로 찾아와요.", "Leave a little quiet space. Inspiration may find you there.")
            ),
        ]
    }

    private var selectedFortune: DailyFortune? {
        fortunes.first(where: { $0.id == selectedFortuneID })
    }

    private var overallScore: Int {
        fortunes.map(\.score).reduce(0, +) / max(fortunes.count, 1)
    }

    private var dailySeed: Int {
        let day = Int(store.currentDayStamp.replacingOccurrences(of: "-", with: "")) ?? 0
        return day + (store.profile?.zodiac.rawValue ?? 0) * 97
    }

    private var dailyHeadline: String {
        let traditionalChinese = [
            "今天不趕，反而比較順",
            "行程別排滿，留點空位",
            "語氣放軟，事情會好談一點",
            "第一個直覺，先記下來",
        ]
        let korean = [
            "오늘은 천천히 갈수록 행운이 가까워져요",
            "작은 여백을 남기면 좋은 일이 다가와요",
            "당신의 다정함이 오늘의 힘이 되어 줄 거예요",
            "직감을 따라가면 별빛이 길을 비춰 줄 거예요",
        ]
        let english = [
            "Today flows better when you don't rush",
            "Leave a little room in your plans",
            "A softer tone may make things easier",
            "Write down your first instinct",
        ]
        let index = abs(dailySeed) % traditionalChinese.count
        return store.language.text(traditionalChinese[index], korean[index], english[index])
    }

    private var zodiacSource: String {
        let zodiac = store.profile?.zodiac.title(in: store.language)
            ?? store.language.text("你的星座", "당신의 별자리", "Your sign")
        return store.language.text(
            "\(zodiac)・今日星象・塔羅：星星",
            "\(zodiac) · 오늘의 별자리 · 타로: 별",
            "\(zodiac) · Today's sky · Tarot: The Star"
        )
    }

    private var todayGuide: DailyGuide {
        let variants = DailyGuideVariant.allCases
        let index = abs(dailySeed) % variants.count
        let variant = variants[index]
        let zodiac = store.profile?.zodiac
        let zodiacID = DailyGuideArchiveCatalog.zodiacID(for: zodiac)
        let zodiacName = DailyGuideArchiveCatalog.zodiacTitle(for: zodiacID, language: store.language)
            ?? store.language.text("旅行者", "여행자", "Traveler")
        let dateStamp = store.currentDayStamp
        let minute = 20 + abs(dailySeed % 35)

        return DailyGuide(
            id: "\(dateStamp)-\(store.profile?.zodiac.rawValue ?? -1)",
            dateStamp: dateStamp,
            zodiacName: zodiacName,
            cardName: store.language.text("星星", "별", "The Star"),
            title: variant.title(in: store.language),
            message: variant.message(in: store.language),
            luckyColor: variant.luckyColor(in: store.language),
            luckyTime: String(format: "20:%02d", minute),
            zodiacID: zodiacID,
            cardID: DailyGuideArchiveCatalog.starCardID,
            variantID: variant.rawValue
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    celestialHero
                    fortuneCard
                }
                .frame(maxWidth: horizontalSizeClass == .regular ? .infinity : 920)
                .padding(.horizontal, horizontalSizeClass == .regular ? 28 : 16)
                .padding(.bottom, 34)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { CelestialBackdrop().ignoresSafeArea() }
            .navigationTitle(
                horizontalSizeClass == .regular
                    ? ""
                    : store.language.text("今日運勢", "오늘의 운세", "Today's Fortune")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $guidePresented, onDismiss: cancelGuideReservation) {
                DailyGuideSheet(guide: todayGuide, reservation: guideReservation)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var celestialHero: some View {
        ZStack(alignment: .bottomLeading) {
            Image("StarHabitat")
                .resizable()
                .scaledToFill()
                .frame(height: horizontalSizeClass == .regular ? 300 : 220)
                .clipped()
                .accessibilityHidden(true)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.54)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(dateCopy)
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.76))
                Text(dailyHeadline)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }
            .padding(22)
        }
        .clipShape(.rect(cornerRadius: 28))
        .shadow(color: Color.fortunePlum.opacity(0.13), radius: 22, y: 10)
        .padding(.top, 12)
    }

    private var fortuneCard: some View {
        VStack(spacing: 20) {
            VStack(spacing: 3) {
                Text(store.language.text("綜合運勢", "종합 운세", "Overall"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(overallScore)")
                    .font(.system(size: 62, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.fortunePlum)
                    .contentTransition(.numericText())
                Text(store.language.text("順順走", "좋은 흐름", "Good flow"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.fortuneRose)
            }

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 9),
                    count: horizontalSizeClass == .regular ? 4 : 2
                ),
                spacing: 9
            ) {
                ForEach(fortunes) { fortune in
                    fortuneButton(fortune)
                }
            }

            Text(selectedFortune?.note ?? store.language.text("點一下分類，看今天的小提醒。", "항목을 눌러 오늘의 작은 메시지를 확인해 보세요.", "Tap a category for today's little note."))
                .font(.subheadline)
                .foregroundStyle(selectedFortune == nil ? .secondary : Color.fortuneInk)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(15)
                .background(Color.fortuneLavender.opacity(0.42), in: .rect(cornerRadius: 17))
                .animation(.easeInOut(duration: 0.2), value: selectedFortuneID)

            Label(
                zodiacSource,
                systemImage: "sparkles"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Button {
                presentDailyGuide()
            } label: {
                Label(
                    store.hasRevealedGuideToday && !store.hasMembership
                        ? store.language.text("查看今日指引", "오늘의 메시지 보기", "View today's guidance")
                        : store.language.text("翻開今日指引", "오늘의 메시지 펼치기", "Reveal today's guidance"),
                    systemImage: store.hasRevealedGuideToday && !store.hasMembership
                        ? "rectangle.portrait.fill"
                        : "rectangle.portrait.on.rectangle.portrait"
                )
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.fortunePlum)

            if !store.hasMembership {
                Label(
                    store.hasRevealedGuideToday
                        ? store.language.text("今天已翻過，明天會有一張新牌。", "오늘의 카드를 이미 펼쳤어요. 내일 새 카드가 와요.", "You've revealed today's card. A new one arrives tomorrow.")
                        : store.language.text("非會員每天可以翻 1 次。", "비회원은 하루에 한 번 펼칠 수 있어요.", "Without membership, you can reveal one card a day."),
                    systemImage: store.hasRevealedGuideToday ? "checkmark.circle.fill" : "clock"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button(action: onAskUniverse) {
                HStack(spacing: 12) {
                    Image("StarPet")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 52, height: 52)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.language.text("有件事拿不定主意？", "마음이 정해지지 않는 일이 있나요?", "Something on your mind?"))
                            .font(.subheadline.weight(.semibold))
                        Text(store.language.text("去抽一張牌", "카드 한 장 뽑기", "Draw a card"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                }
                .foregroundStyle(Color.fortuneInk)
                .padding(12)
                .background(Color.fortunePink.opacity(0.45), in: .rect(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .accessibilityHint(store.language.text("前往塔羅抽牌", "타로 카드 뽑기 화면으로 이동", "Open the tarot draw"))
        }
        .padding(horizontalSizeClass == .regular ? 28 : 20)
        .padding(.vertical, 26)
        .background(.background, in: .rect(cornerRadius: 28))
        .shadow(color: Color.fortunePlum.opacity(0.07), radius: 18, y: 7)
    }

    private func presentDailyGuide() {
        if store.hasRevealedGuideToday && !store.hasMembership {
            guideReservation = nil
            guidePresented = true
            return
        }

        guard let reservation = store.reserveDailyGuideReveal(dayStamp: todayGuide.dateStamp) else {
            return
        }
        guideReservation = reservation
        guidePresented = true
    }

    private func cancelGuideReservation() {
        if let guideReservation {
            store.cancelDailyAccess(guideReservation)
        }
        guideReservation = nil
    }

    private func fortuneButton(_ fortune: DailyFortune) -> some View {
        let isSelected = selectedFortuneID == fortune.id

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedFortuneID = isSelected ? nil : fortune.id
            }
        } label: {
            VStack(spacing: 7) {
                Image(systemName: fortune.symbol)
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : Color.fortuneRose)
                Text(fortune.title)
                    .font(.caption.weight(.semibold))
                Text("\(fortune.score)")
                    .font(.title3.bold())
                    .contentTransition(.numericText())
            }
            .foregroundStyle(isSelected ? .white : Color.fortuneInk)
            .frame(maxWidth: .infinity, minHeight: 104)
            .background(isSelected ? Color.fortunePlum : Color.fortunePink.opacity(0.34), in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityValue("\(fortune.score)")
        .accessibilityHint(fortune.note)
    }

    private func score(at index: Int) -> Int {
        let mixed = dailySeed &* (index * 17 + 31) &+ (index + 7) * 43
        return 68 + abs(mixed % 28)
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
}

struct AskUniverseView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTopicID: String?
    @State private var question = ""
    @State private var readingPresented = false
    @State private var currentReading: TarotReadingRecord?
    @State private var drawingReading: TarotReadingRecord?
    @State private var completedDraw: TarotReadingRecord?
    @State private var drawingReservation: DailyAccessReservation?
    @State private var drawCompletionRejected = false
    @State private var didStartPreviewRitual = false

    private var topics: [TarotTopic] {
        [
            TarotTopic(
                id: "wealth",
                title: store.language.text("財運", "재물", "Money"),
                english: "Wealth",
                detail: store.language.text("金錢與機會", "돈과 기회", "Money and opportunities"),
                symbol: "sparkle",
                placeholder: store.language.text("例如：最近適合做新的財務決定嗎？", "예: 요즘 새로운 재정 결정을 해도 좋을까요?", "For example: Is this a good time for a new financial decision?")
            ),
            TarotTopic(
                id: "love",
                title: store.language.text("桃花", "인연", "Love"),
                english: "Love",
                detail: store.language.text("緣分與關係", "인연과 관계", "Connection and relationships"),
                symbol: "heart.fill",
                placeholder: store.language.text("例如：近期會遇見適合的人嗎？", "예: 곧 나와 잘 맞는 사람을 만날까요?", "For example: Will I meet someone who feels right soon?")
            ),
            TarotTopic(
                id: "today",
                title: store.language.text("當日運勢", "오늘", "Today"),
                english: "Today",
                detail: store.language.text("今日整體能量", "오늘의 전체 에너지", "Today's overall energy"),
                symbol: "moon.stars.fill",
                placeholder: store.language.text("例如：今天最需要留意什麼？", "예: 오늘 가장 주의해야 할 것은 무엇인가요?", "For example: What should I pay attention to today?")
            ),
        ]
    }

    private var selectedTopic: TarotTopic? {
        topics.first(where: { $0.id == selectedTopicID })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image("LuckyStarTarot")
                        .resizable()
                        .scaledToFit()
                        .frame(width: horizontalSizeClass == .regular ? 230 : 168)
                        .shadow(color: Color.fortuneRose.opacity(0.24), radius: 20, y: 8)
                        .accessibilityLabel(store.language.text("抱著塔羅牌的小星", "타로 카드를 안고 있는 작은 별", "Little Star holding a tarot card"))

                    VStack(spacing: 7) {
                        Text(store.language.text("今天想看哪一種？", "오늘은 무엇을 볼까요?", "What would you like to explore?"))
                            .font(.title2.bold())
                        Text(store.language.text("選一個主題。想問得具體一點，也可以把問題寫下來。", "주제를 골라 보세요. 더 구체적으로 보고 싶다면 질문을 적어도 좋아요.", "Choose a topic. You can also write a question if you want something more specific."))
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.76))
                    }
                    .foregroundStyle(.white)

                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 10),
                            count: horizontalSizeClass == .regular ? 3 : 1
                        ),
                        spacing: 10
                    ) {
                        ForEach(topics) { topic in
                            topicButton(topic)
                        }
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text(store.language.text("想問得更具體嗎？", "조금 더 구체적으로 묻고 싶나요?", "Want to ask something specific?"))
                                .font(.subheadline.weight(.semibold))
                            Text(store.language.text("選填", "선택", "Optional"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        TextField(
                            selectedTopic?.placeholder ?? store.language.text("請先選擇上方的塔羅主題", "먼저 위에서 타로 주제를 선택해 주세요", "Choose a tarot topic above first"),
                            text: $question,
                            axis: .vertical
                        )
                        .lineLimit(3...5)
                        .disabled(selectedTopic == nil)
                        .textFieldStyle(.plain)
                        .padding(14)
                        .background(Color.fortuneLavender.opacity(0.34), in: .rect(cornerRadius: 16))
                        .onChange(of: question) { _, value in
                            if value.count > 80 {
                                question = String(value.prefix(80))
                            }
                        }

                        Text("\(question.count)/80")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(18)
                    .background(.background, in: .rect(cornerRadius: 22))

                    Button {
                        beginDrawing()
                    } label: {
                        Label(
                            !store.canDrawTarotToday
                                ? store.language.text("今天已經抽過了", "오늘은 이미 카드를 뽑았어요", "Today's card is already drawn")
                                : selectedTopic.map { store.language.text("開始抽「\($0.title)」", "‘\($0.title)’ 카드 뽑기", "Draw for \($0.title)") }
                                    ?? store.language.text("選擇主題後抽牌", "주제를 선택한 뒤 카드 뽑기", "Choose a topic to draw"),
                            systemImage: store.canDrawTarotToday ? "sparkles" : "checkmark.circle.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.fortunePlum)
                    .disabled(selectedTopic == nil || !store.canDrawTarotToday)

                    if !store.hasMembership {
                        Label(
                            store.hasDrawnTarotToday
                                ? store.language.text("非會員今天的 1 次已用完，明天再來問小星。", "비회원의 오늘 카드 1회를 사용했어요. 내일 작은 별에게 다시 물어보세요.", "Today's non-member draw is used. Ask Little Star again tomorrow.")
                                : store.language.text("非會員每天可以抽 1 次牌。", "비회원은 하루에 한 번 카드를 뽑을 수 있어요.", "Without membership, you can draw one card a day."),
                            systemImage: store.hasDrawnTarotToday ? "clock.badge.checkmark" : "clock"
                        )
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                    }

                    Label(
                        store.language.text("內容僅供娛樂與自我探索，不代替專業建議。", "내용은 오락과 자기 탐색을 위한 것이며 전문적인 조언을 대신하지 않습니다.", "For entertainment and self-reflection only. Not a substitute for professional advice."),
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))

                    if !store.readingHistory.isEmpty {
                        recentReadings
                    }
                }
                .frame(maxWidth: horizontalSizeClass == .regular ? 1180 : 860)
                .padding(.horizontal, horizontalSizeClass == .regular ? 28 : 16)
                .padding(.vertical, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { CelestialBackdrop().ignoresSafeArea() }
            .navigationTitle(
                horizontalSizeClass == .regular
                    ? ""
                    : store.language.text("塔羅", "타로", "Tarot")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(isPresented: $readingPresented) {
                if let currentReading {
                    ReadingDetailView(reading: currentReading)
                }
            }
            .fullScreenCover(item: $drawingReading, onDismiss: finishDrawingIfNeeded) { reading in
                TarotDrawView(
                    reading: reading,
                    onCancel: cancelDrawing,
                    onReveal: {
                        completedDraw = reading
                        drawingReading = nil
                    }
                )
            }
            .alert(
                store.language.text("這次抽牌沒有保存", "이번 카드 뽑기는 저장되지 않았어요", "This draw wasn't saved"),
                isPresented: $drawCompletionRejected
            ) {
                Button(store.language.text("知道了", "확인", "OK"), role: .cancel) {}
            } message: {
                Text(store.language.text(
                    "每日次數可能已在另一個視窗使用，或本機資料暫時無法安全保存。請回到頁面後再確認。",
                    "다른 창에서 오늘의 횟수를 이미 사용했거나 기기 데이터를 안전하게 저장하지 못했을 수 있어요. 화면으로 돌아가 다시 확인해 주세요.",
                    "The daily allowance may have been used in another window, or the on-device record couldn't be saved safely. Return to the page and check again."
                ))
            }
            .task { startPreviewRitualIfNeeded() }
        }
    }

    private func topicButton(_ topic: TarotTopic) -> some View {
        let isSelected = selectedTopicID == topic.id

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTopicID = topic.id
            }
        } label: {
            HStack(spacing: 13) {
                Image(systemName: topic.symbol)
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : Color.fortuneRose)
                    .frame(width: 40, height: 40)
                    .background(isSelected ? Color.white.opacity(0.15) : Color.fortunePink.opacity(0.58), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(topic.title).font(.headline)
                    Text(topic.detail)
                        .font(.caption)
                        .opacity(0.76)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            }
            .foregroundStyle(isSelected ? .white : Color.fortuneInk)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 86)
            .background(isSelected ? Color.fortunePlum : Color.white, in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var recentReadings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(store.language.text("最近抽過", "최근 뽑은 카드", "Recent readings"), systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    ReadingHistoryView()
                } label: {
                    Text(store.language.text("查看全部", "전체 보기", "See all"))
                        .font(.caption.weight(.semibold))
                }
            }

            ForEach(store.readingHistory.prefix(3)) { reading in
                NavigationLink {
                    ReadingDetailView(reading: reading)
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "envelope.open.fill")
                            .foregroundStyle(Color.celestialGold)
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.10), in: .circle)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(reading.localizedAnswer(in: store.language))
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text("\(reading.localizedTopicTitle(in: store.language)) · \(reading.cardTitle(in: store.language))")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.62))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.48))
                    }
                    .foregroundStyle(.white)
                    .padding(11)
                    .background(.white.opacity(0.08), in: .rect(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(.white.opacity(0.07), in: .rect(cornerRadius: 22))
    }

    private func beginDrawing() {
        guard let selectedTopic, store.canDrawTarotToday else { return }
        let startedAt = Date.now
        guard let reservation = store.reserveTarotDraw(at: startedAt) else { return }
        let normalizedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonicalTopic = TarotTopicID(rawValue: selectedTopic.id)
        let usesDefaultQuestion = normalizedQuestion.isEmpty
        let displayQuestion = usesDefaultQuestion
            ? canonicalTopic?.defaultQuestion(in: store.language)
                ?? store.language.text("今天的\(selectedTopic.title)要注意什麼？", "오늘 \(selectedTopic.title)에서 무엇을 조심해야 할까요?", "What should I notice about \(selectedTopic.title) today?")
            : normalizedQuestion
        let draw = TarotDeck.draw(
            topicID: selectedTopic.id,
            question: displayQuestion,
            language: store.language,
            date: startedAt
        )
        let reading = TarotReadingRecord(
            id: UUID(),
            createdAt: startedAt,
            topicTitle: selectedTopic.title,
            topicEnglish: selectedTopic.english,
            question: displayQuestion,
            cardName: draw.cardName,
            answer: draw.headline,
            detail: draw.message,
            orientation: draw.orientation,
            cardSymbol: draw.cardSymbol,
            keywords: draw.keywords,
            topicID: canonicalTopic?.rawValue,
            cardID: draw.cardID,
            topicFrameVariant: draw.topicFrameVariant,
            userQuestion: usesDefaultQuestion ? nil : normalizedQuestion,
            usesDefaultQuestion: usesDefaultQuestion
        )
        drawingReservation = reservation
        drawingReading = reading
    }

    private func finishDrawingIfNeeded() {
        guard let reservation = drawingReservation else {
            completedDraw = nil
            return
        }
        drawingReservation = nil
        guard let completedDraw else {
            store.cancelDailyAccess(reservation)
            return
        }

        self.completedDraw = nil
        if let storedReading = store.completeTarotDraw(reservation, reading: completedDraw) {
            currentReading = storedReading
            readingPresented = true
        } else {
            drawCompletionRejected = true
        }
    }

    private func cancelDrawing() {
        if let drawingReservation {
            store.cancelDailyAccess(drawingReservation)
        }
        drawingReservation = nil
        completedDraw = nil
        drawingReading = nil
    }

    private func startPreviewRitualIfNeeded() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--preview-tarot-ritual"),
              !didStartPreviewRitual
        else { return }
        didStartPreviewRitual = true
        selectedTopicID = "today"
        question = store.language.text(
            "今天最值得留意什麼？",
            "오늘 가장 눈여겨볼 것은 무엇인가요?",
            "What deserves my attention today?"
        )
        beginDrawing()
        #endif
    }
}

private struct DailyGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var store: AppStore
    @State private var isRevealed = false
    @State private var revealFeedback = 0
    @State private var replayTask: Task<Void, Never>?
    @State private var completionRecorded = false
    @State private var completionRejected = false

    let guide: DailyGuide
    let reservation: DailyAccessReservation?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    flipCard

                    if isRevealed, store.hasMembership {
                        Button(action: replayFlip) {
                            Label(
                                store.language.text("再翻一次", "한 번 더 뒤집기", "Flip again"),
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                            .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.glass)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    } else if isRevealed {
                        Label(
                            store.language.text("今天的牌已經翻開，明天再來看新的。", "오늘의 카드를 펼쳤어요. 내일 새 카드를 만나러 오세요.", "Today's card is open. Come back tomorrow for a new one."),
                            systemImage: "moon.stars.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.76))
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background { CelestialBackdrop().ignoresSafeArea() }
            .navigationTitle(store.language.text("今日指引", "오늘의 메시지", "Today's Guidance"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.language.text("關閉", "닫기", "Close"), action: dismiss.callAsFunction)
                }
            }
        }
        .task { await revealAfterArrival() }
        .onDisappear {
            replayTask?.cancel()
            if let reservation {
                store.cancelDailyAccess(reservation)
            }
        }
        .alert(
            store.language.text("今天的指引沒有翻開", "오늘의 메시지를 펼치지 못했어요", "Today's guidance didn't open"),
            isPresented: $completionRejected
        ) {
            Button(store.language.text("知道了", "확인", "OK"), role: .cancel) {}
        } message: {
            Text(store.language.text(
                "每日次數可能已在另一個視窗使用，或本機資料暫時無法安全保存。關閉後再確認一次。",
                "다른 창에서 오늘의 횟수를 이미 사용했거나 기기 데이터를 안전하게 저장하지 못했을 수 있어요. 닫은 뒤 다시 확인해 주세요.",
                "The daily allowance may have been used in another window, or the on-device record couldn't be saved safely. Close this view and check again."
            ))
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: revealFeedback)
    }

    private var flipCard: some View {
        ZStack {
            cardBack
                .opacity(isRevealed ? 0 : 1)
                .rotation3DEffect(
                    .degrees(reduceMotion ? 0 : (isRevealed ? 180 : 0)),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.72
                )

            cardFront
                .opacity(isRevealed ? 1 : 0)
                .rotation3DEffect(
                    .degrees(reduceMotion ? 0 : (isRevealed ? 0 : -180)),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.72
                )
        }
        .frame(maxWidth: 430)
        .frame(minHeight: 460)
        .fixedSize(horizontal: false, vertical: true)
        .shadow(color: .black.opacity(0.28), radius: 28, y: 18)
        .accessibilityElement(children: isRevealed ? .contain : .ignore)
        .accessibilityLabel(
            isRevealed
                ? store.language.text(
                    "今日指引：\(guide.localizedTitle(in: store.language))",
                    "오늘의 메시지: \(guide.localizedTitle(in: store.language))",
                    "Today's guidance: \(guide.localizedTitle(in: store.language))"
                )
                : store.language.text("今日指引正在翻開", "오늘의 메시지를 뒤집는 중", "Revealing today's guidance")
        )
    }

    private var cardBack: some View {
        ZStack {
            CelestialCardBackground()

            RoundedRectangle(cornerRadius: 26)
                .stroke(Color.celestialGold.opacity(0.72), lineWidth: 1.5)
                .padding(12)

            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                .padding(20)

            VStack(spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(Color.celestialGold)

                Image("LuckyStarTarot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)

                VStack(spacing: 7) {
                    Text(store.language.text("今天的牌要來了", "오늘의 카드가 곧 나와요", "Today's card is on its way"))
                        .font(.title3.bold())
                    Text(store.language.text("等它轉過身子", "카드가 뒤집힐 때까지 잠시만 기다려요", "Wait for it to turn around"))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }
                .foregroundStyle(.white)

                Image(systemName: "moon.stars.fill")
                    .font(.title3)
                    .foregroundStyle(Color.celestialPink)
            }
            .padding(30)
        }
        .clipShape(.rect(cornerRadius: 30))
        .accessibilityHidden(true)
    }

    private var cardFront: some View {
        VStack(spacing: 15) {
            Image("LuckyStarTarot")
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 150)
                .accessibilityHidden(true)

            Text(store.language.text(
                "今日塔羅・\(guide.localizedCardName(in: store.language))",
                "오늘의 타로 · \(guide.localizedCardName(in: store.language))",
                "Today's Tarot · \(guide.localizedCardName(in: store.language))"
            ))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.fortuneRose)

            Text(guide.localizedTitle(in: store.language))
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.fortuneInk)

            Text(guide.localizedMessage(in: store.language))
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170), spacing: 9)],
                spacing: 9
            ) {
                luckyChip(
                    store.language.text(
                        "幸運色：\(guide.localizedLuckyColor(in: store.language))",
                        "행운색: \(guide.localizedLuckyColor(in: store.language))",
                        "Lucky color: \(guide.localizedLuckyColor(in: store.language))"
                    ),
                    symbol: "paintpalette.fill"
                )
                luckyChip(store.language.text("幸運時刻：\(guide.luckyTime)", "행운의 시간: \(guide.luckyTime)", "Lucky time: \(guide.luckyTime)"), symbol: "clock.fill")
            }

            Button {
                store.toggleSavedGuide(guide)
            } label: {
                Label(
                    store.isGuideSaved(guide)
                        ? store.language.text("已收好", "저장했어요", "Saved")
                        : store.language.text("把這張收好", "이 카드 저장하기", "Save this card"),
                    systemImage: store.isGuideSaved(guide) ? "bookmark.fill" : "bookmark"
                )
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.fortunePlum)
        }
        .padding(24)
        .background(Color.fortunePaper)
        .clipShape(.rect(cornerRadius: 30))
        .overlay {
            RoundedRectangle(cornerRadius: 30)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        }
    }

    private func luckyChip(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.fortunePink.opacity(0.46), in: .rect(cornerRadius: 15))
    }

    @MainActor
    private func revealAfterArrival() async {
        if reservation == nil {
            isRevealed = true
            return
        }
        do {
            try await Task.sleep(for: reduceMotion ? .milliseconds(120) : .milliseconds(420))
        } catch {
            return
        }
        reveal()
    }

    private func replayFlip() {
        replayTask?.cancel()
        withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .easeInOut(duration: 0.42)) {
            isRevealed = false
        }

        replayTask = Task { @MainActor in
            do {
                try await Task.sleep(for: reduceMotion ? .milliseconds(140) : .milliseconds(500))
            } catch {
                return
            }
            reveal()
        }
    }

    private func reveal() {
        if !completionRecorded, let reservation {
            guard store.completeDailyGuideReveal(reservation) else {
                completionRejected = true
                return
            }
            completionRecorded = true
        }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .timingCurve(0.22, 0.72, 0.18, 1, duration: 0.88)) {
            isRevealed = true
        }
        revealFeedback += 1
    }
}

private struct DailyFortune: Identifiable {
    let id: String
    let title: String
    let score: Int
    let symbol: String
    let note: String
}

private struct TarotTopic: Identifiable {
    let id: String
    let title: String
    let english: String
    let detail: String
    let symbol: String
    let placeholder: String
}

private extension Color {
    static let fortunePaper = Color(red: 0.985, green: 0.965, blue: 0.975)
    static let fortuneInk = Color(red: 0.27, green: 0.18, blue: 0.30)
    static let fortunePlum = Color(red: 0.45, green: 0.25, blue: 0.48)
    static let fortuneRose = Color(red: 0.69, green: 0.39, blue: 0.53)
    static let fortunePink = Color(red: 0.96, green: 0.80, blue: 0.87)
    static let fortuneLavender = Color(red: 0.85, green: 0.79, blue: 0.93)
}
