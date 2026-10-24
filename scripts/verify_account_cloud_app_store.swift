import Combine
import Foundation

// ActivityKit is not available to this host-side executable. AppStore only
// needs this no-op surface; all cloud, account, and persistence code remains
// the production implementation compiled below.
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

private struct CloudFetchCall {
    let id: Int
    let accessToken: String
}

private struct CloudUploadCall {
    let id: Int
    let snapshot: AccountLocalData
    let baseRevision: String?
    let mutationID: String
    let accessToken: String
}

private enum FetchResolution {
    case value(AccountCloudSnapshot?)
    case failure(AccountCloudSyncServiceError)
}

private enum UploadResolution {
    case value(AccountCloudSnapshot)
    case failure(AccountCloudSyncServiceError)
}

private actor ControllableAccountCloudService: AccountCloudSyncing {
    nonisolated let isConfigured = true

    private struct PendingFetch {
        let call: CloudFetchCall
        let continuation: CheckedContinuation<FetchResolution, Never>
    }

    private struct PendingUpload {
        let call: CloudUploadCall
        let continuation: CheckedContinuation<UploadResolution, Never>
    }

    private struct FetchWaiter {
        let index: Int
        let continuation: CheckedContinuation<CloudFetchCall, Never>
    }

    private struct UploadWaiter {
        let index: Int
        let continuation: CheckedContinuation<CloudUploadCall, Never>
    }

    private var fetchCalls: [CloudFetchCall] = []
    private var uploadCalls: [CloudUploadCall] = []
    private var pendingFetches: [PendingFetch] = []
    private var pendingUploads: [PendingUpload] = []
    private var fetchWaiters: [FetchWaiter] = []
    private var uploadWaiters: [UploadWaiter] = []

    func fetchSnapshot(accessToken: String) async throws -> AccountCloudSnapshot? {
        let resolution = await withCheckedContinuation { continuation in
            let call = CloudFetchCall(id: fetchCalls.count, accessToken: accessToken)
            fetchCalls.append(call)
            pendingFetches.append(PendingFetch(call: call, continuation: continuation))
            fulfillFetchWaiters()
        }
        switch resolution {
        case let .value(value): return value
        case let .failure(error): throw error
        }
    }

    func uploadSnapshot(
        _ snapshot: AccountLocalData,
        baseRevision: String?,
        mutationID: String,
        accessToken: String
    ) async throws -> AccountCloudSnapshot {
        let resolution = await withCheckedContinuation { continuation in
            let call = CloudUploadCall(
                id: uploadCalls.count,
                snapshot: snapshot,
                baseRevision: baseRevision,
                mutationID: mutationID,
                accessToken: accessToken
            )
            uploadCalls.append(call)
            pendingUploads.append(PendingUpload(call: call, continuation: continuation))
            fulfillUploadWaiters()
        }
        switch resolution {
        case let .value(value): return value
        case let .failure(error): throw error
        }
    }

    func deleteSnapshot(
        baseRevision: String,
        mutationID: String,
        accessToken: String
    ) async throws {
        throw AccountCloudSyncServiceError.invalidResponse
    }

    func waitForFetchCall(at index: Int) async -> CloudFetchCall {
        if fetchCalls.indices.contains(index) { return fetchCalls[index] }
        return await withCheckedContinuation { continuation in
            fetchWaiters.append(FetchWaiter(index: index, continuation: continuation))
        }
    }

    func waitForUploadCall(at index: Int) async -> CloudUploadCall {
        if uploadCalls.indices.contains(index) { return uploadCalls[index] }
        return await withCheckedContinuation { continuation in
            uploadWaiters.append(UploadWaiter(index: index, continuation: continuation))
        }
    }

    func resolveFetch(id: Int, with value: AccountCloudSnapshot?) {
        resolveFetch(id: id, as: .value(value))
    }

    func failFetch(id: Int, with error: AccountCloudSyncServiceError) {
        resolveFetch(id: id, as: .failure(error))
    }

    func resolveUpload(id: Int, with value: AccountCloudSnapshot) {
        resolveUpload(id: id, as: .value(value))
    }

    func failUpload(id: Int, with error: AccountCloudSyncServiceError) {
        resolveUpload(id: id, as: .failure(error))
    }

    func uploadCallCount() -> Int { uploadCalls.count }
    func fetchCallCount() -> Int { fetchCalls.count }

    private func resolveFetch(id: Int, as resolution: FetchResolution) {
        guard let index = pendingFetches.firstIndex(where: { $0.call.id == id }) else {
            preconditionFailure("No pending fetch with id \(id)")
        }
        let pending = pendingFetches.remove(at: index)
        pending.continuation.resume(returning: resolution)
    }

    private func resolveUpload(id: Int, as resolution: UploadResolution) {
        guard let index = pendingUploads.firstIndex(where: { $0.call.id == id }) else {
            preconditionFailure("No pending upload with id \(id)")
        }
        let pending = pendingUploads.remove(at: index)
        pending.continuation.resume(returning: resolution)
    }

    private func fulfillFetchWaiters() {
        var unresolved: [FetchWaiter] = []
        for waiter in fetchWaiters {
            if fetchCalls.indices.contains(waiter.index) {
                waiter.continuation.resume(returning: fetchCalls[waiter.index])
            } else {
                unresolved.append(waiter)
            }
        }
        fetchWaiters = unresolved
    }

    private func fulfillUploadWaiters() {
        var unresolved: [UploadWaiter] = []
        for waiter in uploadWaiters {
            if uploadCalls.indices.contains(waiter.index) {
                waiter.continuation.resume(returning: uploadCalls[waiter.index])
            } else {
                unresolved.append(waiter)
            }
        }
        uploadWaiters = unresolved
    }
}

