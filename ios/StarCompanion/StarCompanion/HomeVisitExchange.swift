import CryptoKit
import Foundation

enum HomeVisitReaction: String, CaseIterable, Identifiable, Codable {
    case warmWave
    case moonHug
    case tinyCheer

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .warmWave: "hand.wave.fill"
        case .moonHug: "moon.stars.fill"
        case .tinyCheer: "sparkles"
        }
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .warmWave: language.text("揮揮手", "손 흔들기", "A warm wave")
        case .moonHug: language.text("月亮抱抱", "달빛 포옹", "A moonlit hug")
        case .tinyCheer: language.text("小小加油", "작은 응원", "A tiny cheer")
        }
    }
}

struct HomeVisitCard: Codable, Equatable, Hashable, Identifiable {
    static let currentVersion = 1

    let version: Int
    let id: UUID
    let hostShareID: UUID
    let createdAt: Date
    let expiresAt: Date
    let hostAlias: String?
    let appearance: StarAppearanceSnapshot
    let furnitureIDs: [String]
}

struct HomeVisitReceipt: Codable, Equatable, Hashable, Identifiable {
    static let currentVersion = 1

    let version: Int
    let id: UUID
    let cardID: UUID
    let hostShareID: UUID
    let cardDigest: String
    let visitorKey: String
    let visitorAlias: String?
    let reaction: HomeVisitReaction
    let createdAt: Date
}

struct IssuedHomeVisitCard: Codable, Equatable, Identifiable {
    let id: UUID
    let digest: String
    let expiresAt: Date
}

struct HomeVisitRedemption: Codable, Equatable, Identifiable {
    let id: UUID
    let cardID: UUID
    let visitorKey: String
    let acceptedAt: Date
    let reward: Int
}

struct HomeVisitExchangeState: Codable, Equatable {
    var hostShareID: UUID?
    var visitorSecret: Data?
    var issuedCards: [IssuedHomeVisitCard]?
    var outboundReceipts: [HomeVisitReceipt]?
    var redemptions: [HomeVisitRedemption]?

    static func seeded() -> HomeVisitExchangeState {
        HomeVisitExchangeState(
            hostShareID: UUID(),
            visitorSecret: randomSecret(),
            issuedCards: [],
            outboundReceipts: [],
            redemptions: []
        )
    }

    func migrated(now: Date = .now, calendar: Calendar = .current) -> HomeVisitExchangeState {
        var state = self
        state.hostShareID = state.hostShareID ?? UUID()
        if state.visitorSecret?.count != 32 { state.visitorSecret = Self.randomSecret() }

        let oldCardCutoff = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        state.issuedCards = Array((state.issuedCards ?? [])
            .filter { $0.expiresAt >= oldCardCutoff }
            .prefix(32))

        let ledgerCutoff = calendar.date(byAdding: .day, value: -90, to: now) ?? now
        state.outboundReceipts = Array((state.outboundReceipts ?? [])
            .filter { $0.createdAt >= ledgerCutoff }
            .prefix(128))
        state.redemptions = HomeVisitRewardPolicy.retainedRedemptions(
            to: state.redemptions ?? [],
            issuedCards: state.issuedCards ?? [],
            now: now,
            calendar: calendar
        )
        return state
    }

    private static func randomSecret() -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}

enum PendingHomeVisitLink: Identifiable, Equatable {
    case card(HomeVisitCard)
    case receipt(HomeVisitReceipt)

    var id: String {
        switch self {
        case let .card(card): "card-\(card.id.uuidString)"
        case let .receipt(receipt): "receipt-\(receipt.id.uuidString)"
        }
    }
}

enum HomeVisitReceiptAcceptance: Equatable {
    case accepted(reward: Int)
    case acceptedWithoutReward
    case alreadyAccepted
    case alreadyVisitedToday
    case dailyLimitReached
    case expired
    case invalid
}

enum HomeVisitRewardPolicy {
    static let rewardPerVisit = 8
    static let maximumRewardedVisitsPerDay = 3
    static let maximumAcceptedVisitsPerDay = 64

    static func redemptionGraceEnd(
        for card: IssuedHomeVisitCard,
        calendar: Calendar = .current
    ) -> Date {
        calendar.date(byAdding: .day, value: 1, to: card.expiresAt) ?? card.expiresAt
    }

