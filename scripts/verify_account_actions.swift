import Combine
import Foundation

@MainActor final class LiveActivityController {
    static let shared = LiveActivityController()
    func sync(food: Int, status: String, language: AppLanguage, allowsNewActivity: Bool) async {}
    func end(language: AppLanguage) async {}
}

private actor ActionService: AccountCloudSyncing {
    nonisolated let isConfigured = true
    var deletionCalls: [(String, String)] = []
    var snapshotCalls = 0
    var failDeletion = true
    var inviteCalls = 0
    var holdsFetch = false
    var fetchContinuation: CheckedContinuation<PlanetMembership?, Error>?
    var hasWaitingFetch: Bool { fetchContinuation != nil }
    func holdFetch() { holdsFetch = true }
    func finishFetch() {
        holdsFetch = false
        fetchContinuation?.resume(returning: membership)
        fetchContinuation = nil
    }
    let membership = PlanetMembership(id: "planet-a", relationship: .bestie, members: [
        .init(accountID: "alice", name: "Alice", personaID: "classic"),
        .init(accountID: "bob", name: "Bob", personaID: "moonveil")
    ])
    func succeedDeletion() { failDeletion = false }
    func fetchSnapshot(accessToken: String) async throws -> AccountCloudSnapshot? {
        snapshotCalls += 1
        return nil
    }
    func uploadSnapshot(_ snapshot: AccountLocalData, baseRevision: String?, mutationID: String, accessToken: String) async throws -> AccountCloudSnapshot {
        snapshotCalls += 1
        return .init(revision: "1", updatedAt: .now, snapshot: snapshot)
    }
    func deleteSnapshot(baseRevision: String, mutationID: String, accessToken: String) async throws { fatalError("Account deletion must not call snapshot deletion") }
    func deleteAccount(requestID: String, accessToken: String) async throws {
        deletionCalls.append((requestID, accessToken))
        if failDeletion { throw AccountActionError(code: "apple_revoke_failed") }
    }
    func fetchPlanet(accessToken: String) async throws -> PlanetMembership? {
        if holdsFetch {
            return try await withCheckedThrowingContinuation { fetchContinuation = $0 }
        }
        return membership
    }
    func acceptPlanetInvite(code: String, accessToken: String) async throws -> PlanetMembership {
        inviteCalls += 1
        return membership
    }
}

private final class FailingClearVault: SessionVaulting {
    var value: AuthSession?
    var fails = true
    init(_ session: AuthSession) { value = session }
    func load() throws -> AuthSession? { value }
    func save(_ session: AuthSession) throws { value = session }
    func clear() throws {
        if fails { throw SessionVaultError.encodingFailed }
        value = nil
    }
}

