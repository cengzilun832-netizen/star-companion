import Combine
import Foundation
import WatchConnectivity

/// Bridges the minimal pet state to Apple Watch. All mutations are rechecked
/// against `AppStore` on iPhone, including feed limits and gentle-day rules.
final class StarPetWatchSyncController: NSObject, WCSessionDelegate {
    static let shared = StarPetWatchSyncController()

    private weak var store: AppStore?
    private var storeChanges: AnyCancellable?
    private let defaults = UserDefaults.standard
    private var processedActionIDs: [String]

    private enum Key {
        static let processedActions = "xingban.watch.processed-actions.v1"
        static let interactionPrefix = "xingban.watch.gentle-interaction.v1."
        static let accountScopePrefix = "xingban.watch.account-scope.v1."
    }

    private override init() {
        processedActionIDs = defaults.stringArray(forKey: Key.processedActions) ?? []
        super.init()
    }

    @MainActor
    func connect(to store: AppStore) {
        self.store = store
        storeChanges = store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // ObservableObject announces immediately before the mutation.
                // Publish on the next main-loop turn so the snapshot is fresh.
                DispatchQueue.main.async {
                    self?.publishCurrentSnapshot()
                }
            }

        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        publishCurrentSnapshot()
    }

    @MainActor
    func publishCurrentSnapshot() {
        guard WCSession.isSupported(), let store else { return }
        let session = WCSession.default
        guard session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled
        else { return }

        do {
            try session.updateApplicationContext(
                WatchPetMessageCodec.message(for: makeSnapshot(from: store))
            )
        } catch {
            // The newest state will be retried on the next AppStore change or
            // when the watch explicitly requests a snapshot.
        }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated, error == nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.publishCurrentSnapshot()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let action = WatchPetMessageCodec.action(from: message) else {
            replyHandler([:])
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, let store = self.store else {
                replyHandler([:])
                return
            }
            self.perform(action, on: store)
            replyHandler(WatchPetMessageCodec.message(for: self.makeSnapshot(from: store)))
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let action = WatchPetMessageCodec.action(from: userInfo) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let store = self.store else { return }
            self.perform(action, on: store)
            self.publishCurrentSnapshot()
        }
    }

    @MainActor
    private func perform(_ action: WatchPetAction, on store: AppStore) {
        store.refreshDailyContext()
        let today = SharedPlanet.todayStamp()
        guard action.kind == .requestSnapshot || action.dayStamp == today else { return }
        guard action.kind == .requestSnapshot || action.accountScopeID == accountScopeID(for: store) else { return }

        if action.kind != .requestSnapshot {
            let id = action.id.uuidString
            guard !processedActionIDs.contains(id) else { return }
            processedActionIDs.append(id)
            processedActionIDs = Array(processedActionIDs.suffix(128))
            defaults.set(processedActionIDs, forKey: Key.processedActions)
        }

        switch action.kind {
        case .feed:
            guard store.canFeedPet else { return }
            store.feedPet()
        case .gentleInteraction:
            guard canUseWatchInteraction(store: store, dayStamp: today) else { return }
            store.petStar()
            defaults.set(today, forKey: interactionKey(for: store))
        case .requestSnapshot:
            break
        }
    }

    @MainActor
    private func makeSnapshot(from store: AppStore) -> WatchPetSnapshot {
        let dayStamp = SharedPlanet.todayStamp()
        let language = WatchPetLanguage(rawValue: store.language.rawValue) ?? .systemDefault
        let mood = WatchPetMood(rawValue: store.starVisualMood.rawValue) ?? .happy
        return WatchPetSnapshot(
            dayStamp: dayStamp,
            accountScopeID: accountScopeID(for: store),
            mood: mood,
            food: store.planet.food,
            feedCount: store.planet.feedCount,
            feedLimit: store.maxDailyFeedCount,
            canFeed: store.account != nil && store.canFeedPet,
            canInteract: canUseWatchInteraction(store: store, dayStamp: dayStamp),
            gentleMode: store.isGentleModeToday,
            language: language
        )
    }

    @MainActor
    private func canUseWatchInteraction(store: AppStore, dayStamp: String) -> Bool {
        guard store.account != nil, store.deletionIntent == nil, !store.isDeletingAccount else { return false }
        if store.isGentleModeToday, !store.canUseGentleInteraction { return false }
        return defaults.string(forKey: interactionKey(for: store)) != dayStamp
    }

    @MainActor
    private func interactionKey(for store: AppStore) -> String {
        Key.interactionPrefix + accountHash(for: store)
    }

    @MainActor
    private func accountScopeID(for store: AppStore) -> String {
        let key = Key.accountScopePrefix + accountHash(for: store)
        if let existing = defaults.string(forKey: key) { return existing }
        let created = UUID().uuidString.lowercased()
        defaults.set(created, forKey: key)
        return created
    }

    @MainActor
    private func accountHash(for store: AppStore) -> String {
        let accountID = store.account?.id ?? "guest"
        let hash = accountID.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { value, byte in
            (value ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
