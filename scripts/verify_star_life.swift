import Foundation

@main
enum VerifyStarLife {
    static func main() throws {
        var utc = Calendar(identifier: .iso8601)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = ISO8601DateFormatter()
        let night = formatter.date(from: "2026-08-30T22:30:00Z")!
        let tomorrow = formatter.date(from: "2026-08-31T08:00:00Z")!

        let wish = BedtimeWish(
            id: UUID(),
            createdAt: night,
            text: "I hope tomorrow feels lighter.",
            readyDateStamp: "2026-08-31",
            replyTemplateID: .restFirst,
            revealedAt: nil
        )
        precondition(!wish.isReady(on: night, calendar: utc))
        precondition(wish.isReady(on: tomorrow, calendar: utc))

        let empty = StarLifeState(
            schemaVersion: nil,
            wishes: nil,
            weeklyStory: nil,
            home: nil,
            gentleDay: nil
        ).migrated(now: night, calendar: utc)
        precondition(empty.schemaVersion == StarLifeState.currentSchemaVersion)
        precondition(empty.wishes == [])
        precondition(empty.home?.stardust == 60)
        precondition(empty.home?.ownedRoomThemes?.contains(.observatoryGarden) == true)

        var completed = WeeklyStoryProgress.current(for: night, calendar: utc)
        completed.completedTasks = Set(WeeklyJourneyTask.allCases)
        precondition(completed.isUnlocked)
        let nextWeek = formatter.date(from: "2026-09-07T08:00:00Z")!
        let rolled = StarLifeState(
            schemaVersion: 1,
            wishes: [wish],
            weeklyStory: completed,
            home: .starter,
            gentleDay: GentleDayState()
        ).migrated(now: nextWeek, calendar: utc)
        precondition(rolled.weeklyStory?.completedTasks.isEmpty == true)
        precondition(rolled.wishes?.count == 1)

        let languages = AppLanguage.allCases
        for zodiac in ZodiacSign.allCases {
            let localizedStories = languages.map {
                WeeklyZodiacStoryContent.make(
                    zodiac: zodiac,
                    weekID: "2026-W35",
                    language: $0
                )
            }
            precondition(Set(localizedStories.map(\.id)).count == 1)

            for language in languages {
                let story = WeeklyZodiacStoryContent.make(
                    zodiac: zodiac,
                    weekID: "2026-W35",
                    language: language
                )
                let repeatedStory = WeeklyZodiacStoryContent.make(
                    zodiac: zodiac,
                    weekID: "2026-W35",
                    language: language
                )
                precondition(story == repeatedStory)
                precondition(!story.lockedTitle.isEmpty)
                precondition(!story.title.isEmpty)
                precondition(!story.body.isEmpty)
                precondition(!story.ending.isEmpty)

                let nextStory = WeeklyZodiacStoryContent.make(
                    zodiac: zodiac,
                    weekID: "2026-W36",
                    language: language
                )
                precondition(story.id != nextStory.id)
                precondition(story.lockedTitle != nextStory.lockedTitle)
                precondition(story.title != nextStory.title)
                precondition(story.body != nextStory.body)
                precondition(story.ending != nextStory.ending)
            }
        }

        let sixWeekCycle = (35...40).map {
            WeeklyZodiacStoryContent.make(
                zodiac: .capricorn,
                weekID: String(format: "2026-W%02d", $0),
                language: .traditionalChinese
            ).id
        }
        precondition(Set(sixWeekCycle).count == 6)

        for language in languages {
            let stories = ZodiacSign.allCases.map {
                WeeklyZodiacStoryContent.make(
                    zodiac: $0,
                    weekID: "2026-W35",
                    language: language
                )
            }
            precondition(Set(stories.map(\.title)).count == ZodiacSign.allCases.count)
            precondition(Set(stories.map(\.body)).count == ZodiacSign.allCases.count)
        }

        let storyProgressData = try JSONEncoder().encode(WeeklyStoryProgress(
            weekID: "2026-W35",
            completedTasks: [.wish, .care, .play],
            revealedAt: night
        ))
        let storyProgressObject = try JSONSerialization.jsonObject(with: storyProgressData) as! [String: Any]
        precondition(Set(storyProgressObject.keys) == ["weekID", "completedTasks", "revealedAt"])

        let legacyStoryProgress = #"{"weekID":"2026-W35","completedTasks":["wish"],"revealedAt":null}"#.data(using: .utf8)!
        let decodedStoryProgress = try JSONDecoder().decode(WeeklyStoryProgress.self, from: legacyStoryProgress)
        precondition(decodedStoryProgress.weekID == "2026-W35")
        precondition(decodedStoryProgress.completedTasks == [.wish])
        precondition(decodedStoryProgress.revealedAt == nil)

        let legacyReading = #"""
        {
          "id":"00000000-0000-0000-0000-000000000001",
          "createdAt":0,
          "topicTitle":"Love",
          "topicEnglish":"LOVE",
          "question":"What should I notice?",
          "cardName":"The Star",
          "answer":"Stay open.",
          "detail":"A gentle message."
        }
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TarotReadingRecord.self, from: legacyReading)
        precondition(decoded.appearanceSnapshot == nil)

        precondition(StarRoomTheme.moonRabbitFestival.isInSeason(
            on: formatter.date(from: "2026-09-15T00:00:00Z")!,
            calendar: utc
        ))
        precondition(!StarRoomTheme.christmasSnowRoom.isInSeason(
            on: formatter.date(from: "2026-09-15T00:00:00Z")!,
            calendar: utc
        ))
        precondition(StarPersona.moonRabbit.isAvailable(
            on: formatter.date(from: "2026-09-15T00:00:00Z")!,
            calendar: utc
        ))
        precondition(!StarPersona.halloweenGhost.isAvailable(
            on: formatter.date(from: "2026-09-15T00:00:00Z")!,
            calendar: utc
        ))
        precondition(StarPersona.halloweenGhost.isAvailable(
            on: formatter.date(from: "2026-10-20T00:00:00Z")!,
            calendar: utc
        ))

        print("Star life migration, wish timing, weekly rollover, deterministic zodiac-by-week stories in three languages, story schema compatibility, journal compatibility, seasonal rooms, and seasonal personas verified")
    }
}
