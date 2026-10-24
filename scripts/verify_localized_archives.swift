import Foundation

// ActivityKit is unavailable to this host-side executable. AppStore only needs
// this surface while the verifier exercises the real account load/save path.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    private init() {}

    func sync(
        food: Int,
        status: String,
        language: AppLanguage,
        allowsNewActivity: Bool
    ) async {}

    func end(language: AppLanguage) async {}
}

@main
enum VerifyLocalizedArchives {
    @MainActor
    static func main() {
        verifyEveryTarotCardHasAStableIdentity()
        verifyLegacyArchivesMigrateThroughAppStoreWithoutDataLoss()
        print("Localized guide/tarot canonical migration and live language switching verified")
    }

    private static func verifyEveryTarotCardHasAStableIdentity() {
        precondition(TarotCardID.allCases.count == 22)
        for cardID in TarotCardID.allCases {
            for language in AppLanguage.allCases {
                let result = require(TarotDeck.localizedResult(
                    cardID: cardID.rawValue,
                    orientation: .upright,
                    topicID: TarotTopicID.today.rawValue,
                    topicFrameVariant: 0,
                    language: language
                ))
                precondition(result.cardID == cardID.rawValue)
                precondition(TarotDeck.cardID(matchingLocalizedName: result.cardName) == cardID.rawValue)
            }
        }
    }

    @MainActor
    private static func verifyLegacyArchivesMigrateThroughAppStoreWithoutDataLoss() {
        let suite = "xingban.verify.localized-archives.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            preconditionFailure("Could not create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let account = AppAccount(
            provider: .phone,
            providerSubject: "+15550000991",
            displayName: "Archive verifier",
            canonicalAccountID: "archive-verifier"
        )
        let session = AuthSession(
            account: account,
            assurance: .backendVerified,
            accessToken: "test-only-token"
        )
        let vault = MemorySessionVault(session: session)

        let guideVariant = DailyGuideVariant.tryAnotherRoute
        let legacyGuide = DailyGuide(
            id: "2026-08-31-6",
            dateStamp: "2026-08-31",
            zodiacName: ZodiacSign.cancer.title(in: .korean),
            cardName: require(DailyGuideArchiveCatalog.cardTitle(
                for: DailyGuideArchiveCatalog.starCardID,
                language: .korean
            )),
            title: guideVariant.title(in: .korean),
            message: guideVariant.message(in: .korean),
            luckyColor: guideVariant.luckyColor(in: .korean),
            luckyTime: "20:42"
        )
        let unknownGuide = DailyGuide(
            id: "legacy-unknown-guide",
            dateStamp: "2025-01-01",
            zodiacName: "Legacy constellation",
            cardName: "Legacy card",
            title: "Legacy title",
            message: "Legacy message",
            luckyColor: "Legacy color",
            luckyTime: "08:15"
        )

        let legacyDefaultReading = legacyReading(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!,
            topic: .love,
            cardID: .moon,
            orientation: .reversed,
            frameVariant: 2,
            language: .traditionalChinese,
            question: TarotTopicID.love.defaultQuestion(in: .traditionalChinese),
            storesOrientation: false
        )
        let originalQuestion = "Should I accept the new role?"
        let legacyCustomReading = legacyReading(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!,
            topic: .wealth,
            cardID: .justice,
            orientation: .upright,
            frameVariant: 3,
            language: .english,
            question: originalQuestion
        )
        let unknownReading = TarotReadingRecord(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000003")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            topicTitle: "Legacy topic",
            topicEnglish: "Legacy",
            question: "Legacy question",
            cardName: "Legacy card",
            answer: "Legacy answer",
            detail: "Legacy detail",
            orientation: .upright,
            cardSymbol: "sparkles",
            keywords: "Legacy keywords"
        )

        // Nil canonical fields model the exact shape decoded from v1 archives.
        precondition(legacyGuide.zodiacID == nil && legacyGuide.variantID == nil)
        precondition(legacyDefaultReading.topicID == nil && legacyDefaultReading.cardID == nil)
        let encodedLegacyGuide = try! JSONEncoder().encode(legacyGuide)
        precondition(!String(decoding: encodedLegacyGuide, as: UTF8.self).contains("variantID"))

        var data = AccountLocalData.seeded(for: account.canonicalLocalAccountID)
        data.savedGuides = [legacyGuide, unknownGuide]
        data.readingHistory = [legacyDefaultReading, legacyCustomReading, unknownReading]
        precondition(AccountStorage(defaults: defaults).save(data, for: account.canonicalLocalAccountID))

        let store = makeStore(defaults: defaults, vault: vault)
        precondition(store.savedGuides.count == 2)
        precondition(store.readingHistory.count == 3)

        let migratedGuide = require(store.savedGuides.first { $0.id == legacyGuide.id })
        precondition(migratedGuide.zodiacID == DailyGuideArchiveCatalog.zodiacID(for: .cancer))
        precondition(migratedGuide.cardID == DailyGuideArchiveCatalog.starCardID)
        precondition(migratedGuide.variantID == guideVariant.rawValue)
        for language in AppLanguage.allCases {
            precondition(migratedGuide.localizedZodiacName(in: language) == ZodiacSign.cancer.title(in: language))
            precondition(migratedGuide.localizedTitle(in: language) == guideVariant.title(in: language))
            precondition(migratedGuide.localizedMessage(in: language) == guideVariant.message(in: language))
            precondition(migratedGuide.localizedLuckyColor(in: language) == guideVariant.luckyColor(in: language))
        }

        let preservedGuide = require(store.savedGuides.first { $0.id == unknownGuide.id })
        precondition(preservedGuide.title == unknownGuide.title)
        precondition(preservedGuide.localizedTitle(in: .traditionalChinese) == unknownGuide.title)
        precondition(preservedGuide.localizedTitle(in: .english) == unknownGuide.title)

        let migratedDefault = require(store.readingHistory.first { $0.id == legacyDefaultReading.id })
        precondition(migratedDefault.topicID == TarotTopicID.love.rawValue)
        precondition(migratedDefault.cardID == TarotCardID.moon.rawValue)
        precondition(migratedDefault.orientation == .reversed)
        precondition(migratedDefault.topicFrameVariant == 2)
        precondition(migratedDefault.usesDefaultQuestion == true)
        precondition(migratedDefault.userQuestion == nil)
        verifyLocalizedReading(
            migratedDefault,
            topic: .love,
            cardID: .moon,
            orientation: .reversed,
            frameVariant: 2
        )

        let migratedCustom = require(store.readingHistory.first { $0.id == legacyCustomReading.id })
        precondition(migratedCustom.usesDefaultQuestion == false)
        precondition(migratedCustom.userQuestion == originalQuestion)
        for language in AppLanguage.allCases {
            precondition(migratedCustom.localizedQuestion(in: language) == originalQuestion)
        }
        verifyLocalizedReading(
            migratedCustom,
            topic: .wealth,
            cardID: .justice,
            orientation: .upright,
            frameVariant: 3
        )

        let preservedReading = require(store.readingHistory.first { $0.id == unknownReading.id })
        precondition(preservedReading.localizedAnswer(in: .korean) == unknownReading.answer)
        precondition(preservedReading.localizedDetail(in: .english) == unknownReading.detail)

        // AppStore persists the inferred keys. A second launch must not need to
        // infer them again and must retain every archive, including unknown ones.
        let persisted = AccountStorage(defaults: defaults).load(for: account.canonicalLocalAccountID)
        precondition(persisted.savedGuides.count == 2)
        precondition(persisted.readingHistory.count == 3)
        precondition(persisted.savedGuides.first { $0.id == legacyGuide.id }?.variantID == guideVariant.rawValue)
        precondition(persisted.readingHistory.first { $0.id == legacyDefaultReading.id }?.cardID == TarotCardID.moon.rawValue)

        let restarted = makeStore(defaults: defaults, vault: vault)
        precondition(restarted.savedGuides.count == 2)
        precondition(restarted.readingHistory.count == 3)
        precondition(
            restarted.readingHistory.first { $0.id == legacyCustomReading.id }?.userQuestion
                == originalQuestion
        )
    }