private struct FixedPhoneOTPService: PhoneOTPServicing {
    let session: AuthSession

    func requestCode(for phoneNumber: E164PhoneNumber) async throws -> PhoneOTPChallenge {
        PhoneOTPChallenge(
            id: "cloud-switch-challenge",
            maskedDestination: phoneNumber.maskedDescription,
            expiresAt: Date.now.addingTimeInterval(300),
            resendAvailableAt: .now,
            maxAttempts: 5,
            remainingAttempts: 5
        )
    }

    func verify(challengeID: String, code: String) async throws -> AuthSession {
        guard challengeID == "cloud-switch-challenge", code == "123456" else {
            throw PhoneOTPServiceError.invalidCode(remainingAttempts: 4)
        }
        return session
    }
}

private actor FixedSessionRefreshService: AuthSessionRefreshing {
    nonisolated let isConfigured = true
    private let refreshedSession: AuthSession
    private var sourceSessions: [AuthSession] = []

    init(refreshedSession: AuthSession) {
        self.refreshedSession = refreshedSession
    }

    func refresh(_ session: AuthSession) async throws -> AuthSession {
        sourceSessions.append(session)
        return refreshedSession
    }

    func callCount() -> Int { sourceSessions.count }
}

@MainActor
private final class PublishedSubscriptionBox {
    var cancellable: AnyCancellable?
    var resumed = false
}

