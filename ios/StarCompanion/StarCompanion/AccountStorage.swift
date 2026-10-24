import Foundation

struct AccountLocalData: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var profile: BirthProfile?
    var savedGuides: [DailyGuide]
    var readingHistory: [TarotReadingRecord]
    var planet: SharedPlanet
    var visitStreak: Int
    var lastVisitDate: String?
    var dailyGuideRevealDate: String?
    var tarotDrawDate: String?
    var wardrobe: StarWardrobe
    var starLife: StarLifeState

    static func seeded(for accountID: String) -> AccountLocalData {
        var starLife = StarLifeState.seeded()
        if accountID == AccountStorage.guestAccountID {
            starLife.visitExchange = nil
        }
        return AccountLocalData(
            schemaVersion: currentSchemaVersion,
            profile: nil,
            savedGuides: [],
            readingHistory: [],
            planet: SharedPlanet(),
            visitStreak: 0,
            lastVisitDate: nil,
            dailyGuideRevealDate: nil,
            tarotDrawDate: nil,
            wardrobe: .seeded(for: accountID),
            starLife: starLife
        )
    }

    func normalized(for accountID: String) -> AccountLocalData {
        var copy = self
        copy.schemaVersion = Self.currentSchemaVersion
        copy.visitStreak = max(0, copy.visitStreak)
        copy.wardrobe = copy.wardrobe.migrated(for: accountID)
        copy.starLife = copy.starLife.migrated()
        if accountID == AccountStorage.guestAccountID {
            copy.starLife.visitExchange = nil
        }
        return copy
    }
}

/// A server-authenticated account document. `revision` is an opaque value
/// issued by the backend and is used as the compare-and-swap base for the next
/// upload.
struct AccountCloudSnapshot: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var revision: String
    var updatedAt: Date
    var snapshot: AccountLocalData

    init(
        schemaVersion: Int = currentSchemaVersion,
        revision: String,
        updatedAt: Date,
        snapshot: AccountLocalData
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.updatedAt = updatedAt
        self.snapshot = snapshot
    }
}

/// The newest local intent waiting to be acknowledged by the backend. Multiple
/// quick saves may replace this value, but they retain the same `baseRevision`
/// until an earlier in-flight upload advances the server revision.
struct AccountCloudPendingUpload: Codable, Equatable {
    var mutationID: String
    var baseRevision: String?
    var queuedAt: Date
    var snapshot: AccountLocalData

    init(
        mutationID: String = UUID().uuidString.lowercased(),
        baseRevision: String?,
        queuedAt: Date = .now,
        snapshot: AccountLocalData
    ) {
        self.mutationID = mutationID
        self.baseRevision = baseRevision
        self.queuedAt = queuedAt
        self.snapshot = snapshot
    }
}

/// `preferRemote` is appropriate when this device has no owned account data.
/// `preserveLocal` makes a first-sync collision explicit instead of silently
/// replacing data created before cloud sync was introduced.
enum AccountCloudBootstrapMode: String, Codable, Equatable {
    case preferRemote
    case preserveLocal
}

/// A durable, user-recoverable copy of both sides of a compare-and-swap
/// conflict. Recording a conflict never changes the current local snapshot,
/// pending upload, or last known server anchor.
struct AccountCloudConflictBackup: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var recordedAt: Date
    var local: AccountCloudPendingUpload
    var remote: AccountCloudSnapshot

    init(
        schemaVersion: Int = currentSchemaVersion,
        recordedAt: Date = .now,
        local: AccountCloudPendingUpload,
        remote: AccountCloudSnapshot
    ) {
        self.schemaVersion = schemaVersion
        self.recordedAt = recordedAt
        self.local = local
        self.remote = remote
    }
}

private struct AccountCloudBootstrapRecord: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var mode: AccountCloudBootstrapMode
    var preparedAt: Date
}

enum LegacyAccountStorageKey {
    static let userRecoveryPrefix = "xingban.ios.legacy-user-recovery.v1."
    static let planet = "xingban.ios.shared-planet.v1"
    static let profile = "xingban.ios.birth-profile.v1"
    static let savedGuides = "xingban.ios.saved-guides.v1"
    static let readingHistory = "xingban.ios.reading-history.v1"
    static let visitStreak = "xingban.ios.visit-streak.v1"
    static let lastVisit = "xingban.ios.last-visit.v1"
    static let dailyGuideRevealDate = "xingban.ios.daily-guide-reveal-date.v1"
    static let tarotDrawDate = "xingban.ios.tarot-draw-date.v1"
    static let wardrobePrefix = "xingban.ios.star-wardrobe.v1."
    static let starLifePrefix = "xingban.ios.star-life.v1."

    static let globalKeys = [
        planet,
        profile,
        savedGuides,
        readingHistory,
        visitStreak,
        lastVisit,
        dailyGuideRevealDate,
        tarotDrawDate,
    ]
}

enum AccountStorageMigrationResult: Equatable {
    case migrated
    case resumed
    case alreadyCompleted
    case nothingToMigrate
    case targetAlreadyExists
    case invalidLegacyData
    case failedToWrite
}

enum AccountStorageLoadStatus: Equatable {
    case missing
    case loaded
    case normalized
    case quarantined
    case unsupportedSchema(Int)
}

struct AccountStorageLoadResult: Equatable {
    let data: AccountLocalData
    let status: AccountStorageLoadStatus

    var allowsAutomaticWrites: Bool {
        switch status {
        case .quarantined, .unsupportedSchema: false
        case .missing, .loaded, .normalized: true
        }
    }
}

enum AccountRelinkMigrationResult: Equatable {
    case migrated
    case finalizePending
    case sameAccount
    case sourceMissing
    case targetAlreadyExists
    case invalidSource
    case failedToWrite
}

struct AccountStorage {
    static let guestAccountID = "guest"
    static let legacyRecoveryAccountID = "legacy-recovery"

