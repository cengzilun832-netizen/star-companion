import AuthenticationServices
import Combine
import CryptoKit
import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var account: AppAccount?
    @Published private(set) var profile: BirthProfile?
    @Published private(set) var savedGuides: [DailyGuide]
    @Published private(set) var readingHistory: [TarotReadingRecord]
    @Published private(set) var visitStreak: Int
    @Published private(set) var reminderEnabled: Bool
    @Published private(set) var reminderTimeMinutes: Int
    @Published private(set) var hasMembership: Bool
    @Published private(set) var currentDayStamp: String
    @Published private(set) var dailyGuideRevealDate: String?
    @Published private(set) var tarotDrawDate: String?
    @Published var planet: SharedPlanet
    @Published private(set) var wardrobe: StarWardrobe
    @Published private(set) var starLife: StarLifeState
    @Published private(set) var language: AppLanguage
    @Published var isLoggingIn = false
    @Published var actionState = PetActionState.waiting
    @Published var isCelebrating = false
    @Published private(set) var bondSavePulse = 0
    @Published var loginError: String?
    @Published private(set) var accountDataNotice: String?
    @Published private(set) var phoneOTPChallenge: PhoneOTPChallenge?
    @Published private(set) var isRequestingPhoneOTP = false
    @Published private(set) var isVerifyingPhoneOTP = false
    @Published var phoneOTPError: String?
    @Published var reminderError: String?
    @Published private(set) var pendingHomeVisitLink: PendingHomeVisitLink?
    @Published private(set) var homeVisitLinkError: String?
    @Published private(set) var accountCloudSyncStatus: AccountCloudSyncStatus = .localOnly
    @Published private(set) var isAccountCloudBootstrapPending = false
    @Published private(set) var deletionIntent: AccountDeletionIntent?
    @Published private(set) var isDeletingAccount = false
    @Published var deletionError: String?
    @Published private(set) var sharedMembership: PlanetMembership?
    @Published private(set) var isLoadingPlanet = false
    @Published private(set) var isUpdatingPlanet = false
    @Published var planetServiceError: String?
    @Published var pendingPlanetInviteCode: String?
    private var planetGeneration = 0
    private var planetLoadID: UUID?
    private var planetMutationID: UUID?

    private let authService: any WeChatAuthenticating
    private let appleSignInService: any AppleSignInServicing
    private let phoneOTPService: any PhoneOTPServicing
    private let sessionRefreshService: any AuthSessionRefreshing
    private let accountCloudSyncService: any AccountCloudSyncing
    private let cancelAccountReminders: @Sendable () async -> Void
    private let sessionVault: any SessionVaulting
    private let defaults: UserDefaults
    private let accountStorage: AccountStorage
    private var authSession: AuthSession?
    private var pendingAppleRequest: AppleAuthorizationRequestContext?
    private var celebrationTask: Task<Void, Never>?
    private var lastVisitDate: String?
    private var accountDataWritesAllowed = true
    private var dailyAccessReservations: [UUID: DailyAccessReservation] = [:]
    private var accountCloudSyncTask: Task<Void, Never>?
    private var accountCloudSyncRequested = false
    private var accountCloudSyncGeneration = 0
    private var sessionRefreshTask: Task<Void, Never>?
    private var expiredSessionAwaitingRefresh: AuthSession?
    private var isApplyingCloudSnapshot = false
    private var isPreparingAccountState = true
    private var allLooksEntitlementState = AllLooksEntitlementState.unchecked
    private var deferredAllLooksSelection: StarWardrobe?

    private enum AllLooksEntitlementState {
        case unchecked
        case active
        case inactive
    }

    private enum Key {
        static let deletionIntent = "xingban.ios.account-deletion.v1"
        static let user = "xingban.ios.wechat-user.v1"
        static let language = "xingban.ios.language.v1"
        static let reminderEnabled = "xingban.ios.reminder-enabled.v1"
        static let reminderTime = "xingban.ios.reminder-time.v1"
    }

    private enum AccountActivationError: Error {
        case localMigrationFailed
        case localPersistenceFailed
        case sessionRecoveryFailed
    }

    private struct AccountCloudSyncContext: Equatable {
        let generation: Int
        let accountID: String
        let accessToken: String
    }

    init(
        authService: (any WeChatAuthenticating)? = nil,
        appleSignInService: (any AppleSignInServicing)? = nil,
        phoneOTPService: (any PhoneOTPServicing)? = nil,
        sessionRefreshService: (any AuthSessionRefreshing)? = nil,
        accountCloudSyncService: (any AccountCloudSyncing)? = nil,
        cancelAccountReminders: @escaping @Sendable () async -> Void = { FortuneReminderService.shared.cancel() },
        sessionVault: (any SessionVaulting)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.authService = authService ?? DefaultWeChatAuthService.make()
        self.appleSignInService = appleSignInService ?? DefaultAuthServices.apple()
        self.phoneOTPService = phoneOTPService ?? DefaultAuthServices.phoneOTP()
        let sessionRefreshService = sessionRefreshService ?? DefaultAuthServices.sessionRefresh()
        self.sessionRefreshService = sessionRefreshService
        self.accountCloudSyncService = accountCloudSyncService ?? DefaultAccountCloudSyncService.make()
        self.cancelAccountReminders = cancelAccountReminders
        let sessionVault = sessionVault ?? KeychainSessionVault()
        self.sessionVault = sessionVault
        self.defaults = defaults
        let accountStorage = AccountStorage(defaults: defaults)
        self.accountStorage = accountStorage
        let preferredLanguage = Locale.preferredLanguages.first ?? "zh-Hant"
        let systemLanguage: AppLanguage
        if preferredLanguage.hasPrefix("ko") {
            systemLanguage = .korean
        } else if preferredLanguage.hasPrefix("zh") {
            systemLanguage = .traditionalChinese
        } else {
            systemLanguage = .english
        }
        var initialLanguage = defaults.string(forKey: Key.language).flatMap(AppLanguage.init(rawValue:)) ?? systemLanguage
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let languageFlag = arguments.firstIndex(of: "--preview-language"),
           arguments.indices.contains(languageFlag + 1),
           let previewLanguage = AppLanguage(rawValue: arguments[languageFlag + 1]) {
            initialLanguage = previewLanguage
        }
        #endif
        language = initialLanguage
        let legacyUserRawValue = defaults.object(forKey: Key.user)
        let decodedLegacyUser = (legacyUserRawValue as? Data).flatMap {
            try? JSONDecoder().decode(WeChatUser.self, from: $0)
        }
        var storedSession: AuthSession?
        let storedDeletion = defaults.data(forKey: Key.deletionIntent).flatMap {
            try? JSONDecoder().decode(AccountDeletionIntent.self, from: $0)
        }
        var sessionVaultReadFailed = false
        var sessionVaultWriteFailed = false
        do {
            storedSession = try sessionVault.load()
        } catch {
            storedSession = nil
            sessionVaultReadFailed = true
        }

        func quarantineLegacyIdentity() {
            guard let legacyUserRawValue,
                  defaults.object(forKey: Key.user) != nil
            else { return }
            let recoveryKey = LegacyAccountStorageKey.userRecoveryPrefix + UUID().uuidString
            defaults.set(legacyUserRawValue, forKey: recoveryKey)
            if defaults.object(forKey: recoveryKey) != nil {
                defaults.removeObject(forKey: Key.user)
            }
        }

        // Migration ownership and session fallback are deliberately separate.
        // A matching legacy WeChat record may still claim pre-account globals
        // after a prior Keychain save/crash, but it must never replace an
        // existing secure session. A mismatched or unreadable identity is
        // quarantined so account A cannot reappear after account B expires.
        var legacyUserForMigration: WeChatUser?
        var legacyUserForSessionFallback: WeChatUser?
        var legacyMigrationAccount: AppAccount?
        var expiredSessionOwnsLegacyMigration = false
        if decodedLegacyUser == nil, legacyUserRawValue != nil {
            quarantineLegacyIdentity()
        } else if sessionVaultReadFailed {
            quarantineLegacyIdentity()
        } else if let secureSession = storedSession {
            if secureSession.isExpired() {
                if secureSession.account.provider == .weChat,
                   secureSession.account.providerSubject == decodedLegacyUser?.openID {
                    // Expiry ends authentication, not provenance. Use the
                    // matching secure identity once to move any pre-account
                    // globals, then require a fresh sign-in.
                    legacyUserForMigration = decodedLegacyUser
                    legacyMigrationAccount = secureSession.account
                    expiredSessionOwnsLegacyMigration = true
                } else {
                    quarantineLegacyIdentity()
                }
            } else if secureSession.account.provider == .weChat,
                      secureSession.account.providerSubject == decodedLegacyUser?.openID {
                legacyUserForMigration = decodedLegacyUser
                legacyMigrationAccount = secureSession.account
            } else {
                quarantineLegacyIdentity()
            }
        } else {
            legacyUserForMigration = decodedLegacyUser
            legacyUserForSessionFallback = decodedLegacyUser
            legacyMigrationAccount = decodedLegacyUser?.appAccount
        }

        var sessionIsPersisted = storedSession != nil
        var refreshableExpiredSession: AuthSession?
        if storedSession?.isExpired() == true, storedDeletion == nil {
            if let expiredSession = storedSession,
               expiredSession.assurance == .backendVerified,
               expiredSession.refreshToken?.isEmpty == false,
               sessionRefreshService.isConfigured {
                // Keep the expired credentials sealed in Keychain while a
                // refresh is attempted. The account is not activated and its
                // local data is not shown until the backend rotates the token.
                refreshableExpiredSession = expiredSession
            } else {
                do {
                    try sessionVault.clear()
                } catch {
                    sessionVaultReadFailed = true
                }
                sessionIsPersisted = false
            }
            storedSession = nil
            legacyUserForSessionFallback = nil
        }
        if storedSession == nil,
           !sessionVaultReadFailed,
           let legacyUser = legacyUserForSessionFallback {
            let migratedSession = AuthSession(
                account: legacyUser.appAccount,
                assurance: .legacyLocal
            )
            do {
                try sessionVault.save(migratedSession)
                sessionIsPersisted = true
                storedSession = migratedSession
            } catch {
                sessionIsPersisted = false
                sessionVaultWriteFailed = true
                storedSession = nil
            }
            legacyMigrationAccount = migratedSession.account
        }
        #if DEBUG
        if storedSession == nil,
           (ProcessInfo.processInfo.arguments.contains("--preview-logged-in")
               || ProcessInfo.processInfo.environment["STARCOMPANION_PREVIEW_LOGGED_IN"] == "1") {
            storedSession = AuthSession(
                account: AppAccount(
                    provider: .weChat,
                    providerSubject: "local-preview",
                    displayName: "Stargazer"
                ),
                assurance: .localPreview
            )
        }
        if let accountFlag = ProcessInfo.processInfo.arguments.firstIndex(of: "--preview-account-id"),
           ProcessInfo.processInfo.arguments.indices.contains(accountFlag + 1) {
            let accountID = ProcessInfo.processInfo.arguments[accountFlag + 1]
            storedSession = AuthSession(
                account: AppAccount(
                    provider: .weChat,
                    providerSubject: accountID,
                    displayName: "Stargazer"
                ),
                assurance: .localPreview
            )
        }
        #endif
        authSession = storedSession
        expiredSessionAwaitingRefresh = refreshableExpiredSession
        account = storedSession?.account
        let initialAccountID = storedSession?.account.canonicalLocalAccountID ?? AccountStorage.guestAccountID
        var migrationNeedsRecovery = false
        var initialRelinkFinalizePending = false
        var inactiveLegacyMigrationNeedsRecovery = false
        var inactiveLegacyMigrationUsedRecovery = false
        var initialRelinkConflict = false
        if let storedAccount = storedSession?.account,
           storedAccount.providerLocalAccountID != initialAccountID {
            let relinkResult = accountStorage.relinkAccountData(
                from: storedAccount.providerLocalAccountID,
                to: initialAccountID
            )
            if relinkResult == .invalidSource || relinkResult == .failedToWrite {
                migrationNeedsRecovery = true
            } else if relinkResult == .finalizePending {
                migrationNeedsRecovery = true
                initialRelinkFinalizePending = true
            } else if relinkResult == .targetAlreadyExists {
                initialRelinkConflict = true
                accountStorage.recordRelinkConflict(
                    from: storedAccount.providerLocalAccountID,
                    to: initialAccountID
                )
            }
        }
        let claimsLegacyGlobals = legacyUserForMigration != nil
            && legacyMigrationAccount?.provider == .weChat
            && legacyMigrationAccount?.providerSubject == legacyUserForMigration?.openID
        if let legacyUser = legacyUserForMigration,
           let migrationAccount = legacyMigrationAccount,
           claimsLegacyGlobals {
            let migrationAccountID = migrationAccount.canonicalLocalAccountID
            if migrationAccount.providerLocalAccountID != migrationAccountID,
               storedSession == nil {
                let relinkResult = accountStorage.relinkAccountData(
                    from: migrationAccount.providerLocalAccountID,
                    to: migrationAccountID
                )
                if relinkResult == .invalidSource
                    || relinkResult == .failedToWrite
                    || relinkResult == .finalizePending {
                    inactiveLegacyMigrationNeedsRecovery = true
                } else if relinkResult == .targetAlreadyExists {
                    accountStorage.recordRelinkConflict(
                        from: migrationAccount.providerLocalAccountID,
                        to: migrationAccountID
                    )
                }
            }
            let migrationResult = accountStorage.migrateLegacyDataIfNeeded(
                for: migrationAccountID,
                legacyProviderAccountID: legacyUser.openID,
                includeGlobalValues: true
            )
            if migrationResult == .invalidLegacyData || migrationResult == .failedToWrite {
                if migrationAccountID == initialAccountID {
                    migrationNeedsRecovery = true
                } else {
                    inactiveLegacyMigrationNeedsRecovery = true
                }
                accountStorage.protectFromAutomaticWrites(for: migrationAccountID)
            } else if migrationResult == .targetAlreadyExists {
                inactiveLegacyMigrationUsedRecovery = true
                _ = accountStorage.isolateUnownedLegacyGlobalsIfNeeded()
            } else if sessionIsPersisted || expiredSessionOwnsLegacyMigration {
                defaults.removeObject(forKey: Key.user)
            }
        } else {
            _ = accountStorage.isolateUnownedLegacyGlobalsIfNeeded()
        }
        if initialAccountID == AccountStorage.guestAccountID {
            accountStorage.removeAccountData(for: AccountStorage.guestAccountID)
        }
        let accountLoad = accountStorage.loadResult(for: initialAccountID)
        accountDataWritesAllowed = accountLoad.allowsAutomaticWrites && !migrationNeedsRecovery
        let accountData = accountLoad.data
        let canonicalSavedGuides = accountData.savedGuides.map { $0.canonicalized() }
        let canonicalReadingHistory = accountData.readingHistory.map { $0.canonicalized() }
        let localizedArchivesNeedMigration = canonicalSavedGuides != accountData.savedGuides
            || canonicalReadingHistory != accountData.readingHistory
        profile = accountData.profile
        savedGuides = canonicalSavedGuides
        readingHistory = canonicalReadingHistory
        visitStreak = accountData.visitStreak
        lastVisitDate = accountData.lastVisitDate
        dailyGuideRevealDate = accountData.dailyGuideRevealDate
        tarotDrawDate = accountData.tarotDrawDate
        planet = accountData.planet
        wardrobe = accountData.wardrobe
        starLife = accountData.starLife
        reminderEnabled = defaults.bool(forKey: Key.reminderEnabled)
        reminderTimeMinutes = defaults.object(forKey: Key.reminderTime) == nil
            ? 20 * 60 + 40
            : defaults.integer(forKey: Key.reminderTime)
        // Membership is fail-closed until StoreKit verifies the current
        // entitlement for this launch. A cached Boolean could briefly unlock
        // unlimited draws after a subscription has expired.
        hasMembership = false
        currentDayStamp = SharedPlanet.todayStamp()
        #if DEBUG
        if let themeFlag = ProcessInfo.processInfo.arguments.firstIndex(of: "--preview-room-theme"),
           ProcessInfo.processInfo.arguments.indices.contains(themeFlag + 1),
           let previewTheme = StarRoomTheme(rawValue: ProcessInfo.processInfo.arguments[themeFlag + 1]) {
            var previewHome = starLife.home ?? .starter
            previewHome.selectedRoomTheme = previewTheme
            previewHome.ownedRoomThemes = Set(StarRoomTheme.allCases)
            starLife.home = previewHome
        }
        if let auraFlag = ProcessInfo.processInfo.arguments.firstIndex(of: "--preview-tarot-aura"),
           ProcessInfo.processInfo.arguments.indices.contains(auraFlag + 1),
           let previewAura = StarAura(rawValue: ProcessInfo.processInfo.arguments[auraFlag + 1]) {
            wardrobe.tarotAura = previewAura
            wardrobe.followsTarotMeaning = true
        }
        #endif
        deferAllLooksSelectionUntilEntitlementCheck()
        prepareAccountCloudBootstrapIfNeeded(
            preserveLocal: accountLoad.status != .missing
        )
        if !accountLoad.allowsAutomaticWrites {
            loginError = initialLanguage.text(
                "偵測到一份無法讀取的本機帳號資料，已安全留存備份，本次不會覆寫。",
                "읽을 수 없는 기기 계정 데이터를 발견해 안전하게 백업했어요. 이번에는 덮어쓰지 않습니다.",
                "Unreadable local account data was backed up safely and won't be overwritten in this session."
            )
        } else if sessionVaultReadFailed {
            loginError = initialLanguage.text(
                "無法讀取安全登入憑證；已停用舊版身分回復，避免切回錯誤帳號。請重新登入。",
                "보안 로그인 정보를 읽을 수 없어 다른 계정으로 잘못 돌아가지 않도록 이전 계정 복원을 사용하지 않았어요. 다시 로그인해 주세요.",
                "The secure sign-in credential couldn't be read. Legacy identity fallback was disabled to prevent restoring the wrong account; please sign in again."
            )
        } else if sessionVaultWriteFailed {
            loginError = initialLanguage.text(
                "舊帳號資料已安全保留，但無法寫入 iOS 鑰匙圈，因此沒有恢復登入。請重新開啟 App 後再試。",
                "이전 계정 데이터는 안전하게 보관했지만 iOS 키체인에 저장하지 못해 로그인을 복원하지 않았어요. 앱을 다시 연 뒤 재시도해 주세요.",
                "The earlier account data is preserved, but sign-in wasn't restored because iOS Keychain couldn't be updated. Reopen the app and try again."
            )
        }
        if initialRelinkFinalizePending {
            accountDataNotice = initialLanguage.text(
                "帳號資料已複製完成，但最後整理尚未完成；兩份資料都會保留，本次先暫停寫入並在下次開啟時重試。",
                "계정 데이터 복사는 끝났지만 마지막 정리가 아직 완료되지 않았어요. 두 사본을 모두 보관하고 이번에는 저장을 멈춘 뒤 다음 실행 때 다시 시도합니다.",
                "Account data was copied, but final cleanup is still pending. Both copies are preserved, writes are paused for this session, and the app will retry next launch."
            )
        } else if initialRelinkConflict {
            accountDataNotice = initialLanguage.text(
                "已使用這個正式帳號原有的本機資料；登入提供者下的另一份資料仍安全保留，沒有合併或覆寫。",
                "이 정식 계정에 이미 있던 기기 데이터를 사용합니다. 로그인 제공자 쪽의 다른 데이터는 병합하거나 덮어쓰지 않고 그대로 보관했어요.",
                "Existing on-device data for this canonical account is in use. The provider-local copy was preserved without merging or overwriting it."
            )
        } else if expiredSessionOwnsLegacyMigration && inactiveLegacyMigrationNeedsRecovery {
            accountDataNotice = initialLanguage.text(
                "登入已過期，舊資料仍安全保留，但自動搬移未完成。請重新登入同一個微信帳號後再恢復寫入。",
                "로그인이 만료되었어요. 이전 데이터는 안전하게 보관했지만 자동 이전은 끝나지 않았습니다. 같은 WeChat 계정으로 다시 로그인해 주세요.",
                "Your sign-in expired. The earlier data is still protected, but automatic migration couldn't finish. Sign in again with the same WeChat account to resume safely."
            )
        } else if expiredSessionOwnsLegacyMigration && inactiveLegacyMigrationUsedRecovery {
            accountDataNotice = initialLanguage.text(
                "登入已過期。偵測到兩份本機資料，因此沒有自動覆寫；待搬資料已留在復原區，請重新登入同一帳號。",
                "로그인이 만료되었어요. 서로 다른 기기 데이터가 있어 덮어쓰지 않았고, 이전할 데이터는 복구 영역에 보관했습니다. 같은 계정으로 다시 로그인해 주세요.",
                "Your sign-in expired. Two local data sets were found, so neither was overwritten; the pending data was kept in recovery. Sign in again with the same account."
            )
        } else if expiredSessionOwnsLegacyMigration {
            accountDataNotice = initialLanguage.text(
                "登入已過期，舊資料已安全搬到原帳號。重新登入同一個微信帳號後就會回來。",
                "로그인이 만료되었지만 이전 데이터는 원래 계정으로 안전하게 옮겼어요. 같은 WeChat 계정으로 다시 로그인하면 돌아옵니다.",
                "Your sign-in expired, but the earlier data was safely assigned to its original account. Sign in again with the same WeChat account to restore it."
            )
        }
        migrateLegacyBondMemoryIfNeeded()
        refreshDailyTaskIfNeeded()
        if localizedArchivesNeedMigration, account != nil, accountDataWritesAllowed {
            _ = persistAccountData()
        }
        if account != nil {
            syncLiveActivity(allowsNewActivity: false)
        }
        isPreparingAccountState = false
        deletionIntent = storedDeletion
        if storedDeletion != nil {
            accountDataWritesAllowed = false
            resetAccountCloudSyncForAccountChange()
        }
    }

    /// Temporary compatibility bridge for existing views while authentication
    /// itself is provider-neutral.
    var user: WeChatUser? {
        account.map { WeChatUser(account: $0) }
    }

    var authProvider: AuthProvider? { account?.provider }

    var isPhoneOTPAvailable: Bool {
        !(phoneOTPService is UnconfiguredPhoneOTPService)
    }

    var isLocalPreviewSession: Bool {
        authSession?.assurance != .backendVerified
    }

    /// Runs after launch and whenever the scene becomes active. Local changes
    /// remain usable while the request is offline; the durable pending intent
    /// is retried the next time this method is called.
    func startAccountCloudSync() {
        if deletionIntent != nil {
            Task { await deleteAccountPermanently() }
            return
        }
        Task { await refreshSharedPlanet() }
        if scheduleSessionRefreshIfNeeded() { return }
        scheduleAccountCloudSync(delay: nil)
    }

    func loginWithWeChat() async {
        guard !isLoggingIn else { return }
        isLoggingIn = true
        loginError = nil
        defer { isLoggingIn = false }

        do {
            let loggedInUser = try await authService.login()
            try activateSession(
                AuthSession(account: loggedInUser.appAccount, assurance: .localPreview),
                legacyProviderAccountID: loggedInUser.openID
            )
        } catch WeChatSignInServiceError.notConfigured {
            loginError = language.text(
                "微信登入尚未連接正式服務。",
                "WeChat 로그인 서비스가 아직 연결되지 않았어요.",
                "WeChat sign-in isn't connected to the production service yet."
            )
        } catch {
            loginError = language.text("微信登入尚未完成，請再試一次。", "WeChat 로그인이 완료되지 않았어요. 다시 시도해 주세요.", "WeChat sign-in didn't finish. Please try again.")
        }
    }

    func prepareAppleSignIn(_ request: ASAuthorizationAppleIDRequest) {
        loginError = nil
        do {
            pendingAppleRequest = try appleSignInService.prepare(request)
        } catch {
            pendingAppleRequest = nil
            loginError = language.text(
                "無法安全地開始 Apple 登入，請再試一次。",
                "Apple 로그인을 안전하게 시작하지 못했어요. 다시 시도해 주세요.",
                "Apple sign-in couldn't start securely. Please try again."
            )
        }
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        guard !isLoggingIn, let context = pendingAppleRequest else {
            loginError = language.text(
                "這次 Apple 登入已失效，請重新開始。",
                "Apple 로그인 요청이 만료되었어요. 다시 시작해 주세요.",
                "This Apple sign-in request expired. Please start again."
            )
            return
        }
        pendingAppleRequest = nil
        isLoggingIn = true
        loginError = nil
        defer { isLoggingIn = false }

        do {
            let session = try await appleSignInService.complete(result, context: context)
            try activateSession(session)
        } catch AppleSignInServiceError.cancelled {
            return
        } catch AppleSignInServiceError.notConfigured {
            loginError = language.text(
                "Apple 登入的伺服器驗證尚未配置，目前不會建立正式帳號。",
                "Apple 로그인 서버 검증이 아직 설정되지 않아 정식 계정을 만들 수 없어요.",
                "Server verification for Apple sign-in isn't configured, so no production account was created."
            )
        } catch AppleSignInServiceError.stateMismatch {
            loginError = language.text(
                "已擋下這次 Apple 登入，因為安全驗證不一致。",
                "보안 확인 값이 일치하지 않아 Apple 로그인을 중단했어요.",
                "Apple sign-in was stopped because its security state didn't match."
            )
        } catch AppleSignInServiceError.rateLimited {
            loginError = language.text(
                "剛剛嘗試太多次了，等一下再用 Apple 登入。",
                "방금 시도가 너무 많았어요. 잠시 후 Apple로 다시 로그인해 주세요.",
                "There were too many sign-in attempts. Wait a moment, then try Apple again."
            )
        } catch AppleSignInServiceError.temporarilyUnavailable {
            loginError = language.text(
                "Apple 登入暫時連不上，請稍後再試。",
                "Apple 로그인에 잠시 연결할 수 없어요. 잠시 후 다시 시도해 주세요.",
                "Apple sign-in is temporarily unavailable. Please try again shortly."
            )
        } catch {
            loginError = language.text(
                "Apple 登入尚未完成，請再試一次。",
                "Apple 로그인이 완료되지 않았어요. 다시 시도해 주세요.",
                "Apple sign-in didn't finish. Please try again."
            )
        }
    }

    func requestPhoneOTP(phoneNumber input: String) async {
        guard !isRequestingPhoneOTP else { return }
        guard let phoneNumber = E164PhoneNumber(input) else {
            phoneOTPError = language.text(
                "請輸入完整國碼，例如 +886912345678。",
                "국가 코드를 포함해 입력해 주세요. 예: +821012345678",
                "Enter the full country code, for example +14155552671."
            )
            return
        }

        isRequestingPhoneOTP = true
        phoneOTPError = nil
        defer { isRequestingPhoneOTP = false }
        do {
            phoneOTPChallenge = try await phoneOTPService.requestCode(for: phoneNumber)
        } catch let error as PhoneOTPServiceError {
            phoneOTPError = phoneOTPMessage(for: error)
        } catch {
            phoneOTPError = phoneOTPMessage(for: .notConfigured)
        }
    }

    func verifyPhoneOTP(code: String) async {
        guard !isVerifyingPhoneOTP, let challenge = phoneOTPChallenge else { return }
        isVerifyingPhoneOTP = true
        phoneOTPError = nil
        defer { isVerifyingPhoneOTP = false }

        do {
            let session = try await phoneOTPService.verify(
                challengeID: challenge.id,
                code: code
            )
            try activateSession(session)
            resetPhoneOTP()
        } catch let error as PhoneOTPServiceError {
            if case let .invalidCode(remainingAttempts) = error {
                phoneOTPChallenge?.remainingAttempts = remainingAttempts
            } else if error == .tooManyAttempts {
                phoneOTPChallenge?.remainingAttempts = 0
            }
            phoneOTPError = phoneOTPMessage(for: error)
        } catch {
            phoneOTPError = language.text(
                "這次驗證沒有完成，請再試一次。",
                "인증이 완료되지 않았어요. 다시 시도해 주세요.",
                "Verification didn't finish. Please try again."
            )
        }
    }

    func resetPhoneOTP() {
        phoneOTPChallenge = nil
        phoneOTPError = nil
    }

    func setLanguage(_ language: AppLanguage) {
        self.language = language
        defaults.set(language.rawValue, forKey: Key.language)
        syncLiveActivity(allowsNewActivity: false)
    }

    var hasRevealedGuideToday: Bool {
        DailyAccessPolicy.hasUsed(
            lastUsedStamp: dailyGuideRevealDate,
            todayStamp: currentDayStamp
        )
    }

    var canRevealGuideToday: Bool {
        DailyAccessPolicy.canUse(
            isMember: hasMembership,
            lastUsedStamp: dailyGuideRevealDate,
            todayStamp: currentDayStamp
        )
    }

    var hasDrawnTarotToday: Bool {
        DailyAccessPolicy.hasUsed(
            lastUsedStamp: tarotDrawDate,
            todayStamp: currentDayStamp
        )
    }

    var canDrawTarotToday: Bool {
        DailyAccessPolicy.canUse(
            isMember: hasMembership,
            lastUsedStamp: tarotDrawDate,
            todayStamp: currentDayStamp
        )
    }

    func reserveDailyGuideReveal(dayStamp: String) -> DailyAccessReservation? {
        reserveDailyAccess(kind: .guide, dayStamp: dayStamp)
    }

    func reserveTarotDraw(at date: Date = .now, calendar: Calendar = .current) -> DailyAccessReservation? {
        reserveDailyAccess(
            kind: .tarot,
            dayStamp: SharedPlanet.todayStamp(for: date, calendar: calendar)
        )
    }

    func cancelDailyAccess(_ reservation: DailyAccessReservation) {
        dailyAccessReservations.removeValue(forKey: reservation.id)
    }

    @discardableResult
    func completeDailyGuideReveal(_ reservation: DailyAccessReservation) -> Bool {
        guard let active = dailyAccessReservations.removeValue(forKey: reservation.id),
              active == reservation,
              active.kind == .guide,
              active.accountID == currentAccountID,
              account != nil,
              accountDataWritesAllowed,
              DailyAccessPolicy.canUse(
                  isMember: active.wasMemberWhenReserved,
                  lastUsedStamp: dailyGuideRevealDate,
                  todayStamp: active.originatingDayStamp
              )
        else { return false }

        let previousStamp = dailyGuideRevealDate
        dailyGuideRevealDate = DailyAccessPolicy.stampAfterRecording(
            isMember: active.wasMemberWhenReserved,
            lastUsedStamp: dailyGuideRevealDate,
            todayStamp: active.originatingDayStamp
        )

        guard dailyGuideRevealDate != previousStamp else { return true }
        guard persistAccountData() else {
            dailyGuideRevealDate = previousStamp
            return false
        }
        return true
    }

    /// Completes the quota and diary update in one account snapshot write.
    /// The returned record includes the appearance captured at completion and
    /// is the exact value stored in the card album.
    func completeTarotDraw(
        _ reservation: DailyAccessReservation,
        reading: TarotReadingRecord,
        calendar: Calendar = .current
    ) -> TarotReadingRecord? {
        guard let active = dailyAccessReservations.removeValue(forKey: reservation.id),
              active == reservation,
              active.kind == .tarot,
              active.accountID == currentAccountID,
              account != nil,
              accountDataWritesAllowed,
              SharedPlanet.todayStamp(for: reading.createdAt, calendar: calendar) == active.originatingDayStamp,
              DailyAccessPolicy.canUse(
                  isMember: active.wasMemberWhenReserved,
                  lastUsedStamp: tarotDrawDate,
                  todayStamp: active.originatingDayStamp
              )
        else { return nil }

        let previousStamp = tarotDrawDate
        let previousHistory = readingHistory
        let previousWardrobe = wardrobe

        tarotDrawDate = DailyAccessPolicy.stampAfterRecording(
            isMember: active.wasMemberWhenReserved,
            lastUsedStamp: tarotDrawDate,
            todayStamp: active.originatingDayStamp
        )
        if wardrobe.followsTarotMeaning {
            wardrobe.tarotAura = StarAura.matchingTarot(symbol: reading.cardSymbol)
        }
        let snapshot = StarAppearanceSnapshot(
            personaID: wardrobe.displayedLookID,
            auraID: wardrobe.displayedAura.rawValue,
            accessoryID: wardrobe.selectedAccessory.rawValue,
            roomThemeID: starLife.home?.selectedRoomTheme?.rawValue,
            moodID: planet.mood.rawValue
        )
        let storedReading = reading.canonicalized().withAppearanceSnapshot(snapshot)
        readingHistory.insert(storedReading, at: 0)
        readingHistory = Array(readingHistory.prefix(365))

        guard persistAccountData() else {
            tarotDrawDate = previousStamp
            readingHistory = previousHistory
            wardrobe = previousWardrobe
            return nil
        }
        return storedReading
    }

    func refreshDailyContext() {
        let newStamp = SharedPlanet.todayStamp()
        if currentDayStamp != newStamp {
            currentDayStamp = newStamp
        }
        refreshDailyTaskIfNeeded()
    }

    private func reserveDailyAccess(
        kind: DailyAccessKind,
        dayStamp: String
    ) -> DailyAccessReservation? {
        guard account != nil, accountDataWritesAllowed else { return nil }
        let hasMatchingReservation = dailyAccessReservations.values.contains {
            $0.kind == kind
                && $0.accountID == currentAccountID
                && $0.originatingDayStamp == dayStamp
                && !$0.wasMemberWhenReserved
        }
        let lastUsedStamp = kind == .guide ? dailyGuideRevealDate : tarotDrawDate
        guard DailyAccessPolicy.canReserve(
            isMember: hasMembership,
            lastUsedStamp: lastUsedStamp,
            todayStamp: dayStamp,
            hasMatchingReservation: hasMatchingReservation
        ) else { return nil }

        let reservation = DailyAccessReservation(
            id: UUID(),
            kind: kind,
            accountID: currentAccountID,
            originatingDayStamp: dayStamp,
            wasMemberWhenReserved: hasMembership
        )
        dailyAccessReservations[reservation.id] = reservation
        return reservation
    }

    /// StoreKit entitlement updates feed this single source of truth.
    func updateMembership(_ isActive: Bool) {
        hasMembership = isActive
    }

    func saveProfile(_ profile: BirthProfile) {
        let normalizedName = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPlace = profile.birthPlace.trimmingCharacters(in: .whitespacesAndNewlines)
        self.profile = BirthProfile(
            displayName: normalizedName.isEmpty ? (user?.displayName ?? language.text("旅行者", "여행자", "Traveler")) : normalizedName,
            birthDate: profile.birthDate,
            birthTimeMinutes: profile.birthTimeMinutes,
            birthPlace: normalizedPlace,
            focuses: Array(profile.focuses.prefix(3))
        )
        persist()
    }

    func deleteProfile() {
        profile = nil
        persistAccountData()
    }

    func setRelationship(_ relationship: StarRelationship) {
        guard planet.currentRelationship != relationship else { return }
        planet.relationship = relationship
        let today = SharedPlanet.todayStamp()
        let todayMemory = planet.bondMemories?.first {
            $0.relationship == relationship && $0.dateStamp == today
        }
        planet.bondCheckInDate = todayMemory?.dateStamp
        planet.bondMood = todayMemory?.mood
        planet.bondNote = todayMemory?.note
        persist()
    }

    var hasBondCheckInToday: Bool {
        planet.bondCheckInDate == SharedPlanet.todayStamp() && planet.bondMood != nil
    }

    func saveBondCheckIn(mood: BondMood, note: String) {
        let today = SharedPlanet.todayStamp()
        let normalizedNote = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        planet.bondCheckInDate = today
        planet.bondMood = mood
        planet.bondNote = normalizedNote

        let memory = BondMemory(
            dateStamp: today,
            relationship: planet.currentRelationship,
            mood: mood,
            note: normalizedNote.isEmpty ? nil : normalizedNote
        )
        var memories = planet.bondMemories ?? []
        memories.removeAll(where: { $0.id == memory.id })
        memories.append(memory)
        let currentRelationship = planet.currentRelationship
        let currentMemories = memories
            .filter { $0.relationship == currentRelationship }
            .sorted(by: { $0.dateStamp > $1.dateStamp })
            .prefix(90)
        let otherMemories = memories.filter { $0.relationship != currentRelationship }
        planet.bondMemories = (otherMemories + currentMemories)
            .sorted(by: { $0.dateStamp > $1.dateStamp })
        bondSavePulse += 1
        persist()
    }

    var currentBondMemories: [BondMemory] {
        (planet.bondMemories ?? [])
            .filter { $0.relationship == planet.currentRelationship }
            .sorted(by: { $0.dateStamp > $1.dateStamp })
    }

    var bondStreak: Int {
        let stamps = Set(currentBondMemories.map(\.dateStamp))
        guard !stamps.isEmpty else { return 0 }

        let calendar = Calendar.current
        var cursor = Date.now
        let today = SharedPlanet.todayStamp(for: cursor, calendar: calendar)
        if !stamps.contains(today) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  stamps.contains(SharedPlanet.todayStamp(for: yesterday, calendar: calendar))
            else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        while stamps.contains(SharedPlanet.todayStamp(for: cursor, calendar: calendar)) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    func bondMemory(on date: Date) -> BondMemory? {
        let stamp = SharedPlanet.todayStamp(for: date)
        return currentBondMemories.first(where: { $0.dateStamp == stamp })
    }

    private func migrateLegacyBondMemoryIfNeeded() {
        guard (planet.bondMemories ?? []).isEmpty,
              let dateStamp = planet.bondCheckInDate,
              let mood = planet.bondMood
        else { return }

        let normalizedNote = planet.bondNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        planet.bondMemories = [BondMemory(
            dateStamp: dateStamp,
            relationship: planet.currentRelationship,
            mood: mood,
            note: normalizedNote?.isEmpty == false ? normalizedNote : nil
        )]
        persist()
    }

    func isGuideSaved(_ guide: DailyGuide) -> Bool {
        savedGuides.contains(where: { $0.id == guide.id })
    }

    func toggleSavedGuide(_ guide: DailyGuide) {
        if let index = savedGuides.firstIndex(where: { $0.id == guide.id }) {
            savedGuides.remove(at: index)
        } else {
            savedGuides.insert(guide.canonicalized(), at: 0)
            savedGuides = Array(savedGuides.prefix(30))
        }
        persist()
    }

    func removeSavedGuides(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where savedGuides.indices.contains(index) {
            savedGuides.remove(at: index)
        }
        persist()
    }

    func selectAura(_ aura: StarAura) {
        wardrobe.selectedAura = aura
        persistWardrobe()
    }

    /// A stable, one-way account token for StoreKit fraud correlation. The
    /// app account ID itself is never shared with the App Store transaction.
    var storeKitAppAccountToken: UUID? {
        guard let accountID = account?.canonicalLocalAccountID else { return nil }
        let digest = SHA256.hash(data: Data("star-companion-storekit:\(accountID)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    func updateAllLooksEntitlement(_ isUnlocked: Bool) {
        let nextState: AllLooksEntitlementState = isUnlocked ? .active : .inactive
        allLooksEntitlementState = nextState

        if isUnlocked {
            restoreDeferredAllLooksSelectionIfNeeded()
            return
        }

        let removedDeferredSelection = deferredAllLooksSelection != nil
        deferredAllLooksSelection = nil
        let didFallBack = removeEntitlementOnlySelections()
        if removedDeferredSelection || didFallBack {
            persistWardrobe()
        }
    }

    func canUsePersona(_ persona: StarPersona, hasAllLooksUnlocked: Bool) -> Bool {
        wardrobe.availablePersonas.contains(persona)
            || (hasAllLooksUnlocked && (persona.isAvailable() || persona.isSeasonal))
    }

    func selectPersona(_ persona: StarPersona, hasAllLooksUnlocked: Bool = false) {
        let isOwned = wardrobe.availablePersonas.contains(persona)
        guard isOwned
                || (hasAllLooksUnlocked && (persona.isAvailable() || persona.isSeasonal))
        else { return }
        wardrobe.selectedPersona = persona
        wardrobe.selectedCollectionSkinID = nil
        wardrobe.selectedPersonaRequiresAllLooks = isOwned ? nil : true
        wardrobe.selectedCollectionSkinRequiresAllLooks = nil
        persistWardrobe()
    }

    @discardableResult
    func purchasePersona(_ persona: StarPersona, hasAllLooksUnlocked: Bool = false) -> Bool {
        if wardrobe.availablePersonas.contains(persona) {
            selectPersona(persona, hasAllLooksUnlocked: hasAllLooksUnlocked)
            return true
        }

        if hasAllLooksUnlocked, (persona.isAvailable() || persona.isSeasonal) {
            selectPersona(persona, hasAllLooksUnlocked: true)
            return true
        }

        guard persona.isAvailable(), persona.price > 0, wardrobe.starCoins >= persona.price else { return false }
        wardrobe.starCoins -= persona.price
        var owned = wardrobe.ownedPersonas ?? [.classic]
        owned.insert(persona)
        wardrobe.ownedPersonas = owned
        wardrobe.selectedPersona = persona
        wardrobe.selectedCollectionSkinID = nil
        wardrobe.selectedPersonaRequiresAllLooks = nil
        wardrobe.selectedCollectionSkinRequiresAllLooks = nil
        persistWardrobe()
        return true
    }

    func canUseCollectionSkin(_ skin: StarSkinCatalogItem, hasAllLooksUnlocked: Bool) -> Bool {
        wardrobe.availableCollectionSkinIDs.contains(skin.id) || hasAllLooksUnlocked
    }

    func selectCollectionSkin(_ skin: StarSkinCatalogItem, hasAllLooksUnlocked: Bool = false) {
        let isOwned = wardrobe.availableCollectionSkinIDs.contains(skin.id)
        guard isOwned || hasAllLooksUnlocked else { return }
        wardrobe.selectedCollectionSkinID = skin.id
        wardrobe.selectedCollectionSkinRequiresAllLooks = isOwned ? nil : true
        persistWardrobe()
    }

    @discardableResult
    func purchaseCollectionSkin(_ skin: StarSkinCatalogItem, hasAllLooksUnlocked: Bool = false) -> Bool {
        if wardrobe.availableCollectionSkinIDs.contains(skin.id) {
            selectCollectionSkin(skin, hasAllLooksUnlocked: hasAllLooksUnlocked)
            return true
        }

        if hasAllLooksUnlocked {
            selectCollectionSkin(skin, hasAllLooksUnlocked: true)
            return true
        }

        guard skin.price > 0, wardrobe.starCoins >= skin.price else { return false }
        wardrobe.starCoins -= skin.price
        var ownedSkinIDs = wardrobe.ownedCollectionSkinIDs ?? []
        ownedSkinIDs.insert(skin.id)
        wardrobe.ownedCollectionSkinIDs = ownedSkinIDs
        wardrobe.selectedCollectionSkinID = skin.id
        wardrobe.selectedCollectionSkinRequiresAllLooks = nil
        persistWardrobe()
        return true
    }

    func setFollowsTarotMeaning(_ enabled: Bool) {
        wardrobe.followsTarotMeaning = enabled
        persistWardrobe()
    }

    func canUseAccessory(_ accessory: StarAccessory, hasAllLooksUnlocked: Bool) -> Bool {
        wardrobe.ownedAccessories.contains(accessory) || hasAllLooksUnlocked
    }

    func selectAccessory(_ accessory: StarAccessory, hasAllLooksUnlocked: Bool = false) {
        let isOwned = wardrobe.ownedAccessories.contains(accessory)
        guard isOwned || hasAllLooksUnlocked else { return }
        wardrobe.selectedAccessory = accessory
        wardrobe.selectedAccessoryRequiresAllLooks = isOwned ? nil : true
        persistWardrobe()
    }

    @discardableResult
    func purchaseAccessory(_ accessory: StarAccessory, hasAllLooksUnlocked: Bool = false) -> Bool {
        if wardrobe.ownedAccessories.contains(accessory) {
            selectAccessory(accessory, hasAllLooksUnlocked: hasAllLooksUnlocked)
            return true
        }

        if hasAllLooksUnlocked {
            selectAccessory(accessory, hasAllLooksUnlocked: true)
            return true
        }

        guard accessory.price > 0, wardrobe.starCoins >= accessory.price else { return false }
        wardrobe.starCoins -= accessory.price
        wardrobe.ownedAccessories.insert(accessory)
        wardrobe.selectedAccessory = accessory
        wardrobe.selectedAccessoryRequiresAllLooks = nil
        persistWardrobe()
        return true
    }

    func awardStarCoins(_ amount: Int) {
        guard amount > 0 else { return }
        wardrobe.starCoins = min(9_999, wardrobe.starCoins + amount)
        persistWardrobe()
    }

    var starTrailProgress: StarTrailProgress {
        wardrobe.starTrailProgress ?? StarTrailProgress()
    }

    @discardableResult
    func completeStarTrailLevel(_ level: Int, reward: Int) -> Bool {
        guard (1...12).contains(level) else { return false }
        var progress = wardrobe.starTrailProgress ?? StarTrailProgress()
        let isFirstCompletion = progress.completedLevels.insert(level).inserted
        progress.highestUnlockedLevel = min(12, max(progress.highestUnlockedLevel, level + 1))
        wardrobe.starTrailProgress = progress
        if isFirstCompletion {
            wardrobe.starCoins = min(9_999, wardrobe.starCoins + max(reward, 0))
        }
        completeWeeklyJourneyTask(.play)
        persistWardrobe()
        return isFirstCompletion
    }

    var cometCatchProgress: StarTrailProgress {
        wardrobe.cometCatchProgress ?? StarTrailProgress()
    }

    @discardableResult
    func completeCometCatchLevel(_ level: Int, reward: Int) -> Bool {
        guard (1...12).contains(level) else { return false }
        var progress = wardrobe.cometCatchProgress ?? StarTrailProgress()
        let isFirstCompletion = progress.completedLevels.insert(level).inserted
        progress.highestUnlockedLevel = min(12, max(progress.highestUnlockedLevel, level + 1))
        wardrobe.cometCatchProgress = progress
        if isFirstCompletion {
            wardrobe.starCoins = min(9_999, wardrobe.starCoins + max(reward, 0))
        }
        completeWeeklyJourneyTask(.play)
        persistWardrobe()
        return isFirstCompletion
    }

    var currentWeeklyStory: WeeklyStoryProgress {
        let current = starLife.weeklyStory ?? .current()
        guard current.weekID == WeeklyStoryProgress.weekStamp() else {
            return .current()
        }
        return current
    }

    func completeWeeklyJourneyTask(_ task: WeeklyJourneyTask) {
        var progress = currentWeeklyStory
        let inserted = progress.completedTasks.insert(task).inserted
        starLife.weeklyStory = progress
        if inserted { persistStarLife() }
    }

    @discardableResult
    func revealWeeklyStory() -> Bool {
        var progress = currentWeeklyStory
        guard progress.isUnlocked, progress.revealedAt == nil else { return false }
        progress.revealedAt = .now
        starLife.weeklyStory = progress
        wardrobe.starCoins = min(9_999, wardrobe.starCoins + 40)
        persistWardrobe()
        persistStarLife()
        return true
    }

    var bedtimeWishes: [BedtimeWish] {
        starLife.wishes ?? []
    }

    @discardableResult
    func submitBedtimeWish(_ rawText: String, now: Date = .now, calendar: Calendar = .current) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let id = UUID()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
        let templateIndex = abs(text.unicodeScalars.reduce(17) { ($0 &* 31) &+ Int($1.value) }) % WishReplyTemplate.allCases.count
        let wish = BedtimeWish(
            id: id,
            createdAt: now,
            text: String(text.prefix(180)),
            readyDateStamp: SharedPlanet.todayStamp(for: tomorrow, calendar: calendar),
            replyTemplateID: WishReplyTemplate.allCases[templateIndex],
            revealedAt: nil
        )
        var wishes = starLife.wishes ?? []
        wishes.insert(wish, at: 0)
        starLife.wishes = Array(wishes.prefix(90))
        completeWeeklyJourneyTask(.wish)
        persistStarLife()
        return true
    }

    @discardableResult
    func revealWish(id: UUID, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard var wishes = starLife.wishes,
              let index = wishes.firstIndex(where: { $0.id == id }),
              wishes[index].isReady(on: now, calendar: calendar)
        else { return false }
        if wishes[index].revealedAt == nil {
            wishes[index].revealedAt = now
            starLife.wishes = wishes
            persistStarLife()
        }
        return true
    }

    var isGentleModeToday: Bool {
        starLife.gentleDay?.selectedDateStamp == SharedPlanet.todayStamp()
    }

    var canUseGentleInteraction: Bool {
        deletionIntent == nil && !isDeletingAccount && isGentleModeToday
            && starLife.gentleDay?.interactionUsedDateStamp != SharedPlanet.todayStamp()
    }

    func setGentleMode(_ enabled: Bool) {
        var gentle = starLife.gentleDay ?? GentleDayState()
        gentle.selectedDateStamp = enabled ? SharedPlanet.todayStamp() : nil
        if !enabled { gentle.interactionUsedDateStamp = nil }
        starLife.gentleDay = gentle
        persistStarLife()
    }

    var starHome: StarHomeState {
        starLife.home ?? .starter
    }

    var placedFurniture: Set<StarFurniture> {
        starHome.placedFurniture ?? []
    }

    var maxDailyFeedCount: Int {
        let today = SharedPlanet.todayStamp()
        let hasUnusedMoonBedBonus = starHome.moonBedBonusDate == today
            && starHome.moonBedBonusUsedDate != today
        return hasUnusedMoonBedBonus ? 4 : 3
    }

    var canFeedPet: Bool {
        deletionIntent == nil && !isDeletingAccount && !isGentleModeToday && planet.feedCount < maxDailyFeedCount
    }

    @discardableResult
    func purchaseFurniture(_ furniture: StarFurniture) -> Bool {
        var home = starHome
        var owned = home.ownedFurniture ?? []
        if owned.contains(furniture) { return true }
        let stardust = home.stardust ?? 0
        guard stardust >= furniture.price else { return false }
        home.stardust = stardust - furniture.price
        owned.insert(furniture)
        home.ownedFurniture = owned
        starLife.home = home
        persistStarLife()
        return true
    }

    func setFurniture(_ furniture: StarFurniture, placed: Bool, now: Date = .now, calendar: Calendar = .current) {
        var home = starHome
        guard home.ownedFurniture?.contains(furniture) == true else { return }
        var placements = home.placedFurniture ?? []
        if placed {
            placements.insert(furniture)
            if furniture == .moonBed {
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
                home.moonBedBonusDate = SharedPlanet.todayStamp(for: tomorrow, calendar: calendar)
            }
        } else {
            placements.remove(furniture)
        }
        home.placedFurniture = placements
        starLife.home = home
        persistStarLife()
    }

    var canHarvestGarden: Bool {
        placedFurniture.contains(.stardustGarden)
            && starHome.lastGardenHarvestDate != SharedPlanet.todayStamp()
    }

    @discardableResult
    func harvestGarden() -> Bool {
        guard canHarvestGarden else { return false }
        var home = starHome
        home.stardust = min(9_999, (home.stardust ?? 0) + 12)
        home.lastGardenHarvestDate = SharedPlanet.todayStamp()
        starLife.home = home
        persistStarLife()
        return true
    }

    @discardableResult
    func claimSeasonalRoom(_ theme: StarRoomTheme) -> Bool {
        guard theme.isInSeason() else { return false }
        var home = starHome
        var owned = home.ownedRoomThemes ?? [.observatoryGarden]
        owned.insert(theme)
        home.ownedRoomThemes = owned
        home.selectedRoomTheme = theme
        starLife.home = home
        persistStarLife()
        return true
    }

    func selectRoomTheme(_ theme: StarRoomTheme) {
        guard starHome.ownedRoomThemes?.contains(theme) == true else { return }
        var home = starHome
        home.selectedRoomTheme = theme
        starLife.home = home
        persistStarLife()
    }

    func makeHomeVisitCardURL(sharesAlias: Bool, now: Date = .now, calendar: Calendar = .current) -> URL? {
        guard account != nil, accountDataWritesAllowed else { return nil }
        var exchange = homeVisitExchangeState
        guard let hostShareID = exchange.hostShareID,
              let expiresAt = calendar.date(byAdding: .day, value: 7, to: now)
        else { return nil }

        let appearance = StarAppearanceSnapshot(
            personaID: wardrobe.displayedLookID,
            auraID: wardrobe.displayedAura.rawValue,
            accessoryID: wardrobe.selectedAccessory.rawValue,
            roomThemeID: (starHome.selectedRoomTheme ?? .observatoryGarden).rawValue,
            moodID: planet.mood.rawValue
        )
        let card = HomeVisitCard(
            version: HomeVisitCard.currentVersion,
            id: UUID(),
            hostShareID: hostShareID,
            createdAt: now,
            expiresAt: expiresAt,
            hostAlias: sharesAlias ? HomeVisitLinkCodec.sanitizedAlias(user?.displayName) : nil,
            appearance: appearance,
            furnitureIDs: placedFurniture.map(\.rawValue).sorted()
        )
        guard let digest = HomeVisitLinkCodec.digest(for: card),
              let url = HomeVisitLinkCodec.url(for: card)
        else { return nil }

        let issued = IssuedHomeVisitCard(id: card.id, digest: digest, expiresAt: expiresAt)
        exchange.issuedCards = Array(([issued] + (exchange.issuedCards ?? [])).prefix(32))
        var updatedStarLife = starLife
        updatedStarLife.visitExchange = exchange
        guard persistAccountData(overridingStarLife: updatedStarLife) else { return nil }
        starLife = updatedStarLife
        return url
    }

    func makeHomeVisitReceiptURL(
        for card: HomeVisitCard,
        reaction: HomeVisitReaction,
        sharesAlias: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> URL? {
        guard account != nil,
              accountDataWritesAllowed,
              isValidHomeVisitCard(card, now: now, calendar: calendar),
              let digest = HomeVisitLinkCodec.digest(for: card)
        else { return nil }

        var exchange = homeVisitExchangeState
        guard card.hostShareID != exchange.hostShareID,
              let visitorSecret = exchange.visitorSecret
        else { return nil }

        let today = SharedPlanet.todayStamp(for: now, calendar: calendar)
        let requestedAlias = sharesAlias ? HomeVisitLinkCodec.sanitizedAlias(user?.displayName) : nil
        if let existing = (exchange.outboundReceipts ?? []).first(where: {
            $0.cardID == card.id
                && $0.reaction == reaction
                && $0.visitorAlias == requestedAlias
                && SharedPlanet.todayStamp(for: $0.createdAt, calendar: calendar) == today
        }) {
            return HomeVisitLinkCodec.url(for: existing)
        }

        let receipt = HomeVisitReceipt(
            version: HomeVisitReceipt.currentVersion,
            id: UUID(),
            cardID: card.id,
            hostShareID: card.hostShareID,
            cardDigest: digest,
            visitorKey: HomeVisitLinkCodec.visitorKey(secret: visitorSecret, hostShareID: card.hostShareID),
            visitorAlias: requestedAlias,
            reaction: reaction,
            createdAt: now
        )
        guard let receiptURL = HomeVisitLinkCodec.url(for: receipt) else { return nil }
        exchange.outboundReceipts = Array(([receipt] + (exchange.outboundReceipts ?? [])).prefix(128))
        var updatedStarLife = starLife
        updatedStarLife.visitExchange = exchange
        guard persistAccountData(overridingStarLife: updatedStarLife) else { return nil }
        starLife = updatedStarLife
        return receiptURL
    }

    @discardableResult
    func acceptHomeVisitReceipt(
        _ receipt: HomeVisitReceipt,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> HomeVisitReceiptAcceptance {
        guard account != nil, accountDataWritesAllowed else { return .invalid }
        var exchange = homeVisitExchangeState
        guard let hostShareID = exchange.hostShareID,
              receipt.version == HomeVisitReceipt.currentVersion,
              receipt.hostShareID == hostShareID,
              !receipt.visitorKey.isEmpty,
              receipt.visitorKey.count <= 64,
              receipt.createdAt <= now.addingTimeInterval(10 * 60)
        else { return .invalid }

        guard let issued = (exchange.issuedCards ?? []).first(where: { $0.id == receipt.cardID }),
              issued.digest == receipt.cardDigest
        else { return .invalid }

        let graceEnd = HomeVisitRewardPolicy.redemptionGraceEnd(for: issued, calendar: calendar)
        let cardStart = calendar.date(byAdding: .day, value: -7, to: issued.expiresAt) ?? issued.expiresAt
        guard now <= graceEnd, receipt.createdAt >= cardStart, receipt.createdAt <= issued.expiresAt else {
            return .expired
        }

        let redemptions = exchange.redemptions ?? []
        let decision = HomeVisitRewardPolicy.decision(
            for: receipt,
            redemptions: redemptions,
            now: now,
            calendar: calendar
        )
        let reward: Int
        switch decision {
        case let .accepted(value): reward = value
        case .acceptedWithoutReward: reward = 0
        case .alreadyAccepted, .alreadyVisitedToday, .dailyLimitReached: return decision
        case .expired, .invalid: return .invalid
        }
        let redemption = HomeVisitRedemption(
            id: receipt.id,
            cardID: receipt.cardID,
            visitorKey: receipt.visitorKey,
            acceptedAt: now,
            reward: reward
        )
        exchange.redemptions = HomeVisitRewardPolicy.retainedRedemptions(
            adding: redemption,
            to: redemptions,
            issuedCards: exchange.issuedCards ?? [],
            now: now,
            calendar: calendar
        )

        var home = starHome
        let visitorAlias = HomeVisitLinkCodec.sanitizedAlias(receipt.visitorAlias)
            ?? language.text("一位星友", "별 친구", "A star friend")
        let visit = HomeVisitRecord(
            id: UUID(),
            visitorAlias: visitorAlias,
            visitedAt: now,
            stardustAmount: reward,
            receiptID: receipt.id,
            reactionID: receipt.reaction.rawValue
        )
        home.visits = Array(([visit] + (home.visits ?? [])).prefix(30))
        home.stardust = min(9_999, (home.stardust ?? 0) + reward)
        var updatedStarLife = starLife
        updatedStarLife.home = home
        updatedStarLife.visitExchange = exchange
        guard persistAccountData(overridingStarLife: updatedStarLife) else { return .invalid }
        starLife = updatedStarLife
        return reward > 0 ? .accepted(reward: reward) : .acceptedWithoutReward
    }

    func dismissPendingHomeVisitLink() {
        pendingHomeVisitLink = nil
        homeVisitLinkError = nil
    }

    func dismissHomeVisitLinkError() {
        homeVisitLinkError = nil
    }

    func dismissAccountDataNotice() {
        accountDataNotice = nil
    }

    func resolveAccountCloudConflictUsingThisDevice() {
        guard let context = accountCloudSyncContext(),
              accountStorage.resolveCloudConflictUsingLocal(for: context.accountID) != nil
        else {
            pauseCloudSyncForStorageFailure()
            return
        }
        accountDataNotice = nil
        accountCloudSyncStatus = .waitingToSync
        scheduleAccountCloudSync(delay: nil)
    }

    func resolveAccountCloudConflictUsingSyncedCopy() {
        guard let context = accountCloudSyncContext(),
              let remote = accountStorage.resolveCloudConflictUsingRemote(for: context.accountID)
        else {
            pauseCloudSyncForStorageFailure()
            return
        }
        isApplyingCloudSnapshot = true
        loadAccountData(for: context.accountID)
        isApplyingCloudSnapshot = false
        accountDataNotice = nil
        isAccountCloudBootstrapPending = false
        accountCloudSyncStatus = .synced
        if currentAccountCloudData() != remote.snapshot.normalized(for: context.accountID),
           accountStorage.saveLocalSnapshotPreparingCloudUpload(
               currentAccountCloudData(),
               for: context.accountID
           ) != nil {
            accountCloudSyncStatus = .waitingToSync
            scheduleAccountCloudSync(delay: nil)
        }
    }

    func deleteReading(id: UUID) {
        readingHistory.removeAll(where: { $0.id == id })
        persist()
    }

    func setReminderEnabled(_ enabled: Bool) async {
        reminderError = nil

        if enabled {
            do {
                try await FortuneReminderService.shared.schedule(
                    hour: reminderTimeMinutes / 60,
                    minute: reminderTimeMinutes % 60,
                    language: language
                )
                reminderEnabled = true
            } catch {
                reminderEnabled = false
                reminderError = language.text(
                    "尚未取得通知權限。你可以稍後到 iOS「設定」中允許星伴通知。",
                    "알림 권한이 없어요. 나중에 iOS 설정에서 별동무 알림을 허용할 수 있어요.",
                    "Notifications aren't allowed yet. You can enable Star Companion in iOS Settings later."
                )
            }
        } else {
            await FortuneReminderService.shared.cancel()
            reminderEnabled = false
        }
        persistReminderPreferences()
    }

    func setReminderTime(minutes: Int) {
        reminderTimeMinutes = min(max(minutes, 0), 23 * 60 + 59)
        persistReminderPreferences()

        guard reminderEnabled else { return }
        Task { await setReminderEnabled(true) }
    }

    var actionMessage: String {
        switch actionState {
        case .waiting: language.text("小星正在等你一起玩", "작은 별이 함께 놀기를 기다리고 있어요", "Little Star is waiting to play with you")
        case .fed: language.text("吃到星糧了，好幸福 ✦", "별빛 간식을 먹어서 행복해요 ✦", "Starlight snacks make everything better ✦")
        case .taskCompleted: language.text("共同約定完成，星光獎勵已收到 ✦", "오늘의 약속 완료, 별빛 보상을 받았어요 ✦", "Tonight's promise is complete. Starlight received ✦")
        case .petted: language.text("小星輕輕蹭了蹭你", "작은 별이 살며시 기대어 왔어요", "Little Star nuzzled closer")
        }
    }

    func logout() {
        guard deletionIntent == nil, !isDeletingAccount else { return }
        let savedCurrentAccount = persistAccountData()
        do {
            try sessionVault.clear()
        } catch {
            loginError = language.text(
                "無法安全地清除登入憑證，請再試一次。",
                "로그인 정보를 안전하게 지우지 못했어요. 다시 시도해 주세요.",
                "The secure sign-in credential couldn't be cleared. Please try again."
            )
            return
        }
        resetSessionRefreshForAccountChange()
        resetAccountCloudSyncForAccountChange()
        authSession = nil
        account = nil
        defaults.removeObject(forKey: Key.user)
        clearAccountTransientState()
        loadAccountData(for: AccountStorage.guestAccountID)
        if !savedCurrentAccount {
            loginError = language.text(
                "已登出，但剛才的本機變更無法儲存。原有資料沒有被覆寫。",
                "로그아웃했지만 방금 변경한 기기 데이터를 저장하지 못했어요. 기존 데이터는 덮어쓰지 않았습니다.",
                "You were signed out, but the latest on-device changes couldn't be saved. Existing data wasn't overwritten."
            )
        }
        actionState = .waiting
        isCelebrating = false
        defaults.removeObject(forKey: "xingban.ios.profile-setup-deferred.v1")
        let currentLanguage = language
        Task { await LiveActivityController.shared.end(language: currentLanguage) }
    }

    func deleteAllLocalPersonalData() {
        guard deletionIntent == nil, !isDeletingAccount else { return }
        let currentLanguage = language
        do {
            try sessionVault.clear()
        } catch {
            loginError = language.text(
                "無法安全地清除登入憑證，本機資料尚未刪除。",
                "로그인 정보를 지우지 못해 기기 데이터를 아직 삭제하지 않았어요.",
                "The secure sign-in credential couldn't be cleared, so local data wasn't deleted."
            )
            return
        }
        resetSessionRefreshForAccountChange()
        resetAccountCloudSyncForAccountChange()
        authSession = nil
        account = nil
        defaults.removeObject(forKey: Key.user)
        accountStorage.removeAllAccountDataAndLegacyValues()
        clearAccountTransientState()
        loadAccountData(for: AccountStorage.guestAccountID)
        reminderEnabled = false
        reminderTimeMinutes = 20 * 60 + 40
        actionState = .waiting
        isCelebrating = false

        [
            Key.reminderEnabled,
            Key.reminderTime,
            "xingban.ios.profile-setup-deferred.v1",
            "xingban.ios.feedback-draft.v1",
            "xingban.ios.feedback-category.v1",
        ].forEach(defaults.removeObject(forKey:))

        Task {
            await FortuneReminderService.shared.cancel()
            await LiveActivityController.shared.end(language: currentLanguage)
        }
    }

    func feedPet() {
        guard deletionIntent == nil, !isDeletingAccount else { return }
        refreshDailyTaskIfNeeded()
        guard canFeedPet else { return }
        let completedTaskNow = !planet.taskCompleted && planet.feedCount + 1 >= 3
        planet.food = min(100, planet.food + 8)
        planet.feedCount = min(maxDailyFeedCount, planet.feedCount + 1)
        if planet.taskCompleted, !planet.taskRewardClaimed {
            planet.food = min(100, planet.food + 10)
            planet.taskRewardClaimed = true
        }
        planet.mood = completedTaskNow ? .delighted : .glowing
        planet.activity = .fed(actor: user?.displayName ?? "me", amount: 8)
        actionState = completedTaskNow ? .taskCompleted : .fed
        if planet.feedCount == maxDailyFeedCount, maxDailyFeedCount > 3 {
            starLife.home?.moonBedBonusUsedDate = SharedPlanet.todayStamp()
        }
        completeWeeklyJourneyTask(.care)
        celebrate()
        persist()
        syncLiveActivity(allowsNewActivity: true)
    }

    func petStar() {
        guard deletionIntent == nil, !isDeletingAccount else { return }
        refreshDailyTaskIfNeeded()
        if isGentleModeToday {
            guard canUseGentleInteraction else { return }
            starLife.gentleDay?.interactionUsedDateStamp = SharedPlanet.todayStamp()
        }
        planet.mood = .affectionate
        planet.activity = .petted(actor: user?.displayName ?? "me")
        actionState = .petted
        completeWeeklyJourneyTask(.care)
        celebrate()
        persist()
        syncLiveActivity(allowsNewActivity: true)
    }

    func refreshDailyTaskIfNeeded() {
        let today = SharedPlanet.todayStamp()
        if currentDayStamp != today {
            currentDayStamp = today
        }
        registerDailyVisit()
        var changed = false

        if planet.taskDate != today {
            planet.taskDate = today
            planet.feedCount = 0
            planet.taskRewardClaimed = false
            changed = true
        }

        if let checkInDate = planet.bondCheckInDate, checkInDate != today {
            planet.bondCheckInDate = nil
            planet.bondMood = nil
            planet.bondNote = nil
            changed = true
        }

        if changed { persist() }
    }

    private func registerDailyVisit() {
        let today = SharedPlanet.todayStamp()
        guard lastVisitDate != today else {
            visitStreak = max(visitStreak, 1)
            return
        }

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)
            .map { SharedPlanet.todayStamp(for: $0) }
        visitStreak = lastVisitDate == yesterday ? max(visitStreak + 1, 1) : 1
        lastVisitDate = today
        persistAccountData()
    }

    func handleIncomingURL(_ url: URL) {
        if let code = PlanetInviteCode.parse(url.absoluteString, allowedHost: invitationHost) {
            pendingPlanetInviteCode = code
            return
        }
        if let homeLink = HomeVisitLinkCodec.decode(url) {
            guard account != nil else {
                pendingHomeVisitLink = nil
                homeVisitLinkError = language.text(
                    "登入後才能開啟這張星星卡片。",
                    "로그인한 뒤에 이 별 카드를 열 수 있어요.",
                    "Sign in before opening this star card."
                )
                return
            }
            switch homeLink {
            case let .card(card):
                guard isValidHomeVisitCard(card) else {
                    homeVisitLinkError = language.text(
                        "這張訪客卡已經失效。",
                        "이 방문 카드는 더 이상 유효하지 않아요.",
                        "This visit card is no longer valid."
                    )
                    return
                }
            case .receipt:
                break
            }
            homeVisitLinkError = nil
            pendingHomeVisitLink = homeLink
            return
        }

        if url.scheme?.lowercased() == HomeVisitLinkCodec.scheme,
           url.host?.lowercased() == "home" {
            homeVisitLinkError = language.text(
                "這張星星卡片讀取失敗，請朋友重新分享。",
                "별 카드를 읽지 못했어요. 친구에게 다시 공유해 달라고 해 주세요.",
                "This star card couldn't be read. Ask your friend to share it again."
            )
            return
        }

    }

    private var homeVisitExchangeState: HomeVisitExchangeState {
        (starLife.visitExchange ?? .seeded()).migrated()
    }

    private func isValidHomeVisitCard(
        _ card: HomeVisitCard,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard card.version == HomeVisitCard.currentVersion,
              card.createdAt <= now.addingTimeInterval(10 * 60),
              card.expiresAt > now,
              card.furnitureIDs.count <= 8,
              let latestExpiry = calendar.date(byAdding: .day, value: 8, to: card.createdAt),
              card.expiresAt <= latestExpiry
        else { return false }
        return true
    }

    private func celebrate() {
        isCelebrating = true
        celebrationTask?.cancel()
        celebrationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_300))
            guard !Task.isCancelled else { return }
            self?.isCelebrating = false
        }
    }

    private func activateSession(
        _ session: AuthSession,
        legacyProviderAccountID: String? = nil
    ) throws {
        guard deletionIntent == nil else { throw AccountActionError(code: "account_deletion_pending") }
        let previousSession = authSession
        guard persistAccountData() else {
            throw AccountActivationError.localPersistenceFailed
        }

        let sourceAccountID = session.account.providerLocalAccountID
        let targetAccountID = session.account.canonicalLocalAccountID
        var preparedRelink = false
        var relinkConflict = false
        if sourceAccountID != targetAccountID {
            let relinkResult = accountStorage.prepareAccountRelink(
                from: sourceAccountID,
                to: targetAccountID
            )
            if relinkResult == .invalidSource || relinkResult == .failedToWrite {
                throw AccountActivationError.localMigrationFailed
            }
            preparedRelink = relinkResult == .migrated
            if relinkResult == .targetAlreadyExists {
                relinkConflict = true
                accountStorage.recordRelinkConflict(from: sourceAccountID, to: targetAccountID)
            }
        }

        if let legacyProviderAccountID {
            let migrationResult = accountStorage.migrateLegacyDataIfNeeded(
                for: targetAccountID,
                legacyProviderAccountID: legacyProviderAccountID,
                includeGlobalValues: false
            )
            if migrationResult == .invalidLegacyData || migrationResult == .failedToWrite {
                if preparedRelink {
                    accountStorage.rollbackPreparedAccountRelink(
                        from: sourceAccountID,
                        to: targetAccountID
                    )
                }
                throw AccountActivationError.localMigrationFailed
            }
        }

        do {
            try sessionVault.save(session)
        } catch {
            if preparedRelink {
                accountStorage.rollbackPreparedAccountRelink(
                    from: sourceAccountID,
                    to: targetAccountID
                )
            }
            throw error
        }
        if preparedRelink {
            var finalized = accountStorage.finalizeAccountRelink(
                from: sourceAccountID,
                to: targetAccountID
            )
            var targetReadyForRecovery = true
            if !finalized {
                let retryResult = accountStorage.prepareAccountRelink(
                   from: sourceAccountID,
                   to: targetAccountID
                )
                targetReadyForRecovery = retryResult == .migrated
                if targetReadyForRecovery {
                    finalized = accountStorage.finalizeAccountRelink(
                        from: sourceAccountID,
                        to: targetAccountID
                    )
                }
            }
            if !finalized {
                do {
                    if let previousSession {
                        try sessionVault.save(previousSession)
                    } else {
                        try sessionVault.clear()
                    }
                } catch {
                    // Do not silently keep a runtime identity that disagrees
                    // with an uncertain Keychain commit. Reconcile from the
                    // vault when possible and pause all account writes.
                    let persistedSession = try? sessionVault.load()
                    clearAccountTransientState()
                    if let persistedSession,
                       persistedSession.account.canonicalLocalAccountID != targetAccountID
                            || targetReadyForRecovery {
                        authSession = persistedSession
                        account = persistedSession.account
                        loadAccountData(for: persistedSession.account.canonicalLocalAccountID)
                    } else {
                        authSession = nil
                        account = nil
                        loadAccountData(for: AccountStorage.guestAccountID)
                    }
                    accountDataWritesAllowed = false
                    let message = language.text(
                        "安全登入狀態未能完成復原。帳號資料仍保留，但本次已停止寫入；請重新開啟 App 後再登入。",
                        "보안 로그인 상태를 복구하지 못했어요. 계정 데이터는 보관되어 있지만 이번 실행에서는 저장을 중지합니다. 앱을 다시 연 뒤 로그인해 주세요.",
                        "The secure sign-in state couldn't be reconciled. Account data is preserved, but writes are paused; reopen the app and sign in again."
                    )
                    loginError = message
                    accountDataNotice = message
                    throw AccountActivationError.sessionRecoveryFailed
                }
                throw AccountActivationError.localMigrationFailed
            }
        }
        let targetHasOwnedLocalData = accountStorage.hasProtectedOrStoredData(for: targetAccountID)
        resetSessionRefreshForAccountChange()
        resetAccountCloudSyncForAccountChange()
        isPreparingAccountState = true
        authSession = session
        account = session.account
        defaults.removeObject(forKey: Key.user)
        clearAccountTransientState()
        prepareAccountCloudBootstrapIfNeeded(preserveLocal: targetHasOwnedLocalData)
        loadAccountData(for: targetAccountID)
        if relinkConflict {
            accountDataNotice = language.text(
                "已登入並使用正式帳號原有的本機資料。登入提供者下的另一份資料仍安全保留，沒有被覆寫。",
                "로그인했으며 정식 계정에 이미 있던 기기 데이터를 사용합니다. 로그인 제공자 쪽의 다른 데이터는 덮어쓰지 않고 그대로 보관했어요.",
                "Signed in using the canonical account's existing on-device data. The provider-local copy was preserved and wasn't overwritten."
            )
        }
        actionState = .waiting
        isCelebrating = false
        migrateLegacyBondMemoryIfNeeded()
        refreshDailyTaskIfNeeded()
        persist()
        isPreparingAccountState = false
        scheduleAccountCloudSync(delay: nil)
        syncLiveActivity(allowsNewActivity: false)
    }

    private func clearAccountTransientState() {
        planetGeneration &+= 1
        sharedMembership = nil
        isLoadingPlanet = false
        isUpdatingPlanet = false
        planetLoadID = nil
        planetMutationID = nil
        planetServiceError = nil
        pendingAppleRequest = nil
        pendingHomeVisitLink = nil
        homeVisitLinkError = nil
        phoneOTPChallenge = nil
        phoneOTPError = nil
        accountDataNotice = nil
        defaults.removeObject(forKey: "xingban.ios.feedback-draft.v1")
        defaults.removeObject(forKey: "xingban.ios.feedback-category.v1")
    }

    private func phoneOTPMessage(for error: PhoneOTPServiceError) -> String {
        switch error {
        case .invalidPhoneNumber:
            language.text(
                "手機號碼格式不正確，請包含 + 與國碼。",
                "휴대폰 번호 형식을 확인해 주세요. +와 국가 코드가 필요해요.",
                "Check the phone number format, including + and the country code."
            )
        case .notConfigured:
            language.text(
                "手機驗證伺服器尚未配置，目前無法建立正式帳號。",
                "휴대폰 인증 서버가 아직 설정되지 않아 정식 계정을 만들 수 없어요.",
                "Phone verification isn't configured, so a production account can't be created yet."
            )
        case .challengeNotFound:
            language.text(
                "這組驗證碼已失效，請重新取得。",
                "인증 코드 요청을 찾을 수 없어요. 새 코드를 받아 주세요.",
                "That verification request is no longer available. Request a new code."
            )
        case .challengeExpired:
            language.text(
                "驗證碼已過期，請重新發送。",
                "인증 코드가 만료되었어요. 다시 받아 주세요.",
                "The verification code expired. Request a new one."
            )
        case let .invalidCode(remainingAttempts):
            language.text(
                "驗證碼不正確，還可嘗試 \(remainingAttempts) 次。",
                "코드가 맞지 않아요. \(remainingAttempts)회 더 시도할 수 있어요.",
                "That code isn't right. \(remainingAttempts) attempts remain."
            )
        case .tooManyAttempts:
            language.text(
                "嘗試次數已用完，請重新取得驗證碼。",
                "시도 횟수를 모두 사용했어요. 새 코드를 받아 주세요.",
                "There are no attempts left. Request a new code."
            )
        case let .resendTooSoon(seconds):
            language.text(
                "\(seconds) 秒後可以重新發送。",
                "\(seconds)초 후에 다시 보낼 수 있어요.",
                "You can resend in \(seconds) seconds."
            )
        }
    }

    @discardableResult
    private func scheduleSessionRefreshIfNeeded(force: Bool = false) -> Bool {
        guard deletionIntent == nil, !isDeletingAccount else { return false }
        guard sessionRefreshService.isConfigured else { return false }
        guard let session = expiredSessionAwaitingRefresh ?? authSession,
              session.assurance == .backendVerified,
              session.refreshToken?.isEmpty == false,
              force || expiredSessionAwaitingRefresh != nil || session.needsRefresh()
        else { return false }

        guard sessionRefreshTask == nil else { return true }
        accountCloudSyncStatus = .waitingToSync
        sessionRefreshTask = Task { [weak self] in
            await self?.refreshSessionAndResumeCloud(sourceSession: session)
        }
        return true
    }

    private func refreshSessionAndResumeCloud(sourceSession: AuthSession) async {
        do {
            let refreshedSession = try await sessionRefreshService.refresh(sourceSession)
            guard !Task.isCancelled,
                  authSession == sourceSession || expiredSessionAwaitingRefresh == sourceSession
            else {
                sessionRefreshTask = nil
                return
            }

            sessionRefreshTask = nil
            try activateSession(refreshedSession)
        } catch let error as AuthSessionRefreshError {
            guard !Task.isCancelled,
                  authSession == sourceSession || expiredSessionAwaitingRefresh == sourceSession
            else {
                sessionRefreshTask = nil
                return
            }
            sessionRefreshTask = nil
            handleSessionRefreshFailure(error, sourceSession: sourceSession)
        } catch {
            guard !Task.isCancelled,
                  authSession == sourceSession || expiredSessionAwaitingRefresh == sourceSession
            else {
                sessionRefreshTask = nil
                return
            }
            sessionRefreshTask = nil
            handleSessionRefreshFailure(.invalidResponse, sourceSession: sourceSession)
        }
    }

    private func handleSessionRefreshFailure(
        _ error: AuthSessionRefreshError,
        sourceSession: AuthSession
    ) {
        switch error {
        case .temporarilyUnavailable:
            accountCloudSyncStatus = .pendingOffline
            if expiredSessionAwaitingRefresh == sourceSession {
                loginError = language.text(
                    "暫時無法連上帳號服務。登入資料仍安全保存在 iOS 鑰匙圈，恢復連線後會再試一次。",
                    "계정 서비스에 잠시 연결할 수 없어요. 로그인 정보는 iOS 키체인에 안전하게 보관되며, 연결이 돌아오면 다시 시도합니다.",
                    "The account service is temporarily unreachable. Your sign-in remains secured in iOS Keychain, and the app will retry when connectivity returns."
                )
            }
        case .notConfigured, .missingRefreshToken, .rejected, .invalidResponse:
            do {
                try sessionVault.clear()
            } catch {
                accountDataWritesAllowed = false
                loginError = language.text(
                    "登入已失效，但 iOS 鑰匙圈暫時無法清除。帳號資料仍保留，本次已停止寫入；請重新開啟 App。",
                    "로그인이 만료되었지만 iOS 키체인을 지금 비울 수 없어요. 계정 데이터는 보관하고 이번 실행의 저장을 중지했습니다. 앱을 다시 열어 주세요.",
                    "The sign-in expired, but iOS Keychain couldn't be cleared. Account data is preserved and writes are paused for this launch; reopen the app."
                )
                return
            }
            resetSessionRefreshForAccountChange()
            resetAccountCloudSyncForAccountChange()
            authSession = nil
            account = nil
            clearAccountTransientState()
            loadAccountData(for: AccountStorage.guestAccountID)
            loginError = language.text(
                "登入已過期，請重新使用同一個帳號登入；雲端資料不會遺失。",
                "로그인이 만료되었어요. 같은 계정으로 다시 로그인해 주세요. 클라우드 데이터는 사라지지 않습니다.",
                "Your sign-in expired. Sign in again with the same account; your synced data is still there."
            )
        }
    }

    private func resetSessionRefreshForAccountChange() {
        sessionRefreshTask?.cancel()
        sessionRefreshTask = nil
        expiredSessionAwaitingRefresh = nil
    }

    private func prepareAccountCloudBootstrapIfNeeded(preserveLocal: Bool) {
        guard let session = authSession,
              session.assurance == .backendVerified,
              !session.isExpired(),
              session.accessToken?.isEmpty == false,
              accountCloudSyncService.isConfigured,
              account != nil
        else {
            accountCloudSyncStatus = .localOnly
            isAccountCloudBootstrapPending = false
            return
        }
        let accountID = session.account.canonicalLocalAccountID
        guard accountStorage.cloudSyncWritesAllowed(for: accountID) else {
            accountCloudSyncStatus = .paused
            isAccountCloudBootstrapPending = false
            return
        }
        if accountStorage.cloudConflictBackup(for: accountID) != nil {
            accountCloudSyncStatus = .conflict
            isAccountCloudBootstrapPending = false
            return
        }
        if accountStorage.cloudAnchor(for: accountID) == nil,
           accountStorage.cloudPendingUpload(for: accountID) == nil,
           accountStorage.cloudBootstrapMode(for: accountID) == nil {
            _ = accountStorage.prepareCloudBootstrap(
                for: accountID,
                mode: preserveLocal ? .preserveLocal : .preferRemote
            )
        }
        isAccountCloudBootstrapPending = accountStorage.cloudBootstrapMode(for: accountID) != nil
        accountCloudSyncStatus = .waitingToSync
    }

    private func resetAccountCloudSyncForAccountChange() {
        accountCloudSyncGeneration &+= 1
        accountCloudSyncRequested = false
        accountCloudSyncTask?.cancel()
        accountCloudSyncTask = nil
        isApplyingCloudSnapshot = false
        isAccountCloudBootstrapPending = false
        accountCloudSyncStatus = .localOnly
    }

    private func accountCloudSyncContext() -> AccountCloudSyncContext? {
        guard deletionIntent == nil, !isDeletingAccount,
              accountCloudSyncService.isConfigured,
              let session = authSession,
              session.assurance == .backendVerified,
              !session.isExpired(),
              let accessToken = session.accessToken,
              !accessToken.isEmpty,
              account?.canonicalLocalAccountID == session.account.canonicalLocalAccountID
        else { return nil }
        return AccountCloudSyncContext(
            generation: accountCloudSyncGeneration,
            accountID: session.account.canonicalLocalAccountID,
            accessToken: accessToken
        )
    }

    private func isCurrentCloudContext(_ context: AccountCloudSyncContext) -> Bool {
        guard let current = accountCloudSyncContext() else { return false }
        return current == context && !Task.isCancelled
    }

    private func scheduleAccountCloudSync(delay: Duration? = .milliseconds(450)) {
        if scheduleSessionRefreshIfNeeded() { return }
        guard accountCloudSyncContext() != nil else {
            if authSession?.assurance == .backendVerified,
               authSession?.isExpired() == true {
                accountCloudSyncStatus = .signInRequired
            } else {
                accountCloudSyncStatus = .localOnly
            }
            isAccountCloudBootstrapPending = false
            return
        }
        accountCloudSyncRequested = true
        guard accountCloudSyncTask == nil else { return }

        let generation = accountCloudSyncGeneration
        accountCloudSyncTask = Task { [weak self] in
            if let delay {
                try? await Task.sleep(for: delay)
            }
            await self?.runAccountCloudSyncLoop(generation: generation)
        }
    }

    private func runAccountCloudSyncLoop(generation: Int) async {
        guard generation == accountCloudSyncGeneration, !Task.isCancelled else {
            finishAccountCloudSyncLoop(generation: generation)
            return
        }

        repeat {
            accountCloudSyncRequested = false
            await synchronizeAccountCloudOnce(generation: generation)
            guard generation == accountCloudSyncGeneration, !Task.isCancelled else { break }

            switch accountCloudSyncStatus {
            case .conflict, .localOnly, .paused, .pendingOffline, .signInRequired:
                accountCloudSyncRequested = false
            case .synced, .syncing, .waitingToSync:
                if let context = accountCloudSyncContext(),
                   accountStorage.cloudPendingUpload(for: context.accountID) != nil {
                    accountCloudSyncRequested = true
                }
            }
        } while accountCloudSyncRequested

        finishAccountCloudSyncLoop(generation: generation)
    }

    private func finishAccountCloudSyncLoop(generation: Int) {
        guard generation == accountCloudSyncGeneration else { return }
        accountCloudSyncTask = nil
        if accountCloudSyncRequested {
            scheduleAccountCloudSync(delay: nil)
        }
    }

    private func synchronizeAccountCloudOnce(generation: Int) async {
        guard var context = accountCloudSyncContext(), context.generation == generation else { return }
        guard accountStorage.cloudSyncWritesAllowed(for: context.accountID) else {
            accountCloudSyncStatus = .paused
            isAccountCloudBootstrapPending = false
            return
        }
        if accountStorage.cloudConflictBackup(for: context.accountID) != nil {
            accountCloudSyncStatus = .conflict
            isAccountCloudBootstrapPending = false
            presentCloudConflictNotice()
            return
        }

        accountCloudSyncStatus = .syncing
        if let pending = accountStorage.cloudPendingUpload(for: context.accountID) {
            await uploadPendingCloudSnapshot(pending, context: context)
            return
        }
        if let mode = accountStorage.cloudBootstrapMode(for: context.accountID) {
            await synchronizeCloudBootstrap(mode: mode, context: context)
            return
        }

        // Re-read after the branching storage calls above. This makes the
        // captured identity explicit at every network boundary.
        guard let refreshed = accountCloudSyncContext(), refreshed == context else { return }
        context = refreshed
        await reconcileCleanCloudSnapshot(context: context)
    }

    private func synchronizeCloudBootstrap(
        mode: AccountCloudBootstrapMode,
        context: AccountCloudSyncContext
    ) async {
        do {
            let remote = try await accountCloudSyncService.fetchSnapshot(
                accessToken: context.accessToken
            )
            guard isCurrentCloudContext(context) else { return }

            let effectiveMode = accountStorage.cloudBootstrapMode(for: context.accountID) ?? mode
            if let pending = accountStorage.cloudPendingUpload(for: context.accountID) {
                if let remote {
                    if pending.snapshot.normalized(for: context.accountID)
                        == remote.snapshot.normalized(for: context.accountID) {
                        guard accountStorage.acknowledgeCloudUpload(
                            mutationID: pending.mutationID,
                            remote: remote,
                            for: context.accountID
                        ) else {
                            pauseCloudSyncForStorageFailure()
                            return
                        }
                        accountCloudSyncStatus = .synced
                        isAccountCloudBootstrapPending = false
                    } else {
                        recordCloudConflict(
                            local: pending.snapshot,
                            remote: remote,
                            context: context
                        )
                    }
                } else {
                    await uploadPendingCloudSnapshot(pending, context: context)
                }
                return
            }

            guard let remote else {
                guard let pending = accountStorage.saveLocalSnapshotPreparingCloudUpload(
                    currentAccountCloudData(),
                    for: context.accountID
                ) else {
                    pauseCloudSyncForStorageFailure()
                    return
                }
                await uploadPendingCloudSnapshot(pending, context: context)
                return
            }

            let local = currentAccountCloudData()
            if effectiveMode == .preferRemote
                || local == remote.snapshot.normalized(for: context.accountID) {
                applyRemoteCloudSnapshot(remote, context: context)
                return
            }

            recordCloudConflict(local: local, remote: remote, context: context)
        } catch is CancellationError {
            return
        } catch {
            handleCloudSyncError(error)
        }
    }

    private func reconcileCleanCloudSnapshot(context: AccountCloudSyncContext) async {
        do {
            let remote = try await accountCloudSyncService.fetchSnapshot(
                accessToken: context.accessToken
            )
            guard isCurrentCloudContext(context) else { return }

            let local = currentAccountCloudData()
            let anchor = accountStorage.cloudAnchor(for: context.accountID)
            guard let remote else {
                if anchor == nil {
                    guard let pending = accountStorage.saveLocalSnapshotPreparingCloudUpload(
                        local,
                        for: context.accountID
                    ) else {
                        pauseCloudSyncForStorageFailure()
                        return
                    }
                    await uploadPendingCloudSnapshot(pending, context: context)
                } else {
                    accountCloudSyncStatus = .conflict
                    presentCloudConflictNotice()
                }
                return
            }

            guard let anchor else {
                if local == remote.snapshot.normalized(for: context.accountID) {
                    applyRemoteCloudSnapshot(remote, context: context)
                } else {
                    recordCloudConflict(local: local, remote: remote, context: context)
                }
                return
            }

            let normalizedAnchor = anchor.snapshot.normalized(for: context.accountID)
            let normalizedRemote = remote.snapshot.normalized(for: context.accountID)
            if anchor.revision == remote.revision {
                guard normalizedAnchor == normalizedRemote else {
                    recordCloudConflict(local: local, remote: remote, context: context)
                    return
                }
                if local == normalizedAnchor {
                    accountCloudSyncStatus = .synced
                    isAccountCloudBootstrapPending = false
                } else {
                    guard let pending = accountStorage.saveLocalSnapshotPreparingCloudUpload(
                        local,
                        for: context.accountID
                    ) else {
                        pauseCloudSyncForStorageFailure()
                        return
                    }
                    await uploadPendingCloudSnapshot(pending, context: context)
                }
            } else if local == normalizedAnchor || local == normalizedRemote {
                applyRemoteCloudSnapshot(remote, context: context)
            } else {
                recordCloudConflict(local: local, remote: remote, context: context)
            }
        } catch is CancellationError {
            return
        } catch {
            handleCloudSyncError(error)
        }
    }

    private func uploadPendingCloudSnapshot(
        _ pending: AccountCloudPendingUpload,
        context: AccountCloudSyncContext
    ) async {
        do {
            let remote = try await accountCloudSyncService.uploadSnapshot(
                pending.snapshot,
                baseRevision: pending.baseRevision,
                mutationID: pending.mutationID,
                accessToken: context.accessToken
            )
            guard isCurrentCloudContext(context) else { return }
            guard accountStorage.acknowledgeCloudUpload(
                mutationID: pending.mutationID,
                remote: remote,
                for: context.accountID
            ) else {
                pauseCloudSyncForStorageFailure()
                return
            }
            isAccountCloudBootstrapPending = accountStorage.cloudBootstrapMode(for: context.accountID) != nil
            accountCloudSyncStatus = .synced
        } catch is CancellationError {
            return
        } catch AccountCloudSyncServiceError.conflict {
            await resolveUploadConflict(context: context)
        } catch {
            handleCloudSyncError(error)
        }
    }

    private func resolveUploadConflict(context: AccountCloudSyncContext) async {
        do {
            let remote = try await accountCloudSyncService.fetchSnapshot(
                accessToken: context.accessToken
            )
            guard isCurrentCloudContext(context),
                  let pending = accountStorage.cloudPendingUpload(for: context.accountID)
            else { return }

            guard let remote else {
                accountCloudSyncStatus = .conflict
                isAccountCloudBootstrapPending = false
                presentCloudConflictNotice()
                return
            }
            if pending.snapshot.normalized(for: context.accountID)
                == remote.snapshot.normalized(for: context.accountID) {
                guard accountStorage.acknowledgeCloudUpload(
                    mutationID: pending.mutationID,
                    remote: remote,
                    for: context.accountID
                ) else {
                    pauseCloudSyncForStorageFailure()
                    return
                }
                accountCloudSyncStatus = .synced
                isAccountCloudBootstrapPending = false
            } else if accountStorage.recordCloudConflict(remote: remote, for: context.accountID) {
                accountCloudSyncStatus = .conflict
                isAccountCloudBootstrapPending = false
                presentCloudConflictNotice()
            } else {
                pauseCloudSyncForStorageFailure()
            }
        } catch is CancellationError {
            return
        } catch {
            handleCloudSyncError(error)
        }
    }

    private func recordCloudConflict(
        local: AccountLocalData,
        remote: AccountCloudSnapshot,
        context: AccountCloudSyncContext
    ) {
        let pending = accountStorage.cloudPendingUpload(for: context.accountID)
            ?? accountStorage.saveLocalSnapshotPreparingCloudUpload(local, for: context.accountID)
        guard pending != nil,
              accountStorage.recordCloudConflict(remote: remote, for: context.accountID)
        else {
            pauseCloudSyncForStorageFailure()
            return
        }
        accountCloudSyncStatus = .conflict
        isAccountCloudBootstrapPending = false
        presentCloudConflictNotice()
    }

    private func applyRemoteCloudSnapshot(
        _ remote: AccountCloudSnapshot,
        context: AccountCloudSyncContext
    ) {
        guard accountStorage.applyRemoteCloudSnapshot(remote, for: context.accountID) else {
            pauseCloudSyncForStorageFailure()
            return
        }
        isApplyingCloudSnapshot = true
        loadAccountData(for: context.accountID)
        isApplyingCloudSnapshot = false
        isAccountCloudBootstrapPending = false
        accountCloudSyncStatus = .synced

        // Canonicalizing an older localized archive is a real local migration.
        // Queue that normalized value after the remote anchor is safely stored.
        let normalizedRemote = remote.snapshot.normalized(for: context.accountID)
        if currentAccountCloudData() != normalizedRemote,
           accountStorage.saveLocalSnapshotPreparingCloudUpload(
               currentAccountCloudData(),
               for: context.accountID
           ) != nil {
            accountCloudSyncRequested = true
            accountCloudSyncStatus = .waitingToSync
        }
    }

    private func currentAccountCloudData(overridingStarLife: StarLifeState? = nil) -> AccountLocalData {
        AccountLocalData(
            schemaVersion: AccountLocalData.currentSchemaVersion,
            profile: profile,
            savedGuides: savedGuides,
            readingHistory: readingHistory,
            planet: planet,
            visitStreak: visitStreak,
            lastVisitDate: lastVisitDate,
            dailyGuideRevealDate: dailyGuideRevealDate,
            tarotDrawDate: tarotDrawDate,
            wardrobe: wardrobeForPersistence,
            starLife: overridingStarLife ?? starLife
        ).normalized(for: currentAccountID)
    }

    /// Until StoreKit finishes its first entitlement pass, paid-only
    /// selections are kept out of the rendered wardrobe. The original
    /// selection stays available for persistence, so an unrelated launch-time
    /// save cannot overwrite a valid preference before verification completes.
    private func deferAllLooksSelectionUntilEntitlementCheck() {
        guard wardrobe.selectedPersonaRequiresAllLooks == true
                || wardrobe.selectedCollectionSkinRequiresAllLooks == true
                || wardrobe.selectedAccessoryRequiresAllLooks == true
        else {
            deferredAllLooksSelection = nil
            return
        }

        deferredAllLooksSelection = wardrobe
        _ = removeEntitlementOnlySelections()
    }

    private func restoreDeferredAllLooksSelectionIfNeeded() {
        guard let deferred = deferredAllLooksSelection else { return }
        if deferred.selectedPersonaRequiresAllLooks == true {
            wardrobe.selectedPersona = deferred.selectedPersona
            wardrobe.selectedPersonaRequiresAllLooks = true
        }
        if deferred.selectedCollectionSkinRequiresAllLooks == true {
            wardrobe.selectedCollectionSkinID = deferred.selectedCollectionSkinID
            wardrobe.selectedCollectionSkinRequiresAllLooks = true
        }
        if deferred.selectedAccessoryRequiresAllLooks == true {
            wardrobe.selectedAccessory = deferred.selectedAccessory
            wardrobe.selectedAccessoryRequiresAllLooks = true
        }
        deferredAllLooksSelection = nil
    }

    @discardableResult
    private func removeEntitlementOnlySelections() -> Bool {
        var changed = false

        if wardrobe.selectedCollectionSkinRequiresAllLooks == true {
            wardrobe.selectedCollectionSkinID = nil
            wardrobe.selectedCollectionSkinRequiresAllLooks = nil
            changed = true
        }

        if wardrobe.selectedPersonaRequiresAllLooks == true {
            wardrobe.selectedPersona = .classic
            wardrobe.selectedPersonaRequiresAllLooks = nil
            changed = true
        }

        if wardrobe.selectedAccessoryRequiresAllLooks == true {
            wardrobe.selectedAccessory = .none
            wardrobe.selectedAccessoryRequiresAllLooks = nil
            changed = true
        }

        return changed
    }

    private var wardrobeForPersistence: StarWardrobe {
        guard allLooksEntitlementState == .unchecked,
              let deferred = deferredAllLooksSelection
        else { return wardrobe }

        var persisted = wardrobe
        if deferred.selectedPersonaRequiresAllLooks == true {
            persisted.selectedPersona = deferred.selectedPersona
            persisted.selectedPersonaRequiresAllLooks = true
        }
        if deferred.selectedCollectionSkinRequiresAllLooks == true {
            persisted.selectedCollectionSkinID = deferred.selectedCollectionSkinID
            persisted.selectedCollectionSkinRequiresAllLooks = true
        }
        if deferred.selectedAccessoryRequiresAllLooks == true {
            persisted.selectedAccessory = deferred.selectedAccessory
            persisted.selectedAccessoryRequiresAllLooks = true
        }
        return persisted
    }

    private func handleCloudSyncError(_ error: Error) {
        isAccountCloudBootstrapPending = false
        switch error {
        case AccountCloudSyncServiceError.notConfigured:
            accountCloudSyncStatus = .localOnly
        case AccountCloudSyncServiceError.unauthorized,
             AccountCloudSyncServiceError.forbidden:
            if scheduleSessionRefreshIfNeeded(force: true) {
                accountCloudSyncStatus = .waitingToSync
            } else {
                accountCloudSyncStatus = .signInRequired
            }
        case AccountCloudSyncServiceError.transport,
             AccountCloudSyncServiceError.rateLimited,
             AccountCloudSyncServiceError.server:
            accountCloudSyncStatus = .pendingOffline
        case AccountCloudSyncServiceError.conflict:
            accountCloudSyncStatus = .conflict
            presentCloudConflictNotice()
        case AccountCloudSyncServiceError.payloadTooLarge,
             AccountCloudSyncServiceError.unsupportedSchema,
             AccountCloudSyncServiceError.invalidResponse:
            accountCloudSyncStatus = .paused
            presentCloudPausedNotice()
        default:
            accountCloudSyncStatus = .pendingOffline
        }
    }

    private func pauseCloudSyncForStorageFailure() {
        isAccountCloudBootstrapPending = false
        accountCloudSyncStatus = .paused
        presentCloudPausedNotice()
    }

    private func presentCloudConflictNotice() {
        guard accountDataNotice == nil else { return }
        accountDataNotice = language.text(
            "這個帳號在另一部裝置也有變更。兩份資料都已保留，這次不會自動覆寫。",
            "다른 기기에서도 이 계정 데이터가 변경되었어요. 두 사본을 모두 보관하고 자동으로 덮어쓰지 않습니다.",
            "This account also changed on another device. Both copies are preserved and neither was overwritten automatically."
        )
    }

    private func presentCloudPausedNotice() {
        guard accountDataNotice == nil else { return }
        accountDataNotice = language.text(
            "帳號資料已留在這部裝置，但目前無法安全同步。稍後重新開啟 App 會再試一次。",
            "계정 데이터는 이 기기에 보관했지만 지금은 안전하게 동기화할 수 없어요. 앱을 다시 열면 재시도합니다.",
            "Your account data is safe on this device, but it couldn't sync securely. The app will try again when you reopen it."
        )
    }

    private func persist() {
        persistAccountData()
    }

    private var currentAccountID: String {
        account?.canonicalLocalAccountID ?? AccountStorage.guestAccountID
    }

    private func loadAccountData(for accountID: String) {
        // In-flight reveals never cross an account boundary. This prevents a
        // private question started by one person from being committed after a
        // shared iPad switches accounts.
        dailyAccessReservations.removeAll()
        if accountID == AccountStorage.guestAccountID {
            // A logged-out device never reuses a prior guest snapshot. This
            // prevents birth details or tarot history from appearing to the
            // next person on a shared iPad before they authenticate.
            accountStorage.removeAccountData(for: accountID)
        }
        let result = accountStorage.loadResult(for: accountID)
        accountDataWritesAllowed = result.allowsAutomaticWrites
        let data = result.data
        let canonicalSavedGuides = data.savedGuides.map { $0.canonicalized() }
        let canonicalReadingHistory = data.readingHistory.map { $0.canonicalized() }
        let localizedArchivesNeedMigration = canonicalSavedGuides != data.savedGuides
            || canonicalReadingHistory != data.readingHistory
        profile = data.profile
        savedGuides = canonicalSavedGuides
        readingHistory = canonicalReadingHistory
        planet = data.planet
        visitStreak = data.visitStreak
        lastVisitDate = data.lastVisitDate
        dailyGuideRevealDate = data.dailyGuideRevealDate
        tarotDrawDate = data.tarotDrawDate
        wardrobe = data.wardrobe
        starLife = data.starLife
        deferredAllLooksSelection = nil
        switch allLooksEntitlementState {
        case .unchecked:
            deferAllLooksSelectionUntilEntitlementCheck()
        case .active:
            break
        case .inactive:
            _ = removeEntitlementOnlySelections()
        }
        if accountID == AccountStorage.guestAccountID {
            // Guests cannot issue or redeem offline visit receipts. Discard any
            // pre-hardening transient exchange identity from the active view.
            starLife.visitExchange = nil
        }
        if !result.allowsAutomaticWrites {
            loginError = language.text(
                "這個帳號的本機資料無法讀取，已留存備份並暫停寫入。",
                "이 계정의 기기 데이터를 읽을 수 없어 백업하고 저장을 일시 중지했어요.",
                "This account's local data couldn't be read. It was backed up and writes are paused."
            )
        } else if localizedArchivesNeedMigration,
                  accountID == currentAccountID,
                  account != nil {
            _ = persistAccountData()
        }
    }

    @discardableResult
    private func persistAccountData(overridingStarLife: StarLifeState? = nil) -> Bool {
        // Language and the daily gate have their own device-level keys. All
        // personal content requires an authenticated account and is never
        // persisted into a reusable shared guest namespace.
        guard account != nil else { return true }
        guard accountDataWritesAllowed, deletionIntent == nil else { return false }
        let data = currentAccountCloudData(overridingStarLife: overridingStarLife)
        let context = accountCloudSyncContext()
        var queuedCloudUpload = false
        let didSave: Bool

        if !isApplyingCloudSnapshot,
           let context,
           accountStorage.cloudSyncWritesAllowed(for: context.accountID) {
            let bootstrapMode = accountStorage.cloudBootstrapMode(for: context.accountID)
            if bootstrapMode == .preferRemote, isPreparingAccountState {
                // The first remote read owns this short window. Initialization
                // writes stay local so seeded values cannot replace an existing
                // account on a different device.
                didSave = accountStorage.save(data, for: context.accountID)
            } else {
                if bootstrapMode == .preferRemote {
                    // A real local edit happened after an offline/deferred first
                    // read. Preserve it and make any collision explicit.
                    accountStorage.clearCloudBootstrap(for: context.accountID)
                    _ = accountStorage.prepareCloudBootstrap(
                        for: context.accountID,
                        mode: .preserveLocal
                    )
                }
                queuedCloudUpload = accountStorage.saveLocalSnapshotPreparingCloudUpload(
                    data,
                    for: context.accountID
                ) != nil
                didSave = queuedCloudUpload
            }
        } else {
            didSave = accountStorage.save(data, for: currentAccountID)
            if context != nil && !accountStorage.cloudSyncWritesAllowed(for: currentAccountID) {
                accountCloudSyncStatus = .paused
            }
        }
        if !didSave {
            accountDataWritesAllowed = false
            let message = language.text(
                "本機資料暫時無法安全儲存，已停止後續寫入，避免覆蓋原有內容。",
                "기기 데이터를 안전하게 저장할 수 없어 기존 내용을 덮어쓰지 않도록 추가 저장을 중지했어요.",
                "On-device data couldn't be saved safely. Further writes are paused to avoid overwriting existing content."
            )
            loginError = message
            accountDataNotice = message
        } else if queuedCloudUpload {
            accountCloudSyncStatus = .waitingToSync
            scheduleAccountCloudSync()
        }
        return didSave
    }

    private func persistWardrobe() {
        persistAccountData()
    }

    private func persistStarLife() {
        persistAccountData()
    }

    private func persistReminderPreferences() {
        defaults.set(reminderEnabled, forKey: Key.reminderEnabled)
        defaults.set(reminderTimeMinutes, forKey: Key.reminderTime)
    }

    private func syncLiveActivity(allowsNewActivity: Bool) {
        guard deletionIntent == nil, !isDeletingAccount else { return }
        let food = planet.food
        let status: String
        switch planet.mood {
        case .happy:
            status = language.text("今天想安靜地陪你", "오늘은 조용히 곁에 있을게요", "Quietly keeping you company today")
        case .glowing:
            status = language.text("剛剛吃到一點星光", "방금 별빛을 먹었어요", "Just had a little starlight")
        case .affectionate:
            status = language.text("它記得你的手心", "당신의 온기를 기억해요", "It remembers the warmth of your hand")
        case .delighted:
            status = language.text("今晚的約定完成了", "오늘 밤의 약속을 지켰어요", "Tonight's promise is complete")
        }
        Task {
            await LiveActivityController.shared.sync(
                food: food,
                status: status,
                language: language,
                allowsNewActivity: allowsNewActivity
            )
        }
    }
}

