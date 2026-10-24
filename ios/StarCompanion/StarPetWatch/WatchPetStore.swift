import Combine
import Foundation
import WatchConnectivity

@MainActor
final class WatchPetStore: NSObject, ObservableObject, WCSessionDelegate {
    enum SyncState: Equatable {
        case current
        case sending
        case queued
    }

    @Published private(set) var snapshot: WatchPetSnapshot
    @Published private(set) var syncState = SyncState.current

    private let defaults = UserDefaults.standard
    private var session: WCSession?
    private var pendingAction: WatchPetAction?

    private static let cacheKey = "xingban.watch.snapshot-cache.v1"

    override init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder.watchPet.decode(WatchPetSnapshot.self, from: data) {
            snapshot = cached
        } else {
            snapshot = .placeholder
        }
        super.init()

        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()
    }

    var language: WatchPetLanguage { snapshot.language }

    func feed() {
        guard snapshot.canFeed, pendingAction == nil else { return }
        send(.feed)
    }

    func interact() {
        guard snapshot.canInteract, pendingAction == nil else { return }
        send(.gentleInteraction)
    }

    func requestFreshSnapshot() {
        guard pendingAction == nil else { return }
        send(.requestSnapshot)
    }

    private func send(_ kind: WatchPetActionKind) {
        guard let session else { return }
        let action = WatchPetAction(
            kind: kind,
            dayStamp: WatchPetSnapshot.localDayStamp(),
            accountScopeID: snapshot.accountScopeID
        )
        let message = WatchPetMessageCodec.message(for: action)
        guard !message.isEmpty else { return }

        pendingAction = action
        syncState = .sending

        if session.isReachable {
            session.sendMessage(message) { [weak self] reply in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let snapshot = WatchPetMessageCodec.snapshot(from: reply) {
                        self.accept(snapshot)
                    } else {
                        self.queue(action, on: session)
                    }
                }
            } errorHandler: { [weak self] _ in
                DispatchQueue.main.async {
                    self?.queue(action, on: session)
                }
            }
        } else {
            queue(action, on: session)
        }
    }

    private func queue(_ action: WatchPetAction, on session: WCSession) {
        guard pendingAction?.id == action.id else { return }
        session.transferUserInfo(WatchPetMessageCodec.message(for: action))
        syncState = .queued
        // Keep mutation buttons disabled until the authoritative iPhone state
        // arrives. A refresh request remains unnecessary: application context
        // is updated by iPhone after processing the queued action.
    }

    private func accept(_ value: WatchPetSnapshot) {
        guard value.updatedAt >= snapshot.updatedAt || value.dayStamp != snapshot.dayStamp else {
            pendingAction = nil
            syncState = .current
            return
        }
        snapshot = value
        pendingAction = nil
        syncState = .current
        if let data = try? JSONEncoder.watchPet.encode(value) {
            defaults.set(data, forKey: Self.cacheKey)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated, error == nil else { return }
        Task { @MainActor [weak self] in
            if let snapshot = WatchPetMessageCodec.snapshot(from: session.receivedApplicationContext) {
                self?.accept(snapshot)
            }
            self?.requestFreshSnapshot()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let snapshot = WatchPetMessageCodec.snapshot(from: applicationContext) else { return }
        Task { @MainActor [weak self] in
            self?.accept(snapshot)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let snapshot = WatchPetMessageCodec.snapshot(from: userInfo) else { return }
        Task { @MainActor [weak self] in
            self?.accept(snapshot)
        }
    }
}

private extension JSONEncoder {
    static var watchPet: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }
}

private extension JSONDecoder {
    static var watchPet: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