    private static let accountPrefix = "xingban.ios.account-local.v1."
    private static let migrationCompletedPrefix = "xingban.ios.account-local-migration.v1.completed."
    private static let migrationPreparedPrefix = "xingban.ios.account-local-migration.v1.prepared."
    private static let quarantinePrefix = "xingban.ios.account-local-quarantine.v1."
    private static let quarantineBlockedPrefix = "xingban.ios.account-local-quarantine.v1.blocked."
    private static let relinkConflictPrefix = "xingban.ios.account-relink-conflict.v1."
    private static let relinkPreparedPrefix = "xingban.ios.account-relink-prepared.v1."
    private static let cloudAnchorPrefix = "xingban.ios.account-cloud-anchor.v1."
    private static let cloudPendingPrefix = "xingban.ios.account-cloud-pending.v1."
    private static let cloudBootstrapPrefix = "xingban.ios.account-cloud-bootstrap.v1."
    private static let cloudConflictPrefix = "xingban.ios.account-cloud-conflict.v1."
    private static let cloudQuarantinePrefix = "xingban.ios.account-cloud-quarantine.v1."
    private static let cloudBlockedPrefix = "xingban.ios.account-cloud-quarantine.v1.blocked."

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func load(for accountID: String) -> AccountLocalData {
        loadResult(for: accountID).data
    }

    func loadResult(for accountID: String) -> AccountStorageLoadResult {
        let targetKey = storageKey(for: accountID)
        let pending = cloudPendingUpload(for: accountID)
        guard let rawValue = defaults.object(forKey: targetKey) else {
            let isBlocked = defaults.bool(forKey: quarantineBlockedKey(for: accountID))
            if !isBlocked, let pending {
                let recovered = pending.snapshot.normalized(for: accountID)
                _ = save(recovered, for: accountID)
                return AccountStorageLoadResult(data: recovered, status: .normalized)
            }
            return AccountStorageLoadResult(
                data: .seeded(for: accountID),
                status: isBlocked ? .quarantined : .missing
            )
        }
        guard let data = rawValue as? Data else {
            quarantine(rawValue, accountID: accountID, sourceKey: targetKey)
            return AccountStorageLoadResult(data: .seeded(for: accountID), status: .quarantined)
        }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let schemaVersion = (object["schemaVersion"] as? NSNumber)?.intValue,
               schemaVersion > AccountLocalData.currentSchemaVersion {
                quarantine(data, accountID: accountID, sourceKey: targetKey)
                return AccountStorageLoadResult(
                    data: .seeded(for: accountID),
                    status: .unsupportedSchema(schemaVersion)
                )
            }
            if let starLife = object["starLife"] as? [String: Any],
               let schemaVersion = (starLife["schemaVersion"] as? NSNumber)?.intValue,
               schemaVersion > StarLifeState.currentSchemaVersion {
                quarantine(data, accountID: accountID, sourceKey: targetKey)
                return AccountStorageLoadResult(
                    data: .seeded(for: accountID),
                    status: .unsupportedSchema(schemaVersion)
                )
            }
        }
        guard let decoded = try? decoder.decode(AccountLocalData.self, from: data) else {
            quarantine(data, accountID: accountID, sourceKey: targetKey)
            return AccountStorageLoadResult(data: .seeded(for: accountID), status: .quarantined)
        }