@main
enum VerifyAccountCloudAppStore {
    @MainActor
    static func main() async throws {
        var suites: [String] = []
        defer {
            for suite in suites {
                UserDefaults.standard.removePersistentDomain(forName: suite)
            }
        }

        func isolatedDefaults(_ label: String) -> UserDefaults {
            let suite = "xingban.verify.account-cloud.app-store.\(label).\(UUID().uuidString)"
            suites.append(suite)
            guard let defaults = UserDefaults(suiteName: suite) else {
                preconditionFailure("Could not create isolated UserDefaults suite")
            }
            defaults.removePersistentDomain(forName: suite)
            return defaults
        }

        try await verifyNewDevicePrefersRemote(defaults: isolatedDefaults("prefer-remote"))
        try await verifyFirstAccountUploadsWhenRemoteIsMissing(
            defaults: isolatedDefaults("first-upload")
        )
        try await verifyOfflineMutationKeepsDurablePending(
            defaults: isolatedDefaults("offline-pending")
        )
        try await verifyAccountSwitchRejectsStaleResponse(
            defaults: isolatedDefaults("account-switch")
        )
        try await verifyConflictPreservesBothCopies(defaults: isolatedDefaults("conflict"))
        try await verifyExpiredSessionRefreshesBeforeCloud(
            defaults: isolatedDefaults("expired-refresh")
        )
        try await verifyLocalPreviewNeverUploads(
            defaults: isolatedDefaults("preview-no-upload")
        )

        print(
            "AppStore prefer-remote bootstrap, first upload, durable offline outbox, "
                + "account-switch stale-response isolation, two-sided conflicts, token refresh, "
                + "and local-preview upload blocking verified"
        )
    }

    @MainActor
    private static func verifyNewDevicePrefersRemote(defaults: UserDefaults) async throws {
        let session = makeSession("new-device")
        let accountID = session.account.canonicalLocalAccountID
        let service = ControllableAccountCloudService()
        let store = makeStore(
            defaults: defaults,
            session: session,
            cloudService: service
        )

        precondition(store.isAccountCloudBootstrapPending)
        precondition(AccountStorage(defaults: defaults).cloudBootstrapMode(for: accountID) == .preferRemote)

        store.startAccountCloudSync()
        let fetch = await service.waitForFetchCall(at: 0)
        precondition(fetch.accessToken == session.accessToken)

        var remoteData = AccountLocalData.seeded(for: accountID)
        remoteData.profile = profile("Remote Nova", place: "Kaohsiung")
        remoteData.visitStreak = 12
        let remote = AccountCloudSnapshot(
            revision: "5",
            updatedAt: .now,
            snapshot: remoteData
        )
        let synced = statusWaiter(for: store, matching: .synced)
        await service.resolveFetch(id: fetch.id, with: remote)
        await synced.value

        precondition(store.profile?.displayName == "Remote Nova")
        precondition(store.visitStreak == 12)
        let storage = AccountStorage(defaults: defaults)
        precondition(storage.cloudAnchor(for: accountID)?.revision == "5")
        precondition(storage.cloudPendingUpload(for: accountID) == nil)
        precondition(storage.cloudBootstrapMode(for: accountID) == nil)
        let uploadCallCount = await service.uploadCallCount()
        precondition(uploadCallCount == 0)
    }

    @MainActor
    private static func verifyFirstAccountUploadsWhenRemoteIsMissing(
        defaults: UserDefaults
    ) async throws {
        let session = makeSession("first-upload")
        let accountID = session.account.canonicalLocalAccountID
        let service = ControllableAccountCloudService()
        let store = makeStore(
            defaults: defaults,
            session: session,
            cloudService: service
        )

        store.startAccountCloudSync()
        let fetch = await service.waitForFetchCall(at: 0)
        await service.resolveFetch(id: fetch.id, with: nil)
        let upload = await service.waitForUploadCall(at: 0)
        precondition(upload.accessToken == session.accessToken)
        precondition(upload.baseRevision == nil)
        precondition(!upload.mutationID.isEmpty)
        precondition(upload.snapshot == upload.snapshot.normalized(for: accountID))

        let synced = statusWaiter(for: store, matching: .synced)
        await service.resolveUpload(
            id: upload.id,
            with: AccountCloudSnapshot(
                revision: "1",
                updatedAt: .now,
                snapshot: upload.snapshot
            )
        )
        await synced.value

        let storage = AccountStorage(defaults: defaults)
        precondition(storage.cloudAnchor(for: accountID)?.revision == "1")
        precondition(storage.cloudPendingUpload(for: accountID) == nil)
    }

