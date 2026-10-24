import Foundation

@main
enum VerifyStarProgress {
    static func main() throws {
        let legacyJSON = #"""
        {
          "selectedAura":"classic",
          "tarotAura":null,
          "followsTarotMeaning":true,
          "selectedAccessory":"none",
          "ownedAccessories":["none"],
          "starCoins":120,
          "starTrailProgress":{"highestUnlockedLevel":2,"completedLevels":[1]}
        }
        """#.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(StarWardrobe.self, from: legacyJSON)
        let migrated = decoded.migrated(for: "legacy-account")
        precondition(migrated.starTrailProgress?.highestUnlockedLevel == 2)
        precondition(migrated.cometCatchProgress == nil)
        precondition(migrated.starCoins == 120)
        precondition(migrated.ownedAccessories == [.none])
        precondition(migrated.selectedPersona != nil)
        precondition(migrated.availablePersonas.contains(.classic))
        precondition(migrated.availablePersonas.contains(migrated.displayedPersona))

        let first = StarWardrobe.seeded(for: "account-one")
        let second = StarWardrobe.seeded(for: "account-two")
        precondition(first.starTrailProgress?.highestUnlockedLevel == 1)
        precondition(first.cometCatchProgress?.highestUnlockedLevel == 1)
        precondition(first == StarWardrobe.seeded(for: "account-one"))
        precondition(
            first.selectedPersona != second.selectedPersona
                || first.selectedAura != second.selectedAura
                || first.selectedAccessory != second.selectedAccessory
        )

        let seededPersonas = Set((0..<1_000).map {
            StarWardrobe.seeded(for: "account-\($0)").displayedPersona
        })
        precondition(seededPersonas == Set(StarPersona.starterCases))
        precondition(!seededPersonas.contains(.moonRabbit))
        precondition(!seededPersonas.contains(.prismAurora))

        print("Star wardrobe migration preserved legacy progress and kept all \(seededPersonas.count) stable starter personas")
    }
}