extension AppStore {
    var invitationHost: String? {
        AccountCloudBackendConfiguration()?.configuration.endpointURL(path: "invite")?.host
    }

    var canUseAccountActions: Bool {
        account != nil && authSession?.assurance == .backendVerified && accountCloudSyncService.isConfigured
            && deletionIntent == nil && !isDeletingAccount
    }

    /// Membership is fetched separately from editable personal snapshots. A restored
    /// backup must never grant access to another person's planet.
    var visiblePlanetMembers: [PlanetMember] {
        if let membership = sharedMembership {
            return membership.members.map {
                PlanetMember(id: $0.accountID, name: $0.name, symbol: "star.fill", isCurrentUser: $0.accountID == account?.canonicalAccountID)
            }
        }
        return [PlanetMember(id: "me", name: "me", symbol: "sparkles", isCurrentUser: true)]
    }

    var visiblePlanetRelationship: StarRelationship {
        sharedMembership?.relationship ?? planet.currentRelationship
    }

    func deleteAccountPermanently() async {
        guard !isDeletingAccount else { return }
        let confirmedAccountID = deletionIntent?.accountID ?? authSession?.account.id
        isDeletingAccount = true
        deletionError = nil
        defer { isDeletingAccount = false }
        do {
            if deletionIntent == nil {
                // Settle an existing refresh before using its newly rotated token.
                await sessionRefreshTask?.value
                guard var session = authSession, session.account.id == confirmedAccountID,
                      session.assurance == .backendVerified,
                      accountCloudSyncService.isConfigured else { throw AccountActionError(code: "verified_sign_in_required") }
                resetAccountCloudSyncForAccountChange()
                if session.needsRefresh() || session.isExpired() {
                    let refreshed = try await sessionRefreshService.refresh(session)
                    guard authSession == session, refreshed.account.id == session.account.id else { throw CancellationError() }
                    try sessionVault.save(refreshed)
                    authSession = refreshed
                    session = refreshed
                }
                guard let token = session.accessToken, !token.isEmpty else { throw AccountActionError(code: "unauthorized") }
                let intent = AccountDeletionIntent(accountID: session.account.id, providerAccountID: session.account.providerLocalAccountID, requestID: UUID().uuidString, serverDeleted: false)
                try saveDeletionIntent(intent)
                accountDataWritesAllowed = false
                planetGeneration &+= 1
                sharedMembership = nil
                pendingPlanetInviteCode = nil
                resetAccountCloudSyncForAccountChange()
                let currentLanguage = language
                await LiveActivityController.shared.end(language: currentLanguage)
            }
            guard var intent = deletionIntent else { throw AccountCloudSyncServiceError.invalidResponse }
            if !intent.serverDeleted {
                guard let session = authSession, session.account.id == intent.accountID,
                      session.assurance == .backendVerified, let token = session.accessToken
                else { throw AccountActionError(code: "deletion_session_missing") }
                do {
                    try await accountCloudSyncService.deleteAccount(requestID: intent.requestID, accessToken: token)
                } catch let error as AccountActionError where error.code == "unauthorized" && session.isExpired() {
                    // If the original request never reached the service before its
                    // bearer expired, no deletion lock exists. Refresh then retry.
                    // A server-side pending deletion rejects refresh and keeps its
                    // original credential available for the dedicated retry path.
                    let refreshed = try await sessionRefreshService.refresh(session)
                    guard refreshed.account.id == intent.accountID, let refreshedToken = refreshed.accessToken else { throw error }
                    try sessionVault.save(refreshed)
                    authSession = refreshed
                    try await accountCloudSyncService.deleteAccount(requestID: intent.requestID, accessToken: refreshedToken)
                }
                intent.serverDeleted = true
                try saveDeletionIntent(intent)
            }
            // Keep the completion marker until all local cleanup finishes. A crash
            // after server deletion can safely resume even after Keychain is cleared.
            try sessionVault.clear()
            resetSessionRefreshForAccountChange()
            resetAccountCloudSyncForAccountChange()
            accountStorage.removeAccountData(for: intent.accountID)
            accountStorage.removeAccountData(for: intent.providerAccountID)
            accountStorage.removeAccountData(for: AccountStorage.guestAccountID)
            let watchHash = intent.accountID.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
            for prefix in ["xingban.watch.account-scope.v1.", "xingban.watch.gentle-interaction.v1."] {
                defaults.removeObject(forKey: prefix + String(watchHash, radix: 16))
            }
            authSession = nil
            account = nil
            defaults.removeObject(forKey: Key.user)
            clearAccountTransientState()
            loadAccountData(for: AccountStorage.guestAccountID)
            reminderEnabled = false
            reminderTimeMinutes = 20 * 60 + 40
            defaults.removeObject(forKey: Key.reminderEnabled)
            defaults.removeObject(forKey: Key.reminderTime)
            defaults.removeObject(forKey: "xingban.ios.profile-setup-deferred.v1")
            actionState = .waiting
            isCelebrating = false
            await cancelAccountReminders()
            await LiveActivityController.shared.end(language: language)
            defaults.removeObject(forKey: Key.deletionIntent)
            deletionIntent = nil
        } catch {
            deletionError = accountActionMessage(error)
            if deletionIntent == nil {
                // No confirmed request was stored or submitted; the account remains usable.
                accountCloudSyncStatus = .pendingOffline
            }
        }
    }