@main struct VerifyAccountActions {
    @MainActor static func main() async throws {
        let code = "SC-0123-4567-89AB-CDEF-GHJK-MNPQ-RS"
        precondition(PlanetInviteCode.parse(code.lowercased(), allowedHost: nil) == code)
        precondition(PlanetInviteCode.parse("starcompanion://invite?code=\(code)", allowedHost: nil) == code)
        precondition(PlanetInviteCode.parse("https://api.test/invite#code=\(code)", allowedHost: "api.test") == code)
        precondition(PlanetInviteCode.parse("HTTPS://API.TEST/invite#code=\(code)", allowedHost: "api.test") == code)
        precondition(PlanetInviteCode.parse("https://evil.test/invite#code=\(code)", allowedHost: "api.test") == nil)
        precondition(PlanetInviteCode.parse("https://api.test/invite?code=\(code)", allowedHost: "api.test") == nil)
        precondition(PlanetInviteCode.parse("starcompanion://invite?code=\(code)&code=\(code)", allowedHost: nil) == nil)
        precondition(PlanetInviteCode.parse("https://example.com/star-invite?planet=demo-planet&token=demo-preview-only", allowedHost: "example.com") == nil)

        let suite = "verify.account-actions.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let account = AppAccount(provider: .apple, providerSubject: "apple-a", displayName: "Alice", canonicalAccountID: "alice")
        let session = AuthSession(account: account, assurance: .backendVerified, expiresAt: .now.addingTimeInterval(3600), accessToken: "access-alice", refreshToken: "refresh-alice")
        let vault = MemorySessionVault(session: session)
        let service = ActionService()
        let storage = AccountStorage(defaults: defaults)
        var alice = AccountLocalData.seeded(for: account.id)
        alice.wardrobe.starCoins = 177
        precondition(storage.save(alice, for: account.id))
        var bob = AccountLocalData.seeded(for: "account:bob")
        bob.wardrobe.starCoins = 299
        precondition(storage.save(bob, for: "account:bob"))
        let store = AppStore(accountCloudSyncService: service, cancelAccountReminders: {}, sessionVault: vault, defaults: defaults)
        store.handleIncomingURL(URL(string: "starcompanion://invite?code=\(code)")!)
        precondition(store.pendingPlanetInviteCode == code)
        let joined = await store.acceptPlanetInvite(code)
        precondition(joined && store.sharedMembership?.members.count == 2)
        precondition(store.visiblePlanetMembers.filter(\.isCurrentUser).first?.id == "alice")

        await store.deleteAccountPermanently()
        precondition(store.deletionIntent != nil && !store.isDeletingAccount)
        precondition(store.account?.id == account.id && store.deletionError != nil)
        let retainedSession = try vault.load()
        precondition(retainedSession == session)
        precondition(!store.canFeedPet && !store.canUseAccountActions)
        let before = await service.snapshotCalls
        store.startAccountCloudSync()
        try await Task.sleep(for: .milliseconds(80))
        let after = await service.snapshotCalls
        precondition(before == after, "Deletion pending must never upload or fetch snapshots")
        store.logout()
        precondition(store.account != nil, "An uncertain deletion must retain its retry credential")
        let requestID = store.deletionIntent!.requestID
        let expired = AuthSession(account: account, assurance: .backendVerified, expiresAt: .now.addingTimeInterval(-3600), accessToken: "access-alice", refreshToken: "refresh-alice")
        try vault.save(expired)
        let reopened = AppStore(accountCloudSyncService: service, cancelAccountReminders: {}, sessionVault: vault, defaults: defaults)
        precondition(reopened.account?.id == account.id && reopened.deletionIntent?.requestID == requestID)
        await service.succeedDeletion()
        await reopened.deleteAccountPermanently()
        precondition(reopened.account == nil && reopened.deletionIntent == nil)
        let clearedSession = try vault.load()
        precondition(clearedSession == nil)
        precondition(storage.loadResult(for: account.id).status == .missing)
        precondition(storage.loadResult(for: "account:bob").data.wardrobe.starCoins == 299)
        let calls = await service.deletionCalls
        precondition(calls.count >= 2 && calls.allSatisfy { $0.0 == requestID && $0.1 == "access-alice" })

        let failingVault = FailingClearVault(session)
        let cleanup = AppStore(accountCloudSyncService: service, cancelAccountReminders: {}, sessionVault: failingVault, defaults: defaults)
        await cleanup.deleteAccountPermanently()
        precondition(cleanup.deletionIntent?.serverDeleted == true && cleanup.account != nil)
        let countBefore = await service.deletionCalls.count
        failingVault.fails = false
        failingVault.value = nil // Simulate stopping after Keychain was cleared.
        let restartedCleanup = AppStore(accountCloudSyncService: service, cancelAccountReminders: {}, sessionVault: failingVault, defaults: defaults)
        await restartedCleanup.deleteAccountPermanently()
        let countAfter = await service.deletionCalls.count
        precondition(countBefore == countAfter && restartedCleanup.account == nil && restartedCleanup.deletionIntent == nil, "Keychain retry must not repeat successful server deletion")

        let delayedService = ActionService()
        await delayedService.holdFetch()
        let delayedStore = AppStore(accountCloudSyncService: delayedService, cancelAccountReminders: {}, sessionVault: MemorySessionVault(session: session), defaults: defaults)
        let fetchTask = Task { await delayedStore.refreshSharedPlanet() }
        for _ in 0..<1000 {
            if await delayedService.hasWaitingFetch { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let waiting = await delayedService.hasWaitingFetch
        precondition(waiting, "delayed membership request should be in flight")
        delayedStore.logout()
        await delayedService.finishFetch()
        await fetchTask.value
        precondition(delayedStore.account == nil && delayedStore.sharedMembership == nil && !delayedStore.isLoadingPlanet,
                     "A late membership response must not restore another account's members after logout")

        let preview = AuthSession(account: account, assurance: .localPreview)
        let previewStore = AppStore(accountCloudSyncService: service, cancelAccountReminders: {}, sessionVault: MemorySessionVault(session: preview), defaults: defaults)
        await previewStore.deleteAccountPermanently()
        let previewJoined = await previewStore.acceptPlanetInvite(code)
        precondition(!previewJoined && previewStore.deletionIntent == nil)
        let finalCount = await service.deletionCalls.count
        precondition(finalCount == countAfter)

        precondition(storage.save(alice, for: account.id))
        let replacementAccount = AppAccount(provider: .apple, providerSubject: "apple-a", displayName: "Alice", canonicalAccountID: "acc-new-instance")
        let replacementSession = AuthSession(account: replacementAccount, assurance: .backendVerified, expiresAt: .now.addingTimeInterval(3600), accessToken: "replacement-access", refreshToken: "replacement-refresh")
        let replacement = AppStore(accountCloudSyncService: service, cancelAccountReminders: {}, sessionVault: MemorySessionVault(session: replacementSession), defaults: defaults)
        precondition(replacement.account?.id == replacementAccount.id && replacement.wardrobe.starCoins != alice.wardrobe.starCoins,
                     "A newly registered account instance must not load the old canonical account cache")
        print("Account actions: invite validation, membership, stale response isolation, deletion retry, expiry recovery, scoped cleanup, Keychain retry, and preview isolation passed")
    }
}