    @MainActor
    private static func verifyOfflineMutationKeepsDurablePending(
        defaults: UserDefaults
    ) async throws {
        let session = makeSession("offline")
        let accountID = session.account.canonicalLocalAccountID
        let service = ControllableAccountCloudService()
        let store = makeStore(
            defaults: defaults,
            session: session,
            cloudService: service
        )

        store.startAccountCloudSync()
        let fetch = await service.waitForFetchCall(at: 0)
        let initial = AccountCloudSnapshot(
            revision: "7",
            updatedAt: .now,
            snapshot: AccountLocalData.seeded(for: accountID)
        )
        let initiallySynced = statusWaiter(for: store, matching: .synced)
        await service.resolveFetch(id: fetch.id, with: initial)
        await initiallySynced.value

        let changedProfile = profile("Offline Orbit", place: "Tainan")
        store.saveProfile(changedProfile)
        let storage = AccountStorage(defaults: defaults)
        let durableBeforeNetwork = storage.cloudPendingUpload(for: accountID)
        precondition(durableBeforeNetwork?.baseRevision == "7")
        precondition(durableBeforeNetwork?.snapshot.profile == changedProfile)

        // AppStore owns a short production debounce. The verifier waits on the
        // actual upload call rather than guessing its timing with a sleep.
        let upload = await service.waitForUploadCall(at: 0)
        let wentOffline = statusWaiter(for: store, matching: .pendingOffline)
        await service.failUpload(id: upload.id, with: .transport)
        await wentOffline.value

        let durableAfterFailure = storage.cloudPendingUpload(for: accountID)
        precondition(durableAfterFailure?.mutationID == upload.mutationID)
        precondition(durableAfterFailure?.snapshot.profile == changedProfile)
        precondition(storage.load(for: accountID).profile == changedProfile)
    }

    @MainActor
    private static func verifyAccountSwitchRejectsStaleResponse(
        defaults: UserDefaults
    ) async throws {
        let sessionA = makeSession("switch-a")
        let sessionB = makeSession("switch-b")
        let accountBID = sessionB.account.canonicalLocalAccountID
        let service = ControllableAccountCloudService()
        let store = makeStore(
            defaults: defaults,
            session: sessionA,
            cloudService: service,
            phoneOTPService: FixedPhoneOTPService(session: sessionB)
        )

        store.startAccountCloudSync()
        let fetchA = await service.waitForFetchCall(at: 0)
        precondition(fetchA.accessToken == sessionA.accessToken)

        await store.requestPhoneOTP(phoneNumber: "+14155552671")
        await store.verifyPhoneOTP(code: "123456")
        precondition(store.account?.canonicalLocalAccountID == accountBID)
        let fetchB = await service.waitForFetchCall(at: 1)
        precondition(fetchB.accessToken == sessionB.accessToken)

        var staleWasPublished = false
        let staleMonitor = store.$profile.sink { value in
            if value?.displayName == "Stale Account A" {
                staleWasPublished = true
            }
        }

        var staleA = AccountLocalData.seeded(for: sessionA.account.canonicalLocalAccountID)
        staleA.profile = profile("Stale Account A", place: "Taipei")
        await service.resolveFetch(
            id: fetchA.id,
            with: AccountCloudSnapshot(revision: "8", updatedAt: .now, snapshot: staleA)
        )

        var remoteB = AccountLocalData.seeded(for: accountBID)
        remoteB.profile = profile("Current Account B", place: "Taichung")
        let bSynced = statusWaiter(for: store, matching: .synced)
        await service.resolveFetch(
            id: fetchB.id,
            with: AccountCloudSnapshot(revision: "3", updatedAt: .now, snapshot: remoteB)
        )
        await bSynced.value
        for _ in 0..<20 { await Task.yield() }

        precondition(!staleWasPublished)
        precondition(store.account?.canonicalLocalAccountID == accountBID)
        precondition(store.profile?.displayName == "Current Account B")
        withExtendedLifetime(staleMonitor) {}
    }

