import Foundation

@main
enum VerifyAccountStorage {
    static func main() throws {
        let suiteName = "xingban.verify.account-storage.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not create isolated UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        let encoder = JSONEncoder()
        let storage = AccountStorage(defaults: defaults)
        let legacyUserJSON = #"{"openID":"legacy-wechat-user","displayName":"Moon"}"#.data(using: .utf8)!
        let legacyUser = try JSONDecoder().decode(WeChatUser.self, from: legacyUserJSON)
        precondition(legacyUser.canonicalAccountID == nil)
        precondition(legacyUser.canonicalLocalAccountID == "wechat:legacy-wechat-user")

        let accountID = legacyUser.canonicalLocalAccountID
        let profile = BirthProfile(
            displayName: "Moon",
            birthDate: Date(timeIntervalSince1970: 123_456),
            birthTimeMinutes: 21 * 60 + 8,
            birthPlace: "Taipei",
            focuses: [.love, .wellbeing]
        )
        let guide = DailyGuide(
            id: "legacy-guide",
            dateStamp: "2026-08-30",
            zodiacName: "Virgo",
            cardName: "The Star",
            title: "Keep a little room",
            message: "Rest before the next step.",
            luckyColor: "Moon white",
            luckyTime: "21:08"
        )
        let reading = TarotReadingRecord(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            createdAt: Date(timeIntervalSince1970: 456_789),
            topicTitle: "Love",
            topicEnglish: "LOVE",
            question: "What should I notice?",
            cardName: "The Star",
            answer: "Stay open.",
            detail: "A gentle message."
        )
        var planet = SharedPlanet()
        planet.food = 93
        planet.feedCount = 3
        var wardrobe = StarWardrobe.seeded(for: accountID)
        wardrobe.starCoins = 777
        let collectionSkin = StarSkinCatalog.all[0]
        wardrobe.selectedCollectionSkinID = collectionSkin.id
        wardrobe.ownedCollectionSkinIDs = [collectionSkin.id]
        var starLife = StarLifeState.seeded()
        starLife.home?.stardust = 321

        defaults.set(try encoder.encode(profile), forKey: LegacyAccountStorageKey.profile)
        defaults.set(try encoder.encode([guide]), forKey: LegacyAccountStorageKey.savedGuides)
        defaults.set(try encoder.encode([reading]), forKey: LegacyAccountStorageKey.readingHistory)
        defaults.set(try encoder.encode(planet), forKey: LegacyAccountStorageKey.planet)
        defaults.set(14, forKey: LegacyAccountStorageKey.visitStreak)
        defaults.set("2026-08-30", forKey: LegacyAccountStorageKey.lastVisit)
        defaults.set("2026-08-30", forKey: LegacyAccountStorageKey.dailyGuideRevealDate)
        defaults.set("2026-08-29", forKey: LegacyAccountStorageKey.tarotDrawDate)
        defaults.set(
            try encoder.encode(wardrobe),
            forKey: LegacyAccountStorageKey.wardrobePrefix + legacyUser.openID
        )
        defaults.set(
            try encoder.encode(starLife),
            forKey: LegacyAccountStorageKey.starLifePrefix + legacyUser.openID
        )

        precondition(
            storage.migrateLegacyDataIfNeeded(
                for: accountID,
                legacyProviderAccountID: legacyUser.openID,
                includeGlobalValues: true
            ) == .migrated
        )
        let migrated = storage.load(for: accountID)
        precondition(migrated.profile == profile)
        precondition(migrated.savedGuides == [guide])
        precondition(migrated.readingHistory == [reading])
        precondition(migrated.planet == planet)
        precondition(migrated.visitStreak == 14)
        precondition(migrated.lastVisitDate == "2026-08-30")
        precondition(migrated.dailyGuideRevealDate == "2026-08-30")
        precondition(migrated.tarotDrawDate == "2026-08-29")
        precondition(migrated.wardrobe.starCoins == 777)
        precondition(migrated.wardrobe.selectedCollectionSkinID == collectionSkin.id)
        precondition(migrated.wardrobe.availableCollectionSkinIDs == [collectionSkin.id])
        precondition(migrated.starLife.home?.stardust == 321)
        precondition(LegacyAccountStorageKey.globalKeys.allSatisfy { defaults.object(forKey: $0) == nil })
        precondition(defaults.object(forKey: LegacyAccountStorageKey.wardrobePrefix + legacyUser.openID) == nil)
        precondition(defaults.object(forKey: LegacyAccountStorageKey.starLifePrefix + legacyUser.openID) == nil)
        precondition(
            storage.migrateLegacyDataIfNeeded(
                for: accountID,
                legacyProviderAccountID: legacyUser.openID,
                includeGlobalValues: true
            ) == .alreadyCompleted
        )

        var existing = AccountLocalData.seeded(for: "account-b")
        existing.profile = BirthProfile(
            displayName: "Existing B",
            birthDate: Date(timeIntervalSince1970: 999),
            birthTimeMinutes: nil,
            birthPlace: "Seoul",
            focuses: [.work]
        )
        precondition(storage.save(existing, for: "account-b"))
        defaults.set(try encoder.encode(profile), forKey: LegacyAccountStorageKey.profile)
        precondition(
            storage.migrateLegacyDataIfNeeded(
                for: "account-b",
                legacyProviderAccountID: "provider-b",
                includeGlobalValues: true
            ) == .targetAlreadyExists
        )
        precondition(storage.load(for: "account-b").profile?.displayName == "Existing B")
        precondition(defaults.object(forKey: LegacyAccountStorageKey.profile) != nil)
        defaults.removeObject(forKey: LegacyAccountStorageKey.profile)

        var providerOnlyWardrobe = StarWardrobe.seeded(for: "account-provider-only")
        providerOnlyWardrobe.starCoins = 555
        defaults.set(try encoder.encode(profile), forKey: LegacyAccountStorageKey.profile)
        defaults.set(
            try encoder.encode(providerOnlyWardrobe),
            forKey: LegacyAccountStorageKey.wardrobePrefix + "provider-only"
        )
        precondition(
            storage.migrateLegacyDataIfNeeded(
                for: "account-provider-only",
                legacyProviderAccountID: "provider-only",
                includeGlobalValues: false
            ) == .migrated
        )
        precondition(storage.load(for: "account-provider-only").profile == nil)
        precondition(storage.load(for: "account-provider-only").wardrobe.starCoins == 555)
        precondition(defaults.object(forKey: LegacyAccountStorageKey.profile) != nil)
        defaults.removeObject(forKey: LegacyAccountStorageKey.profile)

        var guest = AccountLocalData.seeded(for: AccountStorage.guestAccountID)
        guest.savedGuides = [guide]
        precondition(storage.save(guest, for: AccountStorage.guestAccountID))
        precondition(storage.load(for: accountID).profile?.displayName == "Moon")
        precondition(storage.load(for: "account-b").profile?.displayName == "Existing B")
        precondition(storage.load(for: "account-b").wardrobe.selectedCollectionSkinID == nil)
        precondition(storage.load(for: AccountStorage.guestAccountID).profile == nil)
        precondition(storage.load(for: AccountStorage.guestAccountID).savedGuides == [guide])
        precondition(storage.load(for: AccountStorage.guestAccountID).wardrobe.selectedCollectionSkinID == nil)
        precondition(storage.load(for: AccountStorage.guestAccountID).starLife.visitExchange == nil)

        var providerScoped = AccountLocalData.seeded(for: "wechat-provider-c")
        providerScoped.visitStreak = 22
        precondition(storage.save(providerScoped, for: "wechat-provider-c"))
        precondition(storage.migrateAccountData(from: "wechat-provider-c", to: "canonical-c"))
        precondition(!storage.hasStoredData(for: "wechat-provider-c"))
        precondition(storage.load(for: "canonical-c").visitStreak == 22)

        var twoPhaseSource = AccountLocalData.seeded(for: "apple:provider-two-phase")
        twoPhaseSource.visitStreak = 31
        precondition(storage.save(twoPhaseSource, for: "apple:provider-two-phase"))
        precondition(
            storage.prepareAccountRelink(
                from: "apple:provider-two-phase",
                to: "account:canonical-two-phase"
            ) == .migrated
        )
        precondition(storage.hasStoredData(for: "apple:provider-two-phase"))
        precondition(storage.load(for: "account:canonical-two-phase").visitStreak == 31)
        twoPhaseSource.visitStreak = 32
        precondition(storage.save(twoPhaseSource, for: "apple:provider-two-phase"))
        let restartedStorage = AccountStorage(defaults: defaults)
        precondition(
            restartedStorage.prepareAccountRelink(
                from: "apple:provider-two-phase",
                to: "account:canonical-two-phase"
            ) == .migrated
        )
        precondition(restartedStorage.load(for: "account:canonical-two-phase").visitStreak == 32)
        restartedStorage.rollbackPreparedAccountRelink(
            from: "apple:provider-two-phase",
            to: "account:canonical-two-phase"
        )
        precondition(storage.hasStoredData(for: "apple:provider-two-phase"))
        precondition(!storage.hasStoredData(for: "account:canonical-two-phase"))
        precondition(
            storage.prepareAccountRelink(
                from: "apple:provider-two-phase",
                to: "account:canonical-two-phase"
            ) == .migrated
        )
        precondition(
            storage.finalizeAccountRelink(
                from: "apple:provider-two-phase",
                to: "account:canonical-two-phase"
            )
        )
        precondition(!storage.hasStoredData(for: "apple:provider-two-phase"))
        precondition(storage.load(for: "account:canonical-two-phase").visitStreak == 32)

        var corruptPreparedSource = AccountLocalData.seeded(for: "wechat:prepared-corrupt-source")
        corruptPreparedSource.visitStreak = 57
        precondition(storage.save(corruptPreparedSource, for: "wechat:prepared-corrupt-source"))
        precondition(
            storage.prepareAccountRelink(
                from: "wechat:prepared-corrupt-source",
                to: "account:prepared-corrupt-target"
            ) == .migrated
        )
        let corruptPreparedRaw = Data([0x00, 0xFF, 0x10, 0x80])
        defaults.set(corruptPreparedRaw, forKey: accountStorageKey("account:prepared-corrupt-target"))
        precondition(
            !storage.finalizeAccountRelink(
                from: "wechat:prepared-corrupt-source",
                to: "account:prepared-corrupt-target"
            )
        )
        precondition(storage.hasStoredData(for: "wechat:prepared-corrupt-source"))
        let restartedAfterCorruption = AccountStorage(defaults: defaults)
        precondition(
            restartedAfterCorruption.prepareAccountRelink(
                from: "wechat:prepared-corrupt-source",
                to: "account:prepared-corrupt-target"
            ) == .migrated
        )
        precondition(restartedAfterCorruption.load(for: "account:prepared-corrupt-target").visitStreak == 57)
        precondition(restartedAfterCorruption.hasStoredData(for: "wechat:prepared-corrupt-source"))
        precondition(defaults.dictionaryRepresentation().contains { key, value in
            key.hasPrefix("xingban.ios.account-local-quarantine.v1.")
                && (value as? Data) == corruptPreparedRaw
        })
        precondition(
            restartedAfterCorruption.finalizeAccountRelink(
                from: "wechat:prepared-corrupt-source",
                to: "account:prepared-corrupt-target"
            )
        )

        var futurePreparedSource = AccountLocalData.seeded(for: "apple:prepared-future-source")
        futurePreparedSource.visitStreak = 61
        precondition(storage.save(futurePreparedSource, for: "apple:prepared-future-source"))
        precondition(
            storage.prepareAccountRelink(
                from: "apple:prepared-future-source",
                to: "account:prepared-future-target"
            ) == .migrated
        )
        var futurePreparedObject = try requireDictionary(
            JSONSerialization.jsonObject(with: encoder.encode(futurePreparedSource))
        )
        futurePreparedObject["schemaVersion"] = AccountLocalData.currentSchemaVersion + 1
        defaults.set(
            try JSONSerialization.data(withJSONObject: futurePreparedObject),
            forKey: accountStorageKey("account:prepared-future-target")
        )
        precondition(
            !storage.finalizeAccountRelink(
                from: "apple:prepared-future-source",
                to: "account:prepared-future-target"
            )
        )
        precondition(storage.hasStoredData(for: "apple:prepared-future-source"))
        precondition(
            storage.prepareAccountRelink(
                from: "apple:prepared-future-source",
                to: "account:prepared-future-target"
            ) == .migrated
        )
        precondition(
            storage.finalizeAccountRelink(
                from: "apple:prepared-future-source",
                to: "account:prepared-future-target"
            )
        )

        var conflictSource = AccountLocalData.seeded(for: "phone:conflict-source")
        conflictSource.visitStreak = 41
        var conflictTarget = AccountLocalData.seeded(for: "account:conflict-target")
        conflictTarget.visitStreak = 42
        precondition(storage.save(conflictSource, for: "phone:conflict-source"))
        precondition(storage.save(conflictTarget, for: "account:conflict-target"))
        precondition(
            storage.prepareAccountRelink(
                from: "phone:conflict-source",
                to: "account:conflict-target"
            ) == .targetAlreadyExists
        )
        precondition(storage.load(for: "phone:conflict-source").visitStreak == 41)
        precondition(storage.load(for: "account:conflict-target").visitStreak == 42)
        storage.recordRelinkConflict(from: "phone:conflict-source", to: "account:conflict-target")
        precondition(storage.hasRelinkConflict(from: "phone:conflict-source", to: "account:conflict-target"))

        let corruptID = "wechat:corrupt"
        let corruptRaw = Data([0xCA, 0xFE, 0xBA, 0xBE])
        defaults.set(corruptRaw, forKey: accountStorageKey(corruptID))
        let corruptLoad = storage.loadResult(for: corruptID)
        precondition(corruptLoad.status == .quarantined)
        precondition(!corruptLoad.allowsAutomaticWrites)
        precondition(!storage.save(.seeded(for: corruptID), for: corruptID))
        precondition(defaults.dictionaryRepresentation().contains { key, value in
            key.hasPrefix("xingban.ios.account-local-quarantine.v1.")
                && (value as? Data) == corruptRaw
        })

        let futureID = "apple:future-schema"
        let futureSeed = AccountLocalData.seeded(for: futureID)
        var futureObject = try requireDictionary(JSONSerialization.jsonObject(with: encoder.encode(futureSeed)))
        futureObject["schemaVersion"] = AccountLocalData.currentSchemaVersion + 1
        defaults.set(
            try JSONSerialization.data(withJSONObject: futureObject),
            forKey: accountStorageKey(futureID)
        )
        let futureLoad = storage.loadResult(for: futureID)
        precondition(futureLoad.status == .unsupportedSchema(AccountLocalData.currentSchemaVersion + 1))
        precondition(!futureLoad.allowsAutomaticWrites)
        precondition(!storage.save(.seeded(for: futureID), for: futureID))

        let nestedFutureID = "apple:nested-future-schema"
        var nestedFutureObject = try requireDictionary(
            JSONSerialization.jsonObject(with: encoder.encode(AccountLocalData.seeded(for: nestedFutureID)))
        )
        var nestedStarLife = try requireDictionary(nestedFutureObject["starLife"] ?? [:])
        nestedStarLife["schemaVersion"] = StarLifeState.currentSchemaVersion + 1
        nestedStarLife["futureSentinel"] = "preserve-this-field"
        nestedFutureObject["starLife"] = nestedStarLife
        let nestedFutureRaw = try JSONSerialization.data(
            withJSONObject: nestedFutureObject,
            options: [.sortedKeys]
        )
        defaults.set(nestedFutureRaw, forKey: accountStorageKey(nestedFutureID))
        let nestedFutureLoad = storage.loadResult(for: nestedFutureID)
        precondition(nestedFutureLoad.status == .unsupportedSchema(StarLifeState.currentSchemaVersion + 1))
        precondition(!nestedFutureLoad.allowsAutomaticWrites)
        precondition(defaults.dictionaryRepresentation().contains { key, value in
            key.hasPrefix("xingban.ios.account-local-quarantine.v1.")
                && (value as? Data) == nestedFutureRaw
        })

        let oldWardrobeID = "wechat:old-wardrobe"
        var oldWardrobeObject = try requireDictionary(
            JSONSerialization.jsonObject(with: encoder.encode(AccountLocalData.seeded(for: oldWardrobeID)))
        )
        var oldWardrobe = try requireDictionary(oldWardrobeObject["wardrobe"] ?? [:])
        oldWardrobe.removeValue(forKey: "selectedCollectionSkinID")
        oldWardrobe.removeValue(forKey: "ownedCollectionSkinIDs")
        oldWardrobeObject["wardrobe"] = oldWardrobe
        defaults.set(
            try JSONSerialization.data(withJSONObject: oldWardrobeObject),
            forKey: accountStorageKey(oldWardrobeID)
        )
        let oldWardrobeLoad = storage.loadResult(for: oldWardrobeID)
        precondition(oldWardrobeLoad.data.wardrobe.selectedCollectionSkinID == nil)
        precondition(oldWardrobeLoad.data.wardrobe.ownedCollectionSkinIDs == [])

        defaults.set(try encoder.encode(profile), forKey: LegacyAccountStorageKey.profile)
        precondition(storage.isolateUnownedLegacyGlobalsIfNeeded() == .migrated)
        precondition(storage.load(for: AccountStorage.legacyRecoveryAccountID).profile == profile)
        precondition(defaults.object(forKey: LegacyAccountStorageKey.profile) == nil)
        precondition(
            storage.migrateLegacyDataIfNeeded(
                for: "wechat:next-account",
                legacyProviderAccountID: "next-account",
                includeGlobalValues: true
            ) == .nothingToMigrate
        )

        let canonicalUser = WeChatUser(
            openID: "provider-value",
            displayName: "Linked",
            canonicalAccountID: "backend-account-id"
        )
        precondition(canonicalUser.canonicalLocalAccountID == "account:backend-account-id")

        storage.removeAllAccountDataAndLegacyValues()
        precondition(!storage.hasStoredData(for: accountID))
        precondition(!storage.hasStoredData(for: "account-b"))
        precondition(!storage.hasStoredData(for: AccountStorage.guestAccountID))
        precondition(!storage.hasStoredData(for: "canonical-c"))
        precondition(!storage.hasStoredData(for: "account-provider-only"))
        precondition(!storage.hasStoredData(for: "account:canonical-two-phase"))
        precondition(!storage.hasStoredData(for: "account:prepared-corrupt-target"))
        precondition(!storage.hasStoredData(for: "account:prepared-future-target"))
        precondition(!storage.hasStoredData(for: "phone:conflict-source"))
        precondition(!storage.hasStoredData(for: "account:conflict-target"))
        precondition(!storage.hasProtectedOrStoredData(for: corruptID))
        precondition(!storage.hasProtectedOrStoredData(for: futureID))
        precondition(!storage.hasProtectedOrStoredData(for: nestedFutureID))
        precondition(!storage.hasStoredData(for: oldWardrobeID))
        precondition(!storage.hasStoredData(for: AccountStorage.legacyRecoveryAccountID))

        print("Account isolation, recoverable quarantine, legacy ownership, no-overwrite behavior, and two-phase canonical relinking verified")
    }

    private static func accountStorageKey(_ accountID: String) -> String {
        let component = Data(accountID.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "xingban.ios.account-local.v1." + component
    }

    private static func requireDictionary(_ value: Any) throws -> [String: Any] {
        guard let dictionary = value as? [String: Any] else {
            throw VerificationError.invalidJSONObject
        }
        return dictionary
    }

    private enum VerificationError: Error { case invalidJSONObject }
}
