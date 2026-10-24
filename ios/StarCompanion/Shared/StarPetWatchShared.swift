import Foundation

/// The small, privacy-minimised state shared with the paired Apple Watch.
/// The iPhone remains authoritative; the watch never receives account,
/// subscription, tarot, or purchase data.
enum WatchPetLanguage: String, Codable, CaseIterable {
    case traditionalChinese = "zh-Hant"
    case korean = "ko"
    case english = "en"

    static var systemDefault: WatchPetLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if preferred.hasPrefix("zh") { return .traditionalChinese }
        if preferred.hasPrefix("ko") { return .korean }
        return .english
    }

    func text(_ traditionalChinese: String, _ korean: String, _ english: String) -> String {
        switch self {
        case .traditionalChinese: traditionalChinese
        case .korean: korean
        case .english: english
        }
    }
}

enum WatchPetMood: String, Codable, CaseIterable {
    case happy
    case calm
    case tired
    case low
    case glowing
    case delighted
}

struct WatchPetSnapshot: Codable, Equatable {
    static let schemaVersion = 2

    var version: Int
    var updatedAt: Date
    var dayStamp: String
    var accountScopeID: String
    var mood: WatchPetMood
    var food: Int
    var feedCount: Int
    var feedLimit: Int
    var canFeed: Bool
    var canInteract: Bool
    var gentleMode: Bool
    var language: WatchPetLanguage

    init(
        version: Int = schemaVersion,
        updatedAt: Date = .now,
        dayStamp: String,
        accountScopeID: String,
        mood: WatchPetMood,
        food: Int,
        feedCount: Int,
        feedLimit: Int,
        canFeed: Bool,
        canInteract: Bool,
        gentleMode: Bool,
        language: WatchPetLanguage
    ) {
        self.version = version
        self.updatedAt = updatedAt
        self.dayStamp = dayStamp
        self.accountScopeID = accountScopeID
        self.mood = mood
        self.food = min(max(food, 0), 100)
        self.feedLimit = max(feedLimit, 1)
        self.feedCount = min(max(feedCount, 0), self.feedLimit)
        self.canFeed = canFeed && self.feedCount < self.feedLimit && !gentleMode
        self.canInteract = canInteract
        self.gentleMode = gentleMode
        self.language = language
    }

    static var placeholder: WatchPetSnapshot {
        let language = WatchPetLanguage.systemDefault
        return WatchPetSnapshot(
            dayStamp: localDayStamp(),
            accountScopeID: "unpaired",
            mood: .happy,
            food: 72,
            feedCount: 0,
            feedLimit: 3,
            canFeed: false,
            canInteract: false,
            gentleMode: false,
            language: language
        )
    }

    static func localDayStamp(for date: Date = .now, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }
}

enum WatchPetActionKind: String, Codable {
    case feed
    case gentleInteraction
    case requestSnapshot
}

struct WatchPetAction: Codable, Equatable {
    var id: UUID
    var kind: WatchPetActionKind
    var requestedAt: Date
    var dayStamp: String
    var accountScopeID: String

    init(
        id: UUID = UUID(),
        kind: WatchPetActionKind,
        requestedAt: Date = .now,
        dayStamp: String = WatchPetSnapshot.localDayStamp(),
        accountScopeID: String = "unpaired"
    ) {
        self.id = id
        self.kind = kind
        self.requestedAt = requestedAt
        self.dayStamp = dayStamp
        self.accountScopeID = accountScopeID
    }
}

enum WatchPetMessageCodec {
    static let snapshotKey = "starPet.snapshot.v1"
    static let actionKey = "starPet.action.v1"

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()

    static func message(for snapshot: WatchPetSnapshot) -> [String: Any] {
        guard let data = try? encoder.encode(snapshot) else { return [:] }
        return [snapshotKey: data]
    }

    static func snapshot(from message: [String: Any]) -> WatchPetSnapshot? {
        guard let data = message[snapshotKey] as? Data,
              let snapshot = try? decoder.decode(WatchPetSnapshot.self, from: data),
              snapshot.version <= WatchPetSnapshot.schemaVersion
        else { return nil }
        return snapshot
    }

    static func message(for action: WatchPetAction) -> [String: Any] {
        guard let data = try? encoder.encode(action) else { return [:] }
        return [actionKey: data]
    }

    static func action(from message: [String: Any]) -> WatchPetAction? {
        guard let data = message[actionKey] as? Data else { return nil }
        return try? decoder.decode(WatchPetAction.self, from: data)
    }
}