    private func saveDeletionIntent(_ intent: AccountDeletionIntent) throws {
        let data = try JSONEncoder().encode(intent)
        defaults.set(data, forKey: Key.deletionIntent)
        guard defaults.data(forKey: Key.deletionIntent) == data else { throw AccountActivationError.localPersistenceFailed }
        deletionIntent = intent
    }

    private func accountActionSession() async throws -> AuthSession {
        guard deletionIntent == nil, !isDeletingAccount else { throw AccountActionError(code: "account_deletion_pending") }
        if scheduleSessionRefreshIfNeeded() { await sessionRefreshTask?.value }
        guard let session = authSession, session.assurance == .backendVerified,
              !session.isExpired(), session.accessToken?.isEmpty == false,
              accountCloudSyncService.isConfigured else { throw AccountActionError(code: "verified_sign_in_required") }
        return session
    }

    func refreshSharedPlanet() async {
        guard canUseAccountActions, !isLoadingPlanet, !isUpdatingPlanet else { return }
        let operationID = UUID()
        planetLoadID = operationID
        isLoadingPlanet = true
        defer { if planetLoadID == operationID { isLoadingPlanet = false; planetLoadID = nil } }
        do {
            let session = try await accountActionSession()
            guard planetLoadID == operationID else { return }
            let generation = planetGeneration
            let membership = try await accountCloudSyncService.fetchPlanet(accessToken: session.accessToken!)
            guard authSession?.account.id == session.account.id, planetGeneration == generation, deletionIntent == nil else { return }
            sharedMembership = membership
            planetServiceError = nil
        } catch {
            if planetLoadID == operationID, deletionIntent == nil { planetServiceError = accountActionMessage(error) }
        }
    }