    @MainActor
    private static func verifyConflictPreservesBothCopies(defaults: UserDefaults) async throws {
        let session = makeSession("conflict")
        let accountID = session.account.canonicalLocalAccountID
        let localProfile = profile("Local Comet", place: "Hsinchu")
        var local = AccountLocalData.seeded(for: accountID)
        local.profile = localProfile
        precondition(AccountStorage(defaults: defaults).save(local, for: accountID))

        let service = ControllableAccountCloudService()
        let store = makeStore(
            defaults: defaults,
            session: session,
            cloudService: service
        )
        precondition(AccountStorage(defaults: defaults).cloudBootstrapMode(for: accountID) == .preserveLocal)

        store.startAccountCloudSync()
        let upload = await service.waitForUploadCall(at: 0)
        precondition(upload.snapshot.profile?.displayName == localProfile.displayName)
        await service.failUpload(
            id: upload.id,
            with: .conflict(currentRevision: "11")
        )
        let fetch = await service.waitForFetchCall(at: 0)
        var remote = AccountLocalData.seeded(for: accountID)
        remote.profile = profile("Remote Nebula", place: "Tokyo")
        let remoteSnapshot = AccountCloudSnapshot(
            revision: "11",
            updatedAt: .now,
            snapshot: remote
        )
        let conflicted = statusWaiter(for: store, matching: .conflict)
        await service.resolveFetch(id: fetch.id, with: remoteSnapshot)
        await conflicted.value

        precondition(store.profile?.displayName == localProfile.displayName)
        let storage = AccountStorage(defaults: defaults)
        guard let backup = storage.cloudConflictBackup(for: accountID) else {
            preconditionFailure("Expected durable two-sided conflict backup")
        }
        precondition(backup.local.snapshot.profile?.displayName == localProfile.displayName)
        precondition(backup.remote.snapshot.profile?.displayName == "Remote Nebula")
        precondition(backup.remote.revision == "11")
        precondition(storage.cloudPendingUpload(for: accountID) != nil)
        precondition(storage.cloudAnchor(for: accountID) == nil)
    }

    @MainActor
    private static func verifyExpiredSessionRefreshesBeforeCloud(
        defaults: UserDefaults
    ) async throws {
        let base = makeSession("refresh-account")
        let expired = AuthSession(
            account: base.account,
            assurance: .backendVerified,
            issuedAt: Date.now.addingTimeInterval(-7_200),
            expiresAt: Date.now.addingTimeInterval(-60),
            accessToken: "expired-access-token",
            refreshToken: "refresh-token-before-rotation"
        )
        let refreshed = AuthSession(
            account: base.account,
            assurance: .backendVerified,
            issuedAt: .now,
            expiresAt: Date.now.addingTimeInterval(3_600),
            accessToken: "rotated-access-token",
            refreshToken: "rotated-refresh-token"
        )
        let refreshService = FixedSessionRefreshService(refreshedSession: refreshed)
        let cloudService = ControllableAccountCloudService()
        let vault = MemorySessionVault(session: expired)
        let store = AppStore(
            authService: UnconfiguredWeChatAuthService(),
            appleSignInService: NativeAppleSignInService(
                exchangeService: UnconfiguredAppleCredentialExchange()
            ),
            phoneOTPService: UnconfiguredPhoneOTPService(),
            sessionRefreshService: refreshService,
            accountCloudSyncService: cloudService,
            sessionVault: vault,
            defaults: defaults
        )

        // Expired credentials never unlock local account content while the
        // refresh request is pending.
        precondition(store.account == nil)
        store.startAccountCloudSync()
        let fetch = await cloudService.waitForFetchCall(at: 0)
        precondition(fetch.accessToken == refreshed.accessToken)
        precondition(store.account == refreshed.account)
        let persistedSession = try vault.load()
        precondition(persistedSession == refreshed)
        let refreshCallCount = await refreshService.callCount()
        precondition(refreshCallCount == 1)

        let synced = statusWaiter(for: store, matching: .synced)
        await cloudService.resolveFetch(id: fetch.id, with: nil)
        let upload = await cloudService.waitForUploadCall(at: 0)
        await cloudService.resolveUpload(
            id: upload.id,
            with: AccountCloudSnapshot(
                revision: "1",
                updatedAt: .now,
                snapshot: upload.snapshot
            )
        )
        await synced.value
    }