    static func decision(
        for receipt: HomeVisitReceipt,
        redemptions: [HomeVisitRedemption],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> HomeVisitReceiptAcceptance {
        guard !redemptions.contains(where: { $0.id == receipt.id }) else { return .alreadyAccepted }
        let today = SharedPlanet.todayStamp(for: now, calendar: calendar)
        guard !redemptions.contains(where: {
            $0.visitorKey == receipt.visitorKey
                && SharedPlanet.todayStamp(for: $0.acceptedAt, calendar: calendar) == today
        }) else { return .alreadyVisitedToday }

        let acceptedVisits = redemptions.filter {
            SharedPlanet.todayStamp(for: $0.acceptedAt, calendar: calendar) == today
        }.count
        guard acceptedVisits < maximumAcceptedVisitsPerDay else { return .dailyLimitReached }

        let rewardedVisits = redemptions.filter {
            $0.reward > 0 && SharedPlanet.todayStamp(for: $0.acceptedAt, calendar: calendar) == today
        }.count
        return rewardedVisits < maximumRewardedVisitsPerDay
            ? .accepted(reward: rewardPerVisit)
            : .acceptedWithoutReward
    }

    /// Never evict a receipt while its originating card can still be redeemed.
    /// Otherwise an old URL could become valid again merely by filling the
    /// fixed-size ledger. Expired-card history remains bounded for UI use.
    static func retainedRedemptions(
        adding redemption: HomeVisitRedemption? = nil,
        to existing: [HomeVisitRedemption],
        issuedCards: [IssuedHomeVisitCard],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [HomeVisitRedemption] {
        let activeCardIDs = Set(issuedCards.compactMap { card in
            redemptionGraceEnd(for: card, calendar: calendar) >= now ? card.id : nil
        })
        let ledgerCutoff = calendar.date(byAdding: .day, value: -90, to: now) ?? now
        var candidates = existing
        if let redemption { candidates.insert(redemption, at: 0) }
        candidates = candidates
            .filter { $0.acceptedAt >= ledgerCutoff }
            .sorted { $0.acceptedAt > $1.acceptedAt }

        var seen = Set<UUID>()
        let unique = candidates.filter { seen.insert($0.id).inserted }
        let protected = unique.filter { activeCardIDs.contains($0.cardID) }
        let archival = unique
            .filter { !activeCardIDs.contains($0.cardID) }
            .prefix(512)
        return protected + archival
    }
}

enum HomeVisitLinkCodec {
    static let scheme = "starcompanion"
    private static let host = "home"
    private static let maximumURLLength = 4_096
    private static let maximumPayloadBytes = 3_072

    static func url(for card: HomeVisitCard) -> URL? {
        encode(card, path: "/visit")
    }

    static func url(for receipt: HomeVisitReceipt) -> URL? {
        encode(receipt, path: "/receipt")
    }

    static func decode(_ url: URL) -> PendingHomeVisitLink? {
        guard url.absoluteString.count <= maximumURLLength,
              url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.queryItems?.filter({ $0.name == "v" }).map(\.value) == ["1"],
              let payload = components.queryItems?.filter({ $0.name == "p" }).compactMap(\.value),
              payload.count == 1,
              let data = Data(base64URL: payload[0]),
              data.count <= maximumPayloadBytes
        else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        switch components.path {
        case "/visit":
            guard let card = try? decoder.decode(HomeVisitCard.self, from: data),
                  card.version == HomeVisitCard.currentVersion
            else { return nil }
            return .card(card)
        case "/receipt":
            guard let receipt = try? decoder.decode(HomeVisitReceipt.self, from: data),
                  receipt.version == HomeVisitReceipt.currentVersion
            else { return nil }
            return .receipt(receipt)
        default:
            return nil
        }
    }

    static func digest(for card: HomeVisitCard) -> String? {
        guard let data = encodedData(card) else { return nil }
        return Data(SHA256.hash(data: data)).base64URLEncodedString()
    }

    static func visitorKey(secret: Data, hostShareID: UUID) -> String {
        let key = SymmetricKey(data: secret)
        let value = HMAC<SHA256>.authenticationCode(
            for: Data(hostShareID.uuidString.lowercased().utf8),
            using: key
        )
        return String(Data(value).base64URLEncodedString().prefix(24))
    }

    static func sanitizedAlias(_ value: String?) -> String? {
        guard let value else { return nil }
        let whitespace = CharacterSet.whitespacesAndNewlines
        let controls = CharacterSet.controlCharacters
        let bidirectionalControls = CharacterSet(charactersIn: "\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}")
        let cleanScalars = value.unicodeScalars.compactMap { scalar -> Unicode.Scalar? in
            if whitespace.contains(scalar) { return " " }
            if controls.contains(scalar) || bidirectionalControls.contains(scalar) { return nil }
            return scalar
        }
        let collapsed = String(String.UnicodeScalarView(cleanScalars))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let trimmed = String(collapsed.prefix(20))
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func encode<T: Encodable>(_ value: T, path: String) -> URL? {
        guard let data = encodedData(value), data.count <= maximumPayloadBytes else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        components.queryItems = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "p", value: data.base64URLEncodedString()),
        ]
        guard let url = components.url, url.absoluteString.count <= maximumURLLength else { return nil }
        return url
    }

    private static func encodedData<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try? encoder.encode(value)
    }
}

private extension Data {
    init?(base64URL value: String) {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