    func createPlanetInvite(relationship: StarRelationship) async -> PlanetInvitation? {
        guard !isUpdatingPlanet else { return nil }
        let operationID = UUID()
        planetMutationID = operationID
        isUpdatingPlanet = true
        planetServiceError = nil
        defer { if planetMutationID == operationID { isUpdatingPlanet = false; planetMutationID = nil } }
        do {
            let session = try await accountActionSession()
            guard planetMutationID == operationID else { return nil }
            let generation = planetGeneration
            let result = try await accountCloudSyncService.createPlanetInvite(relationship: relationship, accessToken: session.accessToken!)
            guard authSession?.account.id == session.account.id, planetGeneration == generation, deletionIntent == nil else { return nil }
            planetGeneration &+= 1
            sharedMembership = result.planet
            return result.invite
        } catch {
            if planetMutationID == operationID, deletionIntent == nil { planetServiceError = accountActionMessage(error) }
            return nil
        }
    }

    func acceptPlanetInvite(_ input: String) async -> Bool {
        guard !isUpdatingPlanet else { return false }
        guard let code = PlanetInviteCode.parse(input, allowedHost: invitationHost) else {
            planetServiceError = accountActionMessage(AccountActionError(code: "invalid_invite"))
            return false
        }
        let operationID = UUID()
        planetMutationID = operationID
        isUpdatingPlanet = true
        planetServiceError = nil
        defer { if planetMutationID == operationID { isUpdatingPlanet = false; planetMutationID = nil } }
        do {
            let session = try await accountActionSession()
            guard planetMutationID == operationID else { return false }
            let generation = planetGeneration
            let membership = try await accountCloudSyncService.acceptPlanetInvite(code: code, accessToken: session.accessToken!)
            guard authSession?.account.id == session.account.id, planetGeneration == generation, deletionIntent == nil else { return false }
            planetGeneration &+= 1
            sharedMembership = membership
            pendingPlanetInviteCode = nil
            return true
        } catch {
            if planetMutationID == operationID, deletionIntent == nil { planetServiceError = accountActionMessage(error) }
            return false
        }
    }