        defaults.removeObject(forKey: quarantineBlockedKey(for: accountID))
        let normalized = decoded.normalized(for: accountID)
        if let pending {
            let recovered = pending.snapshot.normalized(for: accountID)
            if recovered != normalized {
                _ = save(recovered, for: accountID)
                return AccountStorageLoadResult(data: recovered, status: .normalized)
            }
            return AccountStorageLoadResult(data: recovered, status: .loaded)
        }
        if normalized != decoded {
            _ = save(normalized, for: accountID)
            return AccountStorageLoadResult(data: normalized, status: .normalized)
        }
        return AccountStorageLoadResult(data: normalized, status: .loaded)
    }

    @discardableResult
    func save(_ value: AccountLocalData, for accountID: String) -> Bool {
        guard !defaults.bool(forKey: quarantineBlockedKey(for: accountID)) else { return false }
        let normalized = value.normalized(for: accountID)
        guard let data = try? encoder.encode(normalized) else { return false }
        defaults.set(data, forKey: storageKey(for: accountID))
        return defaults.data(forKey: storageKey(for: accountID)) == data
    }

    func hasStoredData(for accountID: String) -> Bool {
        defaults.object(forKey: storageKey(for: accountID)) != nil
    }

    func hasProtectedOrStoredData(for accountID: String) -> Bool {
        hasStoredData(for: accountID)
            || defaults.bool(forKey: quarantineBlockedKey(for: accountID))
    }

    func protectFromAutomaticWrites(for accountID: String) {
        defaults.set(true, forKey: quarantineBlockedKey(for: accountID))
    }

    /// Cloud metadata is deliberately independent from local-data quarantine.
    /// A corrupt/future cloud record pauses network reconciliation without
    /// preventing the already-safe local snapshot from being read.
    func cloudSyncWritesAllowed(for accountID: String) -> Bool {
        _ = validateCloudMetadata(for: accountID)
        return !defaults.bool(forKey: cloudBlockedKey(for: accountID))
    }

    /// Persists the first-sync policy so a terminated launch resumes with the
    /// same overwrite decision. An existing decision must be cleared
    /// explicitly before it can be changed.
    @discardableResult
    func prepareCloudBootstrap(
        for accountID: String,
        mode: AccountCloudBootstrapMode,
        preparedAt: Date = .now
    ) -> Bool {
        guard validateCloudMetadata(for: accountID),
              !defaults.bool(forKey: cloudBlockedKey(for: accountID)),
              preparedAt.timeIntervalSinceReferenceDate.isFinite
        else { return false }
        if let existing = cloudBootstrapRecord(for: accountID) {
            return existing.mode == mode
        }
        let record = AccountCloudBootstrapRecord(
            schemaVersion: AccountCloudBootstrapRecord.currentSchemaVersion,
            mode: mode,
            preparedAt: preparedAt
        )
        return writeCloudValue(record, forKey: cloudBootstrapKey(for: accountID))
    }

    func cloudBootstrapMode(for accountID: String) -> AccountCloudBootstrapMode? {
        cloudBootstrapRecord(for: accountID)?.mode
    }

    func clearCloudBootstrap(for accountID: String) {
        defaults.removeObject(forKey: cloudBootstrapKey(for: accountID))
    }

    func cloudAnchor(for accountID: String) -> AccountCloudSnapshot? {
        guard var value: AccountCloudSnapshot = loadCloudValue(
            forKey: cloudAnchorKey(for: accountID),
            accountID: accountID,
            validate: { isValidCloudSnapshot($0, for: accountID) }
        ) else { return nil }
        value.snapshot = value.snapshot.normalized(for: accountID)
        return value
    }

    func cloudPendingUpload(for accountID: String) -> AccountCloudPendingUpload? {
        guard var value: AccountCloudPendingUpload = loadCloudValue(
            forKey: cloudPendingKey(for: accountID),
            accountID: accountID,
            validate: { isValidCloudPendingUpload($0, for: accountID) }
        ) else { return nil }
        value.snapshot = value.snapshot.normalized(for: accountID)
        return value
    }

    func cloudConflictBackup(for accountID: String) -> AccountCloudConflictBackup? {
        guard var value: AccountCloudConflictBackup = loadCloudValue(
            forKey: cloudConflictKey(for: accountID),
            accountID: accountID,
            validate: { isValidCloudConflict($0, for: accountID) }
        ) else { return nil }
        value.local.snapshot = value.local.snapshot.normalized(for: accountID)
        value.remote.snapshot = value.remote.snapshot.normalized(for: accountID)
        return value
    }

    /// Atomically enough for process termination: the complete pending intent
    /// is written and read-verified before the current cache is replaced. If
    /// termination happens between those writes, `loadResult` recovers from the
    /// pending snapshot on the next launch.
    @discardableResult
    func saveLocalSnapshotPreparingCloudUpload(
        _ value: AccountLocalData,
        for accountID: String,
        mutationID: String = UUID().uuidString.lowercased(),
        queuedAt: Date = .now
    ) -> AccountCloudPendingUpload? {
        guard !defaults.bool(forKey: quarantineBlockedKey(for: accountID)),
              validateCloudMetadata(for: accountID),
              !defaults.bool(forKey: cloudBlockedKey(for: accountID))
        else { return nil }

        let existingPending = cloudPendingUpload(for: accountID)
        let baseRevision = existingPending?.baseRevision ?? cloudAnchor(for: accountID)?.revision
        let pending = AccountCloudPendingUpload(
            mutationID: mutationID,
            baseRevision: baseRevision,
            queuedAt: queuedAt,
            snapshot: value.normalized(for: accountID)
        )
        guard isValidCloudPendingUpload(pending, for: accountID) else { return nil }

        let pendingKey = cloudPendingKey(for: accountID)
        let previousPending = defaults.object(forKey: pendingKey)
        guard writeCloudValue(pending, forKey: pendingKey) else {
            restore(previousPending, forKey: pendingKey)
            return nil
        }

        // A failed cache write is still recoverable because the verified
        // pending value remains authoritative on the next `loadResult`.
        _ = writeLocalSnapshot(pending.snapshot, for: accountID)
        return pending
    }

    /// Applies a clean remote document. Dirty local data and unresolved
    /// conflicts are never silently overwritten.
    @discardableResult
    func applyRemoteCloudSnapshot(
        _ remote: AccountCloudSnapshot,
        for accountID: String
    ) -> Bool {
        guard validateCloudMetadata(for: accountID),
              !defaults.bool(forKey: cloudBlockedKey(for: accountID)),
              cloudPendingUpload(for: accountID) == nil,
              cloudConflictBackup(for: accountID) == nil,
              validateIncomingCloudSnapshot(remote, for: accountID)
        else { return false }

        var normalized = remote
        normalized.snapshot = remote.snapshot.normalized(for: accountID)
        let currentKey = storageKey(for: accountID)
        let previousCurrent = defaults.object(forKey: currentKey)
        guard writeLocalSnapshot(normalized.snapshot, for: accountID) else { return false }
        guard writeCloudValue(normalized, forKey: cloudAnchorKey(for: accountID)) else {
            restore(previousCurrent, forKey: currentKey)
            return false
        }
        clearCloudBootstrap(for: accountID)
        return true
    }

    /// Commits a successful server write. Only the exact pending mutation may
    /// be cleared. If a newer local mutation replaced it while the request was
    /// in flight, that newer value is retained and rebased to the acknowledged
    /// server revision.
    @discardableResult
    func acknowledgeCloudUpload(
        mutationID: String,
        remote: AccountCloudSnapshot,
        for accountID: String
    ) -> Bool {
        guard validateCloudMetadata(for: accountID),
              !defaults.bool(forKey: cloudBlockedKey(for: accountID)),
              cloudConflictBackup(for: accountID) == nil,
              validateIncomingCloudSnapshot(remote, for: accountID),
              let pending = cloudPendingUpload(for: accountID)
        else { return false }

        var normalizedRemote = remote
        normalizedRemote.snapshot = remote.snapshot.normalized(for: accountID)
        let anchorKey = cloudAnchorKey(for: accountID)

        if pending.mutationID != mutationID {
            guard writeCloudValue(normalizedRemote, forKey: anchorKey) else { return false }
            var rebased = pending
            rebased.baseRevision = normalizedRemote.revision
            return writeCloudValue(rebased, forKey: cloudPendingKey(for: accountID))
        }

        let currentKey = storageKey(for: accountID)
        let previousCurrent = defaults.object(forKey: currentKey)
        guard writeLocalSnapshot(normalizedRemote.snapshot, for: accountID) else { return false }
        guard writeCloudValue(normalizedRemote, forKey: anchorKey) else {
            restore(previousCurrent, forKey: currentKey)
            return false
        }
        guard cloudPendingUpload(for: accountID)?.mutationID == mutationID else { return false }
        defaults.removeObject(forKey: cloudPendingKey(for: accountID))
        clearCloudBootstrap(for: accountID)
        return true
    }

    /// Saves both sides of a 409 response without changing either live side.
    /// The first unresolved backup wins so repeated retries cannot erase the
    /// original evidence needed for an explicit resolution.
    @discardableResult
    func recordCloudConflict(
        remote: AccountCloudSnapshot,
        for accountID: String,
        recordedAt: Date = .now
    ) -> Bool {
        guard validateCloudMetadata(for: accountID),
              !defaults.bool(forKey: cloudBlockedKey(for: accountID)),
              recordedAt.timeIntervalSinceReferenceDate.isFinite,
              validateIncomingCloudSnapshot(remote, for: accountID),
              let local = cloudPendingUpload(for: accountID)
        else { return false }
        if cloudConflictBackup(for: accountID) != nil { return true }

        var normalizedRemote = remote
        normalizedRemote.snapshot = remote.snapshot.normalized(for: accountID)
        let backup = AccountCloudConflictBackup(
            recordedAt: recordedAt,
            local: local,
            remote: normalizedRemote
        )
        return writeCloudValue(backup, forKey: cloudConflictKey(for: accountID))
    }

    func clearCloudConflictBackup(for accountID: String) {
        defaults.removeObject(forKey: cloudConflictKey(for: accountID))
    }

    /// Resolves an explicit collision by adopting the server copy. The local
    /// and pending values are removed only after both the current cache and the
    /// remote anchor have been written and read-verified.
    @discardableResult
    func resolveCloudConflictUsingRemote(for accountID: String) -> AccountCloudSnapshot? {
        guard validateCloudMetadata(for: accountID),
              !defaults.bool(forKey: cloudBlockedKey(for: accountID)),
              let conflict = cloudConflictBackup(for: accountID),
              validateIncomingCloudSnapshot(conflict.remote, for: accountID)
        else { return nil }

        var remote = conflict.remote
        remote.snapshot = remote.snapshot.normalized(for: accountID)
        let currentKey = storageKey(for: accountID)
        let anchorKey = cloudAnchorKey(for: accountID)
        let pendingKey = cloudPendingKey(for: accountID)
        let bootstrapKey = cloudBootstrapKey(for: accountID)
        let conflictKey = cloudConflictKey(for: accountID)
        let previousValues: [(String, Any?)] = [
            (currentKey, defaults.object(forKey: currentKey)),
            (anchorKey, defaults.object(forKey: anchorKey)),
            (pendingKey, defaults.object(forKey: pendingKey)),
            (bootstrapKey, defaults.object(forKey: bootstrapKey)),
            (conflictKey, defaults.object(forKey: conflictKey)),
        ]

        guard writeLocalSnapshot(remote.snapshot, for: accountID),
              writeCloudValue(remote, forKey: anchorKey)
        else {
            previousValues.forEach { restore($0.1, forKey: $0.0) }
            return nil
        }
        defaults.removeObject(forKey: pendingKey)
        defaults.removeObject(forKey: bootstrapKey)
        defaults.removeObject(forKey: conflictKey)
        guard cloudPendingUpload(for: accountID) == nil,
              cloudBootstrapMode(for: accountID) == nil,
              cloudConflictBackup(for: accountID) == nil
        else {
            previousValues.forEach { restore($0.1, forKey: $0.0) }
            return nil
        }
        return remote
    }

    /// Resolves an explicit collision by keeping this device's copy. A fresh
    /// idempotency key is required because the earlier key may already have
    /// reached the server with a different base revision.
    @discardableResult
    func resolveCloudConflictUsingLocal(
        for accountID: String,
        mutationID: String = UUID().uuidString.lowercased(),
        queuedAt: Date = .now
    ) -> AccountCloudPendingUpload? {
        guard validateCloudMetadata(for: accountID),
              !defaults.bool(forKey: cloudBlockedKey(for: accountID)),
              let conflict = cloudConflictBackup(for: accountID),
              validateIncomingCloudSnapshot(conflict.remote, for: accountID)
        else { return nil }

        let pending = AccountCloudPendingUpload(
            mutationID: mutationID,
            baseRevision: conflict.remote.revision,
            queuedAt: queuedAt,
            snapshot: conflict.local.snapshot.normalized(for: accountID)
        )
        guard pending.mutationID != conflict.local.mutationID,
              isValidCloudPendingUpload(pending, for: accountID)
        else { return nil }

        var remote = conflict.remote
        remote.snapshot = remote.snapshot.normalized(for: accountID)
        let currentKey = storageKey(for: accountID)
        let anchorKey = cloudAnchorKey(for: accountID)
        let pendingKey = cloudPendingKey(for: accountID)
        let bootstrapKey = cloudBootstrapKey(for: accountID)
        let conflictKey = cloudConflictKey(for: accountID)
        let previousValues: [(String, Any?)] = [
            (currentKey, defaults.object(forKey: currentKey)),
            (anchorKey, defaults.object(forKey: anchorKey)),
            (pendingKey, defaults.object(forKey: pendingKey)),
            (bootstrapKey, defaults.object(forKey: bootstrapKey)),
            (conflictKey, defaults.object(forKey: conflictKey)),
        ]

        guard writeCloudValue(pending, forKey: pendingKey),
              writeLocalSnapshot(pending.snapshot, for: accountID),
              writeCloudValue(remote, forKey: anchorKey)
        else {
            previousValues.forEach { restore($0.1, forKey: $0.0) }
            return nil
        }
        defaults.removeObject(forKey: bootstrapKey)
        defaults.removeObject(forKey: conflictKey)
        guard cloudPendingUpload(for: accountID) == pending,
              cloudAnchor(for: accountID) == remote,
              cloudBootstrapMode(for: accountID) == nil,
              cloudConflictBackup(for: accountID) == nil
        else {
            previousValues.forEach { restore($0.1, forKey: $0.0) }
            return nil
        }
        return pending
    }

    func recordRelinkConflict(from sourceAccountID: String, to targetAccountID: String) {
        defaults.set(
            Date.now,
            forKey: Self.relinkConflictPrefix
                + encodedKeyComponent(sourceAccountID)
                + "."
                + encodedKeyComponent(targetAccountID)
        )
    }

    func hasRelinkConflict(from sourceAccountID: String, to targetAccountID: String) -> Bool {
        defaults.object(
            forKey: Self.relinkConflictPrefix
                + encodedKeyComponent(sourceAccountID)
                + "."
                + encodedKeyComponent(targetAccountID)
        ) != nil
    }

    /// Migrates the pre-account global values and the two legacy per-WeChat
    /// values into one account snapshot. The prepared marker makes a launch
    /// interruption safe to resume, while an unrelated existing target is
    /// always preserved.
    @discardableResult
    func migrateLegacyDataIfNeeded(
        for accountID: String,
        legacyProviderAccountID: String,
        includeGlobalValues: Bool
    ) -> AccountStorageMigrationResult {
        let completedKey = migrationCompletedKey(for: accountID)
        let preparedKey = migrationPreparedKey(for: accountID)
        let targetKey = storageKey(for: accountID)

        if defaults.bool(forKey: completedKey) {
            return .alreadyCompleted
        }

        if let preparedMode = defaults.string(forKey: preparedKey) {
            if let targetData = defaults.data(forKey: targetKey),
               (try? decoder.decode(AccountLocalData.self, from: targetData)) != nil {
                finishLegacyMigration(
                    accountID: accountID,
                    legacyProviderAccountID: legacyProviderAccountID,
                    includeGlobalValues: preparedMode == "global"
                )
                return .resumed
            }

            // Only a target accompanied by our prepared marker can be removed.
            defaults.removeObject(forKey: targetKey)
            defaults.removeObject(forKey: preparedKey)
        }

        if hasProtectedOrStoredData(for: accountID) {
            return .targetAlreadyExists
        }

        let legacyKeys = legacyKeys(
            for: legacyProviderAccountID,
            includeGlobalValues: includeGlobalValues
        )
        guard legacyKeys.contains(where: { defaults.object(forKey: $0) != nil }) else {
            return .nothingToMigrate
        }
        guard let migrated = makeLegacySnapshot(
            accountID: accountID,
            legacyProviderAccountID: legacyProviderAccountID,
            includeGlobalValues: includeGlobalValues
        ) else {
            return .invalidLegacyData
        }

        guard let encoded = try? encoder.encode(migrated.normalized(for: accountID)) else {
            return .failedToWrite
        }
        defaults.set(includeGlobalValues ? "global" : "provider", forKey: preparedKey)
        defaults.set(encoded, forKey: targetKey)

        guard let written = defaults.data(forKey: targetKey),
              written == encoded,
              (try? decoder.decode(AccountLocalData.self, from: written)) != nil
        else {
            defaults.removeObject(forKey: targetKey)
            defaults.removeObject(forKey: preparedKey)
            return .failedToWrite
        }

        finishLegacyMigration(
            accountID: accountID,
            legacyProviderAccountID: legacyProviderAccountID,
            includeGlobalValues: includeGlobalValues
        )
        return .migrated
    }

    /// Supports a later provider-linking flow without letting the source
    /// identity overwrite an already established canonical account.
    /// This compatibility entry point performs the full copy/finalize pair.
    /// Authentication flows should call `prepareAccountRelink` first, persist
    /// the new secure session, and only then call `finalizeAccountRelink`.
    @discardableResult
    func relinkAccountData(
        from sourceAccountID: String,
        to targetAccountID: String
    ) -> AccountRelinkMigrationResult {
        let result = prepareAccountRelink(from: sourceAccountID, to: targetAccountID)
        if result == .migrated {
            guard finalizeAccountRelink(from: sourceAccountID, to: targetAccountID) else {
                // Keep both verified copies and the marker. The next launch
                // can refresh from the source and retry the destructive
                // finalize step without seeding or blocking a missing target.
                return .finalizePending
            }
        }
        return result
    }

    /// Copies a provider-local snapshot without deleting it. This is phase one
    /// of account linking, so a Keychain failure cannot strand the only copy
    /// under an identity the next launch no longer knows about.
    @discardableResult
    func prepareAccountRelink(
        from sourceAccountID: String,
        to targetAccountID: String
    ) -> AccountRelinkMigrationResult {
        guard sourceAccountID != targetAccountID else { return .sameAccount }
        let preparedKey = relinkPreparedKey(from: sourceAccountID, to: targetAccountID)
        if defaults.bool(forKey: preparedKey) {
            let source = loadResult(for: sourceAccountID)
            switch source.status {
            case .missing:
                // Finalization removes the source before its marker. If the
                // process stopped in that tiny window, the valid target is now
                // authoritative and the marker can simply be cleared.
                defaults.removeObject(forKey: preparedKey)
                return .sourceMissing
            case .quarantined, .unsupportedSchema:
                return .invalidSource
            case .loaded, .normalized:
                // Always refresh from the latest source. It may have received
                // a receipt or another mutation after the first copy and
                // before the secure-session commit completed.
                let target = loadResult(for: targetAccountID)
                if !target.allowsAutomaticWrites {
                    // The target belongs to this prepared transaction. Its raw
                    // bytes were already quarantined above, so rebuilding from
                    // the still-valid source cannot destroy the only copy.
                    defaults.removeObject(forKey: quarantineBlockedKey(for: targetAccountID))
                }
                guard save(source.data, for: targetAccountID) else {
                    return .failedToWrite
                }
                return .migrated
            }
        }

        if hasProtectedOrStoredData(for: targetAccountID) {
            return hasProtectedOrStoredData(for: sourceAccountID)
                ? .targetAlreadyExists
                : .sourceMissing
        }

        let source = loadResult(for: sourceAccountID)
        switch source.status {
        case .missing:
            return .sourceMissing
        case .quarantined, .unsupportedSchema:
            return .invalidSource
        case .loaded, .normalized:
            defaults.set(true, forKey: preparedKey)
            guard save(source.data, for: targetAccountID) else {
                defaults.removeObject(forKey: preparedKey)
                defaults.removeObject(forKey: storageKey(for: targetAccountID))
                return .failedToWrite
            }
            return .migrated
        }
    }

    @discardableResult
    func finalizeAccountRelink(
        from sourceAccountID: String,
        to targetAccountID: String
    ) -> Bool {
        guard sourceAccountID != targetAccountID else { return true }
        let preparedKey = relinkPreparedKey(from: sourceAccountID, to: targetAccountID)
        guard defaults.bool(forKey: preparedKey),
              let source = compatibleStoredSnapshot(for: sourceAccountID),
              let target = compatibleStoredSnapshot(for: targetAccountID),
              source == target
        else { return false }
        defaults.removeObject(forKey: storageKey(for: sourceAccountID))
        let finalized = !hasStoredData(for: sourceAccountID)
        if finalized {
            defaults.removeObject(forKey: preparedKey)
        }
        return finalized
    }

    /// Safe only after `prepareAccountRelink` returned `.migrated`; callers
    /// use it to undo the newly-created target if secure-session persistence
    /// fails before the relink is finalized.
    func rollbackPreparedAccountRelink(from sourceAccountID: String, to targetAccountID: String) {
        defaults.removeObject(forKey: storageKey(for: targetAccountID))
        defaults.removeObject(forKey: relinkPreparedKey(from: sourceAccountID, to: targetAccountID))
    }

    @discardableResult
    func migrateAccountData(from sourceAccountID: String, to targetAccountID: String) -> Bool {
        relinkAccountData(from: sourceAccountID, to: targetAccountID) == .migrated
    }

    /// Old releases could leave global data behind after signing out. Moving
    /// that data to a non-active recovery namespace prevents the next account
    /// from claiming it while preserving it for a future explicit recovery UI.
    @discardableResult
    func isolateUnownedLegacyGlobalsIfNeeded() -> AccountStorageMigrationResult {
        migrateLegacyDataIfNeeded(
            for: Self.legacyRecoveryAccountID,
            legacyProviderAccountID: "unowned-legacy",
            includeGlobalValues: true
        )
    }

    func removeAllAccountDataAndLegacyValues() {
        let prefixes = [
            Self.accountPrefix,
            Self.migrationCompletedPrefix,
            Self.migrationPreparedPrefix,
            Self.quarantinePrefix,
            Self.quarantineBlockedPrefix,
            Self.relinkConflictPrefix,
            Self.relinkPreparedPrefix,
            Self.cloudAnchorPrefix,
            Self.cloudPendingPrefix,
            Self.cloudBootstrapPrefix,
            Self.cloudConflictPrefix,
            Self.cloudQuarantinePrefix,
            Self.cloudBlockedPrefix,
            LegacyAccountStorageKey.userRecoveryPrefix,
            LegacyAccountStorageKey.wardrobePrefix,
            LegacyAccountStorageKey.starLifePrefix,
        ]
        defaults.dictionaryRepresentation().keys
            .filter { key in prefixes.contains(where: key.hasPrefix) }
            .forEach(defaults.removeObject(forKey:))
        LegacyAccountStorageKey.globalKeys.forEach(defaults.removeObject(forKey:))
    }

    func removeAccountData(for accountID: String) {
        let component = encodedKeyComponent(accountID)
        [
            storageKey(for: accountID),
            migrationCompletedKey(for: accountID),
            migrationPreparedKey(for: accountID),
            quarantineBlockedKey(for: accountID),
            cloudAnchorKey(for: accountID),
            cloudPendingKey(for: accountID),
            cloudBootstrapKey(for: accountID),
            cloudConflictKey(for: accountID),
            cloudBlockedKey(for: accountID),
        ].forEach(defaults.removeObject(forKey:))
        defaults.dictionaryRepresentation().keys
            .filter {
                $0.hasPrefix(Self.quarantinePrefix + component + ".")
                    || $0.hasPrefix(Self.relinkConflictPrefix + component + ".")
                    || ($0.hasPrefix(Self.relinkConflictPrefix) && $0.hasSuffix("." + component))
                    || $0.hasPrefix(Self.relinkPreparedPrefix + component + ".")
                    || ($0.hasPrefix(Self.relinkPreparedPrefix) && $0.hasSuffix("." + component))
                    || $0.hasPrefix(Self.cloudQuarantinePrefix + component + ".")
            }
            .forEach(defaults.removeObject(forKey:))
    }

    private func makeLegacySnapshot(
        accountID: String,
        legacyProviderAccountID: String,
        includeGlobalValues: Bool
    ) -> AccountLocalData? {
        var snapshot = AccountLocalData.seeded(for: accountID)

        if includeGlobalValues, defaults.object(forKey: LegacyAccountStorageKey.profile) != nil {
            guard let value: BirthProfile = decodeLegacy(LegacyAccountStorageKey.profile) else { return nil }
            snapshot.profile = value
        }
        if includeGlobalValues, defaults.object(forKey: LegacyAccountStorageKey.savedGuides) != nil {
            guard let value: [DailyGuide] = decodeLegacy(LegacyAccountStorageKey.savedGuides) else { return nil }
            snapshot.savedGuides = value
        }
        if includeGlobalValues, defaults.object(forKey: LegacyAccountStorageKey.readingHistory) != nil {
            guard let value: [TarotReadingRecord] = decodeLegacy(LegacyAccountStorageKey.readingHistory) else { return nil }
            snapshot.readingHistory = value
        }
        if includeGlobalValues, defaults.object(forKey: LegacyAccountStorageKey.planet) != nil {
            guard let value: SharedPlanet = decodeLegacy(LegacyAccountStorageKey.planet) else { return nil }
            snapshot.planet = value
        }
        if includeGlobalValues, defaults.object(forKey: LegacyAccountStorageKey.visitStreak) != nil {
            snapshot.visitStreak = max(0, defaults.integer(forKey: LegacyAccountStorageKey.visitStreak))
        }
        if includeGlobalValues, defaults.object(forKey: LegacyAccountStorageKey.lastVisit) != nil {
            guard let value = defaults.string(forKey: LegacyAccountStorageKey.lastVisit) else { return nil }
            snapshot.lastVisitDate = value
        }
        if includeGlobalValues, defaults.object(forKey: LegacyAccountStorageKey.dailyGuideRevealDate) != nil {
            guard let value = defaults.string(forKey: LegacyAccountStorageKey.dailyGuideRevealDate) else { return nil }
            snapshot.dailyGuideRevealDate = value
        }
        if includeGlobalValues, defaults.object(forKey: LegacyAccountStorageKey.tarotDrawDate) != nil {
            guard let value = defaults.string(forKey: LegacyAccountStorageKey.tarotDrawDate) else { return nil }
            snapshot.tarotDrawDate = value
        }

        let wardrobeKey = LegacyAccountStorageKey.wardrobePrefix + legacyProviderAccountID
        if defaults.object(forKey: wardrobeKey) != nil {
            guard let value: StarWardrobe = decodeLegacy(wardrobeKey) else { return nil }
            snapshot.wardrobe = value
        }
        let starLifeKey = LegacyAccountStorageKey.starLifePrefix + legacyProviderAccountID
        if defaults.object(forKey: starLifeKey) != nil {
            guard let value: StarLifeState = decodeLegacy(starLifeKey) else { return nil }
            snapshot.starLife = value
        }
        return snapshot.normalized(for: accountID)
    }

    private func decodeLegacy<Value: Decodable>(_ key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(Value.self, from: data)
    }

    private func finishLegacyMigration(
        accountID: String,
        legacyProviderAccountID: String,
        includeGlobalValues: Bool
    ) {
        legacyKeys(
            for: legacyProviderAccountID,
            includeGlobalValues: includeGlobalValues
        ).forEach(defaults.removeObject(forKey:))
        defaults.removeObject(forKey: migrationPreparedKey(for: accountID))
        defaults.set(true, forKey: migrationCompletedKey(for: accountID))
    }

    private func legacyKeys(
        for legacyProviderAccountID: String,
        includeGlobalValues: Bool
    ) -> [String] {
        let providerKeys = [
            LegacyAccountStorageKey.wardrobePrefix + legacyProviderAccountID,
            LegacyAccountStorageKey.starLifePrefix + legacyProviderAccountID,
        ]
        return includeGlobalValues ? LegacyAccountStorageKey.globalKeys + providerKeys : providerKeys
    }

    private func storageKey(for accountID: String) -> String {
        Self.accountPrefix + encodedKeyComponent(accountID)
    }

    private func migrationCompletedKey(for accountID: String) -> String {
        Self.migrationCompletedPrefix + encodedKeyComponent(accountID)
    }

    private func migrationPreparedKey(for accountID: String) -> String {
        Self.migrationPreparedPrefix + encodedKeyComponent(accountID)
    }

    private func quarantineBlockedKey(for accountID: String) -> String {
        Self.quarantineBlockedPrefix + encodedKeyComponent(accountID)
    }

    private func relinkPreparedKey(from sourceAccountID: String, to targetAccountID: String) -> String {
        Self.relinkPreparedPrefix
            + encodedKeyComponent(sourceAccountID)
            + "."
            + encodedKeyComponent(targetAccountID)
    }

    private func cloudAnchorKey(for accountID: String) -> String {
        Self.cloudAnchorPrefix + encodedKeyComponent(accountID)
    }

    private func cloudPendingKey(for accountID: String) -> String {
        Self.cloudPendingPrefix + encodedKeyComponent(accountID)
    }

    private func cloudBootstrapKey(for accountID: String) -> String {
        Self.cloudBootstrapPrefix + encodedKeyComponent(accountID)
    }

    private func cloudConflictKey(for accountID: String) -> String {
        Self.cloudConflictPrefix + encodedKeyComponent(accountID)
    }

    private func cloudBlockedKey(for accountID: String) -> String {
        Self.cloudBlockedPrefix + encodedKeyComponent(accountID)
    }

    private func cloudBootstrapRecord(for accountID: String) -> AccountCloudBootstrapRecord? {
        loadCloudValue(
            forKey: cloudBootstrapKey(for: accountID),
            accountID: accountID,
            validate: {
                $0.schemaVersion == AccountCloudBootstrapRecord.currentSchemaVersion
                    && $0.preparedAt.timeIntervalSinceReferenceDate.isFinite
            }
        )
    }

    /// Reads every metadata value once before a write so an unreadable or
    /// future-schema record is quarantined instead of being overwritten by a
    /// seemingly unrelated sync transition.
    @discardableResult
    private func validateCloudMetadata(for accountID: String) -> Bool {
        _ = cloudAnchor(for: accountID)
        _ = cloudPendingUpload(for: accountID)
        _ = cloudBootstrapRecord(for: accountID)
        _ = cloudConflictBackup(for: accountID)
        return !defaults.bool(forKey: cloudBlockedKey(for: accountID))
    }

    private func isValidCloudSnapshot(
        _ value: AccountCloudSnapshot,
        for accountID: String
    ) -> Bool {
        value.schemaVersion == AccountCloudSnapshot.currentSchemaVersion
            && isCleanCloudIdentifier(value.revision)
            && value.updatedAt.timeIntervalSinceReferenceDate.isFinite
            && isCompatibleAccountSnapshot(value.snapshot, for: accountID)
    }

    private func isValidCloudPendingUpload(
        _ value: AccountCloudPendingUpload,
        for accountID: String
    ) -> Bool {
        isCleanCloudIdentifier(value.mutationID)
            && (value.baseRevision.map(isCleanCloudIdentifier) ?? true)
            && value.queuedAt.timeIntervalSinceReferenceDate.isFinite
            && isCompatibleAccountSnapshot(value.snapshot, for: accountID)
    }

    private func isValidCloudConflict(
        _ value: AccountCloudConflictBackup,
        for accountID: String
    ) -> Bool {
        value.schemaVersion == AccountCloudConflictBackup.currentSchemaVersion
            && value.recordedAt.timeIntervalSinceReferenceDate.isFinite
            && isValidCloudPendingUpload(value.local, for: accountID)
            && isValidCloudSnapshot(value.remote, for: accountID)
    }

    private func isCompatibleAccountSnapshot(
        _ value: AccountLocalData,
        for accountID: String
    ) -> Bool {
        guard (1...AccountLocalData.currentSchemaVersion).contains(value.schemaVersion) else {
            return false
        }
        if let version = value.starLife.schemaVersion,
           version > StarLifeState.currentSchemaVersion {
            return false
        }
        // Normalization is intentionally not equality-checked: older compatible
        // wardrobe/star-life values are migrated when returned to callers.
        _ = value.normalized(for: accountID)
        return true
    }

    private func isCleanCloudIdentifier(_ value: String) -> Bool {
        !value.isEmpty
            && value.count <= 512
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && !value.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains)
    }

    private func validateIncomingCloudSnapshot(
        _ value: AccountCloudSnapshot,
        for accountID: String
    ) -> Bool {
        guard isValidCloudSnapshot(value, for: accountID) else {
            quarantineIncomingCloudValue(value, accountID: accountID)
            return false
        }
        return true
    }

    private func loadCloudValue<Value: Decodable>(
        forKey key: String,
        accountID: String,
        validate: (Value) -> Bool
    ) -> Value? {
        guard let rawValue = defaults.object(forKey: key) else { return nil }
        guard let data = rawValue as? Data,
              let decoded = try? decoder.decode(Value.self, from: data),
              validate(decoded)
        else {
            quarantineCloudValue(rawValue, accountID: accountID, sourceKey: key)
            return nil
        }
        return decoded
    }

    private func writeCloudValue<Value: Encodable>(_ value: Value, forKey key: String) -> Bool {
        guard let data = try? encoder.encode(value) else { return false }
        defaults.set(data, forKey: key)
        return defaults.data(forKey: key) == data
    }

    private func writeLocalSnapshot(_ value: AccountLocalData, for accountID: String) -> Bool {
        guard !defaults.bool(forKey: quarantineBlockedKey(for: accountID)) else { return false }
        let normalized = value.normalized(for: accountID)
        guard let data = try? encoder.encode(normalized) else { return false }
        let key = storageKey(for: accountID)
        defaults.set(data, forKey: key)
        return defaults.data(forKey: key) == data
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func quarantineIncomingCloudValue<Value: Encodable>(
        _ value: Value,
        accountID: String
    ) {
        guard let data = try? encoder.encode(value) else {
            defaults.set(true, forKey: cloudBlockedKey(for: accountID))
            return
        }
        quarantineCloudValue(data, accountID: accountID, sourceKey: nil)
    }

    private func quarantineCloudValue(
        _ value: Any,
        accountID: String,
        sourceKey: String?
    ) {
        let backupKey = Self.cloudQuarantinePrefix
            + encodedKeyComponent(accountID)
            + "."
            + UUID().uuidString
        defaults.set(value, forKey: backupKey)
        defaults.set(true, forKey: cloudBlockedKey(for: accountID))
        if defaults.object(forKey: backupKey) != nil, let sourceKey {
            defaults.removeObject(forKey: sourceKey)
        }
    }

    private func quarantine(_ value: Any, accountID: String, sourceKey: String) {
        let backupKey = Self.quarantinePrefix
            + encodedKeyComponent(accountID)
            + "."
            + UUID().uuidString
        defaults.set(value, forKey: backupKey)
        defaults.set(true, forKey: quarantineBlockedKey(for: accountID))
        if defaults.object(forKey: backupKey) != nil {
            defaults.removeObject(forKey: sourceKey)
        }
    }

    /// A read-only compatibility check used at the destructive commit point.
    /// It never normalizes, saves, quarantines, or removes the inspected value.
    private func compatibleStoredSnapshot(for accountID: String) -> AccountLocalData? {
        guard let data = defaults.data(forKey: storageKey(for: accountID)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let schemaVersion = (object["schemaVersion"] as? NSNumber)?.intValue,
           schemaVersion > AccountLocalData.currentSchemaVersion {
            return nil
        }
        if let starLife = object["starLife"] as? [String: Any],
           let schemaVersion = (starLife["schemaVersion"] as? NSNumber)?.intValue,
           schemaVersion > StarLifeState.currentSchemaVersion {
            return nil
        }
        guard let decoded = try? decoder.decode(AccountLocalData.self, from: data) else {
            return nil
        }
        return decoded.normalized(for: accountID)
    }

    private func encodedKeyComponent(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