    @MainActor
    private static func verifyLocalPreviewNeverUploads(
        defaults: UserDefaults
    ) async throws {
        let previewAccount = AppAccount(
            provider: .apple,
            providerSubject: "local-preview-subject",
            displayName: "Preview Star",
            canonicalAccountID: "preview-must-stay-local"
        )
        // Even a malformed preview carrying token-like strings must fail the
        // assurance gate before any account-service request is constructed.
        let previewSession = AuthSession(
            account: previewAccount,
            assurance: .localPreview,
            expiresAt: Date.now.addingTimeInterval(3_600),
            accessToken: "must-not-be-sent",
            refreshToken: "must-not-be-refreshed"
        )
        let cloudService = ControllableAccountCloudService()
        let store = makeStore(
            defaults: defaults,
            session: previewSession,
            cloudService: cloudService
        )

        store.startAccountCloudSync()
        store.saveProfile(profile("Local Only", place: "Taipei"))
        for _ in 0..<20 { await Task.yield() }

        let fetchCount = await cloudService.fetchCallCount()
        let uploadCount = await cloudService.uploadCallCount()
        precondition(fetchCount == 0)
        precondition(uploadCount == 0)
        precondition(store.accountCloudSyncStatus == .localOnly)
        precondition(
            AccountStorage(defaults: defaults)
                .load(for: previewAccount.canonicalLocalAccountID).profile?.displayName == "Local Only"
        )
    }

    @MainActor
    private static func makeStore(
        defaults: UserDefaults,
        session: AuthSession,
        cloudService: ControllableAccountCloudService,
        phoneOTPService: any PhoneOTPServicing = UnconfiguredPhoneOTPService(),
        sessionRefreshService: any AuthSessionRefreshing = UnconfiguredAuthSessionRefreshService()
    ) -> AppStore {
        AppStore(
            authService: UnconfiguredWeChatAuthService(),
            appleSignInService: NativeAppleSignInService(
                exchangeService: UnconfiguredAppleCredentialExchange()
            ),
            phoneOTPService: phoneOTPService,
            sessionRefreshService: sessionRefreshService,
            accountCloudSyncService: cloudService,
            sessionVault: MemorySessionVault(session: session),
            defaults: defaults
        )
    }

    private static func makeSession(_ label: String) -> AuthSession {
        AuthSession(
            account: AppAccount(
                provider: .phone,
                providerSubject: "+1555000\(label)",
                displayName: "Cloud verifier \(label)",
                canonicalAccountID: "cloud-verifier-\(label)"
            ),
            assurance: .backendVerified,
            issuedAt: .now,
            expiresAt: Date.now.addingTimeInterval(3_600),
            accessToken: "verified-cloud-access-token-\(label)",
            refreshToken: nil
        )
    }

    private static func profile(_ name: String, place: String) -> BirthProfile {
        BirthProfile(
            displayName: name,
            birthDate: Date(timeIntervalSince1970: 946_684_800),
            birthTimeMinutes: 8 * 60 + 30,
            birthPlace: place,
            focuses: [.love, .wellbeing]
        )
    }

    @MainActor
    private static func statusWaiter(
        for store: AppStore,
        matching desired: AccountCloudSyncStatus
    ) -> Task<Void, Never> {
        Task { @MainActor in
            if store.accountCloudSyncStatus == desired { return }
            let box = PublishedSubscriptionBox()
            await withCheckedContinuation { continuation in
                box.cancellable = store.$accountCloudSyncStatus.sink { status in
                    guard status == desired, !box.resumed else { return }
                    box.resumed = true
                    box.cancellable?.cancel()
                    box.cancellable = nil
                    continuation.resume()
                }
            }
            withExtendedLifetime(box) {}
        }
    }
}
