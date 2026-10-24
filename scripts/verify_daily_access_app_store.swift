import Foundation

// The production controller uses ActivityKit, which is unavailable to this
// host-side verifier. This no-op has the same surface used by AppStore; the
// quota, persistence, and AccountStorage implementations remain production
// code in this executable.
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
enum VerifyDailyAccessAppStoreIntegration {
    @MainActor
    static func main() {
        var suites: [String] = []
        defer {
            for suite in suites {
                UserDefaults.standard.removePersistentDomain(forName: suite)
            }
        }

        func isolatedDefaults(_ label: String) -> UserDefaults {
            let suite = "xingban.verify.daily-access.app-store.\(label).\(UUID().uuidString)"
            suites.append(suite)
            guard let defaults = UserDefaults(suiteName: suite) else {
                preconditionFailure("Could not create isolated UserDefaults suite")
            }
            defaults.removePersistentDomain(forName: suite)
            return defaults
        }

        func session(_ label: String) -> AuthSession {
            AuthSession(
                account: AppAccount(
                    provider: .phone,
                    providerSubject: "+1555000\(label)",
                    displayName: "Quota verifier",
                    canonicalAccountID: "quota-verifier-\(label)"
                ),
                assurance: .backendVerified,
                accessToken: "test-only-token"
            )
        }

        func makeStore(
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

        func reading(
            id: UUID = UUID(),
            createdAt: Date = .now,
            symbol: String = "moon.stars.fill"
        ) -> TarotReadingRecord {
            TarotReadingRecord(
                id: id,
                createdAt: createdAt,
                topicTitle: "Today",
                topicEnglish: "TODAY",
                question: "What should I notice?",
                cardName: "The Moon",
                answer: "Pause and look again.",
                detail: "A verifier reading.",
                orientation: .upright,
                cardSymbol: symbol,
                keywords: "pause · notice"
            )
        }

        verifyIndependentCommitRestartAndMembership(
            defaults: isolatedDefaults("normal"),
            session: session("normal"),
            makeStore: makeStore,
            makeReading: reading
        )
        verifyGuidePersistenceRollback(
            defaults: isolatedDefaults("guide-failure"),
            session: session("guide-failure"),
            makeStore: makeStore
        )
        verifyTarotPersistenceRollback(
            defaults: isolatedDefaults("tarot-failure"),
            session: session("tarot-failure"),
            makeStore: makeStore,
            makeReading: reading
        )
        verifyAllLooksSelectionProvenance(
            defaults: isolatedDefaults("all-looks-provenance"),
            session: session("all-looks-provenance"),
            makeStore: makeStore
        )
        verifyStoreKitAppAccountTokenIdentity(
            sameAccountDefaultsA: isolatedDefaults("token-same-a"),
            sameAccountDefaultsB: isolatedDefaults("token-same-b"),
            differentAccountDefaults: isolatedDefaults("token-different"),
            guestDefaults: isolatedDefaults("token-guest"),
            sameAccountSession: session("token-same"),
            differentAccountSession: session("token-different"),
            makeStore: makeStore
        )

        print(
            "AppStore daily guide/tarot independence, cancellation, restart persistence, "
                + "membership bypass, all-looks entitlement lifecycle, StoreKit account tokens, "
                + "and persistence rollback verified"
        )
    }

    @MainActor
    private static func verifyIndependentCommitRestartAndMembership(
        defaults: UserDefaults,
        session: AuthSession,
        makeStore: (UserDefaults, MemorySessionVault) -> AppStore,
        makeReading: (UUID, Date, String) -> TarotReadingRecord
    ) {
        let vault = MemorySessionVault(session: session)
        let today = commitInitialNonMemberQuotas(
            defaults: defaults,
            vault: vault,
            makeStore: makeStore,
            makeReading: makeReading
        )

        // The first AppStore is out of scope. Reconstruct the real AppStore with
        // the same account vault and defaults, matching a fresh launch boundary.
        let restartedStore = makeStore(defaults, vault)
        precondition(restartedStore.dailyGuideRevealDate == today)
        precondition(restartedStore.tarotDrawDate == today)
        precondition(!restartedStore.canRevealGuideToday)
        precondition(!restartedStore.canDrawTarotToday)
        precondition(restartedStore.readingHistory.count == 1)

        // A verified entitlement feeds AppStore's single membership source of
        // truth and makes both already-used quotas available again. Multiple
        // same-kind reservations are valid for a member and do not move stamps.
        restartedStore.updateMembership(true)
        precondition(restartedStore.canRevealGuideToday)
        precondition(restartedStore.canDrawTarotToday)

        let memberGuideA = require(restartedStore.reserveDailyGuideReveal(dayStamp: today))
        let memberGuideB = require(restartedStore.reserveDailyGuideReveal(dayStamp: today))
        precondition(restartedStore.completeDailyGuideReveal(memberGuideA))
        precondition(restartedStore.completeDailyGuideReveal(memberGuideB))
        precondition(restartedStore.dailyGuideRevealDate == today)

        let memberStartedAt = Date.now
        let memberTarotA = require(restartedStore.reserveTarotDraw(at: memberStartedAt))
        let memberTarotB = require(restartedStore.reserveTarotDraw(at: memberStartedAt))
        precondition(restartedStore.completeTarotDraw(
            memberTarotA,
            reading: makeReading(
                UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
                memberStartedAt,
                "sun.max.fill"
            )
        ) != nil)
        precondition(restartedStore.completeTarotDraw(
            memberTarotB,
            reading: makeReading(
                UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
                memberStartedAt,
                "heart.fill"
            )
        ) != nil)
        precondition(restartedStore.tarotDrawDate == today)
        precondition(restartedStore.readingHistory.count == 3)
        precondition(restartedStore.canRevealGuideToday)
        precondition(restartedStore.canDrawTarotToday)
    }

    @MainActor
    private static func commitInitialNonMemberQuotas(
        defaults: UserDefaults,
        vault: MemorySessionVault,
        makeStore: (UserDefaults, MemorySessionVault) -> AppStore,
        makeReading: (UUID, Date, String) -> TarotReadingRecord
    ) -> String {
        let store = makeStore(defaults, vault)
        let today = store.currentDayStamp

        precondition(store.canRevealGuideToday)
        precondition(store.canDrawTarotToday)

        // Cancelling either kind releases its in-memory reservation and does not
        // persist a used stamp.
        let cancelledGuide = require(store.reserveDailyGuideReveal(dayStamp: today))
        store.cancelDailyAccess(cancelledGuide)
        precondition(store.dailyGuideRevealDate == nil)
        let releasedGuide = require(
            store.reserveDailyGuideReveal(dayStamp: today),
            "Expected reservation after cancellation"
        )
        precondition(
            store.reserveDailyGuideReveal(dayStamp: today) == nil,
            "A second non-member guide reservation must be blocked"
        )
        store.cancelDailyAccess(releasedGuide)

        let cancelledTarot = require(store.reserveTarotDraw())
        store.cancelDailyAccess(cancelledTarot)
        precondition(store.tarotDrawDate == nil)
        let releasedTarot = require(store.reserveTarotDraw())
        store.cancelDailyAccess(releasedTarot)

        // Guide and tarot can be reserved together, while duplicate reservations
        // of the same kind are blocked for a non-member.
        let guideReservation = require(store.reserveDailyGuideReveal(dayStamp: today))
        let tarotStartedAt = Date.now
        let tarotReservation = require(store.reserveTarotDraw(at: tarotStartedAt))
        precondition(store.reserveDailyGuideReveal(dayStamp: today) == nil)
        precondition(store.reserveTarotDraw(at: tarotStartedAt) == nil)

        precondition(store.completeDailyGuideReveal(guideReservation))
        precondition(store.dailyGuideRevealDate == today)
        precondition(store.tarotDrawDate == nil)
        precondition(!store.canRevealGuideToday)
        precondition(store.canDrawTarotToday)

        let firstReading = makeReading(
            UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            tarotStartedAt,
            "moon.stars.fill"
        )
        precondition(store.completeTarotDraw(tarotReservation, reading: firstReading) != nil)
        precondition(store.dailyGuideRevealDate == today)
        precondition(store.tarotDrawDate == today)
        precondition(!store.canRevealGuideToday)
        precondition(!store.canDrawTarotToday)
        precondition(store.readingHistory.count == 1)
        return today
    }

    @MainActor
    private static func verifyGuidePersistenceRollback(
        defaults: UserDefaults,
        session: AuthSession,
        makeStore: (UserDefaults, MemorySessionVault) -> AppStore
    ) {
        let vault = MemorySessionVault(session: session)
        let store = makeStore(defaults, vault)
        let today = store.currentDayStamp
        let reservation = require(store.reserveDailyGuideReveal(dayStamp: today))

        AccountStorage(defaults: defaults).protectFromAutomaticWrites(
            for: session.account.canonicalLocalAccountID
        )
        precondition(!store.completeDailyGuideReveal(reservation))
        precondition(store.dailyGuideRevealDate == nil)
        precondition(store.tarotDrawDate == nil)
    }

    @MainActor
    private static func verifyTarotPersistenceRollback(
        defaults: UserDefaults,
        session: AuthSession,
        makeStore: (UserDefaults, MemorySessionVault) -> AppStore,
        makeReading: (UUID, Date, String) -> TarotReadingRecord
    ) {
        let vault = MemorySessionVault(session: session)
        let store = makeStore(defaults, vault)
        let startedAt = Date.now
        let reservation = require(store.reserveTarotDraw(at: startedAt))
        let previousStamp = store.tarotDrawDate
        let previousHistory = store.readingHistory
        let previousWardrobe = store.wardrobe

        AccountStorage(defaults: defaults).protectFromAutomaticWrites(
            for: session.account.canonicalLocalAccountID
        )
        let result = store.completeTarotDraw(
            reservation,
            reading: makeReading(
                UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
                startedAt,
                "moon.stars.fill"
            )
        )
        precondition(result == nil)
        precondition(store.tarotDrawDate == previousStamp)
        precondition(store.readingHistory == previousHistory)
        precondition(store.wardrobe == previousWardrobe)
        precondition(store.dailyGuideRevealDate == nil)
    }

    @MainActor
    private static func verifyAllLooksSelectionProvenance(
        defaults: UserDefaults,
        session: AuthSession,
        makeStore: (UserDefaults, MemorySessionVault) -> AppStore
    ) {
        let vault = MemorySessionVault(session: session)
        let store = makeStore(defaults, vault)
        let startingCoins = store.wardrobe.starCoins

        // Establish a real coin-owned item first. A later entitlement removal
        // may clear paid-only selections, but must not erase this ownership.
        let coinAccessory = require(
            StarAccessory.allCases
                .filter { $0.price > 0 && !store.wardrobe.ownedAccessories.contains($0) }
                .sorted { $0.price < $1.price }
                .first
        )
        precondition(store.purchaseAccessory(coinAccessory))
        precondition(store.wardrobe.ownedAccessories.contains(coinAccessory))
        precondition(store.wardrobe.starCoins == startingCoins - coinAccessory.price)

        let entitlementAccessory = require(
            StarAccessory.allCases.first {
                $0.price > 0 && !store.wardrobe.ownedAccessories.contains($0)
            }
        )
        let initialCoins = store.wardrobe.starCoins
        let initiallyOwnedPersonas = store.wardrobe.ownedPersonas
        let initiallyOwnedSkins = store.wardrobe.ownedCollectionSkinIDs
        let initiallyOwnedAccessories = store.wardrobe.ownedAccessories
        let appAccountToken = require(store.storeKitAppAccountToken)

        store.updateAllLooksEntitlement(true)
        precondition(store.purchasePersona(.halloweenGhost, hasAllLooksUnlocked: true))
        precondition(store.wardrobe.selectedPersona == .halloweenGhost)
        precondition(store.wardrobe.selectedPersonaRequiresAllLooks == true)
        precondition(!store.wardrobe.availablePersonas.contains(.halloweenGhost))

        let paidCollection = require(
            StarSkinCatalog.all.first { !store.wardrobe.availableCollectionSkinIDs.contains($0.id) }
        )
        precondition(store.purchaseCollectionSkin(paidCollection, hasAllLooksUnlocked: true))
        precondition(store.wardrobe.selectedCollectionSkinID == paidCollection.id)
        precondition(store.wardrobe.selectedCollectionSkinRequiresAllLooks == true)
        precondition(store.wardrobe.selectedPersonaRequiresAllLooks == true)
        precondition(!store.wardrobe.availableCollectionSkinIDs.contains(paidCollection.id))

        precondition(store.purchaseAccessory(entitlementAccessory, hasAllLooksUnlocked: true))
        precondition(store.wardrobe.selectedAccessory == entitlementAccessory)
        precondition(store.wardrobe.selectedAccessoryRequiresAllLooks == true)
        precondition(store.wardrobe.starCoins == initialCoins)
        precondition(store.wardrobe.ownedPersonas == initiallyOwnedPersonas)
        precondition(store.wardrobe.ownedCollectionSkinIDs == initiallyOwnedSkins)
        precondition(store.wardrobe.ownedAccessories == initiallyOwnedAccessories)

        // A cold launch is fail-closed while StoreKit is still checking. Once
        // the verified entitlement arrives, all three saved selections return.
        let entitledRestart = makeStore(defaults, vault)
        precondition(entitledRestart.wardrobe.selectedCollectionSkinID == nil)
        precondition(entitledRestart.wardrobe.selectedPersona == .classic)
        precondition(entitledRestart.wardrobe.selectedAccessory == .none)
        entitledRestart.updateAllLooksEntitlement(true)
        precondition(entitledRestart.wardrobe.selectedCollectionSkinID == paidCollection.id)
        precondition(entitledRestart.wardrobe.selectedPersona == .halloweenGhost)
        precondition(entitledRestart.wardrobe.selectedAccessory == entitlementAccessory)
        precondition(entitledRestart.wardrobe.selectedPersonaRequiresAllLooks == true)
        precondition(entitledRestart.wardrobe.selectedCollectionSkinRequiresAllLooks == true)
        precondition(entitledRestart.wardrobe.selectedAccessoryRequiresAllLooks == true)

        // Simulate a refund/revocation after selecting a paid persona, then a
        // paid collection skin. Both provenance flags must fall back; the
        // hidden paid persona must not reappear behind the collection.
        entitledRestart.updateAllLooksEntitlement(false)
        precondition(entitledRestart.wardrobe.selectedCollectionSkinID == nil)
        precondition(entitledRestart.wardrobe.selectedPersona == .classic)
        precondition(entitledRestart.wardrobe.selectedAccessory == .none)
        precondition(entitledRestart.wardrobe.selectedPersonaRequiresAllLooks != true)
        precondition(entitledRestart.wardrobe.selectedCollectionSkinRequiresAllLooks != true)
        precondition(entitledRestart.wardrobe.selectedAccessoryRequiresAllLooks != true)
        precondition(entitledRestart.wardrobe.ownedPersonas == initiallyOwnedPersonas)
        precondition(entitledRestart.wardrobe.ownedCollectionSkinIDs == initiallyOwnedSkins)
        precondition(entitledRestart.wardrobe.ownedAccessories == initiallyOwnedAccessories)
        precondition(entitledRestart.wardrobe.ownedAccessories.contains(coinAccessory))

        let restarted = makeStore(defaults, vault)
        restarted.updateAllLooksEntitlement(false)
        precondition(restarted.wardrobe.selectedCollectionSkinID == nil)
        precondition(restarted.wardrobe.selectedPersona == .classic)
        precondition(restarted.wardrobe.selectedAccessory == .none)
        precondition(restarted.storeKitAppAccountToken == appAccountToken)
        precondition(!restarted.wardrobe.availablePersonas.contains(.halloweenGhost))
        precondition(!restarted.wardrobe.availableCollectionSkinIDs.contains(paidCollection.id))
        precondition(restarted.wardrobe.ownedAccessories.contains(coinAccessory))
        restarted.selectAccessory(coinAccessory)
        precondition(restarted.wardrobe.selectedAccessory == coinAccessory)
        precondition(restarted.wardrobe.selectedAccessoryRequiresAllLooks != true)
    }

    @MainActor
    private static func verifyStoreKitAppAccountTokenIdentity(
        sameAccountDefaultsA: UserDefaults,
        sameAccountDefaultsB: UserDefaults,
        differentAccountDefaults: UserDefaults,
        guestDefaults: UserDefaults,
        sameAccountSession: AuthSession,
        differentAccountSession: AuthSession,
        makeStore: (UserDefaults, MemorySessionVault) -> AppStore
    ) {
        let first = makeStore(
            sameAccountDefaultsA,
            MemorySessionVault(session: sameAccountSession)
        )
        let second = makeStore(
            sameAccountDefaultsB,
            MemorySessionVault(session: sameAccountSession)
        )
        let different = makeStore(
            differentAccountDefaults,
            MemorySessionVault(session: differentAccountSession)
        )
        let guest = makeStore(guestDefaults, MemorySessionVault())

        let firstToken = require(first.storeKitAppAccountToken)
        precondition(second.storeKitAppAccountToken == firstToken)
        precondition(different.storeKitAppAccountToken != firstToken)
        precondition(guest.storeKitAppAccountToken == nil)
        precondition((firstToken.uuid.6 & 0xF0) == 0x80)
        precondition((firstToken.uuid.8 & 0xC0) == 0x80)
    }

    private static func require<Value>(_ value: Value?, _ message: String = "Expected value") -> Value {
        guard let value else { preconditionFailure(message) }
        return value
    }
}