    func leaveSharedPlanet() async -> Bool {
        await changePlanetMembership(inviteCodeToRevoke: nil)
    }

    func revokePlanetInvite(_ code: String) async -> Bool {
        await changePlanetMembership(inviteCodeToRevoke: code)
    }

    private func changePlanetMembership(inviteCodeToRevoke code: String?) async -> Bool {
        guard !isUpdatingPlanet else { return false }
        let operationID = UUID()
        planetMutationID = operationID
        isUpdatingPlanet = true
        planetServiceError = nil
        defer { if planetMutationID == operationID { isUpdatingPlanet = false; planetMutationID = nil } }
        do {
            let session = try await accountActionSession()
            guard planetMutationID == operationID else { return false }
            let generation = planetGeneration
            if let code { try await accountCloudSyncService.revokePlanetInvite(code: code, accessToken: session.accessToken!) }
            else { try await accountCloudSyncService.leavePlanet(accessToken: session.accessToken!) }
            guard authSession?.account.id == session.account.id, planetGeneration == generation, deletionIntent == nil else { return false }
            planetGeneration &+= 1
            if code == nil { sharedMembership = nil }
            return true
        } catch {
            if planetMutationID == operationID, deletionIntent == nil { planetServiceError = accountActionMessage(error) }
            return false
        }
    }

