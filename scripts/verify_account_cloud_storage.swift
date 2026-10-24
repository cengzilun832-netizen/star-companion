import Foundation

@main
enum VerifyAccountCloudStorage {
    static func main() throws {
        let suiteName = "xingban.verify.account-cloud-storage.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not create isolated UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        let storage = AccountStorage(defaults: defaults)
        let accountA = "account:cloud-a"
        let accountB = "account:cloud-b"
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        precondition(storage.prepareCloudBootstrap(for: accountA, mode: .preserveLocal, preparedAt: t0))
        precondition(storage.cloudBootstrapMode(for: accountA) == .preserveLocal)
        precondition(!storage.prepareCloudBootstrap(for: accountA, mode: .preferRemote, preparedAt: t0))
        precondition(storage.prepareCloudBootstrap(for: accountB, mode: .preferRemote, preparedAt: t0))
        precondition(storage.cloudBootstrapMode(for: accountB) == .preferRemote)

        let remoteA1 = cloudSnapshot(
            revision: "a-r1",
            updatedAt: t0,
            accountID: accountA,
            visitStreak: 10
        )
        precondition(storage.applyRemoteCloudSnapshot(remoteA1, for: accountA))
        precondition(storage.cloudAnchor(for: accountA) == remoteA1)
        precondition(storage.cloudBootstrapMode(for: accountA) == nil)
        precondition(storage.load(for: accountA).visitStreak == 10)

        let remoteB1 = cloudSnapshot(
            revision: "b-r1",
            updatedAt: t0,
            accountID: accountB,
            visitStreak: 20
        )
        precondition(storage.applyRemoteCloudSnapshot(remoteB1, for: accountB))
        precondition(storage.cloudAnchor(for: accountB)?.revision == "b-r1")
        precondition(storage.load(for: accountB).visitStreak == 20)

        var localA1 = remoteA1.snapshot
        localA1.visitStreak = 11
        let pendingA1 = storage.saveLocalSnapshotPreparingCloudUpload(
            localA1,
            for: accountA,
            mutationID: "a-m1",
            queuedAt: t0.addingTimeInterval(1)
        )
        precondition(pendingA1?.baseRevision == "a-r1")
        precondition(storage.cloudPendingUpload(for: accountA)?.mutationID == "a-m1")
        precondition(storage.cloudPendingUpload(for: accountB) == nil)
        precondition(storage.load(for: accountA).visitStreak == 11)
        precondition(storage.load(for: accountB).visitStreak == 20)

        // Simulate termination after pending was verified but before current was
        // replaced. The pending snapshot must be the recovered local truth.
        defaults.set(
            try JSONEncoder().encode(remoteA1.snapshot),
            forKey: accountLocalKey(accountA)
        )
        precondition(storage.load(for: accountA).visitStreak == 11)
        let recoveredCurrent = try JSONDecoder().decode(
            AccountLocalData.self,
            from: requireData(defaults, key: accountLocalKey(accountA))
        )
        precondition(recoveredCurrent.visitStreak == 11)

        // A second local save replaces/coalesces the payload but keeps the
        // original server base until the in-flight first write is acknowledged.
        var localA2 = localA1
        localA2.visitStreak = 12
        let pendingA2 = storage.saveLocalSnapshotPreparingCloudUpload(
            localA2,
            for: accountA,
            mutationID: "a-m2",
            queuedAt: t0.addingTimeInterval(2)
        )
        precondition(pendingA2?.baseRevision == "a-r1")

        let acknowledgedA1 = cloudSnapshot(
            revision: "a-r2",
            updatedAt: t0.addingTimeInterval(3),
            accountID: accountA,
            visitStreak: 11
        )
        precondition(storage.acknowledgeCloudUpload(
            mutationID: "a-m1",
            remote: acknowledgedA1,
            for: accountA
        ))
        let rebasedA2 = storage.cloudPendingUpload(for: accountA)
        precondition(rebasedA2?.mutationID == "a-m2")
        precondition(rebasedA2?.baseRevision == "a-r2")
        precondition(rebasedA2?.snapshot.visitStreak == 12)
        precondition(storage.cloudAnchor(for: accountA)?.revision == "a-r2")
        precondition(storage.load(for: accountA).visitStreak == 12)

        let acknowledgedA2 = cloudSnapshot(
            revision: "a-r3",
            updatedAt: t0.addingTimeInterval(4),
            accountID: accountA,
            visitStreak: 12
        )
        precondition(storage.acknowledgeCloudUpload(
            mutationID: "a-m2",
            remote: acknowledgedA2,
            for: accountA
        ))
        precondition(storage.cloudPendingUpload(for: accountA) == nil)
        precondition(storage.cloudAnchor(for: accountA)?.revision == "a-r3")

        let remoteA4 = cloudSnapshot(
            revision: "a-r4",
            updatedAt: t0.addingTimeInterval(5),
            accountID: accountA,
            visitStreak: 14
        )
        precondition(storage.applyRemoteCloudSnapshot(remoteA4, for: accountA))
        precondition(storage.load(for: accountA).visitStreak == 14)
        precondition(storage.cloudAnchor(for: accountA)?.revision == "a-r4")

        var conflictingLocal = remoteA4.snapshot
        conflictingLocal.visitStreak = 15
        precondition(storage.saveLocalSnapshotPreparingCloudUpload(
            conflictingLocal,
            for: accountA,
            mutationID: "a-conflict",
            queuedAt: t0.addingTimeInterval(6)
        ) != nil)
        let conflictingRemote = cloudSnapshot(
            revision: "a-r5",
            updatedAt: t0.addingTimeInterval(7),
            accountID: accountA,
            visitStreak: 99
        )
        precondition(storage.recordCloudConflict(
            remote: conflictingRemote,
            for: accountA,
            recordedAt: t0.addingTimeInterval(8)
        ))
        let conflict = storage.cloudConflictBackup(for: accountA)
        precondition(conflict?.local.snapshot.visitStreak == 15)
        precondition(conflict?.remote.snapshot.visitStreak == 99)
        precondition(storage.cloudPendingUpload(for: accountA)?.mutationID == "a-conflict")
        precondition(storage.cloudAnchor(for: accountA)?.revision == "a-r4")
        precondition(storage.load(for: accountA).visitStreak == 15)
        precondition(!storage.applyRemoteCloudSnapshot(conflictingRemote, for: accountA))
        precondition(storage.load(for: accountA).visitStreak == 15)

        let accountD = "account:resolve-remote"
        let remoteD1 = cloudSnapshot(
            revision: "d-r1",
            updatedAt: t0,
            accountID: accountD,
            visitStreak: 40
        )
        precondition(storage.applyRemoteCloudSnapshot(remoteD1, for: accountD))
        var localD = remoteD1.snapshot
        localD.visitStreak = 41
        precondition(storage.saveLocalSnapshotPreparingCloudUpload(
            localD,
            for: accountD,
            mutationID: "d-old"
        ) != nil)
        let remoteD2 = cloudSnapshot(
            revision: "d-r2",
            updatedAt: t0.addingTimeInterval(9),
            accountID: accountD,
            visitStreak: 49
        )
        precondition(storage.recordCloudConflict(remote: remoteD2, for: accountD))
        precondition(storage.resolveCloudConflictUsingRemote(for: accountD) == remoteD2)
        precondition(storage.load(for: accountD).visitStreak == 49)
        precondition(storage.cloudAnchor(for: accountD)?.revision == "d-r2")
        precondition(storage.cloudPendingUpload(for: accountD) == nil)
        precondition(storage.cloudConflictBackup(for: accountD) == nil)

        let accountE = "account:resolve-local"
        let remoteE1 = cloudSnapshot(
            revision: "e-r1",
            updatedAt: t0,
            accountID: accountE,
            visitStreak: 50
        )
        precondition(storage.applyRemoteCloudSnapshot(remoteE1, for: accountE))
        var localE = remoteE1.snapshot
        localE.visitStreak = 51
        precondition(storage.saveLocalSnapshotPreparingCloudUpload(
            localE,
            for: accountE,
            mutationID: "e-old"
        ) != nil)
        let remoteE2 = cloudSnapshot(
            revision: "e-r2",
            updatedAt: t0.addingTimeInterval(10),
            accountID: accountE,
            visitStreak: 59
        )
        precondition(storage.recordCloudConflict(remote: remoteE2, for: accountE))
        let resolvedLocal = storage.resolveCloudConflictUsingLocal(
            for: accountE,
            mutationID: "e-new",
            queuedAt: t0.addingTimeInterval(11)
        )
        precondition(resolvedLocal?.mutationID == "e-new")
        precondition(resolvedLocal?.baseRevision == "e-r2")
        precondition(resolvedLocal?.snapshot.visitStreak == 51)
        precondition(storage.load(for: accountE).visitStreak == 51)
        precondition(storage.cloudAnchor(for: accountE)?.revision == "e-r2")
        precondition(storage.cloudConflictBackup(for: accountE) == nil)
        precondition(storage.cloudPendingUpload(for: accountE) == resolvedLocal)
        precondition(storage.load(for: accountB).visitStreak == 20)

        // A future cloud schema is backed up and blocks cloud writes, but it
        // never replaces the compatible local snapshot.
        let accountC = "account:future-cloud"
        let remoteC1 = cloudSnapshot(
            revision: "c-r1",
            updatedAt: t0,
            accountID: accountC,
            visitStreak: 30
        )
        precondition(storage.applyRemoteCloudSnapshot(remoteC1, for: accountC))
        var futureC = cloudSnapshot(
            revision: "c-r2",
            updatedAt: t0.addingTimeInterval(1),
            accountID: accountC,
            visitStreak: 31
        )
        futureC.schemaVersion = AccountCloudSnapshot.currentSchemaVersion + 1
        precondition(!storage.applyRemoteCloudSnapshot(futureC, for: accountC))
        precondition(storage.load(for: accountC).visitStreak == 30)
        precondition(!storage.cloudSyncWritesAllowed(for: accountC))
        precondition(defaults.dictionaryRepresentation().keys.contains {
            $0.hasPrefix(cloudQuarantinePrefix(accountC))
        })

        storage.removeAccountData(for: accountA)
        precondition(!storage.hasStoredData(for: accountA))
        precondition(storage.cloudAnchor(for: accountA) == nil)
        precondition(storage.cloudPendingUpload(for: accountA) == nil)
        precondition(storage.cloudConflictBackup(for: accountA) == nil)
        precondition(storage.cloudBootstrapMode(for: accountA) == nil)
        precondition(storage.load(for: accountB).visitStreak == 20)
        precondition(storage.cloudAnchor(for: accountB)?.revision == "b-r1")

        storage.removeAccountData(for: accountC)
        precondition(storage.cloudSyncWritesAllowed(for: accountC))
        precondition(!defaults.dictionaryRepresentation().keys.contains {
            $0.hasPrefix(cloudQuarantinePrefix(accountC))
        })

        storage.removeAllAccountDataAndLegacyValues()
        precondition(!storage.hasStoredData(for: accountB))
        precondition(storage.cloudAnchor(for: accountB) == nil)
        precondition(storage.cloudPendingUpload(for: accountB) == nil)

        print("Cloud cache bootstrap, isolation, crash recovery, acknowledgement rebase, explicit conflict resolution, quarantine, and removal verified")
    }

    private static func cloudSnapshot(
        revision: String,
        updatedAt: Date,
        accountID: String,
        visitStreak: Int
    ) -> AccountCloudSnapshot {
        var snapshot = AccountLocalData.seeded(for: accountID)
        snapshot.visitStreak = visitStreak
        return AccountCloudSnapshot(
            revision: revision,
            updatedAt: updatedAt,
            snapshot: snapshot
        )
    }

    private static func encodedComponent(_ accountID: String) -> String {
        Data(accountID.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func accountLocalKey(_ accountID: String) -> String {
        "xingban.ios.account-local.v1." + encodedComponent(accountID)
    }

    private static func cloudQuarantinePrefix(_ accountID: String) -> String {
        "xingban.ios.account-cloud-quarantine.v1." + encodedComponent(accountID) + "."
    }

    private static func requireData(_ defaults: UserDefaults, key: String) -> Data {
        guard let data = defaults.data(forKey: key) else {
            preconditionFailure("Missing data for \(key)")
        }
        return data
    }
}
