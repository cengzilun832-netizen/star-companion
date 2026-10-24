import Foundation

@main
enum VerifyStarSkinWardrobe {
    static func main() throws {
        let legacyJSON = """
        {
          "selectedAura": "classic",
          "followsTarotMeaning": true,
          "selectedAccessory": "none",
          "ownedAccessories": ["none"],
          "starCoins": 120,
          "selectedPersona": "dreamPajamas",
          "ownedPersonas": ["classic", "dreamPajamas"]
        }
        """.data(using: .utf8)!

        let decodedLegacy = try JSONDecoder().decode(StarWardrobe.self, from: legacyJSON)
        precondition(decodedLegacy.selectedPersona == .dreamPajamas)
        precondition(decodedLegacy.selectedCollectionSkinID == nil)
        precondition(decodedLegacy.ownedCollectionSkinIDs == nil)
        precondition(decodedLegacy.selectedPersonaRequiresAllLooks == nil)
        precondition(decodedLegacy.selectedCollectionSkinRequiresAllLooks == nil)
        precondition(decodedLegacy.selectedAccessoryRequiresAllLooks == nil)

        var migrated = decodedLegacy.migrated(for: "legacy-account")
        precondition(migrated.selectedPersona == .dreamPajamas)
        precondition(migrated.ownedCollectionSkinIDs == [])
        migrated.tarotAura = .rose
        precondition(migrated.displayedAura == .rose)
        migrated.followsTarotMeaning = false
        precondition(migrated.displayedAura == .classic)
        migrated.followsTarotMeaning = true
        precondition(StarAura.matchingTarot(symbol: "sun.max.fill") == .sunrise)
        precondition(StarAura.matchingTarot(symbol: "moon.stars.fill") == .moonlit)
        precondition(StarAura.matchingTarot(symbol: "heart.fill") == .rose)
        precondition(StarAura.matchingTarot(symbol: "sparkles") == .classic)
        precondition(StarAura.matchingTarot(symbol: "link") == .nebula)

        guard let firstSkin = StarSkinCatalog.all.first else {
            preconditionFailure("Generated collection is empty")
        }
        migrated.selectedCollectionSkinID = firstSkin.id
        migrated.ownedCollectionSkinIDs = [firstSkin.id]
        precondition(migrated.displayedLookID == firstSkin.id)
        precondition(migrated.displayedAssetName == firstSkin.assetName)
        precondition(migrated.supportsAccessoryOverlay == false)

        let roundTripData = try JSONEncoder().encode(migrated)
        let roundTrip = try JSONDecoder().decode(StarWardrobe.self, from: roundTripData)
        precondition(roundTrip.selectedCollectionSkinID == firstSkin.id)
        precondition(roundTrip.availableCollectionSkinIDs == [firstSkin.id])
        precondition(roundTrip.selectedPersona == .dreamPajamas)

        // These flags describe why a selection is available; they must never
        // be interpreted as coin ownership while an account snapshot migrates.
        var entitlementOnly = decodedLegacy
        entitlementOnly.selectedPersona = .halloweenGhost
        entitlementOnly.selectedPersonaRequiresAllLooks = true
        entitlementOnly.selectedCollectionSkinID = firstSkin.id
        entitlementOnly.selectedCollectionSkinRequiresAllLooks = true
        entitlementOnly.selectedAccessory = .magicWand
        entitlementOnly.selectedAccessoryRequiresAllLooks = true
        entitlementOnly.ownedPersonas = [.classic]
        entitlementOnly.ownedCollectionSkinIDs = []
        entitlementOnly.ownedAccessories = [.none]

        let entitlementRoundTripData = try JSONEncoder().encode(entitlementOnly)
        let entitlementRoundTrip = try JSONDecoder().decode(
            StarWardrobe.self,
            from: entitlementRoundTripData
        ).migrated(for: "entitlement-only-account")
        precondition(entitlementRoundTrip.selectedPersonaRequiresAllLooks == true)
        precondition(entitlementRoundTrip.selectedCollectionSkinRequiresAllLooks == true)
        precondition(entitlementRoundTrip.selectedAccessoryRequiresAllLooks == true)
        precondition(!entitlementRoundTrip.availablePersonas.contains(.halloweenGhost))
        precondition(!entitlementRoundTrip.availableCollectionSkinIDs.contains(firstSkin.id))
        precondition(!entitlementRoundTrip.ownedAccessories.contains(.magicWand))

        var legacyJadeRabbit = decodedLegacy
        legacyJadeRabbit.selectedCollectionSkinID = "collection.jade-rabbit"
        legacyJadeRabbit.ownedCollectionSkinIDs = ["collection.jade-rabbit"]
        let migratedRabbit = legacyJadeRabbit.migrated(for: "legacy-rabbit-owner")
        precondition(migratedRabbit.selectedCollectionSkinID == nil)
        precondition(migratedRabbit.selectedPersona == .moonRabbit)
        precondition(migratedRabbit.availablePersonas.contains(.moonRabbit))
        precondition(!migratedRabbit.availableCollectionSkinIDs.contains("collection.jade-rabbit"))

        precondition(StarPersona.allCases.count == 20)
        precondition(StarSkinCatalog.all.count == 88)
        precondition(Set(StarSkinCatalog.all.map(\.id)).count == 88)
        precondition(StarSkinCatalog.all.allSatisfy { !$0.title(in: .traditionalChinese).isEmpty })
        precondition(StarSkinCatalog.all.allSatisfy { !$0.title(in: .korean).isEmpty })
        precondition(StarSkinCatalog.all.allSatisfy { !$0.title(in: .english).isEmpty })

        print(
            "Legacy wardrobe decoding, all-looks provenance, duplicate migration, "
                + "20 existing looks, and 88 generated looks verified"
        )
    }
}