    private func accountActionMessage(_ error: Error) -> String {
        switch (error as? AccountActionError)?.code {
        case "verified_sign_in_required", "unauthorized":
            return language.text("請先登入正式帳號，再試一次。", "정식 계정으로 로그인한 뒤 다시 시도해 주세요.", "Sign in with a verified account and try again.")
        case "invalid_invite", "invalid_invite_code", "invite_not_found", "invite_expired", "invite_revoked":
            return language.text("邀請碼無效、已過期或已撤銷，請朋友重新分享。", "초대 코드가 잘못되었거나 만료 또는 취소되었어요. 친구에게 새 초대를 부탁하세요.", "This invitation is invalid, expired, or revoked. Ask your friend for a new one.")
        case "invite_already_used":
            return language.text("這份邀請已經被使用，請朋友建立新的邀請。", "이미 사용된 초대예요. 새로운 초대를 부탁하세요.", "This invitation has already been used. Ask for a new invitation.")
        case "cannot_accept_own_invite":
            return language.text("這是你自己的邀請，分享給朋友後，讓對方來加入吧。", "내가 만든 초대예요. 친구에게 공유하고 참여를 기다려 주세요.", "This is your own invitation. Share it with your friend so they can join.")
        case "already_in_planet":
            return language.text("你已經加入另一顆星球。若想更換，請先在星球設定中退出。", "이미 다른 별에 살고 있어요. 옮기려면 별 설정에서 먼저 나가 주세요.", "You already belong to another planet. Leave it in Planet Settings before joining a new one.")
        case "planet_full":
            return language.text("這顆星球已經住滿兩個人了。", "이 별에는 이미 두 사람이 살고 있어요.", "This planet already has two people.")
        case "relationship_mismatch":
            return language.text("請使用目前星球的關係類型建立邀請。", "현재 별의 관계로 초대를 만들어 주세요.", "Create an invitation using your current planet's relationship.")
        case "rate_limited":
            return language.text("操作太頻繁，請稍等一會兒再試。", "요청이 너무 많아요. 잠시 후 다시 시도해 주세요.", "Too many attempts. Wait a little and try again.")
        case "apple_revoke_failed", "account_deletion_pending":
            return language.text("帳號刪除尚未完成，資料同步已暫停。請按重試繼續。", "계정 삭제가 완료되지 않아 동기화를 멈췄어요. 다시 시도하여 계속해 주세요.", "Account deletion hasn't finished. Sync is paused. Tap Retry to continue.")
        case "deletion_session_missing":
            return language.text("找不到完成刪除所需的安全憑證。請保留這部裝置的資料並聯絡支援。", "삭제에 필요한 보안 인증 정보를 찾지 못했어요. 기기 데이터를 보관하고 지원팀에 문의해 주세요.", "The secure credential needed to finish deletion is missing. Keep this device's data and contact support.")
        default:
            return language.text("暫時無法完成，請確認網路後重試。", "지금은 완료할 수 없어요. 연결을 확인하고 다시 시도해 주세요.", "Couldn't finish right now. Check your connection and try again.")
        }
    }
}