    private static func legacyReading(
        id: UUID,
        topic: TarotTopicID,
        cardID: TarotCardID,
        orientation: TarotOrientation,
        frameVariant: Int,
        language: AppLanguage,
        question: String,
        storesOrientation: Bool = true
    ) -> TarotReadingRecord {
        let draw = require(TarotDeck.localizedResult(
            cardID: cardID.rawValue,
            orientation: orientation,
            topicID: topic.rawValue,
            topicFrameVariant: frameVariant,
            language: language
        ))
        return TarotReadingRecord(
            id: id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            topicTitle: topic.title(in: language),
            topicEnglish: topic.rawValue.capitalized,
            question: question,
            cardName: draw.cardName,
            answer: draw.headline,
            detail: draw.message,
            orientation: storesOrientation ? orientation : nil,
            cardSymbol: draw.cardSymbol,
            keywords: draw.keywords
        )
    }

    private static func verifyLocalizedReading(
        _ reading: TarotReadingRecord,
        topic: TarotTopicID,
        cardID: TarotCardID,
        orientation: TarotOrientation,
        frameVariant: Int
    ) {
        for language in AppLanguage.allCases {
            let expected = require(TarotDeck.localizedResult(
                cardID: cardID.rawValue,
                orientation: orientation,
                topicID: topic.rawValue,
                topicFrameVariant: frameVariant,
                language: language
            ))
            precondition(reading.localizedTopicTitle(in: language) == topic.title(in: language))
            precondition(reading.cardTitle(in: language).hasPrefix(expected.cardName))
            precondition(reading.localizedAnswer(in: language) == expected.headline)
            precondition(reading.localizedDetail(in: language) == expected.message)
            precondition(reading.localizedKeywords(in: language) == expected.keywords)
            precondition(reading.shareText(in: language).contains(expected.headline))
        }
    }

    @MainActor
    private static func makeStore(
        defaults: UserDefaults,
        vault: MemorySessionVault
    ) -> AppStore {
        AppStore(
            authService: UnconfiguredWeChatAuthService(),
            appleSignInService: NativeAppleSignInService(
                exchangeService: UnconfiguredAppleCredentialExchange()
            ),
            phoneOTPService: UnconfiguredPhoneOTPService(),
            sessionVault: vault,
            defaults: defaults
        )
    }

    private static func require<T>(_ value: T?, _ message: String = "Expected a value") -> T {
        guard let value else { preconditionFailure(message) }
        return value
    }
}
